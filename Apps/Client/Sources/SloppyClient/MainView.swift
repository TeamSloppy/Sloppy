import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat

@MainActor
struct MainView: View {
    private static let rowRadius: Float = 18
    private static let sidebarExpandedWidth: Float = 332
    private static let sidebarCollapsedWidth: Float = 64
    private static let sidebarMinimumWidth: Float = 240
    private static let sidebarMaximumWidth: Float = 520

    let baseURL: URL
    let settings: ClientSettings
    let connectionMonitor: ConnectionMonitor
    let onOpenSettings: @MainActor () -> Void
    let onOpenWorkspace: @MainActor () -> Void

    @State private var projects: [APIProjectRecord] = []
    @State private var isLoadingProjects = false
    @State private var expandedTaskLists: Set<String> = []
    @State private var selectedSidebarItem: SidebarSelection? = nil
    @State private var isSidebarCollapsed = false
    @State private var chatViewModel: ChatScreenViewModel
    @State private var chatNavigationSerial = 0

    @Environment(\.theme) private var theme

    init(
        baseURL: URL,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        onOpenSettings: @escaping @MainActor () -> Void,
        onOpenWorkspace: @escaping @MainActor () -> Void
    ) {
        self.baseURL = baseURL
        self.settings = settings
        self.connectionMonitor = connectionMonitor
        self.onOpenSettings = onOpenSettings
        self.onOpenWorkspace = onOpenWorkspace
        _chatViewModel = State(
            initialValue: ChatScreenViewModel(
                apiClient: SloppyAPIClient(baseURL: baseURL),
                settings: settings,
                connectionMonitor: connectionMonitor,
                onOpenSettings: onOpenSettings
            )
        )
    }

    private var sidebarWidth: Float {
        isSidebarCollapsed ? Self.sidebarCollapsedWidth : Self.sidebarExpandedWidth
    }

    private var sidebarMinimumWidth: Float {
        isSidebarCollapsed ? Self.sidebarCollapsedWidth : Self.sidebarMinimumWidth
    }

    private var sidebarMaximumWidth: Float {
        isSidebarCollapsed ? Self.sidebarCollapsedWidth : Self.sidebarMaximumWidth
    }

