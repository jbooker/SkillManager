import Foundation

public enum InventoryBuilder {
    public static func build(_ options: ScanOptions) -> Inventory {
        let copies = SkillDiscovery.discoverSkills(options: options)
        let groups = groupSkills(copies)
        let activeGroups = groups.filter { !$0.archivedOnly }
        let allNames = Set(activeGroups.map(\.name))
        let harnesses = Harnesses.all.map { def -> HarnessSummary in
            let visible = activeGroups.filter { $0.harnesses.contains(def.id) }
            let uniqueNames = visible.map(\.name).sorted()
            let missingNames = allNames.subtracting(uniqueNames).sorted()
            let skillCount = visible.reduce(0) { sum, group in
                sum + group.copies.filter { $0.location.scope != .archived && $0.location.harnesses.contains(def.id) }.count
            }
            return HarnessSummary(
                id: def.id,
                name: def.name,
                shortName: def.shortName,
                colorHex: def.colorHex,
                blurb: def.blurb,
                readsSharedAgents: def.readsSharedAgents,
                skillCount: skillCount,
                uniqueNames: uniqueNames,
                missingNames: missingNames,
                locations: locationsForHarness(def.id)
            )
        }

        let issues = collectIssues(groups)
        let sharedCount = activeGroups.filter(\.inShared).count
        let fragmentedCount = activeGroups.filter { !$0.inShared || $0.harnesses.count < HarnessID.allCases.count }.count
        let activeCopies = copies.filter { $0.location.scope != .archived }

        return Inventory(
            scannedAt: Date(),
            homeDir: options.homeDir,
            scanRoots: options.scanRoots,
            uniqueCount: activeGroups.count,
            archivedCount: groups.filter(\.hasArchive).count,
            copyCount: activeCopies.count,
            sharedCount: sharedCount,
            fragmentedCount: fragmentedCount,
            issueCount: issues.count,
            harnesses: harnesses,
            groups: groups,
            copies: copies,
            issues: issues
        )
    }

    public static func groupSkills(_ copies: [SkillCopy]) -> [SkillGroup] {
        var byName: [String: [SkillCopy]] = [:]
        for copy in copies {
            byName[copy.name, default: []].append(copy)
        }

        var groups: [SkillGroup] = []
        for (name, groupCopies) in byName {
            var harnessSet = Set<HarnessID>()
            var scopes = Set<SkillScope>()
            for copy in groupCopies {
                scopes.insert(copy.location.scope)
                guard copy.location.scope != .archived else { continue }
                for h in copy.location.harnesses { harnessSet.insert(h) }
            }
            let hashes = Set(groupCopies.map(\.contentHash))
            let description = groupCopies.first(where: { !$0.description.isEmpty })?.description
                ?? groupCopies.first?.description
                ?? ""
            var issues = Array(Set(groupCopies.flatMap(\.errors)))
            if hashes.count > 1 { issues.append("divergent-copies") }
            groups.append(
                SkillGroup(
                    name: name,
                    description: description,
                    copies: groupCopies,
                    harnesses: HarnessID.allCases.filter { harnessSet.contains($0) },
                    inShared: groupCopies.contains { $0.location.shared && $0.location.scope != .archived },
                    identical: hashes.count <= 1,
                    scopes: Array(scopes),
                    issues: issues
                )
            )
        }
        groups.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return groups
    }

    public static func defaultScanRoots(homeDir: String, cwd: String) -> [String] {
        let candidates = [
            cwd,
            (homeDir as NSString).appendingPathComponent("projects"),
            (homeDir as NSString).appendingPathComponent("src"),
            (homeDir as NSString).appendingPathComponent("code"),
            (homeDir as NSString).appendingPathComponent("dev"),
            (homeDir as NSString).appendingPathComponent("work"),
            (homeDir as NSString).appendingPathComponent("repos"),
        ]
        var seen = Set<String>()
        return candidates.filter { dir in
            if dir.isEmpty || dir == "/" || dir == homeDir { return false }
            if seen.contains(dir) { return false }
            seen.insert(dir)
            return true
        }
    }

    private static func locationsForHarness(_ id: HarnessID) -> [String] {
        var labels: [String] = []
        for loc in Harnesses.userLocations where loc.harnesses.contains(id) {
            if let homeRel = loc.homeRel {
                labels.append("~/" + homeRel)
            }
        }
        if id == .cursor { labels.append("~/.cursor/plugins/**/skills") }
        if id == .grok { labels.append("~/.grok/config.toml extra paths") }
        return labels
    }

    private static func collectIssues(_ groups: [SkillGroup]) -> [InventoryIssue] {
        var issues: [InventoryIssue] = []
        for group in groups {
            if group.issues.contains("divergent-copies") {
                issues.append(
                    InventoryIssue(
                        level: "warn",
                        code: "divergent-copies",
                        message: "\(group.name) has copies that are not identical",
                        skillName: group.name
                    )
                )
            }
            if !group.harnesses.contains(.claude) && group.copies.contains(where: { $0.location.shared && $0.location.scope != .archived }) {
                issues.append(
                    InventoryIssue(
                        level: "info",
                        code: "claude-blind",
                        message: "\(group.name) is in the shared agents folder, which Claude Code does not read",
                        skillName: group.name
                    )
                )
            }
            for copy in group.copies {
                for code in copy.errors where ["missing-description", "missing-frontmatter", "invalid-frontmatter"].contains(code) {
                    issues.append(
                        InventoryIssue(
                            level: "warn",
                            code: code,
                            message: "\(group.name): \(code.replacingOccurrences(of: "-", with: " "))",
                            skillName: group.name,
                            path: copy.skillFile
                        )
                    )
                }
            }
        }
        return issues
    }
}
