import AdaEngine
import SloppyClientCore
import SloppyClientUI

enum ProjectDetailTab: String, CaseIterable, Hashable {
    case info
    case tasks
    case channels

    var title: String {
        switch self {
        case .info: "INFO"
        case .tasks: "TASKS"
        case .channels: "CHANNELS"
        }
    }
}

struct ProjectDetailView: View {
    let project: APIProjectRecord

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ProjectDetailTab = .info

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.spacingM) {
                BackButton("Projects", action: { dismiss() })
                Spacer()
            }
            .padding(.horizontal, Theme.spacingL)
            .padding(.vertical, Theme.spacingM)

            HStack(spacing: Theme.spacingS) {
                Color.clear
                    .frame(width: Theme.borderThick, height: 28)
                    .background(Theme.accent)
                Text(project.name.uppercased())
                    .font(.system(size: Theme.fontTitle))
                    .foregroundColor(Theme.textPrimary)
            }
            .padding(.horizontal, Theme.spacingL)
            .padding(.bottom, Theme.spacingM)

            TabView(selection: $selectedTab) {
                Tab(ProjectDetailTab.info.title, value: ProjectDetailTab.info) { tabContent(.info) }
                Tab(ProjectDetailTab.tasks.title, value: ProjectDetailTab.tasks) { tabContent(.tasks) }
                Tab(ProjectDetailTab.channels.title, value: ProjectDetailTab.channels) { tabContent(.channels) }
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: ProjectDetailTab) -> some View {
        switch tab {
        case .info:
            projectInfoTab
        case .tasks:
            projectTasksTab
        case .channels:
            projectChannelsTab
        }
    }

    private var projectInfoTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailRow("Name", value: project.name)
                DetailRow("Description", value: project.description.isEmpty ? "—" : project.description)
                DetailRow("Tasks", value: "\(project.tasks?.count ?? 0)")
                DetailRow("Channels", value: "\(project.channels?.count ?? 0)")
                DetailRow("Actors", value: "\(project.actors?.count ?? 0)")
                DetailRow("Teams", value: "\(project.teams?.count ?? 0)")
            }
            .padding(Theme.spacingL)
            .border(Theme.border, lineWidth: Theme.borderThin)
            .padding(Theme.spacingL)
        }
    }

    private var projectTasksTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingS) {
                let tasks = project.tasks ?? []
                if tasks.isEmpty {
                    EmptyStateView("No tasks")
                } else {
                    ForEach(tasks) { task in
                        HStack(spacing: Theme.spacingM) {
                            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                                Text(task.title)
                                    .font(.system(size: Theme.fontBody))
                                    .foregroundColor(Theme.textPrimary)
                                if let priority = task.priority {
                                    Text(priority.uppercased())
                                        .font(.system(size: Theme.fontMicro))
                                        .foregroundColor(Theme.textMuted)
                                }
                            }
                            Spacer()
                            StatusBadge.forTaskStatus(task.status)
                        }
                        .padding(Theme.spacingM)
                        .background(Theme.surface)
                        .border(Theme.border, lineWidth: Theme.borderThin)
                    }
                }
            }
            .padding(Theme.spacingL)
        }
    }

    private var projectChannelsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingS) {
                let channels = project.channels ?? []
                if channels.isEmpty {
                    EmptyStateView("No channels")
                } else {
                    ForEach(channels) { channel in
                        HStack(spacing: Theme.spacingM) {
                            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                                Text(channel.title)
                                    .font(.system(size: Theme.fontBody))
                                    .foregroundColor(Theme.textPrimary)
                                Text(channel.channelId)
                                    .font(.system(size: Theme.fontMicro))
                                    .foregroundColor(Theme.textMuted)
                            }
                            Spacer()
                        }
                        .padding(Theme.spacingM)
                        .background(Theme.surface)
                        .border(Theme.border, lineWidth: Theme.borderThin)
                    }
                }
            }
            .padding(Theme.spacingL)
        }
    }
}
