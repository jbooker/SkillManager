import Foundation
import Observation
import SkillManagerCore
import AppKit
import SwiftUI

enum SidebarFilter: Hashable {
    case all
    case shared
    case archived
    case scope(SkillScope)
    case harness(HarnessID)
}

enum CatalogMode: String, CaseIterable, Identifiable {
    case list
    case matrix
    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: return "List"
        case .matrix: return "Coverage matrix"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static let defaultsKey = "appearanceMode"

    static var stored: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }
}

@MainActor
@Observable
final class AppModel {
    var inventory: Inventory?
    var filter: SidebarFilter = .all
    var selectedSkills: Set<String> = []
    var query = ""
    var catalogView: CatalogMode = .list
    var sortOrder: [KeyPathComparator<SkillGroup>] = [
        KeyPathComparator(\.usage.sessionCount, order: .reverse),
        KeyPathComparator(\.name, comparator: .localizedStandard),
    ]
    var showInspector = true
    var appearance: AppearanceMode = .stored {
        didSet { applyAppearance() }
    }
    var isScanning = false
    var lastError: String?
    var statusText = "Scanning…"
    var includePlugins = true
    var includeBuiltins = true
    var scanRootsText = ""
    var originStatus: [String: RefreshInspection] = [:]
    var originBusy: Set<String> = []
    var confirmDeleteName: String?
    var showLoadLibrary = false
    @ObservationIgnored private var aboutWindowController: NSWindowController?
    var libraryURL = ""
    var libraryTarget: LoadTarget = .everywhere
    var librarySession: LibrarySession?
    var librarySelected: Set<String> = []
    var libraryBusy = false
    var libraryStatus = ""
    var libraryPreviewedURL = ""

    var homeDir: String { NSHomeDirectory() }

    var selectedGroup: SkillGroup? {
        guard let name = selectedSkills.first, let inventory else { return nil }
        return inventory.groups.first { $0.name == name }
    }

