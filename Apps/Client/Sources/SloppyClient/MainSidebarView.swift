import AdaEngine
import SloppyClientCore
import SloppyClientUI

enum MainSidebarSelection: Hashable {
    case project(String)
    case task(projectId: String, taskId: String)
    case chats
}

@MainActor
struct MainSidebarView: View {
    static let expandedWidth: Float = 288
    static let collapsedWidth: Float = 64
    static let minimumWidth: Float = 240
    static let maximumWidth: Float = 420

    let viewModel: MainViewModel
    let isOverlay: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(respectsSafeArea: false) {
                VStack(alignment: .leading, spacing: 20) {
                    primaryActions
                    agentsSection
                    prioritySection
                    projectsSection
                    recentsSection
                    if let error = viewModel.catalogError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(theme.colors.statusBlocked)
                            .padding(.horizontal, 12)
                        Button("Retry") { Task { await viewModel.loadProjects(force: true) } }
                            .accessibilityIdentifier("sidebar.retry")
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            footer
        }
        .padding(.horizontal, 12)
        .background(theme.colors.surface)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("sidebar")
    }

    private var header: some View {
        HStack {
            SloppyWordmark(size: 29)
            Spacer()
            if isOverlay {
                Button(action: viewModel.dismissMobileSidebar) {
                    Icons.symbol(.close, size: 18)
                        .foregroundColor(theme.colors.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("sidebar.close")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .frame(height: 64)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Icons.symbol(.search, size: 16).foregroundColor(theme.colors.textMuted)
            TextField("Search chats and projects", text: Binding(
                get: { viewModel.searchText }, set: { viewModel.searchText = $0 }
            ))
            .textFieldStyle(PlainTextFieldStyle())
            .font(.system(size: 13))
            .foregroundColor(theme.colors.textPrimary)
            .accessibilityIdentifier("sidebar.search")
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Icons.symbol(.close, size: 14)
                        .foregroundColor(theme.colors.textMuted)
                        .frame(width: 28, height: 32)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(theme.colors.background)
    }

    private var primaryActions: some View {
        VStack(spacing: 2) {
            row(.add, "New chat", id: "sidebar.newChat", action: viewModel.selectNewChat)
            row(.notification, "Attention", selected: viewModel.navigation.section == .attention, id: "sidebar.attention") {
                viewModel.selectSection(.attention)
            }
            row(.language, "Sites", selected: viewModel.navigation.section == .sites, id: "sidebar.sites") {
                viewModel.selectSection(.sites)
            }
            row(.branch, "Pull Requests", selected: viewModel.navigation.section == .pullRequests, id: "sidebar.pullRequests") {
                viewModel.selectSection(.pullRequests)
            }
            row(.schedule, "Scheduled", selected: viewModel.navigation.section == .scheduled, id: "sidebar.scheduled") {
                viewModel.selectSection(.scheduled)
            }
        }
    }

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                sectionLabel("Agents")
                Spacer()
                WorkspaceIconButton(icon: .tune) { viewModel.selectSection(.agents) }
                    .accessibilityIdentifier("sidebar.agents")
            }
            ForEach(viewModel.chatViewModel.agents) { agent in
                row(.autoAwesome, agent.displayName, id: "sidebar.agent.\(agent.id)") { viewModel.selectAgent(agent) }
            }
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                sectionLabel("Projects")
                Spacer()
                Button { viewModel.selectSection(.projects) } label: {
                    Icons.symbol(.grid, size: 16).foregroundColor(theme.colors.textMuted).frame(width: 30, height: 30)
                }.accessibilityIdentifier("sidebar.projects")
            }
            if viewModel.visibleProjects.isEmpty {
                status(viewModel.isLoadingProjects ? "Loading projects…" : "No projects")
            }
            ForEach(viewModel.visibleProjects) { project in
                HStack(spacing: 0) {
                    row(.layers, project.name, selected: viewModel.navigation.section == .project && viewModel.workspaceProject?.id == project.id,
                        id: "sidebar.project.\(project.id)") { viewModel.selectProject(project) }
                    Button { viewModel.newProjectChat(project) } label: {
                        Icons.symbol(.chatAddOn, size: 16).foregroundColor(theme.colors.textMuted).frame(width: 30, height: 32)
                    }.accessibilityIdentifier("sidebar.project.\(project.id).newChat")
                }
                projectSessions(project)
            }
        }
    }

