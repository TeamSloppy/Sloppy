import SloppyClientUI
import SwiftUI

struct ProjectKanbanCardContent: View {
    let card: ProjectKanbanCard
    let columnTitle: String
    let assigneeTitle: String?
    let instanceTitle: String?

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            TaskMetadataChip(title: card.id, icon: "number", color: theme.colors.accentCyan)

            Text(card.title)
                .font(.system(size: theme.typography.body, weight: .medium))
                .foregroundColor(theme.colors.textPrimary)

            if let priority = card.priority, !priority.isEmpty {
                TaskPriorityChip(priority: priority)
            }

            Label(assigneeTitle ?? "Unassigned", systemImage: card.isClaimed ? "person.fill.checkmark" : "person")
                .foregroundStyle(theme.colors.accentCyan)
                .help(card.isClaimed ? "Claimed by \(assigneeTitle ?? "—")" : "Assigned to \(assigneeTitle ?? "no one")")

            if !card.tags.isEmpty {
                TaskTagChips(tags: card.tags)
            }

            if let metadata = card.externalMetadata {
                TaskExternalMetadataChips(metadata: metadata)
            }

            if let date = card.kanbanColumnEnteredAt {
                Label {
                    Text("\(columnTitle) since \(date.formatted(date: .abbreviated, time: .shortened))")
                } icon: {
                    Image(systemName: "clock")
                }
            } else {
                Label("Column entry time unavailable", systemImage: "clock")
                    .foregroundColor(theme.colors.textMuted)
            }

            if let instanceTitle, !instanceTitle.isEmpty {
                Label(instanceTitle, systemImage: "desktopcomputer")
            }
        }
        .font(.system(size: theme.typography.caption))
        .foregroundColor(theme.colors.textSecondary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing.m)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
