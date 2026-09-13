import Foundation
import XCTest
@testable import SkillManagerCore

final class LibraryLoadTests: XCTestCase {
    private var temps: [URL] = []
    private var sessions: [LibrarySession] = []

    override func tearDown() {
        super.tearDown()
        for session in sessions {
            SkillLibrary.close(session)
        }
        sessions.removeAll()
        for url in temps {
            try? FileManager.default.removeItem(at: url)
        }
        temps.removeAll()
    }

    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("skill-library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temps.append(url)
        return url
    }

    func writeSkill(dir: URL, name: String, description: String, extraFile: String? = nil) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = "---\nname: \(name)\ndescription: \(description)\n---\n\n# \(name)\n\nDo the thing.\n"
        try body.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        if let extraFile {
            let extra = dir.appendingPathComponent(extraFile)
            try FileManager.default.createDirectory(at: extra.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "script\n".write(to: extra, atomically: true, encoding: .utf8)
        }
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

    func libraryRepo() throws -> URL {
        let root = try tempDir()
        let upstream = root.appendingPathComponent("skills-lib")
        try writeSkill(
            dir: upstream.appendingPathComponent("skills/alpha"),
            name: "alpha",
            description: "Alpha skill.",
            extraFile: "scripts/run.sh"
        )
        try writeSkill(dir: upstream.appendingPathComponent("skills/beta"), name: "beta", description: "Beta skill.")
        try writeSkill(
            dir: upstream.appendingPathComponent("skills/alpha/examples/nested"),
            name: "nested",
            description: "Should not be loaded as its own skill."
        )
        try git(["init", "-b", "main"], cwd: upstream)
        try commitAll(cwd: upstream, message: "init")
        return upstream
    }

    @discardableResult
    func preview(_ url: String) -> LibraryPreviewResult {
        let result = SkillLibrary.preview(url: url)
        if let session = result.session {
            sessions.append(session)
        }
        return result
    }

    func testPreviewListsLibrarySkillsAndIgnoresNestedExamples() throws {
        let upstream = try libraryRepo()
        let result = preview(upstream.path)
        XCTAssertTrue(result.ok, result.error ?? "")
        let names = result.session?.skills.map(\.name).sorted()
        XCTAssertEqual(names, ["alpha", "beta"])
        XCTAssertEqual(result.session?.skills.first { $0.name == "alpha" }?.description, "Alpha skill.")
        XCTAssertEqual(result.session?.skills.first { $0.name == "alpha" }?.subpath, "skills/alpha")
        XCTAssertNotNil(result.session?.revision)
    }

    func testPreviewOfASkillSubpathFindsOnlyThatSkill() throws {
        let upstream = try libraryRepo()
        let result = preview(upstream.appendingPathComponent("skills/beta").path)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.session?.skills.map(\.name), ["beta"])
    }