    var body: some View {
        let c = theme.colors

        ZStack {
            c.background
                .ignoresSafeArea()

            NavigationSplitView {
                sidebarPane(c: c)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .navigationSplitViewColumnWidth(
                        min: sidebarMinimumWidth,
                        ideal: sidebarWidth,
                        max: sidebarMaximumWidth
                    )
            } detail: {
                ChatScreen(viewModel: chatViewModel)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task { await loadProjects() }
        }
    }

    @ViewBuilder
    private func sidebarPane(c: AppColors) -> some View {
        if isSidebarCollapsed {
            collapsedSidebar(c: c)
        } else {
            expandedSidebar(c: c)
        }
    }

    private func expandedSidebar(c: AppColors) -> some View {
        let sp = theme.spacing

        return VStack(alignment: .leading, spacing: 0) {
            projectsHeader(c: c, sp: sp)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    projectsSection(c: c, sp: sp)

                    Color.clear
                        .frame(height: theme.borders.thin)
                        .background(c.border.opacity(0.45 as Float))
                        .padding(.top, sp.m)

                    chatsSection(c: c, sp: sp)
                }
            }
            .frame(minHeight: 0, maxHeight: .infinity)
        }
        .padding(sp.m)
        .glassEffect(.regular, in: RoundedRectangleShape(cornerRadius: 18))
        .padding(6)
    }

    private func collapsedSidebar(c: AppColors) -> some View {
        let sp = theme.spacing

        return VStack(alignment: .center, spacing: sp.m) {
            sidebarIconButton(.collapseContent, isActive: false, c: c) {
                isSidebarCollapsed = false
            }

            Color.clear
                .frame(height: theme.borders.thin)
                .background(c.border.opacity(0.45 as Float))
                .padding(.horizontal, sp.m)

            ForEach(projects.prefix(5)) { project in
                sidebarIconButton(projectMonogram(project.name), isActive: isProjectSelected(project.id), c: c) {
                    selectProject(project)
                }
            }

            Spacer(minLength: 0)

            sidebarIconButton(.chatAddOn, isActive: selectedSidebarItem == .chats, c: c) {
                selectNewChat()
            }

            sidebarIconButton(.settings, isActive: false, c: c, action: onOpenSettings)
        }
        .frame(width: Self.sidebarCollapsedWidth)
        .frame(maxHeight: .infinity)
        .padding(.vertical, sp.l)
    }

    private func projectsHeader(c: AppColors, sp: AppSpacing) -> some View {
        let ty = theme.typography

        return HStack(spacing: sp.s) {
            Text("Projects")
                .font(.system(size: ty.heading))
                .foregroundColor(c.textMuted)

            Spacer(minLength: 0)

            headerIconButton(.collapseContent, c: c) {
                isSidebarCollapsed = true
            }

            headerIconButton(.moreHoriz, c: c, action: {})
            headerIconButton(.openInNew, c: c, action: onOpenWorkspace)
        }
    }

    private func chatsSection(c: AppColors, sp: AppSpacing) -> some View {
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            HStack(spacing: sp.s) {
                Text("Chats")
                    .font(.system(size: ty.heading))
                    .foregroundColor(c.textMuted)

                Spacer(minLength: 0)

                headerIconButton(.moreHoriz, c: c, action: {})
                headerIconButton(.chatAddOn, c: c) {
                    selectNewChat()
                }
            }
            .padding(.horizontal, sp.m)

            sidebarPlainRow(
                icon: .chatAddOn,
                title: "New chat",
                trailing: nil,
                isSelected: selectedSidebarItem == .chats,
                c: c,
                sp: sp
            ) {
                selectNewChat()
            }
        }
        .padding(.top, sp.l)
        .padding(.horizontal, sp.s)
    }

    private func projectsSection(c: AppColors, sp: AppSpacing) -> some View {
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            if projects.isEmpty {
                Text(isLoadingProjects ? "Loading…" : "No projects yet")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                    .padding(.horizontal, sp.m)
                    .padding(.vertical, sp.s)
            } else {
                ForEach(projects) { project in
                    projectGroup(project: project, c: c, sp: sp)
                }
            }
        }
    }

    private func projectGroup(
        project: APIProjectRecord,
        c: AppColors,
        sp: AppSpacing
    ) -> some View {
        let tasks = project.tasks ?? []

        return VStack(alignment: .leading, spacing: sp.xs) {
            projectHeader(project: project, c: c, sp: sp)

            let expanded = expandedTaskLists.contains(project.id)
            let visibleLimit = expanded ? tasks.count : min(tasks.count, 5)
            let visible = Array(tasks.prefix(visibleLimit))

            ForEach(visible) { task in
                taskRow(
                    projectId: project.id,
                    projectName: project.name,
                    task: task,
                    fallbackAgentId: project.actors?.first,
                    trailing: nil,
                    c: c,
                    sp: sp
                )
            }

            if tasks.count > 5 {
                showMoreButton(projectId: project.id, isExpanded: expanded, c: c, sp: sp)
            }
        }
    }

    private func projectHeader(
        project: APIProjectRecord,
        c: AppColors,
        sp: AppSpacing
    ) -> some View {
        let ty = theme.typography

        return sidebarPlainRow(
            icon: .folder,
            title: project.name,
            trailing: nil,
            isSelected: selectedSidebarItem == .project(project.id),
            c: c,
            sp: sp
        ) {
            selectProject(project)
        }
        .font(.system(size: ty.body))
    }

    private func taskRow(
        projectId: String,
        projectName: String,
        task: APIProjectTask,
        fallbackAgentId: String?,
        trailing: String?,
        c: AppColors,
        sp: AppSpacing
    ) -> some View {
        let isSelected = selectedSidebarItem == .task(projectId: projectId, taskId: task.id)

        return sidebarPlainRow(
            icon: statusGlyph(task.status),
            title: task.title,
            trailing: trailing,
            isSelected: isSelected,
            c: c,
            sp: sp,
            titleColor: isSelected ? c.textPrimary : c.textSecondary,
            leadingInset: 12
        ) {
            selectTask(
                projectId: projectId,
                projectName: projectName,
                task: task,
                fallbackAgentId: fallbackAgentId
            )
        }
    }

    private func showMoreButton(
        projectId: String,
        isExpanded: Bool,
        c: AppColors,
        sp: AppSpacing
    ) -> some View {
        let ty = theme.typography

        return Button {
            if isExpanded {
                expandedTaskLists.remove(projectId)
            } else {
                expandedTaskLists.insert(projectId)
            }
        } label: {
            Text(isExpanded ? "Show less" : "Show more")
                .font(.system(size: ty.body))
                .foregroundColor(c.textMuted)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 48)
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.s)
    }

    @ViewBuilder
    private func sidebarPlainRow(
        icon: MaterialSymbol?,
        title: String,
        trailing: String?,
        isSelected: Bool,
        c: AppColors,
        sp: AppSpacing,
        titleColor: Color? = nil,
        leadingInset: Float = 0,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        HoverableSidebarRow(
            icon: icon,
            title: title,
            trailing: trailing,
            isSelected: isSelected,
            colors: c,
            spacing: sp,
            typography: theme.typography,
            titleColor: titleColor,
            leadingInset: leadingInset,
            rowRadius: Self.rowRadius,
            action: action
        )
    }

    private func headerIconButton(
        _ icon: MaterialSymbol,
        c: AppColors,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        let ty = theme.typography

        return Button(action: action) {
            Icons.symbol(icon, size: ty.body)
                .foregroundColor(c.textMuted)
                .frame(width: 30, height: 30)
        }
    }

    private func sidebarIconButton(
        _ icon: MaterialSymbol,
        isActive: Bool,
        c: AppColors,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        let ty = theme.typography

        return Button(action: action) {
            Icons.symbol(icon, size: ty.body)
                .foregroundColor(isActive ? c.textPrimary : c.textMuted)
                .frame(width: 40, height: 40)
                .background(isActive ? c.surfaceRaised.opacity(0.92 as Float) : Color.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }

    private func sidebarIconButton(
        _ title: String,
        isActive: Bool,
        c: AppColors,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        let ty = theme.typography

        return Button(action: action) {
            Text(title)
                .font(.system(size: title.count <= 2 ? ty.caption : ty.micro))
                .foregroundColor(isActive ? c.textPrimary : c.textMuted)
                .frame(width: 40, height: 40)
                .background(isActive ? c.surfaceRaised.opacity(0.92 as Float) : Color.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }

    private func statusGlyph(_ status: String) -> MaterialSymbol? {
        switch status {
        case "in_progress":
            return .radioButtonPartial
        case "ready", "needs_review":
            return .fiberManualRecord
        case "done":
            return .check
        case "blocked":
            return .warning
        default:
            return nil
        }
    }

    private enum SidebarSelection: Hashable {
        case project(String)
        case task(projectId: String, taskId: String)
        case chats
    }

    private func isProjectSelected(_ projectId: String) -> Bool {
        switch selectedSidebarItem {
        case .project(let selectedProjectId):
            return selectedProjectId == projectId
        case .task(let selectedProjectId, _):
            return selectedProjectId == projectId
        case .chats, nil:
            return false
        }
    }

    private func projectMonogram(_ value: String) -> String {
        let letters = value
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let monogram = String(letters)
        return monogram.isEmpty ? "SL" : monogram.uppercased()
    }

    private func selectNewChat() {
        selectedSidebarItem = .chats
        navigateChat(.blank)
    }

    private func selectProject(_ project: APIProjectRecord) {
        selectedSidebarItem = .project(project.id)
        navigateChat(
            .project(
                projectId: project.id,
                projectName: project.name,
                agentId: project.actors?.first
            )
        )
    }

    private func selectTask(
        projectId: String,
        projectName: String,
        task: APIProjectTask,
        fallbackAgentId: String?
    ) {
        selectedSidebarItem = .task(projectId: projectId, taskId: task.id)
        navigateChat(
            .task(
                projectId: projectId,
                projectName: projectName,
                taskId: task.id,
                taskTitle: task.title,
                agentId: task.actorId ?? fallbackAgentId
            )
        )
    }

    private func navigateChat(_ context: ChatNavigationRequest.Context) {
        chatNavigationSerial += 1
        chatViewModel.applyNavigationRequest(
            ChatNavigationRequest(id: chatNavigationSerial, context: context)
        )
    }

    private func loadProjects() async {
        isLoadingProjects = true
        let client = SloppyAPIClient(baseURL: baseURL)
        let list = (try? await client.fetchProjects()) ?? []
        projects = list

        if selectedSidebarItem == nil {
            selectedSidebarItem = .chats
        }
        isLoadingProjects = false
    }
}

@MainActor
private struct HoverableSidebarRow: View {
    let icon: MaterialSymbol?
    let title: String
    let trailing: String?
    let isSelected: Bool
    let colors: AppColors
    let spacing: AppSpacing
    let typography: AppTypography
    let titleColor: Color?
    let leadingInset: Float
    let rowRadius: Float
    let action: @MainActor () -> Void

    @State private var isHovered = false

    var body: some View {
        let isActive = isSelected || isHovered
        let background = if isSelected {
            colors.surfaceRaised.opacity(0.92 as Float)
        } else if isHovered {
            colors.surfaceRaised.opacity(0.52 as Float)
        } else {
            Color.clear
        }

        let row = Button(action: action) {
            HStack(spacing: spacing.s) {
                if let icon {
                    Icons.symbol(icon, size: typography.body)
                        .foregroundColor(isSelected ? colors.accentCyan : colors.textMuted)
                        .frame(width: 22)
                } else {
                    Color.clear
                        .frame(width: 22)
                }

                Text(title)
                    .font(.system(size: typography.body))
                    .foregroundColor(titleColor ?? (isSelected ? colors.textPrimary : colors.textSecondary))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let trailing {
                    Text(trailing)
                        .font(.system(size: typography.body))
                        .foregroundColor(colors.textMuted)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(.leading, leadingInset)
            .padding(.trailing, spacing.m)
            .padding(.vertical, spacing.s)
            .background(background)
        }
        .onHover { isHovered = $0 }

        if isActive {
            row.glassEffect(.regular, in: .rect(cornerRadius: rowRadius))
        } else {
            row
        }
    }
}
