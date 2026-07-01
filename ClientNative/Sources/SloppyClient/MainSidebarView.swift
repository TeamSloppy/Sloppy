import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

enum MainSidebarSelection: Hashable {
    case project(String)
    case task(projectId: String, taskId: String)
    case chats
}

@MainActor
struct MainSidebarView: View {
    static let expandedWidth: CGFloat = 348
    static let collapsedWidth: CGFloat = 64
    static let minimumWidth: CGFloat = 240
    static let maximumWidth: CGFloat = 520

    private static let rowRadius: CGFloat = 18
    private static let rowMinimumHeight: CGFloat = 48
    private static let desktopNavigatorSections: [MainAppSection] = [
        .projects,
        .agents,
        .chats,
        .settings
    ]

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
        let c = theme.colors

        expandedSidebar(c: c)
    }

    private func expandedSidebar(c: AppColors) -> some View {
        let sp = theme.spacing

        let content = HStack(alignment: .top, spacing: 0) {
            navigatorTabBar(c: c, sp: sp)

            ScrollView {
                activeSectionContent(c: c, sp: sp)
            }
            .refreshable {
                await viewModel.refreshContent()
            }
            .frame(minHeight: 0, maxHeight: .infinity)
        }
            .padding(.leading, sp.xs)
            .padding(.trailing, sp.xs)
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

    @ViewBuilder
    private func activeSectionContent(c: AppColors, sp: AppSpacing) -> some View {
        switch viewModel.selectedAppSection {
        case .projects:
            VStack(alignment: .leading, spacing: sp.l) {
                notebooksSection(c: c, sp: sp)
            }
        case .agents:
            VStack(alignment: .leading, spacing: sp.l) {
                sectionIntro(
                    title: "Agents",
                    body: "Agent catalog and details live in the main pane."
                )
            }
        case .chats:
            VStack(alignment: .leading, spacing: sp.l) {
                chatActions(c: c, sp: sp)
                recentsSection(c: c, sp: sp)
            }
        case .workspace:
            VStack(alignment: .leading, spacing: sp.l) {
                sectionIntro(
                    title: "Workspace",
                    body: "Use the toolbar button to open files, reviews, and the web browser for the active project."
                )
            }
        case .settings:
            VStack(alignment: .leading, spacing: sp.l) {
                sectionIntro(
                    title: "Settings",
                    body: "Connection, mesh, providers, and runtime settings open in the main pane."
                )
            }
        }
    }

    private func navigatorTabBar(c: AppColors, sp: AppSpacing) -> some View {
        VStack(alignment: .center, spacing: sp.s) {
            ForEach(Self.desktopNavigatorSections, id: \.self) { section in
                navigatorTabRow(
                    section: section,
                    isSelected: viewModel.selectedAppSection == section,
                    c: c,
                    sp: sp
                )
            }

            Spacer(minLength: 0)
        }
        .frame(width: 52)
        .padding(.top, sp.xs)
        .padding(.trailing, sp.xs)
    }

    private func navigatorTabRow(
        section: MainAppSection,
        isSelected: Bool,
        c: AppColors,
        sp: AppSpacing
    ) -> some View {
        Button {
            viewModel.selectAppSection(section)
        } label: {
            Icons.symbol(icon(for: section), size: theme.typography.body)
                .foregroundColor(isSelected ? c.textPrimary : c.textMuted)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? c.surfaceRaised : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(title(for: section))
    }

    private func sectionIntro(title: String, body: String) -> some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            Text(title)
                .font(.system(size: ty.body))
                .foregroundColor(c.textMuted)
            Text(body)
                .font(.system(size: ty.caption))
                .foregroundColor(c.textSecondary)
        }
        .padding(.horizontal, sp.s)
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
        .glassEffect(.regular.tint(c.surfaceRaised.opacity(0.34 as CGFloat)), in: Circle())
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
            sectionLabel("Projects", c: c, ty: ty)

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
            viewModel.openSessionChatTab(session)
        }
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
        let projectSessions = viewModel.chatViewModel.sessions.filter {
            $0.projectId == project.id && $0.messageCount > 0
        }
        let isCollapsed = viewModel.collapsedProjectIds.contains(project.id)
        let isExpanded = viewModel.expandedTaskLists.contains(project.id)

        return VStack(alignment: .leading, spacing: sp.xs) {
            projectHeader(project: project, c: c, sp: sp)

            if !isCollapsed {
                let visibleLimit = isExpanded ? projectSessions.count : min(projectSessions.count, 5)
                let visible = Array(projectSessions.prefix(visibleLimit))

                ForEach(visible) { session in
                    projectSessionRow(session: session, c: c, sp: sp)
                }

                if projectSessions.count > 5 {
                    showMoreButton(projectId: project.id, isExpanded: isExpanded, c: c, sp: sp)
                }
            }
        }
    }

    private func projectHeader(
        project: APIProjectRecord,
        c: AppColors,
        sp: AppSpacing
    ) -> some View {
        HStack(spacing: sp.xs) {
            sidebarPlainRow(
                icon: .folder,
                title: project.name,
                trailing: nil,
                isSelected: viewModel.selectedSidebarItem == .project(project.id),
                c: c,
                sp: sp
            ) {
                viewModel.openProjectKanbanTab(project: project)
            }

            Button {
                viewModel.toggleProjectCollapse(projectId: project.id)
            } label: {
                Icons.symbol(
                    viewModel.collapsedProjectIds.contains(project.id) ? .arrowForward : .expandMore,
                    size: theme.typography.caption
                )
                .foregroundColor(c.textMuted)
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }

    private func projectSessionRow(
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
            viewModel.openSessionChatTab(session)
        }
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
            let project = APIProjectRecord(
                id: projectId,
                name: projectName,
                tasks: [task]
            )
            viewModel.openTaskChatTab(
                project: project,
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
            viewModel.toggleTaskListExpansion(projectId: projectId)
        } label: {
            Text(isExpanded ? "Show less" : "Show more")
                .font(.system(size: ty.body))
                .foregroundColor(c.textMuted)
                .multilineTextAlignment(.leading)
        }
        .padding(.leading, 32)
        .padding(.trailing, sp.m)
        .padding(.vertical, sp.s)
        .frame(minHeight: Self.rowMinimumHeight, alignment: .leading)
        .buttonStyle(PlainHightlightButtonStyle())
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
        leadingInset: CGFloat = 0,
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

    private func icon(for section: MainAppSection) -> MaterialSymbol {
        switch section {
        case .projects:
            return .folder
        case .agents:
            return .autoAwesome
        case .chats:
            return .chatAddOn
        case .workspace:
            return .description
        case .settings:
            return .settings
        }
    }

    private func title(for section: MainAppSection) -> String {
        switch section {
        case .projects:
            return "Projects"
        case .agents:
            return "Agents"
        case .chats:
            return "Chats"
        case .workspace:
            return "Workspace"
        case .settings:
            return "Settings"
        }
    }

}

private struct MobileSidebarOverlayIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 48, height: 48)
            .glassEffect(.regular, in: Circle())
            .opacity(configuration.isPressed ? 0.78 as CGFloat : 1)
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
    let leadingInset: CGFloat
    let rowRadius: CGFloat
    let rowMinimumHeight: CGFloat
    let usesLiquidGlass: Bool
    let action: @MainActor () -> Void

    @State private var isHovered = false

    var body: some View {
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
        }
        .onHover {
            isHovered = $0
        }
        .buttonStyle(SideBarButtonStyle(isHover: isHovered))
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
        style: GlassEffect = .regular,
        cornerRadius: CGFloat
    ) -> some View {
        if isEnabled {
            glassEffect(style, in: GlassShape.rect(cornerRadius: cornerRadius))
        } else {
            self
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    @Previewable @State var rootViewModel = RootShellViewModel()
    let viewModel = MainViewModel(
        baseURL: URL.debugURL,
        settings: rootViewModel.settings,
        connectionMonitor: rootViewModel.connectionMonitor,
        onOpenSettings: {},
        onOpenWorkspace: {}
    )

    MainSidebarView(viewModel: viewModel, isOverlay: false)
        .task {
            await viewModel.loadProjects()
        }
}

struct SideBarButtonStyle: ButtonStyle {

    let isHover: Bool
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        let isActive = configuration.isPressed || isHover

        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? theme.colors.surfaceRaised : .clear)
            )
            .padding(.all, 4)
    }
}

struct PlainHightlightButtonStyle: ButtonStyle {

    @State private var isHovered: Bool = false
    @Environment(\.theme) private var theme


    func makeBody(configuration: Configuration) -> some View {
        let isActive = isHovered || configuration.isPressed
        configuration.label
            .onHover {
                self.isHovered = $0
            }
            .foregroundStyle(isActive ? theme.colors.textSecondary : theme.colors.textMuted)
    }
}
