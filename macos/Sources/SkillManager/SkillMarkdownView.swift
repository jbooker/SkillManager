import MarkdownUI
import SwiftUI

struct SkillMarkdownView: View {
    let source: String

    var body: some View {
        Markdown(source)
            .markdownTheme(.skillInspector)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Theme {
    static let skillInspector = Theme()
        .text {
            FontSize(13)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            BackgroundColor(.skillCodeFill)
        }
        .strong {
            FontWeight(.semibold)
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.9), bottom: .em(0.35))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(18)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.85), bottom: .em(0.3))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(15)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.75), bottom: .em(0.25))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(13)
                }
        }
        .heading4 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.7), bottom: .em(0.2))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(13)
                }
        }
        .heading5 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.65), bottom: .em(0.2))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(12)
                }
        }
        .heading6 { configuration in
            configuration.label
                .markdownMargin(top: .em(0.6), bottom: .em(0.2))
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(12)
                    ForegroundColor(.secondary)
                }
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.18))
                .markdownMargin(top: .zero, bottom: .em(0.7))
        }
        .blockquote { configuration in
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        FontStyle(.italic)
                        ForegroundColor(.secondary)
                    }
                    .padding(.leading, 10)
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: .zero, bottom: .em(0.7))
        }
        .codeBlock { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.12))
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.85))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.skillCodeFill,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .markdownMargin(top: .zero, bottom: .em(0.75))
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.12))
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: .zero, bottom: .em(0.7))
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.12))
                .relativePadding(.horizontal, length: .em(0.5))
                .relativePadding(.vertical, length: .em(0.22))
        }
        .thematicBreak {
            Divider().markdownMargin(top: .em(0.8), bottom: .em(0.8))
        }
}

private extension Color {
    static let skillCodeFill = Color.primary.opacity(0.06)
}
