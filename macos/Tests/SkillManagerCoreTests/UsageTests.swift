import Foundation
import XCTest
@testable import SkillManagerCore

final class UsageTests: XCTestCase {
    func testIgnoresAvailableSkillListingsOnUserLines() {
        let line = #"{"role":"user","message":{"content":[{"type":"text","text":"<agent_skill fullPath=\"/Users/ada/.cursor/skills/tdd/SKILL.md\">"}]}}"#
        XCTAssertTrue(SkillUsageScanner.namesFromAssistantLine(line).isEmpty)
        let session = SkillUsageScanner.session(fromLines: [line], fileDate: Date())
        XCTAssertNil(session)
    }

    func testCountsReadOfSkillMarkdownOnAssistantLines() {
        let line = #"{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"path":"/Users/ada/.cursor/skills/frontend-design/SKILL.md"}}]}}"#
        XCTAssertEqual(SkillUsageScanner.namesFromAssistantLine(line), ["frontend-design"])
    }

    func testNormalizesFolderNamesAndSkipsNodeModules() {
        let ok = #"{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"path":"/Users/ada/.claude/skills/Make Bot UI/SKILL.md"}}]}}"#
        XCTAssertEqual(SkillUsageScanner.namesFromAssistantLine(ok), ["make-bot-ui"])
        let skip = #"{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"path":"/app/node_modules/@reduxjs/toolkit/skills/modern-redux/SKILL.md"}}]}}"#
        XCTAssertTrue(SkillUsageScanner.namesFromAssistantLine(skip).isEmpty)
    }

    func testReadsClaudeInvokedSkills() {
        let line = #"{"type":"user","attachment":{"type":"invoked_skills","skills":[{"name":"run","path":"bundled:run"},{"name":"TDD","path":"/Users/ada/.claude/skills/tdd/SKILL.md"}]}}"#
        XCTAssertEqual(SkillUsageScanner.namesFromInvokedSkills(line), ["run", "tdd"])
    }

    func testParsesCursorAndIsoTimestamps() {
        let cursor = SkillUsageScanner.timestamp(in: "<timestamp>Sunday, Sep 13, 2026, 10:15 AM (UTC-6)</timestamp>")
        XCTAssertNotNil(cursor)
        let iso = SkillUsageScanner.timestamp(in: #""timestamp":"2026-07-26T00:41:06.548Z""#)
        XCTAssertNotNil(iso)
    }

    func testAggregatesUniqueSessionsAndRelativeLabels() {
        let day = Date(timeIntervalSince1970: 1_789_290_000)
        let earlier = day.addingTimeInterval(-86_400 * 3)
        let usage = SkillUsageScanner.aggregate([
            (["canvas"], earlier),
            (["canvas", "tdd"], day),
        ])
        XCTAssertEqual(usage["canvas"]?.sessionCount, 2)
        XCTAssertEqual(usage["tdd"]?.sessionCount, 1)
        XCTAssertEqual(usage["canvas"]?.lastUsed, day)
        XCTAssertEqual(SkillUsageScanner.relativeString(from: day, now: day), "today")
        XCTAssertEqual(SkillUsageScanner.relativeString(from: earlier, now: day), "3d ago")
    }

    func testHeatmapPutsTodayInTheCurrentWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        let sunday = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 9, day: 13))!
        let usage = SkillUsage(sessionCount: 1, lastUsed: sunday, dates: [sunday])
        let weeks = usage.weeklyCounts(weeks: 4, now: sunday, calendar: calendar)
        XCTAssertEqual(weeks, [0, 0, 0, 1])
        XCTAssertEqual(usage.sessions(inLastWeeks: 4, now: sunday, calendar: calendar), 1)
        let cells = usage.heatmapCounts(weeks: 4, now: sunday, calendar: calendar)
        XCTAssertEqual(cells[3 * 7], 1)
    }

    func testScanFindsTranscriptsUnderAFakeHome() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString)")
        let transcriptDir = home.appendingPathComponent(".cursor/projects/app/agent-transcripts/abc")
        try FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
        let body = """
        {"role":"user","message":{"content":[{"type":"text","text":"<timestamp>Sunday, Sep 13, 2026, 10:15 AM (UTC-6)</timestamp>\\n<agent_skill fullPath=\\"/Users/ada/.cursor/skills/tdd/SKILL.md\\">"}]}}
        {"role":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"path":"/Users/ada/.cursor/skills-cursor/create-skill/SKILL.md"}}]}}
        """
        try body.write(to: transcriptDir.appendingPathComponent("abc.jsonl"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".cursor/skills-cursor/create-skill"), withIntermediateDirectories: true)
        try """
        ---
        name: create-skill
        description: Create skills.
        ---

        # Create
        """.write(to: home.appendingPathComponent(".cursor/skills-cursor/create-skill/SKILL.md"), atomically: true, encoding: .utf8)
        let inventory = InventoryBuilder.build(ScanOptions(homeDir: home.path, includePlugins: false, includeBuiltins: true))
        XCTAssertEqual(inventory.groups.first { $0.name == "create-skill" }?.usage.sessionCount, 1)
        XCTAssertEqual(inventory.groups.first { $0.name == "create-skill" }?.catalogScopes, [.builtin])
        try? FileManager.default.removeItem(at: home)
    }
}
