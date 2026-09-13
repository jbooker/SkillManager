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

public enum SkillScope: String, Codable, Sendable {
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

    public var hasArchive: Bool { copies.contains { $0.location.scope == .archived } }
    public var archivedOnly: Bool { !copies.isEmpty && copies.allSatisfy { $0.location.scope == .archived } }
    public var activeCopies: [SkillCopy] { copies.filter { $0.location.scope != .archived } }
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

    public init(
        homeDir: String,
        scanRoots: [String] = [],
        includePlugins: Bool = true,
        includeBuiltins: Bool = true,
        extraSkillDirs: [String] = [],
        assignedOrigins: [String: AssignedOrigin] = [:]
    ) {
        self.homeDir = homeDir
        self.scanRoots = scanRoots
        self.includePlugins = includePlugins
        self.includeBuiltins = includeBuiltins
        self.extraSkillDirs = extraSkillDirs
        self.assignedOrigins = assignedOrigins
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
