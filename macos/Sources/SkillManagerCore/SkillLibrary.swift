import Foundation

public enum SkillLibrary {
    public static func preview(url: String) -> LibraryPreviewResult {
        guard let locator = SkillOrigins.parseLocator(url) else {
            return .failure("Couldn’t parse that as a GitHub repo or git URL.")
        }
        let fm = FileManager.default
        let cloneParent = fm.temporaryDirectory.appendingPathComponent("skill-library-\(UUID().uuidString)")
        let cloneDir = cloneParent.appendingPathComponent("clone").path
        do {
            try fm.createDirectory(at: cloneParent, withIntermediateDirectories: true)
            try GitProcess.clone(url: locator.url, dest: cloneDir, ref: locator.ref)
            let skills = listSkills(cloneDir: cloneDir, locator: locator)
            if skills.isEmpty {
                try? fm.removeItem(at: cloneParent)
                return .failure("No SKILL.md folders in \(SkillOrigins.displayLabel(locator.url))")
            }
            let session = LibrarySession(
                locator: locator,
                label: SkillOrigins.displayLabel(locator.url),
                revision: GitProcess.head(at: cloneDir),
                skills: skills,
                cloneDir: cloneDir
            )
            return .success(session)
        } catch {
            try? fm.removeItem(at: cloneParent)
            return .failure(error.localizedDescription)
        }
    }

    public static func load(
        session: LibrarySession,
        selecting: Set<String>,
        homeDir: String,
        target: LoadTarget
    ) -> LibraryLoadResult {
        if selecting.isEmpty {
            return LibraryLoadResult(items: [], assignedOrigins: [:], error: "No skills selected")
        }
        let chosen = session.skills.filter { selecting.contains($0.id) }
        if chosen.isEmpty {
            return LibraryLoadResult(items: [], assignedOrigins: [:], error: "No matching skills to load")
        }

        let parent = destParent(homeDir: homeDir, target: target)
        let fm = FileManager.default
        try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)

        var items: [LibraryItemResult] = []
        var origins: [String: AssignedOrigin] = [:]
        var claimed = Set<String>()

        for skill in chosen {
            if claimed.contains(skill.name) {
                items.append(
                    LibraryItemResult(
                        name: skill.name,
                        subpath: skill.subpath,
                        dest: nil,
                        origin: nil,
                        status: .failed,
                        error: "Another selected skill also uses the folder name \(skill.name)"
                    )
                )
                continue
            }
            claimed.insert(skill.name)

            let dest = (parent as NSString).appendingPathComponent(skill.name)
            if fm.fileExists(atPath: dest) {
                items.append(
                    LibraryItemResult(
                        name: skill.name,
                        subpath: skill.subpath,
                        dest: dest,
                        origin: nil,
                        status: .alreadyPresent,
                        error: "Already exists at \(dest)"
                    )
                )
                continue
            }

            let source = skill.subpath.isEmpty
                ? session.cloneDir
                : (session.cloneDir as NSString).appendingPathComponent(skill.subpath)
            do {
                try SkillTrees.copyExcludingGit(from: source, to: dest)
                var warning: String?
                if target == .everywhere {
                    let linked = SkillActions.linkToHarness(
                        skillDir: dest,
                        homeDir: homeDir,
                        harness: .claude
                    )
                    if !linked.ok {
                        warning = linked.error
                    }
                }
                let origin = AssignedOrigin(
                    locator: session.locator.url,
                    subpath: skill.subpath.isEmpty ? nil : skill.subpath,
                    ref: session.revision
                )
                let key = SkillOrigins.originKey(realPath: dest, homeDir: homeDir)
                origins[key] = origin
                items.append(
                    LibraryItemResult(
                        name: skill.name,
                        subpath: skill.subpath,
                        dest: dest,
                        origin: origin,
                        status: .loaded,
                        error: warning
                    )
                )
            } catch {
                items.append(
                    LibraryItemResult(
                        name: skill.name,
                        subpath: skill.subpath,
                        dest: dest,
                        origin: nil,
                        status: .failed,
                        error: error.localizedDescription
                    )
                )
            }
        }

        return LibraryLoadResult(items: items, assignedOrigins: origins, error: nil)
    }

    public static func close(_ session: LibrarySession) {
        let clone = URL(fileURLWithPath: session.cloneDir)
        let parent = clone.deletingLastPathComponent()
        if parent.lastPathComponent.hasPrefix("skill-library-") {
            try? FileManager.default.removeItem(at: parent)
        } else {
            try? FileManager.default.removeItem(at: clone)
        }
    }

    private static func listSkills(cloneDir: String, locator: GitLocator) -> [LibrarySkill] {
        let start: String
        if let subpath = locator.subpath, !subpath.isEmpty {
            start = (cloneDir as NSString).appendingPathComponent(subpath)
        } else {
            start = cloneDir
        }
        let cloneURL = URL(fileURLWithPath: cloneDir).resolvingSymlinksInPath()
        return SkillTrees.skillDirs(in: start).compactMap { dir in
            let skillFile = (dir as NSString).appendingPathComponent("SKILL.md")
            guard let raw = try? String(contentsOfFile: skillFile, encoding: .utf8) else { return nil }
            let dirURL = URL(fileURLWithPath: dir).resolvingSymlinksInPath()
            let isRoot = dirURL.path == cloneURL.path
            let name = isRoot ? repoName(locator.url) : dirURL.lastPathComponent
            let parsed = SkillParser.parse(content: raw, folderName: name)
            let subpath = isRoot ? "" : relativePath(from: cloneDir, to: dir) ?? name
            return LibrarySkill(name: name, description: parsed.meta.description, subpath: subpath)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func destParent(homeDir: String, target: LoadTarget) -> String {
        switch target {
        case .everywhere:
            return Harnesses.sharedAgentsDir(homeDir: homeDir)
        case .harness(let id):
            return Harnesses.userSkillDir(homeDir: homeDir, harness: id)
        }
    }

    private static func repoName(_ locator: String) -> String {
        var path = locator
        if path.hasSuffix(".git") {
            path = String(path.dropLast(4))
        }
        if path.hasPrefix("file://"), let url = URL(string: path) {
            return URL(fileURLWithPath: url.path).lastPathComponent
        }
        return path.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: ".git", with: "")
            ?? "skill"
    }

    private static func relativePath(from root: String, to path: String) -> String? {
        let rootN = (root as NSString).standardizingPath
        let pathN = (path as NSString).standardizingPath
        if pathN == rootN { return nil }
        if pathN.hasPrefix(rootN + "/") {
            return String(pathN.dropFirst(rootN.count + 1))
        }
        return nil
    }
}
