import Foundation

public enum HarnessID: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude
    case cursor
    case grok
    case codex
    case gemini
    case opencode

    public var id: String { rawValue }
}

/// User-level folders the inspector can link into or unlink from.
/// Coverage (who can *load* the skill) is separate: Cursor may already
/// see a shared-global copy without a `~/.cursor/skills` entry.
public enum UserFolderTarget: String, CaseIterable, Identifiable, Sendable, Hashable {
    case shared
    case claude
    case cursor
    case grok
    case codex
    case gemini
    case opencode

    public var id: String { rawValue }

    public var locationId: String {
        switch self {
        case .shared: return "agents-user"
        case .claude: return "claude-user"
        case .cursor: return "cursor-user"
        case .grok: return "grok-user"
        case .codex: return "codex-user"
        case .gemini: return "gemini-user"
        case .opencode: return "opencode-user"
        }
    }

    public var title: String {
        switch self {
        case .shared: return "Shared global"
        case .claude: return "Claude"
        case .cursor: return "Cursor"
        case .grok: return "Grok"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .opencode: return "OpenCode"
        }
    }

    public var homeRel: String {
        switch self {
        case .shared: return "~/.agents/skills"
        case .claude: return "~/.claude/skills"
        case .cursor: return "~/.cursor/skills"
        case .grok: return "~/.grok/skills"
        case .codex: return "~/.codex/skills"
        case .gemini: return "~/.gemini/skills"
        case .opencode: return "~/.config/opencode/skills"
        }
    }

    public var harness: HarnessID? {
        switch self {
        case .shared: return nil
        default: return HarnessID(rawValue: rawValue)
        }
    }

    /// Shared global, plus each installed harness folder. Folders that already
    /// have a copy stay visible so leftover installs can still be unlinked.
    public static func visible(installed: Set<HarnessID>, existingLocationIDs: Set<String> = []) -> [UserFolderTarget] {
        allCases.filter { target in
            guard let harness = target.harness else { return true }
            return installed.contains(harness) || existingLocationIDs.contains(target.locationId)
        }
    }
}

public enum SkillScope: String, Codable, Sendable, Hashable, CaseIterable {
    case user
    case project
    case plugin
    case builtin
    case archived
    case unknown
}

public struct HarnessDef: Sendable, Identifiable {
    public var id: HarnessID
    public var name: String
    public var shortName: String
    public var colorHex: String
    public var blurb: String
    public var readsSharedAgents: Bool
    public var appBundleNames: [String]
    public var bundleIdentifiers: [String]
    public var binaryNames: [String]
    public var homeRelativeBinaries: [String]
    public var appResourceBinaries: [String]
}

public struct LocationRule: Sendable {
    public var id: String
    public var label: String
    public var scope: SkillScope
    public var shared: Bool
    public var harnesses: [HarnessID]
    public var homeRel: String?
    public var projectNeedle: String?
}

public struct SkillMeta: Sendable, Equatable {
    public var name: String
    public var description: String
    public var disableModelInvocation: Bool
    public var userInvocable: Bool?
    public var paths: [String]
    public var whenToUse: String
    public var license: String
    public var compatibility: String
    public var metadata: [String: String]
}

public struct ParseResult: Sendable {
    public var meta: SkillMeta
    public var body: String
    public var errors: [String]
}

public struct SkillLocation: Sendable, Equatable {
    public var id: String
    public var label: String
    public var scope: SkillScope
    public var shared: Bool
    public var harnesses: [HarnessID]
    public var projectRoot: String?
    public var pluginName: String?
    public var pluginAuthor: String?
}

public enum OriginKind: String, Codable, Sendable {
    case git
    case remote
    case plugin
    case builtin
    case local
}

public struct SkillOrigin: Sendable, Equatable {
    public var kind: OriginKind
    public var label: String
    public var locator: String?
    public var subpath: String?
    public var pinnedRef: String?
    public var trackRef: String?

