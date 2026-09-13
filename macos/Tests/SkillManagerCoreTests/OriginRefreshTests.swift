import Foundation
import XCTest
@testable import SkillManagerCore

final class OriginRefreshTests: XCTestCase {
    private var temps: [URL] = []

    override func tearDown() {
        super.tearDown()
        for url in temps {
            try? FileManager.default.removeItem(at: url)
        }
        temps.removeAll()
    }

    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("skill-origin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temps.append(url)
        return url
    }

    func writeSkill(dir: URL, name: String, description: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = "---\nname: \(name)\ndescription: \(description)\n---\n\n# \(name)\n\nDo the thing.\n"
        try body.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    func git(_ args: [String], cwd: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["git"] + args
        proc.currentDirectoryURL = cwd
        proc.environment = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/opt/homebrew/bin",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": "Skill Manager Test",
            "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Skill Manager Test",
            "GIT_COMMITTER_EMAIL": "test@example.com",
            "HOME": cwd.path,
        ]
        let err = Pipe()
        proc.standardError = err
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "git", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func commitAll(cwd: URL, message: String) throws {
        try git(["add", "-A"], cwd: cwd)
        try git(["-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-m", message], cwd: cwd)
    }

    func testParsesGitHubWebAndShortLocators() {
        let tree = SkillOrigins.parseLocator("https://github.com/anthropics/skills/tree/main/skills/frontend-design")
        XCTAssertEqual(tree?.url, "https://github.com/anthropics/skills.git")
        XCTAssertEqual(tree?.subpath, "skills/frontend-design")
        XCTAssertEqual(tree?.ref, "main")

        let blob = SkillOrigins.parseLocator("https://github.com/anthropics/skills/blob/main/skills/tdd/SKILL.md")
        XCTAssertEqual(blob?.subpath, "skills/tdd")

        let short = SkillOrigins.parseLocator("cloudflare/skills/skills/wrangler")
        XCTAssertEqual(short?.url, "https://github.com/cloudflare/skills.git")
        XCTAssertEqual(short?.subpath, "skills/wrangler")

        let ssh = SkillOrigins.parseLocator("git@github.com:cloudflare/skills.git")
        XCTAssertEqual(ssh?.url, "git@github.com:cloudflare/skills.git")
        XCTAssertEqual(SkillOrigins.displayLabel(ssh!.url), "GitHub · cloudflare/skills")
    }

    func testParsesLocalGitCheckoutAsRepoPlusSubpath() throws {
        let root = try tempDir()
        let upstream = root.appendingPathComponent("lib")
        try writeSkill(dir: upstream.appendingPathComponent("skills/demo"), name: "demo", description: "Demo.")
        try git(["init", "-b", "main"], cwd: upstream)
        try commitAll(cwd: upstream, message: "init")

        let parsed = SkillOrigins.parseLocator(upstream.appendingPathComponent("skills/demo").path)
        XCTAssertEqual(parsed?.subpath, "skills/demo")
        XCTAssertTrue(parsed?.url.contains("lib") == true)

        let rootParsed = SkillOrigins.parseLocator(upstream.path)
        XCTAssertNil(rootParsed?.subpath)
    }

    func testInfersGitOriginFromClone() throws {
        let root = try tempDir()
        let upstream = root.appendingPathComponent("upstream")
        try writeSkill(dir: upstream.appendingPathComponent("skills/demo"), name: "demo", description: "Original.")
        try git(["init", "-b", "main"], cwd: upstream)
        try commitAll(cwd: upstream, message: "init")

        let clone = root.appendingPathComponent("clone")
        try git(["clone", upstream.path, clone.path], cwd: root)
        let skillDir = clone.appendingPathComponent("skills/demo").path
        let origin = SkillOrigins.infer(
            skillDir: skillDir,
            location: SkillLocation(id: "agents-user", label: "Shared global", scope: .user, shared: true, harnesses: [.cursor]),
            homeDir: root.path
        )
        XCTAssertEqual(origin.kind, .git)
        XCTAssertEqual(origin.subpath, "skills/demo")
        XCTAssertNotNil(origin.locator)
        XCTAssertTrue(origin.refreshable)
        XCTAssertEqual(origin.pinnedRef?.count, 40)
    }

    func testInfersAssignedGitHubForLocalCopy() throws {
        let home = try tempDir()
        let skill = home.appendingPathComponent(".agents/skills/tdd")
        try writeSkill(dir: skill, name: "tdd", description: "TDD.")
        let assigned = [
            SkillOrigins.originKey(realPath: skill.path, homeDir: home.path): AssignedOrigin(
                locator: "https://github.com/mattpocock/skills.git",
                subpath: "tdd"
            ),
        ]
        let origin = SkillOrigins.infer(
            skillDir: skill.path,
            location: SkillLocation(id: "agents-user", label: "Shared global", scope: .user, shared: true, harnesses: [.cursor]),
            homeDir: home.path,
            assigned: assigned
        )
        XCTAssertEqual(origin.kind, .remote)
        XCTAssertEqual(origin.label, "GitHub · mattpocock/skills")
        XCTAssertEqual(origin.subpath, "tdd")
        XCTAssertTrue(origin.refreshable)
    }

    func testBuiltinAndPluginAreNotRefreshable() throws {
        let home = try tempDir()
        let builtin = home.appendingPathComponent(".cursor/skills-cursor/canvas")
        try writeSkill(dir: builtin, name: "canvas", description: "Built-in.")
        let builtinOrigin = SkillOrigins.infer(
            skillDir: builtin.path,
            location: SkillLocation(id: "cursor-builtin", label: "Cursor built-in", scope: .builtin, shared: false, harnesses: [.cursor]),
            homeDir: home.path
        )
        XCTAssertEqual(builtinOrigin.kind, .builtin)
        XCTAssertFalse(builtinOrigin.refreshable)

        let plugin = home.appendingPathComponent(".cursor/plugins/cache/cursor-public/azure/9d86ae4a15bcbc82bd49d908c050638d99d02e38/skills/rbac")
        try writeSkill(dir: plugin, name: "rbac", description: "RBAC.")
        let pluginOrigin = SkillOrigins.infer(
            skillDir: plugin.path,
            location: SkillLocation(
                id: "cursor-plugin",
                label: "Cursor plugin · azure",
                scope: .plugin,
                shared: false,
                harnesses: [.cursor],
                pluginName: "azure"
            ),
            homeDir: home.path
        )
        XCTAssertEqual(pluginOrigin.kind, .plugin)
        XCTAssertEqual(pluginOrigin.pinnedRef, "9d86ae4a15bcbc82bd49d908c050638d99d02e38")
        XCTAssertFalse(pluginOrigin.refreshable)
        XCTAssertEqual(SkillRefresh.inspect(origin: pluginOrigin).state, .notRefreshable)
    }

    func testRefreshPullsGitCheckoutWhenUpstreamMoves() throws {
        let root = try tempDir()
        let upstream = root.appendingPathComponent("upstream")
        try writeSkill(dir: upstream.appendingPathComponent("skills/demo"), name: "demo", description: "Original.")
        try git(["init", "-b", "main"], cwd: upstream)
        try commitAll(cwd: upstream, message: "init")

        let clone = root.appendingPathComponent("clone")
        try git(["clone", upstream.path, clone.path], cwd: root)
        let skillDir = clone.appendingPathComponent("skills/demo")

        var origin = SkillOrigins.infer(
            skillDir: skillDir.path,
            location: SkillLocation(id: "user", label: "User", scope: .user, shared: false, harnesses: [.cursor]),
            homeDir: root.path
        )
        XCTAssertEqual(SkillRefresh.inspect(origin: origin).state, .current)

        try writeSkill(dir: upstream.appendingPathComponent("skills/demo"), name: "demo", description: "Updated copy.")
        try commitAll(cwd: upstream, message: "update")

        let inspection = SkillRefresh.inspect(origin: origin)
        XCTAssertEqual(inspection.state, .updateAvailable)

        let result = SkillRefresh.apply(skillDir: skillDir.path, origin: origin)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.action, .updated)
        let body = try String(contentsOf: skillDir.appendingPathComponent("SKILL.md"), encoding: .utf8)
        XCTAssertTrue(body.contains("Updated copy."))

        origin = SkillOrigins.infer(
            skillDir: skillDir.path,
            location: SkillLocation(id: "user", label: "User", scope: .user, shared: false, harnesses: [.cursor]),
            homeDir: root.path
        )
        XCTAssertEqual(SkillRefresh.inspect(origin: origin).state, .current)
    }

