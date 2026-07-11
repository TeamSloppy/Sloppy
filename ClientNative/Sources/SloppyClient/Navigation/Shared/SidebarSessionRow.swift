import SloppyClientCore
import SloppyClientUI
import SwiftUI

@MainActor
struct SidebarSessionRow: View {
    let session: ChatSessionSummary
    let projectName: String?
    let isPinned: Bool
    let isSelected: Bool
    let onOpen: @MainActor () -> Void
    let onTogglePin: @MainActor () -> Void
    let onCopyDebugLink: @MainActor () -> Void
    let onDelete: @MainActor () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    private var title: String { session.title.isEmpty ? "Chat" : session.title }

    var body: some View {
        NavigationLink(value: MainSidebarSelection.chats) {
            HStack(spacing: theme.spacing.s) {
                Color.clear.frame(width: 16)
                Text(title)
                    .font(.system(size: theme.typography.body))
                    .foregroundColor(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isPinned {
                    Icons.symbol(.pushPin, size: theme.typography.caption)
                        .foregroundColor(theme.colors.textMuted)
                }
                Text(CompactRelativeTimeFormatter.string(since: session.updatedAt))
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(theme.colors.textMuted)
            }
            .padding(.horizontal, theme.spacing.s)
            .padding(.vertical, theme.spacing.xs)
            .frame(minHeight: MainSidebarView.rowMinimumHeight)
        }
        .clipShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onOpen() })
        .buttonStyle(SidebarHoverButtonStyle(isHovered: isHovered, isSelected: isSelected))
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(isPinned ? "Unpin Chat" : "Pin Chat", action: onTogglePin)
            Button("Copy Session File Debug Link", action: onCopyDebugLink)
            Button("Delete Chat", role: .destructive, action: onDelete)
        }
        .accessibilityHint(projectName.map { "Project \($0)" } ?? "")
    }
}

#Preview("Session Row") {
    SidebarSessionRow(
        session: ChatSessionSummary(
            id: "preview-session",
            agentId: "codex",
            title: "Refactor platform navigation",
            messageCount: 12,
            updatedAt: Date().addingTimeInterval(-180),
            projectId: "sloppy"
        ),
        projectName: "Sloppy",
        isPinned: true,
        isSelected: true,
        onOpen: {},
        onTogglePin: {},
        onCopyDebugLink: {},
        onDelete: {}
    )
    .frame(width: 340)
    .padding()
}
