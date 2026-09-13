import SwiftUI
import SkillManagerCore

struct CatalogTable: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(model.visibleGroups, selection: $model.selectedSkills, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name) { group in
                HStack(spacing: 8) {
                    Circle()
                        .fill(ScopeCatalog.color(group.catalogScopes.first ?? .unknown))
                        .frame(width: 7, height: 7)
                    Text(group.name)
                        .lineLimit(1)
                    if !group.issues.isEmpty {
                        Text("\(group.issues.count)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .width(min: 160, ideal: 240)

            TableColumn("Scope", value: \.scopeSortKey) { group in
                HStack(spacing: 4) {
                    ForEach(group.catalogScopes, id: \.self) { scope in
                        ScopeBadge(scope: scope)
                    }
                    if group.catalogScopes.isEmpty, group.archivedOnly {
                        ScopeBadge(scope: .archived)
                    }
                }
            }
            .width(min: 120, ideal: 180)

            TableColumn("Invoke", value: \.invokeLabel) { group in
                Text(group.invokeLabel)
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 80, max: 100)

            TableColumn("Sessions", value: \.usage.sessionCount) { group in
                Text(group.usage.sessionCount == 0 ? "—" : "\(group.usage.sessionCount)")
                    .monospacedDigit()
                    .foregroundStyle(group.usage.sessionCount == 0 ? .tertiary : .primary)
            }
            .width(min: 70, ideal: 80, max: 100)

            TableColumn("Last Used", value: \.usage.lastUsedSort) { group in
                Text(group.usage.lastUsed.map { SkillUsageScanner.relativeString(from: $0) } ?? "—")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 90, max: 120)

            TableColumn("Activity") { group in
                ActivitySparkline(usage: group.usage)
            }
            .width(min: 90, ideal: 100, max: 120)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let group = model.visibleGroups.first(where: { $0.id == id }) {
                SkillContextMenu(group: group)
            }
        }
    }
}
