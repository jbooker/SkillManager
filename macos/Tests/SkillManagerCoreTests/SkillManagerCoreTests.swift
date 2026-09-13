import Foundation
import XCTest
@testable import SkillManagerCore

final class SkillManagerCoreTests: XCTestCase {
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

    func writeSkill(dir: URL, name: String, description: String, extra: String = "") throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = "---\nname: \(name)\ndescription: \(description)\n\(extra)---\n\n# \(name)\n\nDo the thing.\n"
        try body.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    func scanOf(home: URL, project: URL? = nil) -> ScanOptions {
        ScanOptions(
            homeDir: home.path,
            scanRoots: project.map { [$0.path] } ?? [],
            includePlugins: true,
            includeBuiltins: true,
            extraSkillDirs: []
        )
    }

    func testReadsRequiredFrontmatter() {
        let result = SkillParser.parse(
            content: "---\nname: pdf-processing\ndescription: Extract PDF text.\n---\n\n# PDF\n",
            folderName: "pdf-processing"
        )
        XCTAssertEqual(result.meta.name, "pdf-processing")
        XCTAssertEqual(result.meta.description, "Extract PDF text.")
        XCTAssertEqual(result.errors, [])
    }

    func testFlagsMissingFrontmatterAndEmptyDescription() {
        let noFm = SkillParser.parse(content: "# just a heading\n", folderName: "foo")
        XCTAssertTrue(noFm.errors.contains("missing-frontmatter"))
        let empty = SkillParser.parse(content: "---\nname: canvas\ndescription:\n---\n\nBody\n", folderName: "canvas")
        XCTAssertTrue(empty.errors.contains("missing-description"))
    }

    func testParsesFoldedDescriptionsAndPathLists() {
        let result = SkillParser.parse(
            content: """
            ---
            name: make-bot-ui
            description: >-
              Use when building a custom UI.
            paths:
              - "**/*.tsx"
            disable-model-invocation: true
            ---

            # How
            """,
            folderName: "make-bot-ui"
        )
        XCTAssertTrue(result.meta.description.contains("custom UI"))
        XCTAssertEqual(result.meta.paths, ["**/*.tsx"])
        XCTAssertTrue(result.meta.disableModelInvocation)
    }

    func testPatchesDisableModelInvocationWithoutRewritingTheBody() {
        let original = "---\nname: review\ndescription: Review code.\n---\n\n# Review\n\nDo it.\n"
        let inactive = SkillParser.patchDisableModelInvocation(content: original, inactive: true)
        XCTAssertTrue(inactive.contains("disable-model-invocation: true"))
        XCTAssertTrue(inactive.contains("# Review"))
        let parsed = SkillParser.parse(content: inactive, folderName: "review")
        XCTAssertTrue(parsed.meta.disableModelInvocation)
        let active = SkillParser.patchDisableModelInvocation(content: inactive, inactive: false)
        XCTAssertFalse(active.contains("disable-model-invocation"))
        XCTAssertTrue(active.contains("# Review"))
    }

    func testNormalizesMismatchedNames() {
        let result = SkillParser.parse(
            content: "---\nname: Make Bot UI\ndescription: Webhook UI.\n---\n\nBody\n",
            folderName: "make-bot-ui"
        )
        XCTAssertEqual(result.meta.name, "make-bot-ui")
        XCTAssertTrue(result.errors.contains("name-folder-mismatch"))
    }

