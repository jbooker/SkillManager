import AppKit
import SkillManagerCore
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            actions
            if let manifest = AppInfo.manifest, !manifest.detailFields.isEmpty {
                Divider()
                manifestSection(manifest)
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(AppInfo.name)
                    .font(.title2.weight(.semibold))
                Text("Version \(AppInfo.displayVersion)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Agent Skills across Claude, Cursor, Grok, Codex, Gemini, and OpenCode.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(AppInfo.copyrightLine) · \(AppInfo.license)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Copy Version") {
                copy(AppInfo.displayVersion)
            }
            Button("GitHub") {
                NSWorkspace.shared.open(AppInfo.repositoryURL)
            }
            Spacer()
        }
        .controlSize(.small)
    }

    private func manifestSection(_ manifest: BuildManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Build details")
                    .font(.headline)
                Spacer()
                Button("Copy Manifest") {
                    copy(manifest.prettyJSON)
                }
                .controlSize(.small)
            }

            VStack(spacing: 0) {
                ForEach(Array(manifest.detailFields.enumerated()), id: \.element.id) { index, field in
                    if index > 0 {
                        Divider()
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(field.label)
                            .foregroundStyle(.secondary)
                            .frame(width: 88, alignment: .leading)
                        Text(field.value)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 7)
                    .font(.callout)
                }
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
