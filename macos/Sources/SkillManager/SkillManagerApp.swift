import AppKit
import SwiftUI

enum AppInfo {
    static var displayVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (version?, build?) where version != build:
            return "\(version) (\(build))"
        case let (version?, _):
            return version
        default:
            return "Development"
        }
    }
}

@main
struct SkillManagerApp: App {
    @State private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.appearance = AppearanceMode.stored.nsAppearance
    }

    var body: some Scene {
        WindowGroup("Skill Manager") {
            RootView()
                .environment(model)
                .preferredColorScheme(model.appearance.colorScheme)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    model.applyAppearance()
                    NSApp.activate(ignoringOtherApps: true)
                    await model.rescan()
                }
        }
        .defaultSize(width: 1280, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Load from GitHub…") {
                    model.presentLoadLibrary()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                Button("Rescan") {
                    Task { await model.rescan() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button(model.catalogView == .matrix ? "Show List" : "Coverage Matrix") {
                    model.catalogView = model.catalogView == .matrix ? .list : .matrix
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                Button(model.showInspector ? "Hide Inspector" : "Show Inspector") {
                    model.showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                Divider()
                Picker("Appearance", selection: Bindable(model).appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(model.appearance.colorScheme)
                .frame(width: 520, height: 480)
        }
    }
}
