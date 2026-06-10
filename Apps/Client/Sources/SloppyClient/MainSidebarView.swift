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
    static let expandedWidth: Float = 348
    static let collapsedWidth: Float = 64
    static let minimumWidth: Float = 240
    static let maximumWidth: Float = 520

    private static let rowRadius: Float = 18

    let projects: [APIProjectRecord]
    let isLoadingProjects: Bool
    let chatSessions: [ChatSessionSummary]
    let selectedChatSessionId: String?
    let isLoadingChatSessions: Bool
    let chatActionStatus: String?
    let pinnedSessionIds: Set<String>
    @Binding var expandedTaskLists: Set<String>
    @Binding var selectedItem: MainSidebarSelection?
    @Binding var isCollapsed: Bool
    let isOverlay: Bool
    let onDismissOverlay: @MainActor () -> Void
    let onOpenSettings: @MainActor () -> Void
    let onOpenWorkspace: @MainActor () -> Void
    let onSelectNewChat: @MainActor () -> Void
    let onSelectChatSession: @MainActor (ChatSessionSummary) -> Void
    let onDeleteChatSession: @MainActor (ChatSessionSummary) -> Void
    let onTogglePinChatSession: @MainActor (ChatSessionSummary) -> Void
    let onCopyDebugSessionFileLink: @MainActor (ChatSessionSummary) -> Void
    let onSelectProject: @MainActor (APIProjectRecord) -> Void
    let onSelectTask: @MainActor (String, String, APIProjectTask, String?) -> Void

    @Environment(\.theme) private var theme

    private var usesLiquidGlass: Bool {
        #if os(iOS)
        false
        #else
        true
        #endif
    }

    var body: some View {
        let c = theme.colors

        if isCollapsed && !isOverlay {
            collapsedSidebar(c: c)
        } else {
            expandedSidebar(c: c)
        }
    }

    private func expandedSidebar(c: AppColors) -> some View {
        let sp = theme.spacing

        let content = VStack(alignment: .leading, spacing: 0) {
            desktopWindowHeader(c: c, sp: sp)
                .padding(.bottom, sp.m)

            ScrollView {
                VStack(alignment: .leading, spacing: sp.l) {
                    chatActions(c: c, sp: sp)
                    notebooksSection(c: c, sp: sp)
                    recentsSection(c: c, sp: sp)
                }
            }
            .frame(minHeight: 0, maxHeight: .infinity)
        }
        .padding(sp.m)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)

        return sidebarSurface(content, c: c)
    }

    private func collapsedSidebar(c: AppColors) -> some View {
        let sp = theme.spacing

        return VStack(alignment: .center, spacing: sp.m) {
            sidebarIconButton(.collapseContent, isActive: false, c: c) {
                isCollapsed = false
            }

            Color.clear
                .frame(height: theme.borders.thin)
                .background(c.border.opacity(0.45 as Float))
                .padding(.horizontal, sp.m)

            ForEach(projects.prefix(5)) { project in
                sidebarIconButton(projectMonogram(project.name), isActive: isProjectSelected(project.id), c: c) {
                    onSelectProject(project)
                }
            }

            Spacer(minLength: 0)

            sidebarIconButton(.chatAddOn, isActive: selectedItem == .chats && selectedChatSessionId == nil, c: c) {
                onSelectNewChat()
            }

            sidebarIconButton(.settings, isActive: false, c: c, action: onOpenSettings)
        }
        .frame(width: Self.collapsedWidth)
        .frame(maxHeight: .infinity)
        .padding(.vertical, sp.l)
    }

    private func desktopWindowHeader(c: AppColors, sp: AppSpacing) -> some View {
        HStack(spacing: sp.s) {
            Spacer(minLength: 0)

            headerIconButton(isOverlay ? .close : .collapseContent, c: c) {
                if isOverlay {
                    onDismissOverlay()
                } else {
                    isCollapsed = true
                }
            }
        }
        .padding(.top, sp.l)
    }

    private func chatActions(c: AppColors, sp: AppSpacing) -> some View {
        VStack(alignment: .leading, spacing: sp.xs) {
            sidebarPlainRow(
                icon: .chatAddOn,
                title: "New chat",
                trailing: nil,
                isSelected: selectedItem == .chats && selectedChatSessionId == nil,
                c: c,
                sp: sp
            ) {
                onSelectNewChat()
            }

            sidebarPlainRow(
                icon: .autoAwesome,
                title: "Search chats",
                trailing: nil,
                isSelected: false,
                c: c,
                sp: sp
            ) {}

            sidebarPlainRow(
                icon: .folder,
                title: "Library",
                trailing: nil,
                isSelected: false,
                c: c,
                sp: sp
            ) {}
        }
    }

    private func recentsSection(c: AppColors, sp: AppSpacing) -> some View {
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            sectionLabel("Recents", c: c, ty: ty)

            if isLoadingChatSessions && chatSessions.isEmpty {
                Text("Loading chats…")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                    .padding(.horizontal, sp.m)
                    .padding(.vertical, sp.s)
            } else if chatSessions.isEmpty {
                Text("No chats yet")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                    .padding(.horizontal, sp.m)
                    .padding(.vertical, sp.s)
            } else {
                ForEach(chatSessions.prefix(12)) { session in
                    chatSessionRow(session: session, c: c, sp: sp)
                }
            }

            if let chatActionStatus {
                Text(chatActionStatus)
                    .font(.system(size: ty.micro))
                    .foregroundColor(c.textMuted)
                    .lineLimit(2)
                    .padding(.horizontal, sp.m)
                    .padding(.top, sp.xs)
            }
        }
        .padding(.horizontal, sp.xs)
    }

    private func notebooksSection(c: AppColors, sp: AppSpacing) -> some View {
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            sectionLabel("Notebooks", c: c, ty: ty)

            sidebarPlainRow(
                icon: .add,
                title: "New notebook",
                trailing: nil,
                isSelected: false,
                c: c,
                sp: sp
            ) {}

            projectsSection(c: c, sp: sp)
        }
        .padding(.horizontal, sp.xs)
    }

    private func sectionLabel(_ title: String, c: AppColors, ty: AppTypography) -> some View {
        Text(title)
            .font(.system(size: ty.body))
            .foregroundColor(c.textMuted)
            .padding(.horizontal, theme.spacing.s)
    }

    private func chatSessionRow(
        session: ChatSessionSummary,
        c: AppColors,
        sp: AppSpacing
    ) -> some View {
        let isPinned = pinnedSessionIds.contains(session.id)
        let title = session.title.isEmpty ? "Chat" : session.title
        return sidebarPlainRow(
            icon: nil,
            title: title,
            trailing: isPinned ? "PIN" : nil,
            isSelected: selectedChatSessionId == session.id,
            c: c,
            sp: sp,
            titleColor: selectedChatSessionId == session.id ? c.textPrimary : c.textSecondary,
            leadingInset: 12
        ) {
            onSelectChatSession(session)
        }
        .contextMenu {
            Button(isPinned ? "Unpin Chat" : "Pin Chat") {
                onTogglePinChatSession(session)
            }

            Button("Copy Session File Debug Link") {
                onCopyDebugSessionFileLink(session)
            }

            Button("Delete Chat", role: .destructive) {
                onDeleteChatSession(session)
            }
        }
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
                VStack(alignment: .leading, spacing: sp.s) {
                    ForEach(projects) { project in
                        projectGroup(project: project, c: c, sp: sp)
                    }
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
            isSelected: selectedItem == .project(project.id),
            c: c,
            sp: sp
        ) {
            onSelectProject(project)
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
        let isSelected = selectedItem == .task(projectId: projectId, taskId: task.id)

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
            onSelectTask(projectId, projectName, task, fallbackAgentId)
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
                .multilineTextAlignment(.leading)
        }
        .padding(.leading, 42)
        .padding(.trailing, sp.m)
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
            usesLiquidGlass: usesLiquidGlass,
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
                .applySidebarGlass(usesLiquidGlass, cornerRadius: 14)
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
                .applySidebarGlass(usesLiquidGlass, cornerRadius: 14)
        }
    }

    @ViewBuilder
    private func sidebarSurface<Content: View>(_ content: Content, c: AppColors) -> some View {
        if usesLiquidGlass {
            content
                .padding(8)
                .glassEffect(.regular.tint(Color.black.opacity(0.14 as Float)), in: RoundedRectangleShape(cornerRadius: 28))
        } else {
            content
                .background(c.background)
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

    private func isProjectSelected(_ projectId: String) -> Bool {
        switch selectedItem {
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
    let usesLiquidGlass: Bool
    let action: @MainActor () -> Void

    @State private var isHovered = false

    var body: some View {
        let isActive = isSelected || isHovered
        let displayTitle = shortened(
            title,
            maxCharacters: leadingInset > 0 ? 36 : 30
        )

        Button(action: action) {
            HStack(spacing: spacing.s) {
                if let icon {
                    Icons.symbol(icon, size: typography.body)
                        .foregroundColor(isSelected ? colors.accentCyan : colors.textMuted)
                        .frame(width: 22)
                } else {
                    Color.clear
                        .frame(width: 22)
                }

                Text(displayTitle)
                    .font(.system(size: typography.body))
                    .foregroundColor(titleColor ?? (isSelected ? colors.textPrimary : colors.textSecondary))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if let trailing {
                    Text(trailing)
                        .font(.system(size: typography.body))
                        .foregroundColor(colors.textMuted)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(.leading, leadingInset)
            .padding(.trailing, spacing.m)
            .padding(.vertical, spacing.s)
            .applySidebarGlass(
                usesLiquidGlass,
                style: isActive ? .regular.tint(Color.white.opacity(isSelected ? 0.07 as Float : 0.035 as Float)) : .identity,
                cornerRadius: rowRadius
            )
        }
        .onHover {
            isHovered = $0
        }
    }

    private func shortened(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters, maxCharacters > 1 else {
            return value
        }

        return String(value.prefix(maxCharacters - 1)) + "…"
    }
}

private extension View {
    @ViewBuilder
    func applySidebarGlass(
        _ isEnabled: Bool,
        style: Glass = .regular,
        cornerRadius: Float
    ) -> some View {
        if isEnabled {
            glassEffect(style, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
        }
    }
}
