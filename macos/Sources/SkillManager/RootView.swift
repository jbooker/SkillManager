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
                .inspectorColumnWidth(min: 280, ideal: 360, max: 520)
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

    private func sidebarRow(_ title: String, count: Int, systemImage: String) -> some View {
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
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search name, description, path…")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("View", selection: $model.catalogView) {
                    Text("List").tag(CatalogMode.list)
                    Text("Matrix").tag(CatalogMode.matrix)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Menu("Filters", systemImage: "line.3.horizontal.decrease.circle") {
                    Toggle("Issues", isOn: $model.issuesOnly)
                    Toggle("Not in shared global", isOn: $model.unshared)
                    if case .harness = model.filter {
                        Toggle("Hidden from this harness", isOn: $model.gaps)
                    }
                }
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
        case .harness(let id):
            return Harnesses.all.first { $0.id == id }?.name ?? id.rawValue
        }
    }
}

struct SkillCatalogList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedSkills) {
            if model.catalogView == .matrix {
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
            } else {
                ForEach(model.visibleGroups) { group in
                    SkillRow(group: group)
                        .tag(group.id)
                        .contextMenu { SkillContextMenu(group: group) }
                }
            }
        }
        .listStyle(.inset)
    }

    private func matrixHeader(_ title: String) -> some View {
        Text(title)
            .frame(width: 36)
            .multilineTextAlignment(.center)
    }
}

struct SkillRow: View {
    let group: SkillGroup

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.headline)
                Text(group.copies.first?.homeRelative ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let origin = group.copies.first?.origin, origin.kind != .local {
                    Text(origin.label)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if !group.description.isEmpty {
                    Text(group.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                CoverageGlyph(present: Set(group.harnesses))
                HStack(spacing: 6) {
                    if group.inShared {
                        Text("shared")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    if group.archivedOnly {
                        Text("archived")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    if !group.issues.isEmpty {
                        Text("\(group.issues.count)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
            if group.copies.contains(where: { $0.location.id == "agents-user" }) {
                Button("Unload from shared global") {
                    Task { await model.run { SkillActions.unloadFromShared(skillName: group.name, homeDir: model.homeDir) } }
                }
            }
            ForEach(HarnessID.allCases) { id in
                if group.copies.contains(where: { $0.location.id == userLocationId(id) }) {
                    Button("Unload from \(Harnesses.all.first { $0.id == id }?.shortName ?? id.rawValue)") {
                        Task { await model.run { SkillActions.unloadFromHarness(skillName: group.name, homeDir: model.homeDir, harness: id) } }
                    }
                }
            }
            Button("Archive user copies") {
                Task { await model.run { SkillActions.archiveUserCopies(skillName: group.name, homeDir: model.homeDir) } }
            }
            Divider()
            Button("Delete user copies…", role: .destructive) {
                model.confirmDeleteName = group.name
            }
        }
    }

    private func userLocationId(_ harness: HarnessID) -> String {
        switch harness {
        case .claude: return "claude-user"
        case .cursor: return "cursor-user"
        case .grok: return "grok-user"
        case .codex: return "codex-user"
        case .gemini: return "gemini-user"
        case .opencode: return "opencode-user"
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
