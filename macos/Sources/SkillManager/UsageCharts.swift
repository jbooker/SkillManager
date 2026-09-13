import SwiftUI
import SkillManagerCore

enum ScopeCatalog {
    static let sidebarScopes: [SkillScope] = [.project, .user, .plugin, .builtin]

    static func label(_ scope: SkillScope) -> String {
        switch scope {
        case .user: return "User"
        case .project: return "Team"
        case .plugin: return "Plugin"
        case .builtin: return "Built-in"
        case .archived: return "Archived"
        case .unknown: return "Other"
        }
    }

    static func icon(_ scope: SkillScope) -> String {
        switch scope {
        case .user: return "person"
        case .project: return "person.2"
        case .plugin: return "puzzlepiece.extension"
        case .builtin: return "cube"
        case .archived: return "archivebox"
        case .unknown: return "questionmark.circle"
        }
    }

    static func color(_ scope: SkillScope) -> Color {
        switch scope {
        case .user: return Color(hex: "B5D97A")
        case .project: return Color(hex: "3DDC97")
        case .plugin: return Color(hex: "7AA2FF")
        case .builtin: return Color(hex: "6FBF73")
        case .archived: return Color(hex: "E8A838")
        case .unknown: return Color.secondary
        }
    }
}

struct ScopeBadge: View {
    let scope: SkillScope

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: ScopeCatalog.icon(scope))
                .font(.system(size: 9, weight: .semibold))
            Text(ScopeCatalog.label(scope))
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(ScopeCatalog.color(scope))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(ScopeCatalog.color(scope).opacity(0.14), in: Capsule())
    }
}

struct ActivitySparkline: View {
    let usage: SkillUsage
    var weeks: Int = 26

    var body: some View {
        let counts = usage.weeklyCounts(weeks: weeks)
        let peak = max(counts.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                Capsule()
                    .fill(barColor(count: count, peak: peak))
                    .frame(width: 2.5, height: barHeight(count: count, peak: peak))
            }
        }
        .frame(width: 84, height: 22, alignment: .bottom)
        .accessibilityLabel("\(usage.sessionCount) sessions")
    }

    private func barHeight(count: Int, peak: Int) -> CGFloat {
        guard count > 0 else { return 2 }
        return max(3, 22 * CGFloat(count) / CGFloat(peak))
    }

    private func barColor(count: Int, peak: Int) -> Color {
        guard count > 0 else { return Color.primary.opacity(0.12) }
        let t = CGFloat(count) / CGFloat(peak)
        return Color(hex: "3DDC97").opacity(0.35 + 0.65 * t)
    }
}

struct SessionHeatmap: View {
    let usage: SkillUsage
    var weeks: Int = 26
    private let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        let cells = usage.heatmapCounts(weeks: weeks)
        let peak = max(cells.max() ?? 0, 1)
        let recent = usage.sessions(inLastWeeks: weeks)
        VStack(alignment: .leading, spacing: 8) {
            Text("\(recent) \(recent == 1 ? "session" : "sessions") in the last \(weeks) weeks")
                .font(.callout)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                let gap: CGFloat = 3
                let labelWidth: CGFloat = 26
                let available = max(60, geo.size.width - labelWidth - gap)
                let cell = min(12, max(6, floor((available - CGFloat(weeks - 1) * gap) / CGFloat(weeks))))
                HStack(alignment: .top, spacing: gap) {
                    VStack(alignment: .trailing, spacing: gap) {
                        ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, label in
                            Text(label)
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .frame(width: labelWidth, height: cell, alignment: .trailing)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { day in
                                HStack(spacing: gap) {
                                    ForEach(0..<weeks, id: \.self) { week in
                                        let count = cells[week * 7 + day]
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(cellColor(count: count, peak: peak))
                                            .frame(width: cell, height: cell)
                                            .help(count == 0 ? "No sessions" : "\(count) \(count == 1 ? "session" : "sessions")")
                                    }
                                }
                            }
                        }
                        HStack(spacing: 4) {
                            Text("Less")
                            ForEach(0..<5, id: \.self) { step in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(cellColor(count: step, peak: 4))
                                    .frame(width: cell, height: cell)
                            }
                            Text("More")
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(height: 7 * 12 + 6 * 3 + 22)
        }
        .accessibilityLabel("\(recent) sessions in the last \(weeks) weeks")
    }

    private func cellColor(count: Int, peak: Int) -> Color {
        guard count > 0 else { return Color.primary.opacity(0.08) }
        let t = min(1, CGFloat(count) / CGFloat(max(peak, 1)))
        return Color(hex: "26A641").opacity(0.22 + 0.78 * t)
    }
}
