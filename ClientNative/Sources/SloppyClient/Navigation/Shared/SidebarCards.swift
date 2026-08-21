import SloppyClientCore
import SloppyClientUI
import SwiftUI

@MainActor
struct SidebarSessionCard: View {
    let viewModel: MainViewModel
    let session: ChatSessionSummary

    @Environment(\.theme) private var theme

    private var title: String { session.title.isEmpty ? "Chat" : session.title }
    private var projectName: String {
        viewModel.projects.first { $0.id == session.projectId }?.name ?? "No project"
    }
    private var isPinned: Bool { viewModel.chatViewModel.pinnedSessionIds.contains(session.id) }
    private var isSelected: Bool { viewModel.selectedChatSessionID == session.id }

    var body: some View {
        primaryAction
            .buttonStyle(.plain)
            .contextMenu {
                Button(isPinned ? "Unpin Chat" : "Pin Chat") {
                    viewModel.togglePinChatSession(session)
                }
                Button("Copy Session File Debug Link") {
                    viewModel.copyDebugSessionFileLink(session)
                }
                Button("Delete Chat", role: .destructive) {
                    viewModel.deleteChatSession(session)
                }
            }
            .accessibilityHint("Project \(projectName)")
    }

    @ViewBuilder
    private var primaryAction: some View {
        #if os(macOS)
        Button { viewModel.openSessionChatTab(session) } label: { content }
        #else
        NavigationLink(value: MainSidebarSelection.chats) { content }
            .simultaneousGesture(TapGesture().onEnded { viewModel.openSessionChatTab(session) })
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
                Text(cardDate(session.updatedAt))
                    .font(.system(size: theme.typography.caption, weight: .semibold))
                    .foregroundColor(theme.colors.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isPinned {
                    Icons.symbol(.pushPin, size: theme.typography.caption)
                        .foregroundColor(theme.colors.textMuted)
                }
            }

            Text(title)
                .font(.system(size: theme.typography.body, weight: .bold))
                .foregroundColor(theme.colors.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            Spacer(minLength: theme.spacing.xs)

            VStack(alignment: .leading, spacing: 3) {
                Label(projectName, systemImage: "folder")
                    .lineLimit(1)
                Text("\(session.messageCount) messages")
            }
            .font(.system(size: theme.typography.caption))
            .foregroundColor(theme.colors.textSecondary)
        }
        .padding(theme.spacing.m)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.colors.surfaceRaised)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isSelected ? theme.colors.accent : theme.colors.border, lineWidth: theme.borders.thin)
        }
    }
}

@MainActor
struct SidebarProjectCard: View {
    let viewModel: MainViewModel
    let group: ChatSidebarProjectGroup

    @Environment(\.theme) private var theme
    @State private var isDropTarget = false

    private var isSelected: Bool { viewModel.selectedSidebarItem == .project(group.id) }
    private var projectDescription: String {
        let description = group.project.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? "No description" : description
    }

    var body: some View {
        NavigationLink(value: MainSidebarSelection.project(group.id)) {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                HStack {
                    Image(systemName: group.project.semanticIconName)
                        .font(.system(size: theme.typography.body, weight: .semibold))
                        .foregroundColor(theme.colors.accentCyan)
                    Spacer(minLength: 0)
                    Text("\(group.totalSessions.count) chats")
                        .font(.system(size: theme.typography.caption, weight: .semibold))
                        .foregroundColor(theme.colors.textMuted)
                }

                Text(group.project.name)
                    .font(.system(size: theme.typography.body, weight: .bold))
                    .foregroundColor(theme.colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                Text(projectDescription)
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(theme.colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)

                Spacer(minLength: theme.spacing.xs)

                Label("\(group.project.tasks?.count ?? 0) tasks", systemImage: "checklist")
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(theme.colors.textMuted)
            }
            .padding(theme.spacing.m)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isDropTarget ? theme.colors.surfaceGlow : theme.colors.surfaceRaised)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? theme.colors.accent : theme.colors.border, lineWidth: theme.borders.thin)
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            viewModel.openProjectKanbanTab(project: group.project)
        })
        .buttonStyle(.plain)
        .draggable(group.id)
        .dropDestination(for: String.self) { projectIDs, _ in
            guard let projectID = projectIDs.first else { return false }
            return viewModel.moveProject(projectID, relativeTo: group.id)
        } isTargeted: {
            isDropTarget = $0
        }
        .projectContextMenu(viewModel: viewModel, project: group.project)
    }
}

private func cardDate(_ date: Date) -> String {
    let calendar = Calendar.autoupdatingCurrent
    if calendar.isDateInToday(date) {
        return date.formatted(date: .omitted, time: .shortened)
    }
    if calendar.isDateInYesterday(date) {
        return "Yesterday"
    }
    if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    return date.formatted(.dateTime.day().month().year())
}