    public var refreshable: Bool {
        locator != nil && (kind == .git || kind == .remote)
    }

    public init(
        kind: OriginKind,
        label: String,
        locator: String? = nil,
        subpath: String? = nil,
        pinnedRef: String? = nil,
        trackRef: String? = nil
    ) {
        self.kind = kind
        self.label = label
        self.locator = locator
        self.subpath = subpath
        self.pinnedRef = pinnedRef
        self.trackRef = trackRef
    }

    public static let local = SkillOrigin(kind: .local, label: "Local")
}

public struct GitLocator: Sendable, Equatable {
    public var url: String
    public var subpath: String?
    public var ref: String?

    public init(url: String, subpath: String? = nil, ref: String? = nil) {
        self.url = url
        self.subpath = subpath
        self.ref = ref
    }
}

public struct AssignedOrigin: Codable, Equatable, Sendable {
    public var locator: String
    public var subpath: String?
    public var ref: String?

    public init(locator: String, subpath: String? = nil, ref: String? = nil) {
        self.locator = locator
        self.subpath = subpath
        self.ref = ref
    }
}

public enum RefreshState: String, Sendable {
    case current
    case updateAvailable = "update-available"
    case unknown
    case notRefreshable = "not-refreshable"
    case unreachable
}

public struct RefreshInspection: Sendable {
    public var state: RefreshState
    public var localRef: String?
    public var remoteRef: String?
    public var message: String
}

public struct SkillCopy: Sendable, Identifiable, Equatable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var folderName: String
    public var description: String
    public var skillDir: String
    public var skillFile: String
    public var homeRelative: String
    public var realPath: String
    public var isSymlink: Bool
    public var symlinkTarget: String?
    public var contentHash: String
    public var mtimeMs: Double
    public var bytes: Int
    public var fileCount: Int
    public var hasScripts: Bool
    public var hasReferences: Bool
    public var hasAssets: Bool
    public var extraFiles: [String]
    public var errors: [String]
    public var disableModelInvocation: Bool
    public var location: SkillLocation
    public var origin: SkillOrigin = .local
    public var meta: SkillMeta
}

public struct SkillUsage: Sendable, Equatable {
    public var sessionCount: Int
    public var lastUsed: Date?
    public var dates: [Date]

    public static let empty = SkillUsage(sessionCount: 0, lastUsed: nil, dates: [])

    public init(sessionCount: Int = 0, lastUsed: Date? = nil, dates: [Date] = []) {
        self.sessionCount = sessionCount
        self.lastUsed = lastUsed
        self.dates = dates
    }

    public var lastUsedSort: Date { lastUsed ?? .distantPast }

    /// One count per week, oldest first, covering `weeks` including the week of `now`.
    public func weeklyCounts(weeks: Int = 26, now: Date = Date(), calendar: Calendar = SkillUsage.weekCalendar) -> [Int] {
        let cells = heatmapCounts(weeks: weeks, now: now, calendar: calendar)
        return (0..<weeks).map { week in
            (0..<7).reduce(0) { $0 + cells[week * 7 + $1] }
        }
    }

    /// Sunday-first grid: `weeks` columns × 7 day rows. Index is `week * 7 + weekdayOffset`.
    public func heatmapCounts(weeks: Int = 26, now: Date = Date(), calendar: Calendar = SkillUsage.weekCalendar) -> [Int] {
        guard weeks > 0 else { return [] }
        let start = heatmapStart(weeks: weeks, now: now, calendar: calendar)
        var cells = Array(repeating: 0, count: weeks * 7)
        for date in dates {
            let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
            if days >= 0 && days < weeks * 7 {
                cells[days] += 1
            }
        }
        return cells
    }

    public func sessions(inLastWeeks weeks: Int, now: Date = Date(), calendar: Calendar = SkillUsage.weekCalendar) -> Int {
        weeklyCounts(weeks: weeks, now: now, calendar: calendar).reduce(0, +)
    }