    var visibleGroups: [SkillGroup] {
        guard let inventory else { return [] }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = inventory.groups.filter { group in
            switch filter {
            case .all:
                if group.archivedOnly { return false }
            case .shared:
                if !group.inShared { return false }
            case .archived:
                if !group.hasArchive { return false }
            case .scope(let scope):
                if group.archivedOnly { return false }
                if !group.catalogScopes.contains(scope) { return false }
            case .harness(let id):
                if !group.harnesses.contains(id) { return false }
            }
            if q.isEmpty { return true }
            let blob = ([group.name, group.description] + group.copies.map {
                "\($0.homeRelative) \($0.location.label) \($0.location.pluginName ?? "") \($0.origin.label)"
            }).joined(separator: " ").lowercased()
            return blob.contains(q)
        }
        if catalogView == .matrix {
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return filtered.sorted(using: sortOrder)
    }

    func scopeCount(_ scope: SkillScope) -> Int {
        inventory?.groups.filter { !$0.archivedOnly && $0.catalogScopes.contains(scope) }.count ?? 0
    }

    var filterBlurb: String? {
        guard let inventory else { return nil }
        switch filter {
        case .shared:
            return "Shared global is ~/.agents/skills (and project .agents/skills). Cursor, Grok, Codex, Gemini, and OpenCode load it. Claude Code does not."
        case .archived:
            return "Archived skills live in ~/.config/skill-manager/archive. No harness loads them. Restore to put a copy back, or delete if you are done with it."
        case .harness(let id):
            guard let h = inventory.harnesses.first(where: { $0.id == id }) else { return nil }
            return "\(h.shortName) can load \(h.uniqueNames.count) skills. \(h.blurb) Missing \(h.missingNames.count) that live only elsewhere."
        case .all:
            return nil
        case .scope(let scope):
            switch scope {
            case .user:
                return "User folders: ~/.claude/skills, ~/.cursor/skills, ~/.agents/skills, and the other harness user dirs."
            case .project:
                return "Team skills live in a repo: .claude/skills, .cursor/skills, .agents/skills, and friends."
            case .plugin:
                return "Skills that arrived with a Cursor or Claude plugin, under ~/.cursor/plugins or ~/.claude/plugins. The plugin cache owns them; they cannot be unlinked here."
            case .builtin:
                return "Skills Cursor ships itself in ~/.cursor/skills-cursor. Cursor updates them; they cannot be unlinked here."
            default:
                return nil
            }
        }
    }

    func applyAppearance() {
        UserDefaults.standard.set(appearance.rawValue, forKey: AppearanceMode.defaultsKey)
        NSApp.appearance = appearance.nsAppearance
    }

    func loadSettingsFromDisk() {
        let cfg = ConfigStore.load(homeDir: homeDir)
        includePlugins = cfg.includePlugins
        includeBuiltins = cfg.includeBuiltins
        scanRootsText = cfg.scanRoots.joined(separator: "\n")
    }

    func rescan() async {
        isScanning = true
        statusText = "Scanning…"
        loadSettingsFromDisk()
        let options = ConfigStore.resolve(
            homeDir: homeDir,
            cwd: "",
            includePlugins: includePlugins,
            includeBuiltins: includeBuiltins
        )
        let built = await Task.detached(priority: .userInitiated) {
            InventoryBuilder.build(options)
        }.value
        inventory = built
        originStatus = [:]
        if let name = selectedSkills.first, !built.groups.contains(where: { $0.name == name }) {
            selectedSkills = []
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        statusText = "\(built.copyCount) copies on disk · scanned \(formatter.string(from: built.scannedAt))"
        isScanning = false
    }

    func saveSettingsAndRescan() async {
        let roots = scanRootsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            var cfg = ConfigStore.load(homeDir: homeDir)
            cfg.scanRoots = roots
            cfg.includePlugins = includePlugins
            cfg.includeBuiltins = includeBuiltins
            try ConfigStore.save(homeDir: homeDir, config: cfg)
            await rescan()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func run(_ work: () -> ActionResult) async {
        let result = work()
        if !result.ok {
            lastError = result.error ?? "Action failed"
            return
        }
        await rescan()
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    func skillBody(for copy: SkillCopy) -> String {
        guard let raw = try? String(contentsOfFile: copy.skillFile, encoding: .utf8) else { return "" }
        return SkillParser.parse(content: raw, folderName: copy.folderName).body
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func inspectOrigin(_ copy: SkillCopy) async {
        let key = copy.key
        if originBusy.contains(key) || originStatus[key] != nil { return }
        let origin = copy.origin
        if !origin.refreshable {
            originStatus[key] = SkillRefresh.inspect(origin: origin)
            return
        }
        originBusy.insert(key)
        let result = await Task.detached(priority: .utility) {
            SkillRefresh.inspect(origin: origin)
        }.value
        originStatus[key] = result
        originBusy.remove(key)
    }

    func refreshCopy(_ copy: SkillCopy) async {
        guard !originBusy.contains(copy.key) else { return }
        originBusy.insert(copy.key)
        let dest = copy.realPath
        let origin = copy.origin
        let result = await Task.detached(priority: .userInitiated) {
            SkillRefresh.apply(skillDir: dest, origin: origin)
        }.value
        originBusy.remove(copy.key)
        if !result.ok {
            lastError = result.error ?? "Refresh failed"
            return
        }
        if let revision = result.revision, origin.kind == .remote, let locator = origin.locator {
            var cfg = ConfigStore.load(homeDir: homeDir)
            let key = SkillOrigins.originKey(realPath: copy.realPath, homeDir: homeDir)
            cfg.origins[key] = AssignedOrigin(locator: locator, subpath: origin.subpath, ref: revision)
            try? ConfigStore.save(homeDir: homeDir, config: cfg)
        }
        await rescan()
    }

    func presentAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let hosting = NSHostingController(
            rootView: AboutView()
                .preferredColorScheme(appearance.colorScheme)
        )
        if let window = aboutWindowController?.window {
            window.contentViewController = hosting
            sizeAboutWindow(window, hosting: hosting)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentViewController: hosting)
        window.title = "About Skill Manager"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        sizeAboutWindow(window, hosting: hosting)
        window.center()
        let controller = NSWindowController(window: window)
        aboutWindowController = controller
        controller.showWindow(nil)
    }

    private func sizeAboutWindow(_ window: NSWindow, hosting: NSHostingController<some View>) {
        hosting.view.layoutSubtreeIfNeeded()
        var size = hosting.view.fittingSize
        if size.width < 420 { size.width = 420 }
        if size.height < 220 { size.height = 220 }
        window.setContentSize(size)
    }

    func presentLoadLibrary() {
        discardLibrarySession()
        libraryURL = ""
        libraryStatus = ""
        switch filter {
        case .harness(let id):
            libraryTarget = .harness(id)
        default:
            libraryTarget = .everywhere
        }
        showLoadLibrary = true
    }

    func discardLibrarySession() {
        if let session = librarySession {
            SkillLibrary.close(session)
        }
        librarySession = nil
        librarySelected = []
        libraryPreviewedURL = ""
    }

    func findLibrarySkills() async {
        let url = libraryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            libraryStatus = "Paste a GitHub URL or owner/repo path."
            return
        }
        discardLibrarySession()
        libraryBusy = true
        libraryStatus = "Finding skills…"
        let result = await Task.detached(priority: .userInitiated) {
            SkillLibrary.preview(url: url)
        }.value
        libraryBusy = false
        guard showLoadLibrary else {
            if let session = result.session {
                SkillLibrary.close(session)
            }
            return
        }
        guard result.ok, let session = result.session else {
            libraryStatus = result.error ?? "Couldn’t find skills in that repo."
            return
        }
        librarySession = session
        libraryPreviewedURL = url
        librarySelected = Set(session.skills.map(\.id))
        let noun = session.skills.count == 1 ? "skill" : "skills"
        libraryStatus = "\(session.skills.count) \(noun) in \(session.label)"
    }

    func loadLibrary() async {
        guard let session = librarySession else { return }
        libraryBusy = true
        libraryStatus = "Loading…"
        let target = libraryTarget
        let selected = librarySelected
        let home = homeDir
        let result = await Task.detached(priority: .userInitiated) {
            SkillLibrary.load(session: session, selecting: selected, homeDir: home, target: target)
        }.value
        libraryBusy = false
        if !result.ok {
            let details = result.items.filter { $0.status == .failed }.compactMap(\.error)
            libraryStatus = ([result.error].compactMap { $0 } + details).joined(separator: "\n")
            lastError = result.error ?? details.first ?? "Couldn’t load those skills."
            return
        }
        if !result.assignedOrigins.isEmpty {
            var cfg = ConfigStore.load(homeDir: homeDir)
            for (key, origin) in result.assignedOrigins {
                cfg.origins[key] = origin
            }
            do {
                try ConfigStore.save(homeDir: homeDir, config: cfg)
            } catch {
                lastError = error.localizedDescription
            }
        }
        let loaded = result.loadedCount
        let skipped = result.items.filter { $0.status == .alreadyPresent }.count
        discardLibrarySession()
        showLoadLibrary = false
        await rescan()
        if loaded == 0, skipped > 0 {
            statusText = skipped == 1 ? "That skill was already on disk" : "Those skills were already on disk"
        } else {
            statusText = loaded == 1 ? "Loaded 1 skill" : "Loaded \(loaded) skills"
        }
    }

    func assignOrigin(copy: SkillCopy, text: String) async {
        guard let parsed = SkillOrigins.parseLocator(text, skillName: copy.name) else {
            lastError = "Couldn’t parse that as a GitHub repo or git URL."
            return
        }
        var cfg = ConfigStore.load(homeDir: homeDir)
        let key = SkillOrigins.originKey(realPath: copy.realPath, homeDir: homeDir)
        cfg.origins[key] = AssignedOrigin(locator: parsed.url, subpath: parsed.subpath, ref: parsed.ref)
        do {
            try ConfigStore.save(homeDir: homeDir, config: cfg)
            await rescan()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
