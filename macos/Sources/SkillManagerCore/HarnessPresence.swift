import Foundation

public enum HarnessPresence {
    public static func detectOnThisMac(homeDir: String, extraApplicationPaths: [String] = []) -> Set<HarnessID> {
        detect(
            homeDir: homeDir,
            applicationsDirectories: defaultApplicationsDirectories(homeDir: homeDir),
            pathDirectories: defaultPathDirectories(homeDir: homeDir),
            extraApplicationPaths: extraApplicationPaths
        )
    }

    public static func detect(
        homeDir: String,
        applicationsDirectories: [String],
        pathDirectories: [String],
        extraApplicationPaths: [String] = []
    ) -> Set<HarnessID> {
        let apps = applicationPaths(in: applicationsDirectories, extra: extraApplicationPaths)
        var found = Set<HarnessID>()
        for def in Harnesses.all {
            if isInstalled(def, homeDir: homeDir, applications: apps, pathDirectories: pathDirectories) {
                found.insert(def.id)
            }
        }
        return found
    }

    public static func defaultApplicationsDirectories(homeDir: String) -> [String] {
        [
            "/Applications",
            (homeDir as NSString).appendingPathComponent("Applications"),
        ]
    }

    public static func defaultPathDirectories(homeDir: String, path: String? = ProcessInfo.processInfo.environment["PATH"]) -> [String] {
        var dirs: [String] = []
        var seen = Set<String>()
        func add(_ dir: String) {
            guard !dir.isEmpty, !seen.contains(dir) else { return }
            seen.insert(dir)
            dirs.append(dir)
        }
        for item in (path ?? "").split(separator: ":").map(String.init) {
            add(item)
        }
        let home = homeDir as NSString
        for rel in [
            ".local/bin",
            "bin",
            ".grok/bin",
            ".opencode/bin",
            ".claude/local",
            ".volta/bin",
            ".cargo/bin",
            ".asdf/shims",
            ".local/share/mise/shims",
        ] {
            add(home.appendingPathComponent(rel))
        }
        add("/opt/homebrew/bin")
        add("/usr/local/bin")
        return dirs
    }

    private static func isInstalled(
        _ def: HarnessDef,
        homeDir: String,
        applications: [String],
        pathDirectories: [String]
    ) -> Bool {
        for app in applications {
            let name = (app as NSString).lastPathComponent
            if def.appBundleNames.contains(name) { return true }
            if let bundleID = bundleIdentifier(ofApp: app), def.bundleIdentifiers.contains(bundleID) {
                return true
            }
            for rel in def.appResourceBinaries {
                if existsFile((app as NSString).appendingPathComponent(rel)) { return true }
            }
        }
        for rel in def.homeRelativeBinaries {
            if existsFile((homeDir as NSString).appendingPathComponent(rel)) { return true }
        }
        for binary in def.binaryNames {
            for dir in pathDirectories {
                if existsFile((dir as NSString).appendingPathComponent(binary)) { return true }
            }
        }
        return false
    }

    private static func applicationPaths(in directories: [String], extra: [String]) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()
        func add(_ path: String) {
            guard !path.isEmpty, !seen.contains(path) else { return }
            seen.insert(path)
            paths.append(path)
        }
        for dir in directories {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for name in names where name.hasSuffix(".app") {
                add((dir as NSString).appendingPathComponent(name))
            }
        }
        for path in extra where path.hasSuffix(".app") {
            add(path)
        }
        return paths
    }

    private static func bundleIdentifier(ofApp path: String) -> String? {
        let plist = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOfFile: plist) else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    private static func existsFile(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return false }
        return !isDir.boolValue
    }
}
