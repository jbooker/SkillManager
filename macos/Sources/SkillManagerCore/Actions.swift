import Foundation

public enum SkillActions {
    public static func promoteToShared(skillDir: String, homeDir: String, mode: ActionMode = .symlink) -> ActionResult {
        linkInto(skillDir: skillDir, destParent: Harnesses.sharedAgentsDir(homeDir: homeDir), mode: mode)
    }

    public static func linkToHarness(skillDir: String, homeDir: String, harness: HarnessID, mode: ActionMode = .symlink) -> ActionResult {
        linkInto(skillDir: skillDir, destParent: Harnesses.userSkillDir(homeDir: homeDir, harness: harness), mode: mode)
    }

    public static func makeEverywhere(skillDir: String, homeDir: String, mode: ActionMode = .symlink) -> ActionResult {
        let results = [
            promoteToShared(skillDir: skillDir, homeDir: homeDir, mode: mode),
            linkToHarness(skillDir: skillDir, homeDir: homeDir, harness: .claude, mode: mode),
        ]
        if results.allSatisfy({ !$0.ok }) {
            return .failure(results.compactMap(\.error).joined(separator: "; "))
        }
        return ActionResult(ok: true, action: nil, target: nil, source: nil, mode: nil, error: nil, results: results)
    }

    public static func unlinkManaged(targetPath: String) -> ActionResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: targetPath) else {
            return .failure("Path does not exist")
        }
        guard isSymlink(targetPath) else {
            return .failure("Refusing to delete a non-symlink skill folder")
        }
        let source = URL(fileURLWithPath: targetPath).resolvingSymlinksInPath().path
        do {
            try fm.removeItem(atPath: targetPath)
            return .success(action: .removed, target: targetPath, source: source, mode: .symlink)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Remove one copy from a load path. Symlinks are unlinked. A real user folder is
    /// relocated onto a remaining symlink, or archived if it is the last user copy.
    public static func unloadCopy(targetPath: String, homeDir: String) -> ActionResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: targetPath) else {
            return .failure("Path does not exist")
        }
        if let blocked = protectionError(for: targetPath, homeDir: homeDir) {
            return .failure(blocked)
        }
        if isSymlink(targetPath) {
            return unlinkManaged(targetPath: targetPath)
        }

        let loc = SkillDiscovery.classifyLocation(skillFile: skillFile(for: targetPath), homeDir: homeDir)
        if loc.scope == .project {
            return .failure("Refusing to move a project skill folder. Delete it from the repo, or archive user copies instead.")
        }
        if loc.scope == .archived {
            return .failure("Already archived. Restore it or delete the archive.")
        }

        let name = URL(fileURLWithPath: targetPath).lastPathComponent
        let siblings = knownUserCopyPaths(skillName: name, homeDir: homeDir).filter { !sameEntry($0, targetPath) }
        let remainingReals = siblings.filter { !isSymlink($0) }
        let linksToUs = siblings.filter { isSymlink($0) && realPath($0) == realPath(targetPath) }

        if !remainingReals.isEmpty {
            do {
                try fm.removeItem(atPath: targetPath)
                return .success(action: .removed, target: targetPath, source: remainingReals[0], mode: .copy)
            } catch {
                return .failure(error.localizedDescription)
            }
        }

        if let keep = linksToUs.first {
            return relocate(from: targetPath, onto: keep, otherLinks: linksToUs.filter { !sameEntry($0, keep) })
        }

        return archiveFolders(skillName: name, realPaths: [targetPath], unlinkPaths: [], homeDir: homeDir)
    }

    public static func unloadFromShared(skillName: String, homeDir: String) -> ActionResult {
        unloadNamed(skillName: skillName, destParent: Harnesses.sharedAgentsDir(homeDir: homeDir), homeDir: homeDir)
    }

    public static func unloadFromHarness(skillName: String, homeDir: String, harness: HarnessID) -> ActionResult {
        unloadNamed(skillName: skillName, destParent: Harnesses.userSkillDir(homeDir: homeDir, harness: harness), homeDir: homeDir)
    }

    /// Take every user-level copy out of harness load paths and keep one archive.
    public static func archiveUserCopies(skillName: String, homeDir: String) -> ActionResult {
        let paths = knownUserCopyPaths(skillName: skillName, homeDir: homeDir)
        guard !paths.isEmpty else {
            return .failure("No user-level copy of \(skillName) to archive")
        }
        var realPaths: [String] = []
        var unlinkPaths: [String] = []
        for path in paths {
            if let blocked = protectionError(for: path, homeDir: homeDir) {
                return .failure(blocked)
            }
            if isSymlink(path) {
                unlinkPaths.append(path)
            } else {
                realPaths.append(path)
            }
        }
        if realPaths.isEmpty {
            let results = unlinkPaths.map { unlinkManaged(targetPath: $0) }
            if results.allSatisfy(\.ok) {
                return ActionResult(ok: true, action: .removed, target: unlinkPaths.first, source: nil, mode: .symlink, error: nil, results: results)
            }
            return .failure(results.compactMap(\.error).joined(separator: "; "))
        }
        let managedReals = realPaths.filter { isManagedUserPath($0, homeDir: homeDir) }
        let toArchive = managedReals.isEmpty ? realPaths : managedReals
        return archiveFolders(
            skillName: skillName,
            realPaths: toArchive,
            unlinkPaths: unlinkPaths,
            homeDir: homeDir
        )
    }

    public static func restoreArchived(skillName: String, homeDir: String, destParent: String? = nil) -> ActionResult {
        let fm = FileManager.default
        let archived = (Harnesses.archiveDir(homeDir: homeDir) as NSString).appendingPathComponent(skillName)
        guard fm.fileExists(atPath: archived) else {
            return .failure("No archive named \(skillName)")
        }
        let original = readManifest(at: archived)?.first
        let parent: String
        if let destParent, !destParent.isEmpty {
            parent = destParent
        } else if let original {
            parent = URL(fileURLWithPath: original).deletingLastPathComponent().path
        } else {
            parent = Harnesses.sharedAgentsDir(homeDir: homeDir)
        }
        let target = (parent as NSString).appendingPathComponent(skillName)
        if fm.fileExists(atPath: target) {
            return .failure("Target already exists: \(target)")
        }
        do {
            try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try moveOrCopy(from: archived, to: target)
            let sidecar = (target as NSString).appendingPathComponent(".skill-manager.json")
            if fm.fileExists(atPath: sidecar) {
                try fm.removeItem(atPath: sidecar)
            }
            return .success(action: .restored, target: target, source: archived)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    public static func deleteCopy(targetPath: String, homeDir: String) -> ActionResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: targetPath) else {
            return .failure("Path does not exist")
        }
        if let blocked = protectionError(for: targetPath, homeDir: homeDir) {
            return .failure(blocked)
        }
        let loc = SkillDiscovery.classifyLocation(skillFile: skillFile(for: targetPath), homeDir: homeDir)
        if loc.scope == .project && !isSymlink(targetPath) {
            return .failure("Refusing to delete a project skill folder from here. Remove it in the repo.")
        }
        let source = isSymlink(targetPath) ? realPath(targetPath) : targetPath
        do {
            try fm.removeItem(atPath: targetPath)
            return .success(action: .deleted, target: targetPath, source: source)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    public static func deleteUserCopies(skillName: String, homeDir: String, includeArchive: Bool = true) -> ActionResult {
        var paths = knownUserCopyPaths(skillName: skillName, homeDir: homeDir)
        let archived = (Harnesses.archiveDir(homeDir: homeDir) as NSString).appendingPathComponent(skillName)
        if includeArchive, FileManager.default.fileExists(atPath: archived) {
            paths.append(archived)
        }
        guard !paths.isEmpty else {
            return .failure("No user-level copy of \(skillName) to delete")
        }
        var results: [ActionResult] = []
        for path in paths {
            if let blocked = protectionError(for: path, homeDir: homeDir) {
                results.append(.failure(blocked))
                continue
            }
            do {
                try FileManager.default.removeItem(atPath: path)
                results.append(.success(action: .deleted, target: path, source: path))
            } catch {
                results.append(.failure(error.localizedDescription))
            }
        }
        if results.allSatisfy(\.ok) {
            return ActionResult(ok: true, action: .deleted, target: paths.first, source: nil, mode: nil, error: nil, results: results)
        }
        if results.contains(where: { $0.ok }) {
            return ActionResult(ok: true, action: .deleted, target: paths.first, source: nil, mode: nil, error: results.compactMap(\.error).joined(separator: "; "), results: results)
        }
        return .failure(results.compactMap(\.error).joined(separator: "; "))
    }

    public static func setInactive(skillDir: String, homeDir: String, inactive: Bool) -> ActionResult {
        if let blocked = protectionError(for: skillDir, homeDir: homeDir) {
            return .failure(blocked)
        }
        let loc = SkillDiscovery.classifyLocation(skillFile: skillFile(for: skillDir), homeDir: homeDir)
        if loc.scope == .archived {
            return .failure("Archived skills are already out of every harness. Restore first to change auto-load.")
        }
        let realDir = realPath(skillDir)
        let file = (realDir as NSString).appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: file) else {
            return .failure("SKILL.md not found")
        }
        do {
            let raw = try String(contentsOfFile: file, encoding: .utf8)
            let next = SkillParser.patchDisableModelInvocation(content: raw, inactive: inactive)
            try next.write(toFile: file, atomically: true, encoding: .utf8)
            return .success(
                action: inactive ? .deactivated : .activated,
                target: file,
                source: realDir
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    public static func knownUserCopyPaths(skillName: String, homeDir: String) -> [String] {
        let fm = FileManager.default
        var paths: [String] = []
        for loc in Harnesses.userLocations where loc.scope == .user {
            guard let homeRel = loc.homeRel else { continue }
            let candidate = (Harnesses.userSkillDir(homeDir: homeDir, homeRel: homeRel) as NSString)
                .appendingPathComponent(skillName)
            if fm.fileExists(atPath: candidate) {
                paths.append(candidate)
            }
        }
        return paths
    }

    private static func unloadNamed(skillName: String, destParent: String, homeDir: String) -> ActionResult {
        let target = (destParent as NSString).appendingPathComponent(skillName)
        guard FileManager.default.fileExists(atPath: target) else {
            return .failure("No copy at \(target)")
        }
        return unloadCopy(targetPath: target, homeDir: homeDir)
    }

    private static func relocate(from source: String, onto keep: String, otherLinks: [String]) -> ActionResult {
        let fm = FileManager.default
        do {
            try fm.removeItem(atPath: keep)
            try moveOrCopy(from: source, to: keep)
            for link in otherLinks {
                if fm.fileExists(atPath: link) {
                    try fm.removeItem(atPath: link)
                }
                try fm.createSymbolicLink(atPath: link, withDestinationPath: keep)
            }
            return .success(action: .relocated, target: keep, source: source, mode: .symlink)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func archiveFolders(skillName: String, realPaths: [String], unlinkPaths: [String], homeDir: String) -> ActionResult {
        let fm = FileManager.default
        let archiveRoot = Harnesses.archiveDir(homeDir: homeDir)
        let dest = (archiveRoot as NSString).appendingPathComponent(skillName)
        if fm.fileExists(atPath: dest) {
            return .failure("An archive named \(skillName) already exists. Restore or delete it first.")
        }

        var results: [ActionResult] = []
        for path in unlinkPaths {
            let result = unlinkManaged(targetPath: path)
            results.append(result)
            if !result.ok { return result }
        }

        let extras = Array(realPaths.dropFirst())
        let canonical = realPaths[0]
        do {
            try fm.createDirectory(atPath: archiveRoot, withIntermediateDirectories: true)
            if isManagedUserPath(canonical, homeDir: homeDir) {
                try moveOrCopy(from: canonical, to: dest)
            } else {
                try fm.copyItem(atPath: canonical, toPath: dest)
            }
            writeManifest(
                at: dest,
                name: skillName,
                originalPaths: [canonical] + extras + unlinkPaths
            )
            for extra in extras where isManagedUserPath(extra, homeDir: homeDir) {
                try fm.removeItem(atPath: extra)
                results.append(.success(action: .removed, target: extra, source: dest, mode: .copy))
            }
            return ActionResult(
                ok: true,
                action: .archived,
                target: dest,
                source: canonical,
                mode: nil,
                error: nil,
                results: results.isEmpty ? nil : results
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func writeManifest(at dest: String, name: String, originalPaths: [String]) {
        let payload: [String: Any] = [
            "name": name,
            "archivedAt": ISO8601DateFormatter().string(from: Date()),
            "originalPaths": originalPaths,
            "originalHomeRel": originalPaths.first.map { path in
                // keep as-is; UI uses originalPaths
                path
            } as Any,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        var text = String(data: data, encoding: .utf8) ?? ""
        if !text.hasSuffix("\n") { text.append("\n") }
        try? text.write(
            to: URL(fileURLWithPath: dest).appendingPathComponent(".skill-manager.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func readManifest(at dest: String) -> [String]? {
        let file = (dest as NSString).appendingPathComponent(".skill-manager.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (json["originalPaths"] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func protectionError(for path: String, homeDir: String) -> String? {
        let loc = SkillDiscovery.classifyLocation(skillFile: skillFile(for: path), homeDir: homeDir)
        if loc.scope == .plugin { return "Refusing to change a plugin skill" }
        if loc.scope == .builtin { return "Refusing to change a built-in skill" }
        return nil
    }

    private static func skillFile(for skillDir: String) -> String {
        (skillDir as NSString).appendingPathComponent("SKILL.md")
    }

    private static func isManagedUserPath(_ path: String, homeDir: String) -> Bool {
        let real = realPath(path)
        for loc in Harnesses.userLocations where loc.scope == .user {
            guard let homeRel = loc.homeRel else { continue }
            let parent = Harnesses.userSkillDir(homeDir: homeDir, homeRel: homeRel)
            if isInside(real, parent) { return true }
        }
        return isInside(real, Harnesses.archiveDir(homeDir: homeDir))
    }

    private static func isSymlink(_ path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        return (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private static func realPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private static func moveOrCopy(from source: String, to dest: String) throws {
        let fm = FileManager.default
        do {
            try fm.moveItem(atPath: source, toPath: dest)
        } catch {
            try fm.copyItem(atPath: source, toPath: dest)
            try fm.removeItem(atPath: source)
        }
    }

    private static func linkInto(skillDir: String, destParent: String, mode: ActionMode) -> ActionResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillDir) else {
            return .failure("Skill directory does not exist")
        }
        let source = URL(fileURLWithPath: skillDir).resolvingSymlinksInPath().path
        let name = URL(fileURLWithPath: source).lastPathComponent
        guard !name.isEmpty else { return .failure("Could not determine skill name") }

        try? fm.createDirectory(atPath: destParent, withIntermediateDirectories: true)
        let target = (destParent as NSString).appendingPathComponent(name)

        if pathsEqual(source, target) {
            return .success(action: .alreadyLinked, target: target, source: source, mode: mode)
        }
        if isInside(source, destParent) && URL(fileURLWithPath: source).deletingLastPathComponent().path == destParent {
            return .success(action: .alreadyLinked, target: source, source: source, mode: mode)
        }

        if fm.fileExists(atPath: target) {
            let existing = URL(fileURLWithPath: target).resolvingSymlinksInPath().path
            if existing == source {
                return .success(action: .alreadyLinked, target: target, source: source, mode: mode)
            }
            return .failure("Target already exists: \(target)")
        }

        do {
            if mode == .copy {
                try fm.copyItem(atPath: source, toPath: target)
            } else {
                try fm.createSymbolicLink(atPath: target, withDestinationPath: source)
            }
            return .success(action: .created, target: target, source: source, mode: mode)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func sameEntry(_ a: String, _ b: String) -> Bool {
        a.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            == b.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func pathsEqual(_ a: String, _ b: String) -> Bool {
        normalize(a) == normalize(b)
    }

    private static func isInside(_ child: String, _ parent: String) -> Bool {
        let childN = URL(fileURLWithPath: child).resolvingSymlinksInPath().path
        let parentN = URL(fileURLWithPath: parent).resolvingSymlinksInPath().path
        return childN == parentN || childN.hasPrefix(parentN + "/")
    }

    private static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .precomposedStringWithCanonicalMapping
    }
}
