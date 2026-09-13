import Foundation
import XCTest
@testable import SkillManagerCore

final class BuildManifestTests: XCTestCase {
    func testParsesKnownFieldsAndKeepsExtraKeys() throws {
        let json = """
        {
          "version": "0.1.0",
          "build": "12",
          "commit": "abc1234",
          "ref": "main",
          "builtAt": "2026-09-13T18:00:00Z",
          "channel": "release"
        }
        """
        let manifest = try XCTUnwrap(BuildManifest.parse(Data(json.utf8)))
        XCTAssertEqual(manifest.value(for: "version"), "0.1.0")
        XCTAssertEqual(manifest.value(for: "build"), "12")
        XCTAssertEqual(manifest.value(for: "commit"), "abc1234")
        XCTAssertEqual(manifest.value(for: "ref"), "main")
        XCTAssertEqual(manifest.value(for: "channel"), "release")
        XCTAssertEqual(manifest.detailFields.first { $0.key == "channel" }?.label, "Channel")
        XCTAssertEqual(manifest.detailFields.map(\.key), ["commit", "ref", "builtAt", "channel"])
        XCTAssertFalse(manifest.detailFields.contains { $0.key == "version" || $0.key == "build" })
        XCTAssertTrue(manifest.prettyJSON.contains("abc1234"))
    }

    func testIgnoresEmptyOrInvalidPayloads() {
        XCTAssertNil(BuildManifest.parse(Data("{}".utf8)))
        XCTAssertNil(BuildManifest.parse(Data("[]".utf8)))
        XCTAssertNil(BuildManifest.parse(Data("not-json".utf8)))
        XCTAssertNil(BuildManifest.parse(Data(#"{"version":"","build":null}"#.utf8)))
    }

    func testVersionOnlyManifestHasNoDetailSection() throws {
        let json = #"{"version":"0.1.0","build":"1"}"#
        let manifest = try XCTUnwrap(BuildManifest.parse(Data(json.utf8)))
        XCTAssertTrue(manifest.detailFields.isEmpty)
    }
}
