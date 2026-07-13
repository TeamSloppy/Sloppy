import SloppyClientCore
import SloppyClientUI
import SwiftUI

@MainActor
struct SidebarRecentsList: View {
    let viewModel: MainViewModel

    @Environment(\.theme) private var theme

    private var sections: ChatSidebarSections {
        ChatSidebarSections.build(
            sessions: viewModel.chatViewModel.sessions,
            projects: viewModel.projects,
            pinnedSessionIds: viewModel.chatViewModel.pinnedSessionIds,
            mode: viewModel.chatSidebarMode,
            projectPreviewLimit: 5
        )
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: theme.spacing.s) {
            if !sections.pinned.isEmpty {
                SidebarSectionTitle(title: "Pinned")
                ForEach(sections.pinned) { SidebarSessionItem(viewModel: viewModel, session: $0) }
            }

            HStack {
                SidebarSectionTitle(title: viewModel.chatSidebarMode == .projects ? "Projects" : "Recents")
                Spacer()
                if !viewModel.chatViewModel.sessions.isEmpty {
                    SidebarListModeMenu(viewModel: viewModel)
                }
            }
            .padding(.trailing, theme.spacing.m)

            content

            if let status = viewModel.chatViewModel.sessionActionStatus {
                Text(status)
                    .font(.system(size: theme.typography.micro))
                    .foregroundColor(theme.colors.textMuted)
                    .padding(.horizontal, theme.spacing.m)
            }
        }
        .padding(.horizontal, theme.spacing.xs)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.chatViewModel.isLoadingSessions && viewModel.chatViewModel.sessions.isEmpty {
            SidebarStatusText(text: "Loading chats…")
        } else if sections.pinned.isEmpty && sections.sessions.isEmpty && sections.projectGroups.isEmpty {
            SidebarStatusText(text: "No chats yet")
        } else if viewModel.chatSidebarMode == .allChats {
            ForEach(sections.sessions.prefix(12)) { SidebarSessionItem(viewModel: viewModel, session: $0) }
        } else {
            ForEach(sections.projectGroups.prefix(viewModel.visibleProjectCount)) {
                SidebarProjectGroupView(viewModel: viewModel, group: $0)
            }

            if sections.projectGroups.count > viewModel.visibleProjectCount {
                Button("Show more project") {
                    viewModel.showMoreProjects()
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.colors.textMuted)
                .padding(.leading, 42)
                .padding(.vertical, theme.spacing.s)
            }
        }
    }
}

@MainActor
private struct SidebarSessionItem: View {
    let viewModel: MainViewModel
    let session: ChatSessionSummary

    var body: some View {
        SidebarSessionRow(
            session: session,
            projectName: viewModel.projects.first { $0.id == session.projectId }?.name,
            isPinned: viewModel.chatViewModel.pinnedSessionIds.contains(session.id),
            isSelected: viewModel.selectedChatSessionID == session.id,
            onOpen: { viewModel.openSessionChatTab(session) },
            onTogglePin: { viewModel.togglePinChatSession(session) },
            onCopyDebugLink: { viewModel.copyDebugSessionFileLink(session) },
            onDelete: { viewModel.deleteChatSession(session) }
        )
    }
}

@MainActor
private struct SidebarProjectGroupView: View {
    let viewModel: MainViewModel
    let group: ChatSidebarProjectGroup

    @Environment(\.theme) private var theme

    private var isCollapsed: Bool { viewModel.collapsedProjectIds.contains(group.id) }
    private var isExpanded: Bool { viewModel.expandedTaskLists.contains(group.id) }
    private var sessions: [ChatSessionSummary] { isExpanded ? group.totalSessions : group.visibleSessions }

    private var isSelected: Bool {
        viewModel.selectedSidebarItem == .project(group.id)
    }

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                viewModel.toggleProjectCollapse(projectId: group.id)
            } label: {
                HStack {
                    SidebarNavigationRow(
                        icon: .folder,
                        title: group.project.name,
                        isSelected: isSelected,
                        navigationValue: .project(group.id),
                        action: { viewModel.openProjectKanbanTab(project: group.project) }
                    )
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")

                    Spacer()
                }
            }
            .onHover {
                isHovered = $0
            }
            .buttonStyle(
                SidebarHoverButtonStyle(
                    isHovered: isHovered || isSelected
                )
            )
            if !isCollapsed {
                ForEach(sessions) {
                    SidebarSessionItem(viewModel: viewModel, session: $0)
                }

                if group.hiddenCount > 0 {
                    Button(isExpanded ? "Show less" : "Show more") {
                        viewModel.toggleTaskListExpansion(projectId: group.id)
                    }
                    .clipShape(Rectangle())
                    .buttonStyle(.plain)
                    .foregroundColor(theme.colors.textMuted)
                    .padding(.leading, 42)
                    .padding(.vertical, theme.spacing.s)
                }
            }
        }
        .animation(.linear(duration: 0.2), value: isCollapsed)
    }
}

private struct SidebarSectionTitle: View {
    let title: String
    @Environment(\.theme) private var theme
    var body: some View {
        Text(title)
            .font(.system(size: theme.typography.body))
            .foregroundColor(theme.colors.textMuted)
            .padding(.horizontal, theme.spacing.s)
    }
}

private struct SidebarStatusText: View {
    let text: String
    @Environment(\.theme) private var theme
    var body: some View {
        Text(text)
            .font(.system(size: theme.typography.caption))
            .foregroundColor(theme.colors.textMuted)
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.s)
    }
}

@MainActor
private struct SidebarListModeMenu: View {
    let viewModel: MainViewModel
    var body: some View {
        Menu {
            ForEach(ChatSidebarListMode.allCases, id: \.self) { mode in
                Button(mode.title) { viewModel.chatSidebarMode = mode }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
    }
}

#Preview("Recents List") {
    let viewModel = MainViewModel.preview()
    SidebarRecentsList(viewModel: viewModel)
        .frame(width: 348, height: 520, alignment: .top)
        .task {
            await viewModel.loadProjects()
        }
}
