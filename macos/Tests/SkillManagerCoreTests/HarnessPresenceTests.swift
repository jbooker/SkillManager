import Foundation
import XCTest
@testable import SkillManagerCore

final class HarnessPresenceTests: XCTestCase {
    private var temps: [URL] = []

    override func tearDown() {
        super.tearDown()
        for url in temps {
            try? FileManager.default.removeItem(at: url)
        }
        temps.removeAll()
    }

    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("skill-manager-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temps.append(url)
        return url
    }

    func detect(home: URL, apps: URL, path: URL, extraApps: [URL] = []) -> Set<HarnessID> {
        HarnessPresence.detect(
            homeDir: home.path,
            applicationsDirectories: [apps.path],
            pathDirectories: [path.path],
            extraApplicationPaths: extraApps.map(\.path)
        )
    }

    func testEmptyMachineHasNoHarnesses() throws {
        let home = try tempDir()
        let apps = try tempDir()
        let path = try tempDir()
        XCTAssertEqual(detect(home: home, apps: apps, path: path), [])
    }

    func testFindsCursorAppBundle() throws {
        let home = try tempDir()
        let apps = try tempDir()
        let path = try tempDir()
        try FileManager.default.createDirectory(at: apps.appendingPathComponent("Cursor.app"), withIntermediateDirectories: true)
        XCTAssertEqual(detect(home: home, apps: apps, path: path), [.cursor])
    }

    func testFindsClaudeFromHomeLocalBin() throws {
        let home = try tempDir()
        let apps = try tempDir()
        let path = try tempDir()
        let claude = home.appendingPathComponent(".local/bin/claude")
        try FileManager.default.createDirectory(at: claude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cli".utf8).write(to: claude)
        XCTAssertEqual(detect(home: home, apps: apps, path: path), [.claude])
    }

    func testFindsGrokFromGrokBinNotGrokBotApp() throws {
        let home = try tempDir()
        let apps = try tempDir()
        let path = try tempDir()
        try FileManager.default.createDirectory(at: apps.appendingPathComponent("Grok Bot.app"), withIntermediateDirectories: true)
        XCTAssertEqual(detect(home: home, apps: apps, path: path), [])

        let grok = home.appendingPathComponent(".grok/bin/grok")
        try FileManager.default.createDirectory(at: grok.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cli".utf8).write(to: grok)
        XCTAssertEqual(detect(home: home, apps: apps, path: path), [.grok])
    }

    func testConfigDirectoryAloneDoesNotCountAsInstalled() throws {
        let home = try tempDir()
        let apps = try tempDir()
        let path = try tempDir()
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".gemini"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".config/opencode"), withIntermediateDirectories: true)
        XCTAssertEqual(detect(home: home, apps: apps, path: path), [])
    }

    func testFindsCodexInsideChatGPTAppByBundleID() throws {
        let home = try tempDir()
        let apps = try tempDir()
        let path = try tempDir()
        let chatgpt = apps.appendingPathComponent("ChatGPT.app")
        let info = chatgpt.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.openai.codex</string>
        </dict>
        </plist>
        """.write(to: info.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        XCTAssertEqual(detect(home: home, apps: apps, path: path), [.codex])
    }

    func testFindsGeminiAndOpenCodeBinariesOnPath() throws {
        let home = try tempDir()
        let apps = try tempDir()
        let path = try tempDir()
        try Data("cli".utf8).write(to: path.appendingPathComponent("gemini"))
        try Data("cli".utf8).write(to: path.appendingPathComponent("opencode"))
        XCTAssertEqual(detect(home: home, apps: apps, path: path), [.gemini, .opencode])
    }

    func testInventorySummariesOnlyIncludeInstalledHarnesses() throws {
        let home = try tempDir()
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".agents/skills/portable"), withIntermediateDirectories: true)
        try """
        ---
        name: portable
        description: Shared.
        ---

        # Portable
        """.write(to: home.appendingPathComponent(".agents/skills/portable/SKILL.md"), atomically: true, encoding: .utf8)

        let options = ScanOptions(
            homeDir: home.path,
            installedHarnesses: [.cursor, .claude]
        )
        let inventory = InventoryBuilder.build(options)
        XCTAssertEqual(inventory.harnesses.map(\.id), [.claude, .cursor])
        let cursor = inventory.harnesses.first { $0.id == .cursor }!
        XCTAssertTrue(cursor.uniqueNames.contains("portable"))
        let claude = inventory.harnesses.first { $0.id == .claude }!
        XCTAssertTrue(claude.missingNames.contains("portable"))
        XCTAssertTrue(inventory.issues.contains { $0.code == "claude-blind" && $0.skillName == "portable" })
    }

    func testClaudeBlindIssueOnlyWhenClaudeIsInstalled() throws {
        let home = try tempDir()
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".agents/skills/portable"), withIntermediateDirectories: true)
        try """
        ---
        name: portable
        description: Shared.
        ---

        # Portable
        """.write(to: home.appendingPathComponent(".agents/skills/portable/SKILL.md"), atomically: true, encoding: .utf8)

        var withClaude = ScanOptions(homeDir: home.path, installedHarnesses: [.cursor, .claude])
        XCTAssertTrue(InventoryBuilder.build(withClaude).issues.contains { $0.code == "claude-blind" })

        withClaude.installedHarnesses = [.cursor]
        XCTAssertFalse(InventoryBuilder.build(withClaude).issues.contains { $0.code == "claude-blind" })
    }

    func testUserFolderTargetsHideUninstalledHarnessesUnlessACopyExists() {
        XCTAssertEqual(
            UserFolderTarget.visible(installed: [.cursor]),
            [.shared, .cursor]
        )
        XCTAssertEqual(
            UserFolderTarget.visible(installed: [.cursor], existingLocationIDs: ["gemini-user"]),
            [.shared, .cursor, .gemini]
        )
    }
}
