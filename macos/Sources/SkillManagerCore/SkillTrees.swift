import Foundation

enum SkillTrees {
    private static let ignoreDirs: Set<String> = [
        "node_modules", ".git", ".hg", ".svn", "dist", "build",
        ".next", ".turbo", ".nuxt", ".output", ".venv", "venv",
        "__pycache__", ".cache", "coverage", ".pnpm-store",
        ".github",
    ]

    static func copyExcludingGit(from source: String, to dest: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
        guard let entries = try? fm.contentsOfDirectory(atPath: source) else {
            throw GitError.failed("Could not read \(source)")
        }
        for name in entries where name != ".git" {
            let from = (source as NSString).appendingPathComponent(name)
            let to = (dest as NSString).appendingPathComponent(name)
            try fm.copyItem(atPath: from, toPath: to)
        }
    }

    /// Directories that contain SKILL.md. Does not walk into a skill folder, so example
    /// copies nested under a skill are not treated as a library of their own.
    static func skillDirs(in root: String) -> [String] {
        var found: [String] = []
        walk(root, depth: 0, into: &found)
        return found
    }

    private static func walk(_ dir: String, depth: Int, into found: inout [String]) {
        if depth > 12 { return }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return }
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
        if entries.contains(where: { $0.lowercased() == "skill.md" }) {
            found.append(dir)
            return
        }
        for name in entries {
            if ignoreDirs.contains(name) || name.hasPrefix(".") { continue }
            let child = (dir as NSString).appendingPathComponent(name)
            walk(child, depth: depth + 1, into: &found)
        }
    }
}
