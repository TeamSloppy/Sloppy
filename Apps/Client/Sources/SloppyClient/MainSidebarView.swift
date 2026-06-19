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
    private static let rowMinimumHeight: Float = 48

    let viewModel: MainViewModel
    let isOverlay: Bool

    @Environment(\.theme) private var theme
    @State private var contextMenuSessionId: String?
    @Environment(\.userInterfaceIdiom) private var userInterfaceIdiom

    private var usesLiquidGlass: Bool {
        #if os(iOS)
        false
        #else
        true
        #endif
    }

    var body: some View {
        NavigationStack {
            let c = theme.colors

            expandedSidebar(c: c)
        }
    }

    private func expandedSidebar(c: AppColors) -> some View {
        let sp = theme.spacing

        let content = VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: sp.l) {
                    chatActions(c: c, sp: sp)
                    notebooksSection(c: c, sp: sp)
                    recentsSection(c: c, sp: sp)
                }
            }
            .frame(minHeight: 0, maxHeight: .infinity)
        }
        .padding(.horizontal, sp.xs)
        .padding(.vertical, sp.s)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .overlay(anchor: .bottomTrailing) {
            if userInterfaceIdiom == .phone {
                newChatFloatingButton(c: c, sp: sp)
                    .padding(
                        EdgeInsets(
                            top: 0,
                            leading: 0,
                            bottom: isOverlay ? sp.xl + sp.s : sp.m,
                            trailing: sp.s
                        )
                    )
            }
        }

        return sidebarSurface(content, c: c)
    }

    private func chatActions(c: AppColors, sp: AppSpacing) -> some View {
        VStack(alignment: .leading, spacing: sp.xs) {
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

    private func newChatFloatingButton(c: AppColors, sp: AppSpacing) -> some View {
        let ty = theme.typography

        return Button {
            viewModel.selectNewChat()
        } label: {
            Icons.symbol(.add, size: ty.body)
                .foregroundColor(c.textPrimary)
        }
        .frame(width: 48, height: 48)
        .background(c.surfaceRaised.opacity(0.92 as Float))
        .glassEffect(.regular.tint(c.surfaceRaised.opacity(0.34 as Float)), in: Circle())
    }

    private func recentsSection(c: AppColors, sp: AppSpacing) -> some View {
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            sectionLabel("Recents", c: c, ty: ty)

            if viewModel.chatViewModel.isLoadingSessions && viewModel.chatViewModel.sessions.isEmpty {
                Text("Loading chats…")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                    .padding(.horizontal, sp.m)
                    .padding(.vertical, sp.s)
            } else if viewModel.chatViewModel.sessions.isEmpty {
                Text("No chats yet")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                    .padding(.horizontal, sp.m)
                    .padding(.vertical, sp.s)
            } else {
                ForEach(viewModel.chatViewModel.sessions.prefix(12)) { session in
                    chatSessionRow(session: session, c: c, sp: sp)
                }
            }

            if let sessionActionStatus = viewModel.chatViewModel.sessionActionStatus {
                Text(sessionActionStatus)
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
        let isPinned = viewModel.chatViewModel.pinnedSessionIds.contains(session.id)
        let isSelected = viewModel.selectedSidebarItem == .chats
            && viewModel.chatViewModel.selectedSessionId == session.id
        let isContextMenuTarget = contextMenuSessionId == session.id
        let title = session.title.isEmpty ? "Chat" : session.title
        return sidebarPlainRow(
            icon: nil,
            title: title,
            trailing: isPinned ? "PIN" : nil,
            isSelected: isSelected || isContextMenuTarget,
            c: c,
            sp: sp,
            titleColor: (isSelected || isContextMenuTarget) ? c.textPrimary : c.textSecondary,
            leadingInset: 12
        ) {
            viewModel.selectChatSession(session)
        }
        .contextMenu(
            onPresent: {
                contextMenuSessionId = session.id
            },
            onDismiss: {
                if contextMenuSessionId == session.id {
                    contextMenuSessionId = nil
                }
            }
        ) {
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
    }

    private func projectsSection(c: AppColors, sp: AppSpacing) -> some View {
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            if viewModel.projects.isEmpty {
                Text(viewModel.isLoadingProjects ? "Loading…" : "No projects yet")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                    .padding(.horizontal, sp.m)
                    .padding(.vertical, sp.s)
            } else {
                VStack(alignment: .leading, spacing: sp.s) {
                    ForEach(viewModel.projects) { project in
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

            let expanded = viewModel.expandedTaskLists.contains(project.id)
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
            isSelected: viewModel.selectedSidebarItem == .project(project.id),
            c: c,
            sp: sp
        ) {
            viewModel.expandedTaskLists.remove(project.id)
            viewModel.selectProject(project)
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
        let isSelected = viewModel.selectedSidebarItem == .task(projectId: projectId, taskId: task.id)

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
            viewModel.selectTask(
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
                viewModel.expandedTaskLists.remove(projectId)
            } else {
                viewModel.expandedTaskLists.insert(projectId)
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
        .frame(minHeight: Self.rowMinimumHeight, alignment: .leading)
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
            rowMinimumHeight: Self.rowMinimumHeight,
            usesLiquidGlass: usesLiquidGlass,
            action: action
        )
    }

    @ViewBuilder
    private func sidebarSurface<Content: View>(_ content: Content, c: AppColors) -> some View {
        if usesLiquidGlass {
            content
                .padding(4)
                .glassEffect(.regular.tint(Color.black.opacity(0.14 as Float)), in: RoundedRectangle(cornerRadius: 28))
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

}

private struct MobileSidebarOverlayIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 48, height: 48)
            .glassEffect(.regular, in: Circle())
            .opacity(configuration.isPressed ? 0.78 as Float : 1)
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
    let rowMinimumHeight: Float
    let usesLiquidGlass: Bool
    let action: @MainActor () -> Void

    @State private var isHovered = false

    var body: some View {
        let isActive = isSelected || isHovered
        let displayTitle = shortened(
            title,
            maxCharacters: leadingInset > 0 ? 36 : 30
        )

        Button(action: {
            action()
        }) {
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
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: rowMinimumHeight, alignment: .leading)
            .padding(EdgeInsets(top: 0, leading: leadingInset + spacing.s, bottom: 0, trailing: spacing.m + spacing.s))
            .glassEffect(
                isActive ? .regular.tint(Color.white.opacity(isSelected ? 0.07 as Float : 0.035 as Float)) : .identity,
                in: Capsule()
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
