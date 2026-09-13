import AppKit
import SwiftUI
import SkillManagerCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 196, ideal: 220, max: 280)
        } detail: {
            CatalogView()
        }
        .inspector(isPresented: $model.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 300, ideal: 400, max: 560)
        }
        .sheet(isPresented: $model.showLoadLibrary, onDismiss: {
            model.discardLibrarySession()
        }) {
            LoadLibrarySheet()
                .environment(model)
        }
        .alert("Couldn’t complete that", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        .confirmationDialog(
            "Delete \(model.confirmDeleteName ?? "this skill")?",
            isPresented: Binding(
                get: { model.confirmDeleteName != nil },
                set: { if !$0 { model.confirmDeleteName = nil } }
            )
        ) {
            Button("Delete user copies", role: .destructive) {
                let name = model.confirmDeleteName
                model.confirmDeleteName = nil
                guard let name else { return }
                Task { await model.run { SkillActions.deleteUserCopies(skillName: name, homeDir: model.homeDir, includeArchive: true) } }
            }
            Button("Cancel", role: .cancel) { model.confirmDeleteName = nil }
        } message: {
            Text("Permanently delete user-level copies and any archive. Plugin, built-in, and project copies stay put.")
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.filter) {
            Section("Scope") {
                ForEach(ScopeCatalog.sidebarScopes, id: \.self) { scope in
                    sidebarRow(
                        ScopeCatalog.label(scope),
                        count: model.scopeCount(scope),
                        systemImage: ScopeCatalog.icon(scope),
                        tint: ScopeCatalog.color(scope)
                    )
                    .tag(SidebarFilter.scope(scope))
                }
            }

            Section("Catalog") {
                sidebarRow("All skills", count: model.inventory?.uniqueCount ?? 0, systemImage: "square.grid.2x2")
                    .tag(SidebarFilter.all)
                sidebarRow("Shared global", count: model.inventory?.sharedCount ?? 0, systemImage: "link")
                    .tag(SidebarFilter.shared)
                sidebarRow("Archived", count: model.inventory?.archivedCount ?? 0, systemImage: "archivebox")
                    .tag(SidebarFilter.archived)
            }

            Section("Who can load it") {
                ForEach(model.inventory?.harnesses ?? []) { harness in
                    Label {
                        HStack {
                            Text(harness.shortName)
                            Spacer()
                            Text("\(harness.uniqueNames.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } icon: {
                        Circle()
                            .fill(Color(hex: harness.colorHex))
                            .frame(width: 8, height: 8)
                    }
                    .tag(SidebarFilter.harness(harness.id))
                    .help(harness.blurb)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                if let inv = model.inventory {
                    Text("\(inv.copyCount) copies · \(inv.issueCount) notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(model.statusText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }

    private func sidebarRow(_ title: String, count: Int, systemImage: String, tint: Color? = nil) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint ?? Color.secondary)
        }
    }
}

struct CatalogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isScanning && model.inventory == nil {
                ProgressView("Scanning skill folders…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleGroups.isEmpty {
                ContentUnavailableView(
                    "No skills match",
                    systemImage: "tray",
                    description: Text("Load a GitHub library, change the sidebar filter, clear search, or add a scan root in Settings.")
                )
            } else {
                SkillCatalogList()
            }
        }
        .navigationTitle(title)
        .navigationSubtitle("\(model.visibleGroups.count) shown")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Picker("View", selection: $model.catalogView) {
                    Text("List").tag(CatalogMode.list)
                    Text("Matrix").tag(CatalogMode.matrix)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Button {
                    model.presentLoadLibrary()
                } label: {
                    Label("Load from GitHub", systemImage: "plus")
                }
                .help("Load skills from a GitHub library")
                .disabled(model.libraryBusy)
                Button {
                    model.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the skill inspector")
                Button {
                    Task { await model.rescan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)
                .help("Rescan skill folders")
                CatalogSearchField(text: $model.query, prompt: "Search skills")
                    .frame(width: 180)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let blurb = model.filterBlurb {
                Text(blurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
        }
    }

    private var title: String {
        switch model.filter {
        case .all: return "All skills"
        case .shared: return "Shared global"
        case .archived: return "Archived"
        case .scope(let scope):
            return ScopeCatalog.label(scope)
        case .harness(let id):
            return Harnesses.all.first { $0.id == id }?.name ?? id.rawValue
        }
    }
}

struct SkillCatalogList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if model.catalogView == .matrix {
            List(selection: $model.selectedSkills) {
                Section {
                    ForEach(model.visibleGroups) { group in
                        MatrixRow(group: group)
                            .tag(group.id)
                            .contextMenu { SkillContextMenu(group: group) }
                    }
                } header: {
                    HStack(spacing: 0) {
                        Text("Skill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        matrixHeader("Shr")
                        ForEach(Harnesses.all) { harness in
                            matrixHeader(String(harness.shortName.prefix(3)))
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                }
            }
            .listStyle(.inset)
        } else {
            CatalogTable()
        }
    }

    private func matrixHeader(_ title: String) -> some View {
        Text(title)
            .frame(width: 36)
            .multilineTextAlignment(.center)
    }
}

struct SkillContextMenu: View {
    @Environment(AppModel.self) private var model
    let group: SkillGroup

    var body: some View {
        if group.archivedOnly {
            Button("Restore") {
                Task { await model.run { SkillActions.restoreArchived(skillName: group.name, homeDir: model.homeDir) } }
            }
            Button("Delete archive…", role: .destructive) {
                model.confirmDeleteName = group.name
            }
        } else {
            ForEach(UserFolderTarget.allCases) { target in
                if let existing = group.copies.first(where: { $0.location.id == target.locationId }) {
                    Button("Unlink from \(target.title)") {
                        Task { await model.run { SkillActions.unloadCopy(targetPath: existing.skillDir, homeDir: model.homeDir) } }
                    }
                } else if group.managedPresence(for: target) == nil, let path = group.activeCopies.first?.skillDir {
                    Button("Link to \(target.title)") {
                        Task {
                            await model.run {
                                if let harness = target.harness {
                                    SkillActions.linkToHarness(skillDir: path, homeDir: model.homeDir, harness: harness)
                                } else {
                                    SkillActions.promoteToShared(skillDir: path, homeDir: model.homeDir)
                                }
                            }
                        }
                    }
                }
            }
            if group.hasUserCopy {
                Button("Archive user copies") {
                    Task { await model.run { SkillActions.archiveUserCopies(skillName: group.name, homeDir: model.homeDir) } }
                }
                Divider()
                Button("Delete user copies…", role: .destructive) {
                    model.confirmDeleteName = group.name
                }
            }
        }
    }
}

struct MatrixRow: View {
    let group: SkillGroup

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(group.name)
                    .lineLimit(1)
                if !group.issues.isEmpty {
                    Text("\(group.issues.count)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MatrixCell(on: group.inShared)
                .frame(width: 36)
            ForEach(HarnessID.allCases) { id in
                MatrixCell(on: group.harnesses.contains(id))
                    .frame(width: 36)
            }
        }
    }
}

struct MatrixCell: View {
    let on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(on ? Color.accentColor : Color.primary.opacity(0.18))
            .frame(width: 10, height: 10)
            .frame(maxWidth: .infinity)
    }
}

/// Native search as a regular toolbar item. `.searchable` pins to the window’s trailing
/// edge and sits on top of the inspector; an `NSSearchField` stays with the catalog controls.
struct CatalogSearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != prompt { field.placeholderString = prompt }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
