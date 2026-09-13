import Foundation

public enum ConfigStore {
    public static func configPath(homeDir: String) -> String {
        (homeDir as NSString).appendingPathComponent(".config/skill-manager/config.json")
    }

    public static func load(homeDir: String) -> ManagerConfig {
        let file = configPath(homeDir: homeDir)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)),
              let parsed = try? JSONDecoder().decode(PartialConfig.self, from: data)
        else {
            return ManagerConfig()
        }
        return ManagerConfig(
            scanRoots: parsed.scanRoots ?? [],
            includePlugins: parsed.includePlugins ?? true,
            includeBuiltins: parsed.includeBuiltins ?? true,
            origins: parsed.origins ?? [:]
        )
    }

    public static func save(homeDir: String, config: ManagerConfig) throws {
        let file = configPath(homeDir: homeDir)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: file).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(config)
        if var str = String(data: data, encoding: .utf8) {
            str.append("\n")
            data = Data(str.utf8)
        }
        try data.write(to: URL(fileURLWithPath: file))
    }

    public static func resolve(
        homeDir: String = NSHomeDirectory(),
        cwd: String = "",
        scanRoots: [String]? = nil,
        includePlugins: Bool? = nil,
        includeBuiltins: Bool? = nil
    ) -> ScanOptions {
        let stored = load(homeDir: homeDir)
        let extraRoots = (scanRoots?.isEmpty == false ? scanRoots : nil) ?? stored.scanRoots
        let roots = Array(Set(InventoryBuilder.defaultScanRoots(homeDir: homeDir, cwd: cwd) + extraRoots)).sorted()
        return ScanOptions(
            homeDir: homeDir,
            scanRoots: roots,
            includePlugins: includePlugins ?? stored.includePlugins,
            includeBuiltins: includeBuiltins ?? stored.includeBuiltins,
            extraSkillDirs: SkillDiscovery.extraGrokSkillPaths(homeDir: homeDir),
            assignedOrigins: stored.origins
        )
    }
}

private struct PartialConfig: Codable {
    var scanRoots: [String]?
    var includePlugins: Bool?
    var includeBuiltins: Bool?
    var origins: [String: AssignedOrigin]?
}