    func testClassifiesHarnessVisibilityFromDiskLocation() throws {
        let home = try tempDir()
        let agents = home.appendingPathComponent(".agents/skills/shared-one/SKILL.md")
        let claude = home.appendingPathComponent(".claude/skills/claude-only/SKILL.md")
        let cursor = home.appendingPathComponent(".cursor/skills/cursor-only/SKILL.md")
        try FileManager.default.createDirectory(at: agents.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cursor.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\nname: shared-one\ndescription: d\n---\n\n# x\n".write(to: agents, atomically: true, encoding: .utf8)
        try "---\nname: claude-only\ndescription: d\n---\n\n# x\n".write(to: claude, atomically: true, encoding: .utf8)
        try "---\nname: cursor-only\ndescription: d\n---\n\n# x\n".write(to: cursor, atomically: true, encoding: .utf8)

        XCTAssertTrue(SkillDiscovery.classifyLocation(skillFile: agents.path, homeDir: home.path).shared)
        XCTAssertEqual(
            SkillDiscovery.classifyLocation(skillFile: agents.path, homeDir: home.path).harnesses,
            [.cursor, .grok, .codex, .gemini, .opencode]
        )
        let claudeLoc = SkillDiscovery.classifyLocation(skillFile: claude.path, homeDir: home.path)
        XCTAssertTrue(claudeLoc.harnesses.contains(.claude))
        XCTAssertTrue(claudeLoc.harnesses.contains(.cursor))
        XCTAssertEqual(SkillDiscovery.classifyLocation(skillFile: cursor.path, homeDir: home.path).harnesses, [.cursor])
        XCTAssertFalse(SkillDiscovery.classifyLocation(skillFile: cursor.path, homeDir: home.path).shared)
    }

    func testBuildsInventoryAcrossHarnessesPluginsProjectsAndGrokExtras() throws {
        let home = try tempDir()
        let project = home.appendingPathComponent("code/app")
        try writeSkill(dir: home.appendingPathComponent(".agents/skills/portable"), name: "portable", description: "Works almost everywhere.")
        try writeSkill(dir: home.appendingPathComponent(".claude/skills/review"), name: "review", description: "Claude review.")
        try writeSkill(dir: home.appendingPathComponent(".cursor/skills/canvas"), name: "canvas", description: "Cursor canvases.")
        try writeSkill(dir: home.appendingPathComponent(".grok/skills/grok-only"), name: "grok-only", description: "Grok only.")
        try writeSkill(dir: home.appendingPathComponent(".codex/skills/codex-only"), name: "codex-only", description: "Codex only.")
        try writeSkill(dir: home.appendingPathComponent(".gemini/skills/gemini-only"), name: "gemini-only", description: "Gemini only.")
        try writeSkill(dir: home.appendingPathComponent(".config/opencode/skills/oc-only"), name: "oc-only", description: "OpenCode only.")
        try writeSkill(dir: home.appendingPathComponent(".cursor/skills-cursor/env-setup"), name: "env-setup", description: "Built-in.")

        let pluginRoot = home.appendingPathComponent(".cursor/plugins/cache/org/1/hash")
        try FileManager.default.createDirectory(at: pluginRoot.appendingPathComponent(".cursor-plugin"), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["name": "cloudflare", "author": ["name": "Cloudflare"]])
            .write(to: pluginRoot.appendingPathComponent(".cursor-plugin/plugin.json"))
        try writeSkill(dir: pluginRoot.appendingPathComponent("skills/wrangler"), name: "wrangler", description: "Wrangler CLI.")

        try writeSkill(dir: project.appendingPathComponent(".claude/skills/deploy"), name: "deploy", description: "Project deploy.")
        try writeSkill(dir: project.appendingPathComponent("apps/web/.cursor/skills/deploy-web"), name: "deploy-web", description: "Web deploy.")

        try FileManager.default.createDirectory(at: home.appendingPathComponent(".grok"), withIntermediateDirectories: true)
        let extra = home.appendingPathComponent("extras/from-toml")
        try writeSkill(dir: extra.appendingPathComponent("toml-skill"), name: "toml-skill", description: "From grok config.")
        try "[skills]\npaths = [\"\(extra.path)\"]\n".write(to: home.appendingPathComponent(".grok/config.toml"), atomically: true, encoding: .utf8)

        var options = scanOf(home: home, project: home.appendingPathComponent("code"))
        options.extraSkillDirs = SkillDiscovery.extraGrokSkillPaths(homeDir: home.path)
        let inventory = InventoryBuilder.build(options)
        let names = inventory.groups.map(\.name)

        for expected in [
            "portable", "review", "canvas", "grok-only", "codex-only", "gemini-only",
            "oc-only", "env-setup", "wrangler", "deploy", "deploy-web", "toml-skill",
        ] {
            XCTAssertTrue(names.contains(expected), "missing \(expected)")
        }

        let portable = inventory.groups.first { $0.name == "portable" }!
        XCTAssertTrue(portable.inShared)
        XCTAssertFalse(portable.harnesses.contains(.claude))
        XCTAssertTrue(Set(portable.harnesses).isSuperset(of: [.cursor, .codex, .gemini, .grok, .opencode]))

        let review = inventory.groups.first { $0.name == "review" }!
        XCTAssertTrue(Set(review.harnesses).isSuperset(of: [.claude, .cursor, .grok, .opencode]))
        XCTAssertFalse(review.harnesses.contains(.codex))
        XCTAssertFalse(review.inShared)

        let wrangler = inventory.groups.first { $0.name == "wrangler" }!
        XCTAssertEqual(wrangler.copies.first?.location.pluginName, "cloudflare")
        XCTAssertEqual(wrangler.harnesses, [.cursor])

        let deployWeb = inventory.groups.first { $0.name == "deploy-web" }!
        XCTAssertEqual(deployWeb.copies.first?.location.id, "cursor-project")

        let toml = inventory.groups.first { $0.name == "toml-skill" }
        XCTAssertNotNil(toml)
        XCTAssertTrue(toml?.harnesses.contains(.grok) == true)

        let claude = inventory.harnesses.first { $0.id == .claude }!
        XCTAssertTrue(Set(claude.uniqueNames).isSuperset(of: ["review", "deploy"]))
        XCTAssertTrue(claude.missingNames.contains("portable"))
        XCTAssertTrue(claude.missingNames.contains("canvas"))

        let cursorH = inventory.harnesses.first { $0.id == .cursor }!
        XCTAssertTrue(Set(cursorH.uniqueNames).isSuperset(of: ["portable", "review", "canvas", "wrangler", "env-setup"]))
    }

    func testOmitsFilesystemRootAndHomeFromDefaultScanRoots() {
        XCTAssertFalse(InventoryBuilder.defaultScanRoots(homeDir: "/Users/ada", cwd: "/").contains("/"))
        XCTAssertFalse(InventoryBuilder.defaultScanRoots(homeDir: "/Users/ada", cwd: "/Users/ada").contains("/Users/ada"))
        XCTAssertTrue(InventoryBuilder.defaultScanRoots(homeDir: "/Users/ada", cwd: "/Users/ada/code").contains("/Users/ada/code"))
    }

    func testSkipsFullWalkOfHome() throws {
        let home = try tempDir()
        try writeSkill(dir: home.appendingPathComponent(".claude/skills/alpha"), name: "alpha", description: "A")
        try writeSkill(dir: home.appendingPathComponent("Documents/not-a-skill-root/beta"), name: "beta", description: "Should not be found via home walk")
        let files = SkillDiscovery.collectSkillFiles(options: scanOf(home: home, project: home))
        XCTAssertTrue(files.contains { $0.contains("alpha") })
        XCTAssertFalse(files.contains { $0.contains("beta") })
        XCTAssertFalse(files.contains { $0.contains("Documents") })
    }

    func testPromotesClaudeSkillIntoSharedAgents() throws {
        let home = try tempDir()
        let source = home.appendingPathComponent(".claude/skills/review")
        try writeSkill(dir: source, name: "review", description: "Review code.")
        let result = SkillActions.promoteToShared(skillDir: source.path, homeDir: home.path)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.action, .created)
        let linked = home.appendingPathComponent(".agents/skills/review")
        XCTAssertEqual(
            URL(fileURLWithPath: linked.path).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: source.path).resolvingSymlinksInPath().path
        )
        let again = SkillActions.promoteToShared(skillDir: source.path, homeDir: home.path)
        XCTAssertTrue(again.ok)
        XCTAssertEqual(again.action, .alreadyLinked)
    }

    func testMakeEverywhereAndUnlinkOnlyRemovesSymlinks() throws {
        let home = try tempDir()
        let source = home.appendingPathComponent(".cursor/skills/canvas")
        try writeSkill(dir: source, name: "canvas", description: "Canvases.")
        let result = SkillActions.makeEverywhere(skillDir: source.path, homeDir: home.path)
        XCTAssertTrue(result.ok)
        let shared = home.appendingPathComponent(".agents/skills/canvas")
        let claude = home.appendingPathComponent(".claude/skills/canvas")
        XCTAssertEqual(
            URL(fileURLWithPath: shared.path).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: source.path).resolvingSymlinksInPath().path
        )
        XCTAssertEqual(
            URL(fileURLWithPath: claude.path).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: source.path).resolvingSymlinksInPath().path
        )
        XCTAssertTrue(SkillActions.unlinkManaged(targetPath: shared.path).ok)
        XCTAssertFalse(SkillActions.unlinkManaged(targetPath: source.path).ok)
    }

    func testLinksIntoHarnessSpecificUserDir() throws {
        let home = try tempDir()
        let source = home.appendingPathComponent(".agents/skills/portable")
        try writeSkill(dir: source, name: "portable", description: "Portable.")
        let result = SkillActions.linkToHarness(skillDir: source.path, homeDir: home.path, harness: .gemini)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(
            URL(fileURLWithPath: home.appendingPathComponent(".gemini/skills/portable").path).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: source.path).resolvingSymlinksInPath().path
        )
    }

    func testUnloadsSymlinkFromSharedWithoutTouchingTheSource() throws {
        let home = try tempDir()
        let source = home.appendingPathComponent(".claude/skills/review")
        try writeSkill(dir: source, name: "review", description: "Review code.")
        XCTAssertTrue(SkillActions.promoteToShared(skillDir: source.path, homeDir: home.path).ok)
        let unloaded = SkillActions.unloadFromShared(skillName: "review", homeDir: home.path)
        XCTAssertTrue(unloaded.ok)
        XCTAssertEqual(unloaded.action, .removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".agents/skills/review").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testUnloadingLastUserCopyArchivesIt() throws {
        let home = try tempDir()
        let source = home.appendingPathComponent(".cursor/skills/canvas")
        try writeSkill(dir: source, name: "canvas", description: "Canvases.")
        let result = SkillActions.unloadCopy(targetPath: source.path, homeDir: home.path)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.action, .archived)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        let archived = home.appendingPathComponent(".config/skill-manager/archive/canvas")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archived.appendingPathComponent("SKILL.md").path))

        let inventory = InventoryBuilder.build(scanOf(home: home))
        let group = inventory.groups.first { $0.name == "canvas" }!
        XCTAssertTrue(group.archivedOnly)
        XCTAssertEqual(group.harnesses, [])
        XCTAssertEqual(inventory.uniqueCount, 0)
        XCTAssertEqual(inventory.archivedCount, 1)
        XCTAssertFalse(inventory.harnesses.first { $0.id == .cursor }!.missingNames.contains("canvas"))
    }

    func testUnloadingRealFolderRelocatesOntoRemainingSymlink() throws {
        let home = try tempDir()
        let source = home.appendingPathComponent(".claude/skills/review")
        try writeSkill(dir: source, name: "review", description: "Review code.")
        XCTAssertTrue(SkillActions.promoteToShared(skillDir: source.path, homeDir: home.path).ok)
        let result = SkillActions.unloadFromHarness(skillName: "review", homeDir: home.path, harness: .claude)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.action, .relocated)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        let shared = home.appendingPathComponent(".agents/skills/review")
        XCTAssertTrue(FileManager.default.fileExists(atPath: shared.appendingPathComponent("SKILL.md").path))
        let attrs = try FileManager.default.attributesOfItem(atPath: shared.path)
        XCTAssertNotEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)
    }

    func testArchiveRestoreAndDeleteUserCopies() throws {
        let home = try tempDir()
        let source = home.appendingPathComponent(".claude/skills/review")
        try writeSkill(dir: source, name: "review", description: "Review code.")
        XCTAssertTrue(SkillActions.promoteToShared(skillDir: source.path, homeDir: home.path).ok)
        let archived = SkillActions.archiveUserCopies(skillName: "review", homeDir: home.path)
        XCTAssertTrue(archived.ok)
        XCTAssertEqual(archived.action, .archived)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".agents/skills/review").path))

        let restored = SkillActions.restoreArchived(skillName: "review", homeDir: home.path)
        XCTAssertTrue(restored.ok)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".config/skill-manager/archive/review").path))

        XCTAssertTrue(SkillActions.deleteUserCopies(skillName: "review", homeDir: home.path).ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testMarksSkillInactiveAndActiveAgain() throws {
        let home = try tempDir()
        let source = home.appendingPathComponent(".claude/skills/review")
        try writeSkill(dir: source, name: "review", description: "Review code.")
        XCTAssertTrue(SkillActions.setInactive(skillDir: source.path, homeDir: home.path, inactive: true).ok)
        let raw = try String(contentsOf: source.appendingPathComponent("SKILL.md"), encoding: .utf8)
        XCTAssertTrue(raw.contains("disable-model-invocation: true"))
        XCTAssertTrue(SkillActions.setInactive(skillDir: source.path, homeDir: home.path, inactive: false).ok)
        let again = try String(contentsOf: source.appendingPathComponent("SKILL.md"), encoding: .utf8)
        XCTAssertFalse(again.contains("disable-model-invocation"))
    }

    func testRefusesToChangePluginAndBuiltinSkills() throws {
        let home = try tempDir()
        let builtin = home.appendingPathComponent(".cursor/skills-cursor/env-setup")
        try writeSkill(dir: builtin, name: "env-setup", description: "Built-in.")
        XCTAssertFalse(SkillActions.unloadCopy(targetPath: builtin.path, homeDir: home.path).ok)
        XCTAssertFalse(SkillActions.deleteCopy(targetPath: builtin.path, homeDir: home.path).ok)

        let pluginRoot = home.appendingPathComponent(".cursor/plugins/cache/org/1/hash")
        try FileManager.default.createDirectory(at: pluginRoot.appendingPathComponent(".cursor-plugin"), withIntermediateDirectories: true)
        try writeSkill(dir: pluginRoot.appendingPathComponent("skills/wrangler"), name: "wrangler", description: "Wrangler CLI.")
        XCTAssertFalse(SkillActions.deleteCopy(targetPath: pluginRoot.appendingPathComponent("skills/wrangler").path, homeDir: home.path).ok)
        XCTAssertTrue(FileManager.default.fileExists(atPath: builtin.path))
    }

    func testRefusesToMoveAProjectSkillFolder() throws {
        let home = try tempDir()
        let project = home.appendingPathComponent("code/app/.claude/skills/deploy")
        try writeSkill(dir: project, name: "deploy", description: "Project deploy.")
        let result = SkillActions.unloadCopy(targetPath: project.path, homeDir: home.path)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.path))
    }
}
