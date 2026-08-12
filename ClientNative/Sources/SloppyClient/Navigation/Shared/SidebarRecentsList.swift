import SloppyClientCore
import SloppyClientUI
import SwiftUI

@MainActor
struct SidebarRecentsList: View {
    let viewModel: MainViewModel

    @Environment(\.theme) private var theme
    @AppStorage("client_chat_sidebar_layout_mode") private var layoutMode = SidebarLayoutMode.list

    private var sections: ChatSidebarSections {
        ChatSidebarSections.build(
            sessions: viewModel.chatViewModel.sessionCatalog,
            projects: viewModel.projects,
            pinnedSessionIds: viewModel.chatViewModel.pinnedSessionIds,
            mode: viewModel.chatSidebarMode,
            projectPreviewLimit: 5
        )
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: theme.spacing.s) {
            if !sections.pinned.isEmpty {
                SidebarSectionTitle(title: "Priority")
                if layoutMode == .cards {
                    sessionCardGrid(sections.pinned)
                } else {
                    ForEach(sections.pinned) { SidebarSessionItem(viewModel: viewModel, session: $0) }
                }
            }

            HStack {
                SidebarSectionTitle(title: viewModel.chatSidebarMode.title)
                Spacer()
                if viewModel.chatSidebarMode == .projects {
                    Button {
                        viewModel.presentProjectCreator()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New project")
                    .help("New project")
                }
                if !viewModel.chatViewModel.sessionCatalog.isEmpty {
                    SidebarListModeMenu(viewModel: viewModel)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        layoutMode = layoutMode == .list ? .cards : .list
                    }
                } label: {
                    Image(systemName: layoutMode == .list ? "rectangle.grid.2x2" : "list.bullet")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(layoutMode == .list ? "Show as cards" : "Show as list")
                .help(layoutMode == .list ? "Card view" : "List view")
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
        if viewModel.chatViewModel.isLoadingSessions && viewModel.chatViewModel.sessionCatalog.isEmpty {
            SidebarStatusText(text: "Loading chats…")
        } else if sections.pinned.isEmpty && sections.sessions.isEmpty && sections.projectGroups.isEmpty {
            SidebarStatusText(text: "No chats yet")
        } else if viewModel.chatSidebarMode == .allChats {
            if layoutMode == .cards {
                sessionCardGrid(sections.sessions)
            } else {
                ForEach(sections.dayGroups) { group in
                    SidebarSectionTitle(title: daySectionTitle(for: group.day))
                        .padding(.top, theme.spacing.s)
                    ForEach(group.sessions) { session in
                        SidebarSessionItem(viewModel: viewModel, session: session)
                    }
                }
            }
        } else {
            if layoutMode == .cards {
                LazyVGrid(columns: cardColumns, alignment: .leading, spacing: theme.spacing.s) {
                    ForEach(sections.projectGroups.prefix(viewModel.visibleProjectCount)) {
                        SidebarProjectCard(viewModel: viewModel, group: $0)
                    }
                }
                .padding(.horizontal, theme.spacing.xs)
            } else {
                ForEach(sections.projectGroups.prefix(viewModel.visibleProjectCount)) {
                    SidebarProjectGroupView(viewModel: viewModel, group: $0)
                }
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

    private var cardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 148, maximum: 280), spacing: theme.spacing.s, alignment: .top)]
    }

    private func sessionCardGrid(_ sessions: [ChatSessionSummary]) -> some View {
        LazyVGrid(columns: cardColumns, alignment: .leading, spacing: theme.spacing.s) {
            ForEach(sessions) { session in
                SidebarSessionCard(viewModel: viewModel, session: session)
            }
        }
        .padding(.horizontal, theme.spacing.xs)
    }

    private func daySectionTitle(for day: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(day) {
            return "Today"
        }

        let today = calendar.startOfDay(for: Date())
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        if (1...6).contains(daysAgo) {
            return day.formatted(.dateTime.weekday(.wide))
        }

        if calendar.component(.year, from: day) == calendar.component(.year, from: today) {
            return day.formatted(.dateTime.month(.wide).day())
        }
        return day.formatted(.dateTime.month(.wide).day().year())
    }
}

private enum SidebarLayoutMode: String {
    case list
    case cards
}

@MainActor
private struct SidebarSessionItem: View {
    let viewModel: MainViewModel
    let session: ChatSessionSummary
    var showsProjectName = true

    var body: some View {
        SidebarSessionRow(
            session: session,
            projectName: viewModel.projects.first { $0.id == session.projectId }?.name,
            showsProjectName: showsProjectName,
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
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.spacing.xs) {
                NavigationLink(value: MainSidebarSelection.project(group.id)) {
                    HStack(spacing: theme.spacing.s) {
                        Image(systemName: group.project.semanticIconName)
                            .font(.system(size: theme.typography.body))
                            .foregroundColor(isSelected ? theme.colors.accentCyan : theme.colors.textMuted)
                            .frame(width: 22)
                        Text(group.project.name)
                            .font(.system(size: theme.typography.body))
                            .foregroundColor(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        viewModel.openProjectKanbanTab(project: group.project)
                    }
                )
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Button {
                    viewModel.showNewProjectChat(project: group.project)
                } label: {
                    Icons.symbol(.chatAddOn, size: theme.typography.body)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.colors.textMuted)
                .opacity(Double(isHovered ? 1 : 0))
                .allowsHitTesting(isHovered)
                .accessibilityLabel("New chat in \(group.project.name)")
                .help("New chat")

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: theme.typography.caption, weight: .semibold))
                    .foregroundColor(theme.colors.textMuted)
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
                    .draggable(group.id)
                    .accessibilityLabel("Reorder \(group.project.name)")
                    .help("Drag to reorder")

                Button {
                    viewModel.toggleProjectCollapse(projectId: group.id)
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: theme.typography.caption, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.colors.textMuted)
                .accessibilityLabel(isCollapsed ? "Expand \(group.project.name)" : "Collapse \(group.project.name)")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .frame(minHeight: MainSidebarView.rowMinimumHeight)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered || isSelected || isDropTarget ? theme.colors.surfaceRaised : .clear)
            }
            .dropDestination(for: String.self) { projectIDs, _ in
                guard let projectID = projectIDs.first else { return false }
                return viewModel.moveProject(projectID, relativeTo: group.id)
            } isTargeted: {
                isDropTarget = $0
            }
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .contextMenu {
                Button("Edit Project") {
                    viewModel.presentProjectEditor(group.project)
                }
            }

            if !isCollapsed {
                ForEach(sessions) {
                    SidebarSessionItem(viewModel: viewModel, session: $0, showsProjectName: false)
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
