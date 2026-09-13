import SwiftUI
import SkillManagerCore

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let group = model.selectedGroup {
            SkillDetail(group: group)
        } else {
            ContentUnavailableView(
                "Select a skill",
                systemImage: "sidebar.trailing",
                description: Text("Coverage, copies on disk, and link actions show up here.")
            )
            .navigationTitle("Inspector")
        }
    }
}

struct SkillDetail: View {
    @Environment(AppModel.self) private var model
    let group: SkillGroup
    @State private var pending: PendingAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if group.archivedOnly {
                    archiveActions
                } else {
                    foldersSection
                    if group.hasUserCopy {
                        archiveDeleteSection
                    }
                    hideSection
                }

                ForEach(group.copies) { copy in
                    CopyCard(copy: copy, group: group)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("SKILL.md")
                        .font(.headline)
                    if let copy = group.copies.first {
                        let body = model.skillBody(for: copy)
                        if body.isEmpty {
                            Text("No body.")
                                .foregroundStyle(.secondary)
                        } else {
                            SkillMarkdownView(source: body)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(group.name)
        .toolbarTitleDisplayMode(.inline)
        .confirmationDialog(pending?.title ?? "Confirm", isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        )) {
            if let pending {
                Button(pending.confirmLabel, role: .destructive) {
                    Task { await run(pending) }
                    self.pending = nil
                }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text(pending?.message ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.name)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            Text(group.description.isEmpty ? "No description." : group.description)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Text("invocation")
                    .foregroundStyle(.tertiary)
                Text(group.invokeLabel)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            if group.usage.sessionCount > 0 {
                SessionHeatmap(usage: group.usage)
                    .padding(.top, 4)
            }
            CoverageGlyph(present: Set(group.harnesses), size: 10)
            HStack(spacing: 6) {
                ForEach(group.catalogScopes, id: \.self) { scope in
                    ScopeBadge(scope: scope)
                }
            }
            if let note = ownershipNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                if group.archivedOnly {
                    Text("Archived — no harness loads this")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if group.inShared {
                    Text("In shared global")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if group.hasUserCopy {
                    Text("Not in shared global")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if group.hasArchive && !group.archivedOnly {
                    Text("Also archived")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if group.hasUserCopy {
                    ForEach(HarnessID.allCases.filter { !group.harnesses.contains($0) }) { id in
                        Text("Hidden from \(Harnesses.all.first { $0.id == id }?.shortName ?? id.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("User folders")
                .font(.headline)
            Text("Each row is a folder on this Mac. Link if this skill isn’t there; unlink if it is. Cursor and the other shared-global harnesses can already load a skill from ~/.agents/skills without a per-harness copy.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !linkedEverywhere {
                Button("Link everywhere") {
                    guard let path = group.activeCopies.first?.skillDir else { return }
                    Task { await model.run { SkillActions.makeEverywhere(skillDir: path, homeDir: model.homeDir) } }
                }
                .help("Symlink into ~/.agents/skills and ~/.claude/skills so every harness can load it")
            }

            ForEach(UserFolderTarget.allCases) { target in
                folderRow(target)
            }
        }
    }

    private var ownershipNote: String? {
        let managed = group.activeCopies.filter { $0.location.scope == .plugin || $0.location.scope == .builtin }
        guard !managed.isEmpty else { return nil }
        let pluginName = managed.compactMap(\.location.pluginName).first
        if managed.contains(where: { $0.location.scope == .builtin }) {
            if group.hasUserCopy {
                return "Cursor ships a built-in copy in ~/.cursor/skills-cursor. Unlink only removes your user-folder copies; the built-in stays."
            }
            return "Cursor ships this as a built-in in ~/.cursor/skills-cursor. Cursor owns that folder, so it cannot be unlinked. Link it into a user folder only if you want other harnesses to load it too."
        }
        let plugin = pluginName.map { "the \($0) plugin" } ?? "a Cursor or Claude plugin"
        if group.hasUserCopy {
            return "A copy also lives in the cache for \(plugin). Unlink only removes your user-folder copies; the plugin cache stays."
        }
        return "This copy lives in the plugin cache from \(plugin). The plugin owns it, so it cannot be unlinked. Link it into a user folder if you want a personal copy other harnesses can load."
    }

    private var linkedEverywhere: Bool {
        copy(withLocation: UserFolderTarget.shared.locationId) != nil
            && copy(withLocation: UserFolderTarget.claude.locationId) != nil
    }

    private func folderRow(_ target: UserFolderTarget) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.title)
                Text(target.homeRel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let existing = copy(withLocation: target.locationId) {
                Button("Unlink", role: .destructive) {
                    unlink(existing)
                }
            } else if let presence = group.managedPresence(for: target) {
                Text(presence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Link") {
                    link(target)
                }
            }
        }
    }

    private var hideSection: some View {
        let editable = group.activeCopies.first { $0.location.scope == .user || $0.location.scope == .project }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Keep on disk, hide from auto-load")
                .font(.headline)
            if let editable {
                if editable.disableModelInvocation {
                    Button("Allow auto-load again") {
                        Task { await model.run { SkillActions.setInactive(skillDir: editable.skillDir, homeDir: model.homeDir, inactive: false) } }
                    }
                    .help("Removes disable-model-invocation from SKILL.md")
                } else {
                    Button("Mark inactive") {
                        Task { await model.run { SkillActions.setInactive(skillDir: editable.skillDir, homeDir: model.homeDir, inactive: true) } }
                    }
                    .help("Sets disable-model-invocation so models do not auto-load this skill")
                }
            } else {
                Text("Plugin and built-in skills cannot be marked inactive here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var archiveDeleteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Archive or delete")
                .font(.headline)
            Button("Archive user copies") {
                pending = .archiveAll
            }
            .help("Remove from every user skill folder and keep a copy in ~/.config/skill-manager/archive")
            Button("Delete user copies…", role: .destructive) {
                pending = .deleteAll
            }
        }
    }

    private var archiveActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Archived")
                .font(.headline)
            Button("Restore") {
                Task { await model.run { SkillActions.restoreArchived(skillName: group.name, homeDir: model.homeDir) } }
            }
            Button("Delete archive…", role: .destructive) {
                pending = .deleteArchive
            }
        }
    }

    private func copy(withLocation id: String) -> SkillCopy? {
        group.copies.first { $0.location.id == id }
    }

    private func link(_ target: UserFolderTarget) {
        guard let path = group.activeCopies.first?.skillDir else { return }
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

    private func unlink(_ copy: SkillCopy) {
        if copy.isSymlink {
            Task { await model.run { SkillActions.unloadCopy(targetPath: copy.skillDir, homeDir: model.homeDir) } }
        } else {
            pending = .unlink(copy)
        }
    }

    private func run(_ action: PendingAction) async {
        switch action {
        case .unlink(let copy):
            await model.run { SkillActions.unloadCopy(targetPath: copy.skillDir, homeDir: model.homeDir) }
        case .archiveAll:
            await model.run { SkillActions.archiveUserCopies(skillName: group.name, homeDir: model.homeDir) }
        case .deleteAll:
            await model.run { SkillActions.deleteUserCopies(skillName: group.name, homeDir: model.homeDir, includeArchive: true) }
        case .deleteArchive:
            await model.run { SkillActions.deleteUserCopies(skillName: group.name, homeDir: model.homeDir, includeArchive: true) }
        }
    }
}

private enum PendingAction {
    case unlink(SkillCopy)
    case archiveAll
    case deleteAll
    case deleteArchive

    var title: String {
        switch self {
        case .unlink: return "Unlink this copy?"
        case .archiveAll: return "Archive user copies?"
        case .deleteAll: return "Delete user copies?"
        case .deleteArchive: return "Delete archive?"
        }
    }

    var confirmLabel: String {
        switch self {
        case .unlink: return "Unlink"
        case .archiveAll: return "Archive"
        case .deleteAll, .deleteArchive: return "Delete"
        }
    }

    var message: String {
        switch self {
        case .unlink:
            return "This is a real skill folder. If it is the last user copy, it will be moved to the Skill Manager archive so harnesses stop loading it."
        case .archiveAll:
            return "Remove this skill from every user skill folder and keep a copy in ~/.config/skill-manager/archive. Plugin, built-in, and project copies stay put."
        case .deleteAll:
            return "Permanently delete user-level copies and any archive of this skill. This cannot be undone. Plugin, built-in, and project copies stay put."
        case .deleteArchive:
            return "Permanently delete the archived copy. This cannot be undone."
        }
    }
}

struct CopyCard: View {
    @Environment(AppModel.self) private var model
    let copy: SkillCopy
    let group: SkillGroup
    @State private var confirmDelete = false
    @State private var showSourceSheet = false
    @State private var sourceText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.location.label)
                .font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Path", copy.homeRelative)
                row("Loads in", copy.location.harnesses.map { id in
                    Harnesses.all.first { $0.id == id }?.shortName ?? id.rawValue
                }.joined(separator: ", ").nilIfEmpty ?? "—")
                row("Scope", scopeLine)
                row("Source", copy.origin.label)
                if let rev = copy.origin.pinnedRef {
                    row("Revision", String(rev.prefix(12)))
                }
                row("Invoke", copy.disableModelInvocation ? "Slash command only" : "Model can auto-load")
                row("Files", filesLine)
            }
            if let status = model.originStatus[copy.key] {
                Text(status.message)
                    .font(.caption)
                    .foregroundStyle(status.state == .updateAvailable ? Color.orange : .secondary)
            } else if model.originBusy.contains(copy.key) {
                Text("Checking source…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Copy path") { model.copyPath(copy.skillDir) }
                Button("Show in Finder") { model.reveal(copy.skillDir) }
                if copy.origin.refreshable {
                    Button(model.originBusy.contains(copy.key) ? "Refreshing…" : "Refresh from source") {
                        Task { await model.refreshCopy(copy) }
                    }
                    .disabled(model.originBusy.contains(copy.key))
                    .help(copy.origin.locator.map { "Pull the latest from \($0)" } ?? "Refresh from the recorded source")
                }
                if copy.location.scope != .plugin && copy.location.scope != .builtin {
                    Button(copy.origin.kind == .local ? "Set GitHub source…" : "Change source…") {
                        sourceText = copy.origin.locator ?? ""
                        showSourceSheet = true
                    }
                }
            }
            .controlSize(.small)
            HStack {
                if copy.location.scope == .archived {
                    Button("Restore") {
                        Task { await model.run { SkillActions.restoreArchived(skillName: group.name, homeDir: model.homeDir) } }
                    }
                    Button("Delete archive", role: .destructive) { confirmDelete = true }
                } else if copy.location.scope == .builtin {
                    Text("Cursor built-in — cannot unlink")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if copy.location.scope == .plugin {
                    Text("Plugin cache — cannot unlink")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if copy.location.scope == .project && !copy.isSymlink {
                    Text("Project copy — edit it in the repo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if copy.location.scope == .user || copy.isSymlink {
                    Button("Unlink", role: .destructive) {
                        if copy.isSymlink {
                            Task { await model.run { SkillActions.unloadCopy(targetPath: copy.skillDir, homeDir: model.homeDir) } }
                        } else {
                            confirmDelete = true
                        }
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: "\(copy.key)|\(copy.contentHash)|\(copy.origin.pinnedRef ?? "")") {
            await model.inspectOrigin(copy)
        }
        .sheet(isPresented: $showSourceSheet) {
            SourceSheet(sourceText: $sourceText) {
                showSourceSheet = false
                Task { await model.assignOrigin(copy: copy, text: sourceText) }
            } onCancel: {
                showSourceSheet = false
            }
        }
        .confirmationDialog(copy.location.scope == .archived ? "Delete archive?" : "Unlink this copy?", isPresented: $confirmDelete) {
            Button(copy.location.scope == .archived ? "Delete" : "Unlink", role: .destructive) {
                Task {
                    if copy.location.scope == .archived {
                        await model.run { SkillActions.deleteCopy(targetPath: copy.skillDir, homeDir: model.homeDir) }
                    } else {
                        await model.run { SkillActions.unloadCopy(targetPath: copy.skillDir, homeDir: model.homeDir) }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if copy.location.scope == .archived {
                Text("Permanently delete the archived copy of \(group.name).")
            } else {
                Text("This is a real skill folder. If it is the last user copy, it will be archived so harnesses stop loading it.")
            }
        }
    }

    private var scopeLine: String {
        var parts = [ScopeCatalog.label(copy.location.scope)]
        if let plugin = copy.location.pluginName { parts.append(plugin) }
        return parts.joined(separator: " · ")
    }

    private var filesLine: String {
        var parts = ["\(copy.fileCount)"]
        if copy.hasScripts { parts.append("scripts") }
        if copy.hasReferences { parts.append("references") }
        return parts.joined(separator: " · ")
    }

    private func row(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}

private struct SourceSheet: View {
    @Binding var sourceText: String
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub source")
                .font(.headline)
            Text("Paste a GitHub URL or owner/repo/path. Refresh will copy the latest SKILL.md folder from that repo.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("anthropics/skills/skills/frontend-design", text: $sourceText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
