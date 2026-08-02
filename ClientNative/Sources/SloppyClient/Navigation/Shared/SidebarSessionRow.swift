import SloppyClientCore
import SloppyClientUI
import SwiftUI

@MainActor
struct SidebarSessionRow: View {
    let session: ChatSessionSummary
    let projectName: String?
    var showsProjectName = true
    let isPinned: Bool
    let isSelected: Bool
    let onOpen: @MainActor () -> Void
    let onTogglePin: @MainActor () -> Void
    let onCopyDebugLink: @MainActor () -> Void
    let onDelete: @MainActor () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    private var title: String { session.title.isEmpty ? "Chat" : session.title }
    private var resolvedProjectName: String { projectName ?? "No project" }

    var body: some View {
        primaryAction
        .buttonStyle(SidebarHoverButtonStyle(isHovered: isHovered, isSelected: isSelected))
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(isPinned ? "Unpin Chat" : "Pin Chat", action: onTogglePin)
            Button("Copy Session File Debug Link", action: onCopyDebugLink)
            Button("Delete Chat", role: .destructive, action: onDelete)
        }
        .accessibilityHint(projectName.map { "Project \($0)" } ?? "")
    }

    @ViewBuilder
    private var primaryAction: some View {
        #if os(macOS)
        Button(action: onOpen) {
            content
        }
        #else
        NavigationLink(value: MainSidebarSelection.chats) {
            content
        }
        .simultaneousGesture(TapGesture().onEnded { onOpen() })
        #endif
    }

    private var content: some View {
        HStack(spacing: theme.spacing.s) {
            Color.clear.frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: theme.typography.body))
                    .foregroundColor(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
                    .lineLimit(1)

                if showsProjectName {
                    HStack(spacing: theme.spacing.xs) {
                        Image(systemName: "folder")
                            .font(.system(size: theme.typography.caption))
                        Text(resolvedProjectName)
                            .font(.system(size: theme.typography.caption))
                            .lineLimit(1)
                    }
                    .foregroundColor(theme.colors.textMuted)
                }
            }
            Spacer(minLength: 0)
            if isPinned {
                Icons.symbol(.pushPin, size: theme.typography.caption)
                    .foregroundColor(theme.colors.textMuted)
            }
        }
        .padding(.horizontal, theme.spacing.s)
        .padding(.vertical, 6)
        .frame(minHeight: MainSidebarView.rowMinimumHeight)
        .contentShape(Rectangle())
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
    .frame(width: 340, height: 56)
    .padding()
}
