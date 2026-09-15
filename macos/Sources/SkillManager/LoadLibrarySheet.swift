import SwiftUI
import SkillManagerCore

struct LoadLibrarySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Load from GitHub")
                    .font(.title2.weight(.semibold))
                Text("Paste a skill library, or a URL that points at one skill. Choose who should see them before anything is copied onto disk.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("https://github.com/anthropics/skills", text: $model.libraryURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await model.findLibrarySkills() }
                }

            Picker("Available to", selection: $model.libraryTarget) {
                Text("All harnesses").tag(LoadTarget.everywhere)
                ForEach(model.installedHarnessIDs) { id in
                    Text(Harnesses.all.first { $0.id == id }?.name ?? id.rawValue)
                        .tag(LoadTarget.harness(id))
                }
            }
            Text(targetBlurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    Task { await model.findLibrarySkills() }
                } label: {
                    if model.libraryBusy && model.librarySession == nil {
                        Text("Finding…")
                    } else {
                        Text("Find skills")
                    }
                }
                .disabled(model.libraryBusy || model.libraryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut("f", modifiers: [.command])

                if previewIsStale {
                    Text("URL changed — find skills again")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let session = model.librarySession {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(session.label)
                            .font(.headline)
                        Spacer()
                        Button("Select all") {
                            model.librarySelected = Set(session.skills.map(\.id))
                        }
                        .disabled(model.libraryBusy)
                        Button("Select none") {
                            model.librarySelected = []
                        }
                        .disabled(model.libraryBusy)
                    }
                    .controlSize(.small)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(session.skills) { skill in
                                Toggle(isOn: selectedBinding(for: skill.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(skill.name)
                                            .font(.body.weight(.medium))
                                        if !skill.description.isEmpty {
                                            Text(skill.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        if !skill.subpath.isEmpty {
                                            Text(skill.subpath)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .disabled(model.libraryBusy)
                            }
                        }
                    }
                    .frame(minHeight: 120, maxHeight: 260)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !model.libraryStatus.isEmpty {
                Text(model.libraryStatus)
                    .font(.caption)
                    .foregroundStyle(model.libraryBusy ? .secondary : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(model.libraryBusy)
                Button(loadLabel) {
                    Task { await model.loadLibrary() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canLoad)
            }
        }
        .padding(24)
        .frame(width: 540)
        .interactiveDismissDisabled(model.libraryBusy)
        .overlay {
            if model.libraryBusy {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
    }

    private var previewIsStale: Bool {
        guard model.librarySession != nil else { return false }
        return model.libraryURL.trimmingCharacters(in: .whitespacesAndNewlines) != model.libraryPreviewedURL
    }

    private var canLoad: Bool {
        model.librarySession != nil
            && !model.librarySelected.isEmpty
            && !model.libraryBusy
            && !previewIsStale
    }

    private var loadLabel: String {
        let count = model.librarySelected.count
        if model.libraryBusy, model.librarySession != nil {
            return "Loading…"
        }
        if count == 0 {
            return "Load skills"
        }
        return count == 1 ? "Load 1 skill" : "Load \(count) skills"
    }

    private var targetBlurb: String {
        switch model.libraryTarget {
        case .everywhere:
            return "Copies into ~/.agents/skills and links ~/.claude/skills, which is the pair that every installed harness can see."
        case .harness(let id):
            let name = Harnesses.all.first { $0.id == id }?.shortName ?? id.rawValue
            let path: String
            switch id {
            case .claude: path = "~/.claude/skills"
            case .cursor: path = "~/.cursor/skills"
            case .grok: path = "~/.grok/skills"
            case .codex: path = "~/.codex/skills"
            case .gemini: path = "~/.gemini/skills"
            case .opencode: path = "~/.config/opencode/skills"
            }
            return "Copies into \(path). \(name) will load them; other harnesses will not, unless they already read that folder."
        }
    }

    private func selectedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { model.librarySelected.contains(id) },
            set: { on in
                if on {
                    model.librarySelected.insert(id)
                } else {
                    model.librarySelected.remove(id)
                }
            }
        )
    }
}