    func testRefreshCopiesFromAssignedRemoteWithoutLocalGit() throws {
        let root = try tempDir()
        let upstream = root.appendingPathComponent("upstream")
        try writeSkill(dir: upstream.appendingPathComponent("skills/demo"), name: "demo", description: "Original.")
        try git(["init", "-b", "main"], cwd: upstream)
        try commitAll(cwd: upstream, message: "init")

        let copy = root.appendingPathComponent("home/.agents/skills/demo")
        try writeSkill(dir: copy, name: "demo", description: "Stale local copy.")
        let origin = SkillOrigin(
            kind: .remote,
            label: "upstream",
            locator: upstream.path,
            subpath: "skills/demo"
        )
        try writeSkill(dir: upstream.appendingPathComponent("skills/demo"), name: "demo", description: "From remote.")
        try commitAll(cwd: upstream, message: "remote update")

        let result = SkillRefresh.apply(skillDir: copy.path, origin: origin)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.action, .updated)
        let body = try String(contentsOf: copy.appendingPathComponent("SKILL.md"), encoding: .utf8)
        XCTAssertTrue(body.contains("From remote."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.appendingPathComponent(".git").path))
    }

    func testRefreshRefusesDirtyGitCheckout() throws {
        let root = try tempDir()
        let upstream = root.appendingPathComponent("upstream")
        try writeSkill(dir: upstream.appendingPathComponent("skills/demo"), name: "demo", description: "Original.")
        try git(["init", "-b", "main"], cwd: upstream)
        try commitAll(cwd: upstream, message: "init")
        let clone = root.appendingPathComponent("clone")
        try git(["clone", upstream.path, clone.path], cwd: root)
        let skillDir = clone.appendingPathComponent("skills/demo")
        try "dirty".write(to: skillDir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let origin = SkillOrigins.infer(
            skillDir: skillDir.path,
            location: SkillLocation(id: "user", label: "User", scope: .user, shared: false, harnesses: [.cursor]),
            homeDir: root.path
        )
        let result = SkillRefresh.apply(skillDir: skillDir.path, origin: origin)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("Local changes") == true)
    }

    func testInventoryAttachesOriginFromAssignedConfig() throws {
        let home = try tempDir()
        let skill = home.appendingPathComponent(".agents/skills/demo")
        try writeSkill(dir: skill, name: "demo", description: "Demo.")
        let options = ScanOptions(
            homeDir: home.path,
            assignedOrigins: [
                "~/.agents/skills/demo": AssignedOrigin(
                    locator: "https://github.com/example/skills.git",
                    subpath: "demo"
                ),
            ]
        )
        let inventory = InventoryBuilder.build(options)
        let copy = inventory.groups.first { $0.name == "demo" }?.copies.first
        XCTAssertEqual(copy?.origin.kind, .remote)
        XCTAssertEqual(copy?.origin.label, "GitHub · example/skills")
    }
}
