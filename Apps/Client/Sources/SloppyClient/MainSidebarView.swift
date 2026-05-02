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
    static let expandedWidth: Float = 332
    static let collapsedWidth: Float = 64
    static let minimumWidth: Float = 240
    static let maximumWidth: Float = 520

    private static let rowRadius: Float = 18

    let projects: [APIProjectRecord]
    let isLoadingProjects: Bool
    @Binding var expandedTaskLists: Set<String>
    @Binding var selectedItem: MainSidebarSelection?
    @Binding var isCollapsed: Bool
    let isOverlay: Bool
    let onDismissOverlay: @MainActor () -> Void
    let onOpenSettings: @MainActor () -> Void
    let onOpenWorkspace: @MainActor () -> Void
    let onSelectNewChat: @MainActor () -> Void
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

            sidebarIconButton(.chatAddOn, isActive: selectedItem == .chats, c: c) {
                onSelectNewChat()
            }

            sidebarIconButton(.settings, isActive: false, c: c, action: onOpenSettings)
        }
        .frame(width: Self.collapsedWidth)
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

            headerIconButton(isOverlay ? .close : .collapseContent, c: c) {
                if isOverlay {
                    onDismissOverlay()
                } else {
                    isCollapsed = true
                }
            }

            headerIconButton(.moreHoriz, c: c, action: {})
            headerIconButton(.openInNew, c: c, action: onOpenWorkspace)
        }
        .padding(.top, 16)
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
                    onSelectNewChat()
                }
            }
            .padding(.horizontal, sp.m)

            sidebarPlainRow(
                icon: .chatAddOn,
                title: "New chat",
                trailing: nil,
                isSelected: selectedItem == .chats,
                c: c,
                sp: sp
            ) {
                onSelectNewChat()
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
                LazyVStack(
                    projects,
                    alignment: .leading,
                    spacing: sp.s,
                    estimatedRowHeight: 212,
                    overscan: 6
                ) { project in
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
                .background(isActive ? c.surfaceRaised.opacity(0.92 as Float) : Color.clear)
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
                .background(isActive ? c.surfaceRaised.opacity(0.92 as Float) : Color.clear)
                .applySidebarGlass(usesLiquidGlass, cornerRadius: 14)
        }
    }

    @ViewBuilder
    private func sidebarSurface<Content: View>(_ content: Content, c: AppColors) -> some View {
        if usesLiquidGlass {
            content
                .glassEffect(.regular, in: RoundedRectangleShape(cornerRadius: 12))
                .padding(6)
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
                style: isActive ? .regular : .identity,
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
