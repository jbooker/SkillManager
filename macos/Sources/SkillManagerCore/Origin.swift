import Foundation

public enum SkillOrigins {
    public static func infer(
        skillDir: String,
        location: SkillLocation,
        homeDir: String,
        assigned: [String: AssignedOrigin] = [:]
    ) -> SkillOrigin {
        let real = URL(fileURLWithPath: skillDir).resolvingSymlinksInPath().path
        if let repo = GitProcess.repo(containing: real), let locator = repo.remoteURL, !locator.isEmpty {
            let sub = relativePath(from: repo.root, to: real)
            return SkillOrigin(
                kind: .git,
                label: displayLabel(locator),
                locator: locator,
                subpath: sub,
                pinnedRef: repo.head
            )
        }

        if location.scope == .builtin {
            return SkillOrigin(kind: .builtin, label: location.label)
        }
        if location.scope == .plugin {
            return SkillOrigin(
                kind: .plugin,
                label: location.label,
                pinnedRef: pluginPinnedRef(path: real)
            )
        }

        if let found = lookup(assigned, realPath: real, homeDir: homeDir) {
            let sha = found.ref.flatMap { GitProcess.looksLikeSHA($0) ? $0 : nil }
            return SkillOrigin(
                kind: .remote,
                label: displayLabel(found.locator),
                locator: found.locator,
                subpath: found.subpath,
                pinnedRef: sha,
                trackRef: sha == nil ? found.ref : nil
            )
        }

        if location.scope == .archived {
            return SkillOrigin(kind: .local, label: "Archived")
        }
        return .local
    }

    public static func parseLocator(_ raw: String, skillName: String = "") -> GitLocator? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if trimmed.hasPrefix("git@") {
            return parseSSH(trimmed)
        }

        if trimmed.hasPrefix("file://") {
            return parseLocalPath(URL(string: trimmed)?.path ?? trimmed)
        }

        if trimmed.hasPrefix("/") {
            return parseLocalPath(trimmed)
        }

        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            if host.contains("github.com") {
                return parseGitHubURL(url)
            }
            return GitLocator(url: trimmed)
        }

        return parseShortGitHub(trimmed, skillName: skillName)
    }

    public static func originKey(realPath: String, homeDir: String) -> String {
        if realPath == homeDir || realPath.hasPrefix(homeDir + "/") {
            return "~" + String(realPath.dropFirst(homeDir.count)).replacingOccurrences(of: "\\", with: "/")
        }
        return realPath.replacingOccurrences(of: "\\", with: "/")
    }

    public static func displayLabel(_ locator: String) -> String {
        if let gh = githubOwnerRepo(locator) {
            return "GitHub · \(gh.owner)/\(gh.repo)"
        }
        if locator.hasPrefix("file://") {
            return URL(string: locator)?.path ?? locator
        }
        return locator
    }

    public static func lookup(
        _ assigned: [String: AssignedOrigin],
        realPath: String,
        homeDir: String
    ) -> AssignedOrigin? {
        let name = URL(fileURLWithPath: realPath).lastPathComponent
        let keys = [
            originKey(realPath: realPath, homeDir: homeDir),
            realPath,
            name,
        ]
        for key in keys {
            if let found = assigned[key] { return found }
        }
        return nil
    }

    private static func parseLocalPath(_ path: String) -> GitLocator? {
        let standardized = (path as NSString).standardizingPath
        if let repo = GitProcess.repo(containing: standardized) {
            return GitLocator(
                url: URL(fileURLWithPath: repo.root).absoluteString,
                subpath: relativePath(from: repo.root, to: standardized)
            )
        }
        return GitLocator(url: URL(fileURLWithPath: standardized).absoluteString)
    }

    private static func parseGitHubURL(_ url: URL) -> GitLocator? {
        let parts = url.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        let repo = parts[1].replacingOccurrences(of: ".git", with: "")
        var ref: String?
        var subpath: String?
        if parts.count >= 4, parts[2] == "tree" || parts[2] == "blob" {
            ref = parts[3]
            var rest = Array(parts.dropFirst(4))
            if parts[2] == "blob", rest.last?.lowercased() == "skill.md" {
                rest.removeLast()
            }
            if !rest.isEmpty { subpath = rest.joined(separator: "/") }
        } else if parts.count > 2 {
            subpath = parts.dropFirst(2).joined(separator: "/")
        }
        return GitLocator(url: "https://github.com/\(owner)/\(repo).git", subpath: subpath, ref: ref)
    }

    private static func parseSSH(_ value: String) -> GitLocator? {
        guard let colon = value.firstIndex(of: ":") else { return GitLocator(url: value) }
        let path = String(value[value.index(after: colon)...]).replacingOccurrences(of: ".git", with: "")
        let parts = path.split(separator: "/").map(String.init)
        if parts.count >= 2, value.contains("github.com") {
            return GitLocator(url: value, subpath: parts.count > 2 ? parts.dropFirst(2).joined(separator: "/") : nil)
        }
        return GitLocator(url: value)
    }

    private static func parseShortGitHub(_ value: String, skillName: String) -> GitLocator? {
        let parts = value.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let ident = try! NSRegularExpression(pattern: "^[A-Za-z0-9_.-]+$")
        let owner = parts[0]
        let repo = parts[1].replacingOccurrences(of: ".git", with: "")
        let ownerRange = NSRange(owner.startIndex..., in: owner)
        let repoRange = NSRange(repo.startIndex..., in: repo)
        guard ident.firstMatch(in: owner, range: ownerRange) != nil,
              ident.firstMatch(in: repo, range: repoRange) != nil
        else { return nil }
        var subpath = parts.count > 2 ? parts.dropFirst(2).joined(separator: "/") : nil
        if subpath == nil, !skillName.isEmpty {
            subpath = nil
        }
        return GitLocator(url: "https://github.com/\(owner)/\(repo).git", subpath: subpath)
    }

    private static func githubOwnerRepo(_ locator: String) -> (owner: String, repo: String)? {
        var path = locator
        if path.hasPrefix("git@github.com:") {
            path = String(path.dropFirst("git@github.com:".count))
        } else if let url = URL(string: path), url.host?.contains("github.com") == true {
            path = url.path
        } else if path.contains("github.com/") {
            path = String(path.split(separator: "github.com/").last ?? "")
        } else {
            return nil
        }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let repo = parts[1].replacingOccurrences(of: ".git", with: "")
        return (parts[0], repo)
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

    private static func pluginPinnedRef(path: String) -> String? {
        let posix = path.replacingOccurrences(of: "\\", with: "/")
        let pattern = try! NSRegularExpression(pattern: "/\\.cursor/plugins/(?:cache/)?[^/]+/[^/]+/([a-f0-9]{8,40})(?:/|$)")
        let range = NSRange(posix.startIndex..., in: posix)
        if let match = pattern.firstMatch(in: posix, range: range),
           let r = Range(match.range(at: 1), in: posix)
        {
            return String(posix[r])
        }
        return nil
    }
}