    public static var weekCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = .current
        return calendar
    }

    public func heatmapStart(weeks: Int, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let daysFromSunday = (weekday - calendar.firstWeekday + 7) % 7
        let startOfThisWeek = calendar.date(byAdding: .day, value: -daysFromSunday, to: today) ?? today
        return calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: startOfThisWeek) ?? startOfThisWeek
    }
}

public struct SkillGroup: Sendable, Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var copies: [SkillCopy]
    public var harnesses: [HarnessID]
    public var inShared: Bool
    public var identical: Bool
    public var scopes: [SkillScope]
    public var issues: [String]
    public var usage: SkillUsage = .empty

    public var hasArchive: Bool { copies.contains { $0.location.scope == .archived } }
    public var archivedOnly: Bool { !copies.isEmpty && copies.allSatisfy { $0.location.scope == .archived } }
    public var activeCopies: [SkillCopy] { copies.filter { $0.location.scope != .archived } }
    public var hasUserCopy: Bool { copies.contains { $0.location.scope == .user } }

    /// Cursor built-in or plugin cache already covers this harness's own folder.
    public func managedPresence(for target: UserFolderTarget) -> String? {
        guard let harness = target.harness else { return nil }
        let managed = activeCopies.filter { $0.location.scope == .plugin || $0.location.scope == .builtin }
        guard managed.contains(where: { $0.location.harnesses.contains(harness) }) else { return nil }
        if managed.contains(where: { $0.location.scope == .builtin && $0.location.harnesses.contains(harness) }) {
            return "Built-in"
        }
        return "Plugin"
    }

    public var catalogScopes: [SkillScope] {
        let active = Set(activeCopies.map(\.location.scope))
        return Self.catalogScopeOrder.filter { active.contains($0) }
    }

    public var scopeSortKey: String {
        catalogScopes.map(\.rawValue).joined(separator: ",")
    }

    public var invokeLabel: String {
        let flags = Set((activeCopies.isEmpty ? copies : activeCopies).map(\.disableModelInvocation))
        if flags.count > 1 { return "mixed" }
        if flags.contains(true) { return "manual" }
        return "auto"
    }

    public static let catalogScopeOrder: [SkillScope] = [.user, .project, .plugin, .builtin]
}

public struct HarnessSummary: Sendable, Identifiable {
    public var id: HarnessID
    public var name: String
    public var shortName: String
    public var colorHex: String
    public var blurb: String
    public var readsSharedAgents: Bool
    public var skillCount: Int
    public var uniqueNames: [String]
    public var missingNames: [String]
    public var locations: [String]
}

public struct InventoryIssue: Sendable, Identifiable {
    public var id: String { "\(code)|\(skillName ?? "")|\(path ?? "")|\(message)" }
    public var level: String
    public var code: String
    public var message: String
    public var skillName: String?
    public var path: String?
}

public struct Inventory: Sendable {
    public var scannedAt: Date
    public var homeDir: String
    public var scanRoots: [String]
    public var uniqueCount: Int
    public var archivedCount: Int
    public var copyCount: Int
    public var sharedCount: Int
    public var fragmentedCount: Int
    public var issueCount: Int
    public var harnesses: [HarnessSummary]
    public var groups: [SkillGroup]
    public var copies: [SkillCopy]
    public var issues: [InventoryIssue]
}

public struct ScanOptions: Sendable {
    public var homeDir: String
    public var scanRoots: [String]
    public var includePlugins: Bool
    public var includeBuiltins: Bool
    public var extraSkillDirs: [String]
    public var assignedOrigins: [String: AssignedOrigin]
    /// `nil` means every known harness. The app passes the set detected on this Mac.
    public var installedHarnesses: Set<HarnessID>?

