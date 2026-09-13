import CryptoKit
import Foundation

public enum SkillDiscovery {
    private static let ignoreDirs: Set<String> = [
        "node_modules", ".git", ".hg", ".svn", "dist", "build",
        ".next", ".turbo", ".nuxt", ".output", ".venv", "venv",
        "__pycache__", ".cache", "coverage", ".pnpm-store",
        "Library", "AppData", ".Trash",
    ]
    private static let maxWalkDepth = 14

    public static func discoverSkills(options: ScanOptions) -> [SkillCopy] {
        let files = collectSkillFiles(options: options)
        var copies: [SkillCopy] = []
        var seenReal = Set<String>()
        let extraDirs = (extraGrokSkillPaths(homeDir: options.homeDir) + options.extraSkillDirs)
            .map { expandHome($0, homeDir: options.homeDir) }

        for skillFile in files {
            do {
                let copy = try readSkillCopy(
                    skillFile: skillFile,
                    homeDir: options.homeDir,
                    extraSkillDirs: extraDirs,
                    assignedOrigins: options.assignedOrigins
                )
                let seenKey = copy.realPath + "::" + copy.skillFile
                if seenReal.contains(seenKey) { continue }
                seenReal.insert(seenKey)
                copies.append(copy)
            } catch {
                let folder = URL(fileURLWithPath: skillFile).deletingLastPathComponent().lastPathComponent
                let skillDir = URL(fileURLWithPath: skillFile).deletingLastPathComponent().path
                let location = classifyLocation(skillFile: skillFile, homeDir: options.homeDir, extraSkillDirs: extraDirs)
                copies.append(
                    SkillCopy(
                        key: skillFile,
                        name: folder.isEmpty ? "unknown" : folder,
                        folderName: folder.isEmpty ? "unknown" : folder,
                        description: "",
                        skillDir: skillDir,
                        skillFile: skillFile,
                        homeRelative: skillFile,
                        realPath: skillFile,
                        isSymlink: false,
                        symlinkTarget: nil,
                        contentHash: "",
                        mtimeMs: 0,
                        bytes: 0,
                        fileCount: 1,
                        hasScripts: false,
                        hasReferences: false,
                        hasAssets: false,
                        extraFiles: [],
                        errors: ["unreadable", error.localizedDescription],
                        disableModelInvocation: false,
                        location: location,
                        origin: SkillOrigins.infer(
                            skillDir: skillDir,
                            location: location,
                            homeDir: options.homeDir,
                            assigned: options.assignedOrigins
                        ),
                        meta: SkillMeta(
                            name: "unknown",
                            description: "",
                            disableModelInvocation: false,
                            userInvocable: nil,
                            paths: [],
                            whenToUse: "",
                            license: "",
                            compatibility: "",
                            metadata: [:]
                        )
                    )
                )
            }
        }

        copies.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
                || ($0.name == $1.name && $0.skillDir.localizedStandardCompare($1.skillDir) == .orderedAscending)
        }
        return copies
    }

    public static func collectSkillFiles(options: ScanOptions) -> [String] {
        var found = Set<String>()
        let add: (String) -> Void = { file in
            if isSkillMarkdown(file) { found.insert(file) }
        }

        for loc in Harnesses.userLocations {
            guard let homeRel = loc.homeRel else { continue }
            if loc.scope == .builtin && !options.includeBuiltins { continue }
            walkForSkillFiles(Harnesses.userSkillDir(homeDir: options.homeDir, homeRel: homeRel), add: add, depth: 0, visited: [])
        }

        walkForSkillFiles(Harnesses.archiveDir(homeDir: options.homeDir), add: add, depth: 0, visited: [])

        if options.includePlugins {
            walkForSkillFiles(
                (options.homeDir as NSString).appendingPathComponent(".cursor/plugins"),
                add: add,
                depth: 0,
                visited: []
            )
            walkForSkillFiles(
                (options.homeDir as NSString).appendingPathComponent(".claude/plugins"),
                add: add,
                depth: 0,
                visited: []
            )
        }

        let grokExtras = extraGrokSkillPaths(homeDir: options.homeDir)
        for extra in grokExtras + options.extraSkillDirs {
            walkForSkillFiles(expandHome(extra, homeDir: options.homeDir), add: add, depth: 0, visited: [])
        }

        let fm = FileManager.default
        for root in options.scanRoots {
            if root.isEmpty { continue }
            let abs = expandHome(root, homeDir: options.homeDir)
            if !fm.fileExists(atPath: abs) { continue }
            if samePath(abs, options.homeDir) { continue }
            if abs == "/" { continue }
            walkProjectSkillRoots(abs, add: add, depth: 0, visited: [])
        }

        return found.sorted()
    }

    public static func extraGrokSkillPaths(homeDir: String) -> [String] {
        let configPath = (homeDir as NSString).appendingPathComponent(".grok/config.toml")
        guard let text = try? String(contentsOfFile: configPath, encoding: .utf8) else { return [] }
        guard let header = text.range(of: "[skills]", options: [.caseInsensitive]) else { return [] }
        let after = text[header.upperBound...]
        let section: Substring
        if let next = after.range(of: "\n[") {
            section = after[..<next.lowerBound]
        } else {
            section = after
        }
        let quoted = try! NSRegularExpression(pattern: "[\"']([^\"']+)[\"']")
        let str = String(section)
        let range = NSRange(str.startIndex..., in: str)
        return quoted.matches(in: str, range: range).compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: str) else { return nil }
            let value = String(str[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { return nil }
            return value
        }
    }

    public static func classifyLocation(skillFile: String, homeDir: String, extraSkillDirs: [String] = []) -> SkillLocation {
        let posix = skillFile.replacingOccurrences(of: "\\", with: "/")
        let homePrefix = homeDir.replacingOccurrences(of: "\\", with: "/")
        let homeBase = homePrefix.hasSuffix("/") ? String(homePrefix.dropLast()) : homePrefix

        if let plugin = classifyPlugin(skillFile: skillFile, posix: posix, homePosix: homeBase) {
            return plugin
        }

        let archive = Harnesses.archiveDir(homeDir: homeDir).replacingOccurrences(of: "\\", with: "/")
        if posix == archive || posix.hasPrefix(archive + "/") {
            return SkillLocation(
                id: "archive",
                label: "Archived · ~/.config/skill-manager/archive",
                scope: .archived,
                shared: false,
                harnesses: []
            )
        }

        let userLocs = Harnesses.userLocations.sorted { ($0.homeRel?.count ?? 0) > ($1.homeRel?.count ?? 0) }
        for loc in userLocs {
            guard let homeRel = loc.homeRel else { continue }
            let abs = Harnesses.userSkillDir(homeDir: homeDir, homeRel: homeRel).replacingOccurrences(of: "\\", with: "/")
            if posix == abs || posix.hasPrefix(abs + "/") {
                return SkillLocation(
                    id: loc.id,
                    label: loc.label,
                    scope: loc.scope,
                    shared: loc.shared,
                    harnesses: loc.harnesses
                )
            }
        }

        let grokExtraRoot = (homeDir as NSString).appendingPathComponent(".grok").replacingOccurrences(of: "\\", with: "/")
        if posix.hasPrefix(grokExtraRoot + "/") && posix.contains("/skills/") {
            return SkillLocation(id: "grok-extra", label: "Grok extra path", scope: .user, shared: false, harnesses: [.grok])
        }

        for extra in extraSkillDirs {
            let extraPosix = extra.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let extraNorm = extra.replacingOccurrences(of: "\\", with: "/")
            if posix == extraNorm || posix.hasPrefix(extraNorm + "/") || posix == extraPosix || posix.hasPrefix(extraPosix + "/") {
                return SkillLocation(id: "grok-extra", label: "Grok extra path", scope: .user, shared: false, harnesses: [.grok])
            }
        }

        for loc in Harnesses.projectLocations {
            guard let needle = loc.projectNeedle else { continue }
            if let idx = posix.range(of: needle) {
                let root = String(posix[..<idx.lowerBound]).replacingOccurrences(of: "/", with: "/")
                return SkillLocation(
                    id: loc.id,
                    label: loc.label,
                    scope: .project,
                    shared: loc.shared,
                    harnesses: loc.harnesses,
                    projectRoot: root
                )
            }
        }

        return SkillLocation(id: "unknown", label: "Unknown location", scope: .unknown, shared: false, harnesses: [])
    }

    public static func readSkillCopy(
        skillFile: String,
        homeDir: String,
        extraSkillDirs: [String] = [],
        assignedOrigins: [String: AssignedOrigin] = [:]
    ) throws -> SkillCopy {
        let skillDir = URL(fileURLWithPath: skillFile).deletingLastPathComponent().path
        let folderName = URL(fileURLWithPath: skillDir).lastPathComponent
        let raw = try String(contentsOfFile: skillFile, encoding: .utf8)
        let parsed = SkillParser.parse(content: raw, folderName: folderName)
        let fm = FileManager.default
        let fileAttrs = try fm.attributesOfItem(atPath: skillFile)
        let dirAttrs = try fm.attributesOfItem(atPath: skillDir)
        let realPath = safeRealpath(skillDir) ?? skillDir
        let isSymlink = (dirAttrs[.type] as? FileAttributeType) == .typeSymbolicLink
            || (fileAttrs[.type] as? FileAttributeType) == .typeSymbolicLink
        let listing = listSkillTree(skillDir)
        let mtime = (fileAttrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let location = classifyLocation(skillFile: skillFile, homeDir: homeDir, extraSkillDirs: extraSkillDirs)

        return SkillCopy(
            key: skillFile,
            name: parsed.meta.name,
            folderName: folderName,
            description: parsed.meta.description,
            skillDir: skillDir,
            skillFile: skillFile,
            homeRelative: toHomeRelative(skillDir, homeDir: homeDir),
            realPath: realPath,
            isSymlink: isSymlink,
            symlinkTarget: isSymlink ? safeRealpath(skillDir) : nil,
            contentHash: sha256(raw.replacingOccurrences(of: "\r\n", with: "\n")),
            mtimeMs: mtime * 1000,
            bytes: raw.utf8.count,
            fileCount: listing.fileCount,
            hasScripts: listing.hasScripts,
            hasReferences: listing.hasReferences,
            hasAssets: listing.hasAssets,
            extraFiles: listing.extraFiles,
            errors: parsed.errors,
            disableModelInvocation: parsed.meta.disableModelInvocation,
            location: location,
            origin: SkillOrigins.infer(
                skillDir: realPath,
                location: location,
                homeDir: homeDir,
                assigned: assignedOrigins
            ),
            meta: parsed.meta
        )
    }

    private static func walkProjectSkillRoots(_ dir: String, add: (String) -> Void, depth: Int, visited: Set<String>) {
        if depth > maxWalkDepth { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
        var visited = visited

        for name in entries {
            let full = (dir as NSString).appendingPathComponent(name)
            var isDir = false
            if let attrs = try? fm.attributesOfItem(atPath: full),
               let type = attrs[.type] as? FileAttributeType
            {
                if type == .typeSymbolicLink {
                    let dest = URL(fileURLWithPath: full).resolvingSymlinksInPath().path
                    if let destAttrs = try? fm.attributesOfItem(atPath: dest),
                       let destType = destAttrs[.type] as? FileAttributeType
                    {
                        isDir = destType == .typeDirectory
                    }
                } else {
                    isDir = type == .typeDirectory
                }
            }
            if !isDir { continue }
            if ignoreDirs.contains(name) { continue }

            if Harnesses.projectSkillParents.contains(name) {
                let skillsDir = (full as NSString).appendingPathComponent("skills")
                if fm.fileExists(atPath: skillsDir) {
                    walkForSkillFiles(skillsDir, add: add, depth: 0, visited: [])
                }
                continue
            }

            if let real = safeRealpath(full) {
                if visited.contains(real) { continue }
                visited.insert(real)
            }
            walkProjectSkillRoots(full, add: add, depth: depth + 1, visited: visited)
        }
    }

    @discardableResult
    private static func walkForSkillFiles(_ dir: String, add: (String) -> Void, depth: Int, visited: Set<String>) -> Set<String> {
        if depth > maxWalkDepth { return visited }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir, isDirectory: &isDir) else { return visited }
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return visited }
        var visited = visited

        for name in entries {
            let full = (dir as NSString).appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let type = attrs[.type] as? FileAttributeType
            else { continue }

            if type == .typeSymbolicLink {
                let dest = URL(fileURLWithPath: full).resolvingSymlinksInPath().path
                let destAttrs = try? fm.attributesOfItem(atPath: dest)
                let destType = destAttrs?[.type] as? FileAttributeType
                if destType == .typeRegular && isSkillMarkdown(full) {
                    add(full)
                } else if destType == .typeDirectory {
                    if let real = safeRealpath(full) {
                        if visited.contains(real) { continue }
                        visited.insert(real)
                    }
                    if !ignoreDirs.contains(name) {
                        visited = walkForSkillFiles(full, add: add, depth: depth + 1, visited: visited)
                    }
                }
                continue
            }
            if type == .typeRegular && isSkillMarkdown(full) {
                add(full)
                continue
            }
            if type == .typeDirectory {
                if ignoreDirs.contains(name) { continue }
                if let real = safeRealpath(full) {
                    if visited.contains(real) { continue }
                    visited.insert(real)
                }
                visited = walkForSkillFiles(full, add: add, depth: depth + 1, visited: visited)
            }
        }
        return visited
    }

    private static func classifyPlugin(skillFile: String, posix: String, homePosix: String) -> SkillLocation? {
        let cursorPlugins = homePosix + "/.cursor/plugins/"
        if posix.hasPrefix(cursorPlugins) {
            let meta = readNearestPluginJson(startDir: URL(fileURLWithPath: skillFile).deletingLastPathComponent().path)
            let label = meta?.name.map { "Cursor plugin · \($0)" } ?? "Cursor plugin"
            return SkillLocation(
                id: "cursor-plugin",
                label: label,
                scope: .plugin,
                shared: false,
                harnesses: [.cursor],
                pluginName: meta?.name,
                pluginAuthor: meta?.author
            )
        }
        let claudePlugins = homePosix + "/.claude/plugins/"
        if posix.hasPrefix(claudePlugins) {
            return SkillLocation(
                id: "claude-plugin",
                label: "Claude plugin",
                scope: .plugin,
                shared: false,
                harnesses: [.claude, .grok]
            )
        }
        return nil
    }

    private static func readNearestPluginJson(startDir: String) -> (name: String?, author: String?)? {
        var dir = startDir
        for _ in 0..<12 {
            for candidate in [
                (dir as NSString).appendingPathComponent(".cursor-plugin/plugin.json"),
                (dir as NSString).appendingPathComponent(".claude-plugin/plugin.json"),
            ] {
                guard FileManager.default.fileExists(atPath: candidate),
                      let data = try? Data(contentsOf: URL(fileURLWithPath: candidate)),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                let author: String?
                if let s = json["author"] as? String {
                    author = s
                } else if let obj = json["author"] as? [String: Any] {
                    author = obj["name"] as? String
                } else {
                    author = nil
                }
                return (json["name"] as? String, author)
            }
            let parent = URL(fileURLWithPath: dir).deletingLastPathComponent().path
            if parent == dir { break }
            dir = parent
        }
        return nil
    }

    private static func listSkillTree(_ skillDir: String) -> (fileCount: Int, hasScripts: Bool, hasReferences: Bool, hasAssets: Bool, extraFiles: [String]) {
        var extraFiles: [String] = []
        var fileCount = 0
        var hasScripts = false
        var hasReferences = false
        var hasAssets = false
        let fm = FileManager.default

        func visit(_ dir: String, rel: String, depth: Int) {
            if depth > 6 { return }
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for name in entries {
                let relPath = rel.isEmpty ? name : "\(rel)/\(name)"
                let full = (dir as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: full, isDirectory: &isDir)
                if isDir.boolValue {
                    if name == "scripts" { hasScripts = true }
                    if name == "references" { hasReferences = true }
                    if name == "assets" { hasAssets = true }
                    if !ignoreDirs.contains(name) { visit(full, rel: relPath, depth: depth + 1) }
                } else if fm.fileExists(atPath: full) {
                    fileCount += 1
                    if name.lowercased() != "skill.md" {
                        extraFiles.append(relPath)
                    }
                }
            }
        }

        visit(skillDir, rel: "", depth: 0)
        extraFiles.sort()
        return (fileCount, hasScripts, hasReferences, hasAssets, Array(extraFiles.prefix(40)))
    }

    private static func isSkillMarkdown(_ file: String) -> Bool {
        URL(fileURLWithPath: file).lastPathComponent.lowercased() == "skill.md"
    }

    private static func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func safeRealpath(_ path: String) -> String? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return FileManager.default.fileExists(atPath: resolved) ? resolved : nil
    }

    private static func toHomeRelative(_ path: String, homeDir: String) -> String {
        if path == homeDir || path.hasPrefix(homeDir + "/") {
            return "~" + String(path.dropFirst(homeDir.count)).replacingOccurrences(of: "\\", with: "/")
        }
        return path.replacingOccurrences(of: "\\", with: "/")
    }

    public static func expandHome(_ path: String, homeDir: String) -> String {
        if path == "~" { return homeDir }
        if path.hasPrefix("~/") {
            return (homeDir as NSString).appendingPathComponent(String(path.dropFirst(2)))
        }
        return path
    }

    private static func samePath(_ a: String, _ b: String) -> Bool {
        if let ra = safeRealpath(a), let rb = safeRealpath(b) {
            return ra == rb
        }
        return (a as NSString).standardizingPath == (b as NSString).standardizingPath
    }
}