    private func projectSessions(_ project: APIProjectRecord) -> some View {
        let sessions = viewModel.sidebarContent.sessions(in: project.id)
        let expanded = viewModel.expandedTaskLists.contains(project.id)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sessions.prefix(expanded ? sessions.count : 5))) { session in chatSessionRow(session) }
            if sessions.count > 5 {
                Button(expanded ? "Show less" : "Show more") { viewModel.toggleTaskList(projectId: project.id) }
                    .font(.system(size: 12)).foregroundColor(theme.colors.textMuted).padding(8)
            }
        }.padding(.leading, 22)
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.sidebarContent.pinned.isEmpty {
                sectionLabel("Priority")
                ForEach(viewModel.sidebarContent.pinned) { session in chatSessionRow(session) }
            }
        }
    }

    private var recentsSection: some View {
        let content = viewModel.sidebarContent
        return VStack(alignment: .leading, spacing: 2) {
            if !content.personal.isEmpty { sectionLabel("Personal") }
            ForEach(content.personal) { session in chatSessionRow(session) }
            if content.pinned.isEmpty && content.recent.isEmpty {
                status(viewModel.searchText.isEmpty ? "No chats yet" : "No matching chats")
            }
        }
    }

    private func chatSessionRow(_ session: ChatSessionSummary) -> some View {
        let pinned = viewModel.settings.pinnedSessionIds.contains(session.id)
        let selected = viewModel.navigation.section == .chats && viewModel.selectedSidebarItem == .chats
            && viewModel.chatViewModel.selectedSessionId == session.id
            && viewModel.chatViewModel.selectedAgent?.id == session.agentId
        return row(pinned ? .pushPin : .chatAddOn, session.title.isEmpty ? "Chat" : session.title,
                   selected: selected, id: "sidebar.session.\(session.agentId).\(session.id)") {
            viewModel.selectChatSession(session)
        }
        .contextMenu {
            Button(pinned ? "Unpin Chat" : "Pin Chat") { viewModel.togglePinChatSession(session) }
            Button("Copy Session File Debug Link") { viewModel.copyDebugSessionFileLink(session) }
            Button("Delete Chat", role: .destructive) { viewModel.deleteChatSession(session) }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            theme.colors.border.frame(height: 1)
            HStack(spacing: 8) {
                Button(action: viewModel.onOpenWorkspace) {
                    HStack(spacing: 8) {
                        Icons.symbol(.layers, size: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("All").font(.system(size: 13, weight: .semibold))
                            Text(viewModel.connectionMonitor.state == .connected ? "Connected" : "Disconnected")
                                .font(.system(size: 11))
                                .foregroundColor(theme.colors.textMuted)
                        }
                        Spacer()
                    }
                    .foregroundColor(theme.colors.textPrimary)
                }
                .accessibilityIdentifier("sidebar.connection")
                Button(action: viewModel.onOpenSettings) {
                    Icons.symbol(.settings, size: 20)
                        .foregroundColor(theme.colors.textSecondary)
                        .frame(width: 44, height: 48)
                }
                .accessibilityIdentifier("sidebar.settings")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(theme.colors.textMuted)
            .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func status(_ title: String) -> some View {
        Text(title).font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
            .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func row(_ icon: MaterialSymbol, _ title: String, selected: Bool = false,
                     id: String, action: @escaping @MainActor () -> Void) -> some View {
        SidebarNavigationRow(icon: icon, title: title, selected: selected, action: action)
            .accessibilityIdentifier(id)
    }
}

private struct SidebarNavigationRow: View {
    let icon: MaterialSymbol
    let title: String
    let selected: Bool
    let action: @MainActor () -> Void
    @Environment(\.theme) private var theme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icons.symbol(icon, size: 18)
                    .foregroundColor(selected ? theme.colors.textPrimary : theme.colors.textMuted)
                Text(title).font(.system(size: 14)).foregroundColor(theme.colors.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? theme.colors.surfaceRaised : hovered ? theme.colors.background : .clear)
            }
        }
        .onHover { hovered = $0 }
    }
}
