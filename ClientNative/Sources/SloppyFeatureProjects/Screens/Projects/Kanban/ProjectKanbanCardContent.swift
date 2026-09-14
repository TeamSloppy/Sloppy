import SloppyClientUI
import SwiftUI

struct ProjectKanbanCardContent: View {
    let card: ProjectKanbanCard
    let columnTitle: String
    let assigneeTitle: String?
    let instanceTitle: String?

    @Environment(\.theme) private var theme
    @State private var isHovered = false

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
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isHovered ? theme.colors.surfaceRaised : theme.colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isHovered ? theme.colors.accent.opacity(0.65) : theme.colors.border, lineWidth: theme.borders.thin)
        }
        .shadow(color: .black.opacity(isHovered ? 0.24 : 0), radius: isHovered ? 10 : 0, y: isHovered ? 4 : 0)
        .scaleEffect(isHovered ? 1.01 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }
}
