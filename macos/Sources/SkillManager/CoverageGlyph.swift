import SwiftUI
import SkillManagerCore

struct CoverageGlyph: View {
    let present: Set<HarnessID>
    var ids: [HarnessID] = Array(HarnessID.allCases)
    var size: CGFloat = 8

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ids) { id in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(present.contains(id) ? Color(hex: Harnesses.all.first { $0.id == id }?.colorHex ?? "8E8E93") : Color.primary.opacity(0.18))
                    .frame(width: size, height: size)
                    .help(Harnesses.all.first { $0.id == id }?.shortName ?? id.rawValue)
            }
        }
        .accessibilityLabel(ids.filter { present.contains($0) }.map(\.rawValue).joined(separator: ", "))
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(red: r, green: g, blue: b)
    }
}
