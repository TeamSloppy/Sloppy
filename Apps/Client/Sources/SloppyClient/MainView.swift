import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat

@MainActor
struct MainView: View {
    private static let shellRadius: Float = 34
    private static let panelRadius: Float = 28
    private static let rowRadius: Float = 22
    private static let sidebarWidth: Float = 292

    let baseURL: URL
    let settings: ClientSettings
    let connectionMonitor: ConnectionMonitor
    let onOpenSettings: @MainActor () -> Void
    let onOpenWorkspace: @MainActor () -> Void

    @State private var projects: [APIProjectRecord] = []
    @State private var isLoadingProjects = false
    @State private var expandedTaskLists: Set<String> = []

    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing

        ZStack {
            c.background.ignoresSafeArea()

            HStack(spacing: sp.l) {
                sidebarContent(c: c, sp: sp)
                    .frame(width: Self.sidebarWidth)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .padding(sp.l)
                    .glassEffect(.regular, in: .rect(cornerRadius: Self.panelRadius))

                ChatScreen(
                    apiClient: SloppyAPIClient(baseURL: baseURL),
                    settings: settings,
                    connectionMonitor: connectionMonitor,
                    onOpenSettings: onOpenSettings
                )
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .padding(sp.l)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.shellRadius))
        .padding(8)
        .onAppear {
            Task { await loadProjects() }
        }
    }

    @ViewBuilder
    private func sidebarContent(c: AppColors, sp: AppSpacing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sp.l) {
                sidebarHeader(c: c, sp: sp)
                topActions(c: c, sp: sp)
                projectsSection(c: c, sp: sp)
                pinnedSection(c: c, sp: sp)
                sidebarFooter(c: c, sp: sp)
            }
        }
    }

    private func sidebarHeader(c: AppColors, sp: AppSpacing) -> some View {
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.m) {
            HStack(spacing: sp.m) {
                Text("◈")
                    .font(.system(size: ty.heading))
                    .foregroundColor(c.accentCyan)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))

                VStack(alignment: .leading, spacing: sp.xs) {
                    Text("Sloppy")
                        .font(.system(size: ty.heading))
                        .foregroundColor(c.textPrimary)
                    Text("Desktop Workspace")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func topActions(c: AppColors, sp: AppSpacing) -> some View {
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            Button(action: {}) {
                HStack(spacing: sp.s) {
                    Text("✦")
                        .font(.system(size: ty.body))
                        .foregroundColor(c.accentCyan)
                        .frame(width: 20)
                    Text("New Chat")
                        .font(.system(size: ty.body))
                        .foregroundColor(c.textPrimary)
                    Spacer()
                    Text("⌘N")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                }
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.m)
                .glassEffect(.regular, in: .rect(cornerRadius: Self.rowRadius))
            }

            sidebarRow(
                icon: "⌘",
                title: "Search Projects",
                trailing: "K",
                c: c,
                sp: sp,
                action: {}
            )
        }
    }

    private func projectsSection(c: AppColors, sp: AppSpacing) -> some View {
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            sidebarSectionHeader("Projects", c: c)

            if projects.isEmpty {
                Text(isLoadingProjects ? "Loading…" : "No projects yet")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                    .padding(.leading, sp.xs)
            } else {
                ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                    projectCard(
                        project: project,
                        isActive: index == 0,
                        c: c,
                        sp: sp
                    )
                }
            }
        }
    }

    private func pinnedSection(c: AppColors, sp: AppSpacing) -> some View {
        let ty = theme.typography
        let pinned = pinnedTasks()

        return VStack(alignment: .leading, spacing: sp.s) {
            sidebarSectionHeader("Recent Tasks", c: c)

            if pinned.isEmpty {
                Text(isLoadingProjects ? "Loading…" : "No active tasks yet")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                    .padding(.leading, sp.xs)
            } else {
                ForEach(pinned, id: \.id) { item in
                    taskRow(title: item.task.title, status: item.task.status, c: c, sp: sp)
                }
            }
        }
    }

    private func sidebarFooter(c: AppColors, sp: AppSpacing) -> some View {
        VStack(alignment: .leading, spacing: sp.s) {
            sidebarRow(
                icon: "⌂",
                title: "Open Workspace",
                trailing: nil,
                c: c,
                sp: sp,
                action: onOpenWorkspace
            )

            sidebarRow(
                icon: "⋯",
                title: "Settings",
                trailing: nil,
                c: c,
                sp: sp,
                action: onOpenSettings
            )
        }
        .padding(.top, sp.m)
    }

    private func sidebarSectionHeader(_ title: String, c: AppColors) -> some View {
        let ty = theme.typography

        return Text(title)
            .font(.system(size: ty.caption))
            .foregroundColor(c.textMuted)
    }

    private func projectCard(
        project: APIProjectRecord,
        isActive: Bool,
        c: AppColors,
        sp: AppSpacing
    ) -> some View {
        let ty = theme.typography
        let tasks = project.tasks ?? []
        let expanded = expandedTaskLists.contains(project.id)
        let visibleLimit = expanded ? tasks.count : min(tasks.count, 3)
        let visible = Array(tasks.prefix(visibleLimit))
        let activeTasks = tasks.filter { ["in_progress", "ready", "needs_review"].contains($0.status) }.count

        return VStack(alignment: .leading, spacing: sp.s) {
            HStack(spacing: sp.s) {
                Text(projectMonogram(project.name))
                    .font(.system(size: ty.caption))
                    .foregroundColor(isActive ? c.background : c.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(isActive ? c.accentCyan.opacity(0.85 as Float) : c.surfaceRaised.opacity(0.85 as Float))
                    .glassEffect(.regular, in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: ty.body))
                        .foregroundColor(c.textPrimary)
                        .lineLimit(1)

                    Text("\(activeTasks) active · \(tasks.count) tasks")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                }

                Spacer(minLength: 0)

                if isActive {
                    Text("LIVE")
                        .font(.system(size: ty.micro))
                        .foregroundColor(c.accentCyan)
                }
            }

            if !visible.isEmpty {
                VStack(alignment: .leading, spacing: sp.xs) {
                    ForEach(visible) { task in
                        Text(task.title)
                            .font(.system(size: ty.caption))
                            .foregroundColor(c.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, sp.xs)
            }

            if tasks.count > 3 {
                Button {
                    if expanded {
                        expandedTaskLists.remove(project.id)
                    } else {
                        expandedTaskLists.insert(project.id)
                    }
                } label: {
                    Text(expanded ? "Show less" : "Show more")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.accentCyan)
                }
            }
        }
        .padding(sp.m)
        .background(isActive ? c.surfaceRaised.opacity(0.65 as Float) : c.surface.opacity(0.7 as Float))
        .glassEffect(.regular, in: .rect(cornerRadius: Self.rowRadius))
    }

    private func sidebarRow(
        icon: String,
        title: String,
        trailing: String?,
        c: AppColors,
        sp: AppSpacing,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        let ty = theme.typography

        return Button(action: action) {
            HStack(spacing: sp.s) {
                Text(icon)
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textSecondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: ty.body))
                    .foregroundColor(c.textPrimary)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                }
            }
            .padding(.horizontal, sp.m)
            .padding(.vertical, sp.m)
            .glassEffect(.regular, in: .rect(cornerRadius: Self.rowRadius))
        }
    }

    private func taskRow(
        title: String,
        status: String,
        c: AppColors,
        sp: AppSpacing
    ) -> some View {
        let ty = theme.typography

        return HStack(spacing: sp.s) {
            Color.clear
                .frame(width: 8, height: 8)
                .background(colorForStatus(status, c: c))
                .glassEffect(.regular, in: .rect(cornerRadius: 4))

            Text(title)
                .font(.system(size: ty.body))
                .foregroundColor(c.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.m)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.rowRadius))
    }

    private func projectMonogram(_ value: String) -> String {
        let letters = value
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let monogram = String(letters)
        return monogram.isEmpty ? "SL" : monogram.uppercased()
    }

    private func colorForStatus(_ status: String, c: AppColors) -> Color {
        switch status {
        case "in_progress":
            return c.statusActive
        case "ready", "needs_review":
            return c.statusWarning
        case "done":
            return c.statusDone
        case "blocked":
            return c.statusBlocked
        default:
            return c.statusNeutral
        }
    }

    /// Recent / active tasks shown under Pinned (no separate API yet).
    private func pinnedTasks() -> [(id: String, task: APIProjectTask)] {
        var out: [(String, APIProjectTask)] = []
        let active: Set<String> = ["in_progress", "ready", "needs_review"]
        for project in projects {
            guard let tasks = project.tasks else { continue }
            for task in tasks where active.contains(task.status) {
                out.append(("\(project.id)/\(task.id)", task))
                if out.count >= 6 { return out }
            }
        }
        return out
    }

    private func loadProjects() async {
        isLoadingProjects = true
        let client = SloppyAPIClient(baseURL: baseURL)
        let list = (try? await client.fetchProjects()) ?? []
        projects = list
        isLoadingProjects = false
    }
}
