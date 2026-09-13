import Foundation

public enum SkillRefresh {
    public static func inspect(origin: SkillOrigin) -> RefreshInspection {
        guard origin.refreshable, let locator = origin.locator else {
            return RefreshInspection(
                state: .notRefreshable,
                localRef: origin.pinnedRef,
                remoteRef: nil,
                message: notRefreshableMessage(origin)
            )
        }
        let needle = origin.trackRef
        guard let remote = GitProcess.remoteHead(url: locator, ref: needle) else {
            return RefreshInspection(
                state: .unreachable,
                localRef: origin.pinnedRef,
                remoteRef: nil,
                message: "Couldn’t reach \(SkillOrigins.displayLabel(locator))"
            )
        }
        if let local = origin.pinnedRef, refsMatch(local, remote) {
            return RefreshInspection(
                state: .current,
                localRef: local,
                remoteRef: remote,
                message: "Up to date"
            )
        }
        if origin.pinnedRef == nil {
            return RefreshInspection(
                state: .unknown,
                localRef: nil,
                remoteRef: remote,
                message: "Source recorded"
            )
        }
        return RefreshInspection(
            state: .updateAvailable,
            localRef: origin.pinnedRef,
            remoteRef: remote,
            message: "Update available"
        )
    }

    public static func apply(skillDir: String, origin: SkillOrigin) -> ActionResult {
        guard origin.refreshable, let locator = origin.locator else {
            return .failure(notRefreshableMessage(origin))
        }
        let dest = URL(fileURLWithPath: skillDir).resolvingSymlinksInPath().path
        switch origin.kind {
        case .git:
            return pullGit(dest: dest, locator: locator)
        case .remote:
            return materialize(dest: dest, origin: origin, locator: locator)
        case .plugin, .builtin, .local:
            return .failure(notRefreshableMessage(origin))
        }
    }

    private static func pullGit(dest: String, locator: String) -> ActionResult {
        guard let repo = GitProcess.repo(containing: dest) else {
            return .failure("Not a git checkout")
        }
        if GitProcess.isDirty(repo.root) {
            return .failure("Local changes in \(repo.root). Commit or stash them before refreshing.")
        }
        let before = repo.head
        do {
            let after = try GitProcess.pull(root: repo.root)
            if after == before {
                return .success(action: .alreadyCurrent, target: dest, source: locator, revision: after)
            }
            return .success(action: .updated, target: dest, source: locator, revision: after)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func materialize(dest: String, origin: SkillOrigin, locator: String) -> ActionResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dest) else {
            return .failure("Skill directory does not exist")
        }
        let incomingParent = fm.temporaryDirectory.appendingPathComponent("skill-refresh-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: incomingParent, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: incomingParent) }
            let cloneDir = incomingParent.appendingPathComponent("clone").path
            try GitProcess.clone(url: locator, dest: cloneDir, ref: origin.trackRef ?? origin.pinnedRef)
            guard let sourceSkill = findSkillFolder(in: cloneDir, subpath: origin.subpath, dest: dest) else {
                return .failure("No SKILL.md at \(origin.subpath ?? URL(fileURLWithPath: dest).lastPathComponent) in \(SkillOrigins.displayLabel(locator))")
            }
            let revision = GitProcess.head(at: cloneDir)
            try replaceDirectory(from: sourceSkill, to: dest)
            return .success(action: .updated, target: dest, source: locator, revision: revision)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func findSkillFolder(in clone: String, subpath: String?, dest: String) -> String? {
        let name = URL(fileURLWithPath: dest).lastPathComponent
        let candidates: [String] = [
            subpath.map { (clone as NSString).appendingPathComponent($0) },
            (clone as NSString).appendingPathComponent(name),
            (clone as NSString).appendingPathComponent("skills/\(name)"),
            clone,
        ].compactMap { $0 }
        for path in candidates {
            let skill = (path as NSString).appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: skill) { return path }
        }
        return nil
    }

    private static func replaceDirectory(from source: String, to dest: String) throws {
        let fm = FileManager.default
        let parent = URL(fileURLWithPath: dest).deletingLastPathComponent()
        let incoming = parent.appendingPathComponent(".\(URL(fileURLWithPath: dest).lastPathComponent).incoming-\(UUID().uuidString)").path
        let backup = parent.appendingPathComponent(".\(URL(fileURLWithPath: dest).lastPathComponent).bak-\(UUID().uuidString)").path
        try SkillTrees.copyExcludingGit(from: source, to: incoming)
        try fm.moveItem(atPath: dest, toPath: backup)
        do {
            try fm.moveItem(atPath: incoming, toPath: dest)
            try fm.removeItem(atPath: backup)
        } catch {
            try? fm.removeItem(atPath: incoming)
            if fm.fileExists(atPath: backup), !fm.fileExists(atPath: dest) {
                try? fm.moveItem(atPath: backup, toPath: dest)
            }
            throw error
        }
    }

    private static func refsMatch(_ local: String, _ remote: String) -> Bool {
        local == remote || local.hasPrefix(remote) || remote.hasPrefix(local)
    }

    private static func notRefreshableMessage(_ origin: SkillOrigin) -> String {
        switch origin.kind {
        case .builtin:
            return "Cursor syncs built-in skills itself."
        case .plugin:
            return "Plugin caches are managed by the harness. Copy the skill into your own folder to refresh it from GitHub."
        case .local:
            return "No git or GitHub source recorded. Set a GitHub repo to refresh this copy."
        case .git, .remote:
            return "No upstream URL to refresh from."
        }
    }
}
