import AppKit
import SwiftUI
import SkillManagerCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            Form {
                Picker("Appearance", selection: $model.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text("Dark uses macOS Dark Aqua for the window, sidebar, and menus. System follows Settings → Appearance.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Section {
                    LabeledContent("Version", value: AppInfo.displayVersion)
                    Button("About Skill Manager…") {
                        model.presentAbout()
                    }
                } header: {
                    Text("Skill Manager")
                }
            }
            .formStyle(.grouped)
            .padding(8)
            .tabItem { Label("General", systemImage: "paintpalette") }

            Form {
                Section {
                    Text("User-level skill folders are always scanned. Add project directories so repo `.claude/skills` and `.agents/skills` show up too. Home itself is never deep-walked.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $model.scanRootsText)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .frame(minHeight: 140)
                        .overlay(alignment: .topLeading) {
                            if model.scanRootsText.isEmpty {
                                Text("One directory per line")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 16)
                                    .padding(.leading, 13)
                                    .allowsHitTesting(false)
                            }
                        }
                    HStack {
                        Button("Add Folder…") { addFolder() }
                        Spacer()
                    }
                } header: {
                    Text("Scan roots")
                }

                Section {
                    Toggle("Include Cursor / Claude plugin caches", isOn: $model.includePlugins)
                    Toggle("Include Cursor built-in skills", isOn: $model.includeBuiltins)
                }

                Section {
                    Button("Save and Rescan") {
                        Task { await model.saveSettingsAndRescan() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .formStyle(.grouped)
            .padding(8)
            .tabItem { Label("Scan Roots", systemImage: "folder") }
        }
        .onAppear { model.loadSettingsFromDisk() }
        .navigationTitle("Settings")
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose project folders to scan for .claude/skills, .agents/skills, and friends."
        guard panel.runModal() == .OK else { return }
        var lines = model.scanRootsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for url in panel.urls {
            if !lines.contains(url.path) {
                lines.append(url.path)
            }
        }
        model.scanRootsText = lines.joined(separator: "\n")
    }
}
