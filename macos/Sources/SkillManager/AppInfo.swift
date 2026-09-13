import Foundation
import SkillManagerCore

enum AppInfo {
    static let name = "Skill Manager"
    static let copyright = "© 2026 Joe Booker"
    static let license = "MIT License"
    static let repositoryURL = URL(string: "https://github.com/jbooker/SkillsManager")!

    static var shortVersion: String? {
        string(forInfoKey: "CFBundleShortVersionString")
    }

    static var buildNumber: String? {
        string(forInfoKey: "CFBundleVersion")
    }

    static var displayVersion: String {
        switch (shortVersion, buildNumber) {
        case let (version?, build?) where version != build:
            return "\(version) (\(build))"
        case let (version?, _):
            return version
        case let (nil, build?):
            return build
        default:
            return manifest?.value(for: "version") ?? "Development"
        }
    }

    static var copyrightLine: String {
        string(forInfoKey: "NSHumanReadableCopyright") ?? copyright
    }

    static let manifest: BuildManifest? = BuildManifest.loadFromBundle()

    private static func string(forInfoKey key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