    public init(
        homeDir: String,
        scanRoots: [String] = [],
        includePlugins: Bool = true,
        includeBuiltins: Bool = true,
        extraSkillDirs: [String] = [],
        assignedOrigins: [String: AssignedOrigin] = [:],
        installedHarnesses: Set<HarnessID>? = nil
    ) {
        self.homeDir = homeDir
        self.scanRoots = scanRoots
        self.includePlugins = includePlugins
        self.includeBuiltins = includeBuiltins
        self.extraSkillDirs = extraSkillDirs
        self.assignedOrigins = assignedOrigins
        self.installedHarnesses = installedHarnesses
    }
}

public struct ManagerConfig: Codable, Equatable, Sendable {
    public var scanRoots: [String]
    public var includePlugins: Bool
    public var includeBuiltins: Bool
    public var origins: [String: AssignedOrigin]

    public init(
        scanRoots: [String] = [],
        includePlugins: Bool = true,
        includeBuiltins: Bool = true,
        origins: [String: AssignedOrigin] = [:]
    ) {
        self.scanRoots = scanRoots
        self.includePlugins = includePlugins
        self.includeBuiltins = includeBuiltins
        self.origins = origins
    }
}

public enum LoadTarget: Hashable, Sendable {
    case everywhere
    case harness(HarnessID)
}

public struct LibrarySkill: Sendable, Equatable, Identifiable {
    public var id: String { subpath.isEmpty ? name : subpath }
    public var name: String
    public var description: String
    public var subpath: String
}

public struct LibrarySession: Sendable {
    public var locator: GitLocator
    public var label: String
    public var revision: String?
    public var skills: [LibrarySkill]
    var cloneDir: String
}

public struct LibraryPreviewResult: Sendable {
    public var ok: Bool
    public var session: LibrarySession?
    public var error: String?

    public static func success(_ session: LibrarySession) -> LibraryPreviewResult {
        LibraryPreviewResult(ok: true, session: session, error: nil)
    }

    public static func failure(_ error: String) -> LibraryPreviewResult {
        LibraryPreviewResult(ok: false, session: nil, error: error)
    }
}

public enum LibraryItemStatus: String, Sendable {
    case loaded
    case alreadyPresent = "already-present"
    case failed
}

public struct LibraryItemResult: Sendable {
    public var name: String
    public var subpath: String
    public var dest: String?
    public var origin: AssignedOrigin?
    public var status: LibraryItemStatus
    public var error: String?
}

public struct LibraryLoadResult: Sendable {
    public var items: [LibraryItemResult]
    public var assignedOrigins: [String: AssignedOrigin]
    public var error: String?

    public var ok: Bool { error == nil && items.allSatisfy { $0.status != .failed } }
    public var loadedCount: Int { items.filter { $0.status == .loaded }.count }
}

public enum ActionMode: String, Sendable {
    case symlink
    case copy
}

public enum LinkAction: String, Sendable {
    case created
    case alreadyLinked = "already-linked"
    case removed
    case relocated
    case archived
    case restored
    case deleted
    case deactivated
    case activated
    case updated
    case alreadyCurrent = "already-current"
}

public struct ActionResult: Sendable {
    public var ok: Bool
    public var action: LinkAction?
    public var target: String?
    public var source: String?
    public var mode: ActionMode?
    public var error: String?
    public var results: [ActionResult]?
    public var revision: String? = nil

    public static func success(
        action: LinkAction,
        target: String,
        source: String,
        mode: ActionMode? = nil,
        revision: String? = nil
    ) -> ActionResult {
        ActionResult(
            ok: true,
            action: action,
            target: target,
            source: source,
            mode: mode,
            error: nil,
            results: nil,
            revision: revision
        )
    }

    public static func failure(_ error: String) -> ActionResult {
        ActionResult(
            ok: false,
            action: nil,
            target: nil,
            source: nil,
            mode: nil,
            error: error,
            results: nil,
            revision: nil
        )
    }
}