    func testPreviewOfASingleSkillRepoUsesTheRepoName() throws {
        let root = try tempDir()
        let upstream = root.appendingPathComponent("frontend-design")
        try writeSkill(dir: upstream, name: "frontend-design", description: "Distinctive UI.")
        try git(["init", "-b", "main"], cwd: upstream)
        try commitAll(cwd: upstream, message: "init")

        let result = preview(upstream.path)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.session?.skills.map(\.name), ["frontend-design"])
        XCTAssertEqual(result.session?.skills.first?.subpath, "")
    }

    func testLoadEverywherePutsARealCopyInSharedAndLinksClaude() throws {
        let upstream = try libraryRepo()
        let home = try tempDir()
        let previewed = preview(upstream.path)
        guard let session = previewed.session else {
            return XCTFail(previewed.error ?? "no session")
        }

        let loaded = SkillLibrary.load(
            session: session,
            selecting: Set(session.skills.map(\.id)),
            homeDir: home.path,
            target: .everywhere
        )
        XCTAssertTrue(loaded.ok, loaded.error ?? "")
        XCTAssertEqual(loaded.loadedCount, 2)

        let alpha = home.appendingPathComponent(".agents/skills/alpha")
        XCTAssertTrue(FileManager.default.fileExists(atPath: alpha.appendingPathComponent("SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: alpha.appendingPathComponent("scripts/run.sh").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: alpha.appendingPathComponent(".git").path))

        let claude = home.appendingPathComponent(".claude/skills/alpha")
        XCTAssertEqual(
            URL(fileURLWithPath: claude.path).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: alpha.path).resolvingSymlinksInPath().path
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".cursor/skills/alpha").path))

        let originKey = SkillOrigins.originKey(realPath: alpha.path, homeDir: home.path)
        XCTAssertEqual(loaded.assignedOrigins[originKey]?.subpath, "skills/alpha")
        XCTAssertEqual(loaded.assignedOrigins[originKey]?.locator, previewed.session?.locator.url)

        var options = ScanOptions(homeDir: home.path)
        options.assignedOrigins = loaded.assignedOrigins
        let inventory = InventoryBuilder.build(options)
        let group = inventory.groups.first { $0.name == "alpha" }
        XCTAssertNotNil(group)
        XCTAssertTrue(group?.inShared == true)
        XCTAssertEqual(Set(group?.harnesses ?? []), Set(HarnessID.allCases))
        XCTAssertEqual(group?.copies.first { $0.location.id == "agents-user" }?.origin.kind, .remote)
    }

    func testLoadIntoOneHarnessDoesNotTouchSharedGlobal() throws {
        let upstream = try libraryRepo()
        let home = try tempDir()
        let previewed = preview(upstream.path)
        guard let session = previewed.session else {
            return XCTFail(previewed.error ?? "no session")
        }

        let loaded = SkillLibrary.load(
            session: session,
            selecting: ["skills/beta"],
            homeDir: home.path,
            target: .harness(.gemini)
        )
        XCTAssertTrue(loaded.ok, loaded.error ?? "")
        XCTAssertEqual(loaded.loadedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".gemini/skills/beta/SKILL.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".agents/skills/beta").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/skills/beta").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".gemini/skills/alpha").path))

        let inventory = InventoryBuilder.build(ScanOptions(homeDir: home.path))
        let group = inventory.groups.first { $0.name == "beta" }
        XCTAssertEqual(group?.harnesses, [.gemini])
        XCTAssertEqual(group?.inShared, false)
    }

    func testLoadSkipsASkillThatAlreadyExists() throws {
        let upstream = try libraryRepo()
        let home = try tempDir()
        try writeSkill(dir: home.appendingPathComponent(".agents/skills/alpha"), name: "alpha", description: "Already here.")
        let previewed = preview(upstream.path)
        guard let session = previewed.session else {
            return XCTFail(previewed.error ?? "no session")
        }

        let loaded = SkillLibrary.load(
            session: session,
            selecting: ["skills/alpha"],
            homeDir: home.path,
            target: .everywhere
        )
        XCTAssertTrue(loaded.ok, loaded.error ?? "")
        XCTAssertEqual(loaded.loadedCount, 0)
        XCTAssertEqual(loaded.items.first?.status, .alreadyPresent)
        let body = try String(contentsOf: home.appendingPathComponent(".agents/skills/alpha/SKILL.md"), encoding: .utf8)
        XCTAssertTrue(body.contains("Already here."))
    }

    func testPreviewFailsOnAnEmptyRepo() throws {
        let root = try tempDir()
        let upstream = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: upstream, withIntermediateDirectories: true)
        try "readme\n".write(to: upstream.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try git(["init", "-b", "main"], cwd: upstream)
        try commitAll(cwd: upstream, message: "init")

        let result = preview(upstream.path)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("No SKILL.md") == true)
    }

    func testPreviewFailsOnUnparseableURL() {
        let result = preview("not a repo")
        XCTAssertFalse(result.ok)
        XCTAssertNil(result.session)
    }
}
