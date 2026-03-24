import AdaEngine
import SloppyClientCore
import SloppyClientUI

enum AgentDetailTab: String, CaseIterable, Hashable {
    case info
    case tasks

    var title: String {
        switch self {
        case .info: "INFO"
        case .tasks: "TASKS"
        }
    }
}

struct AgentDetailView: View {
    let agent: APIAgentRecord
    let apiClient: SloppyAPIClient
    let onBack: () -> Void

    @State private var selectedTab: AgentDetailTab = .info
    @State private var agentTasks: [APIAgentTaskRecord] = []
    @State private var tasksLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.spacingM) {
                BackButton("Agents", action: onBack)
                Spacer()
            }
            .padding(.horizontal, Theme.spacingL)
            .padding(.vertical, Theme.spacingM)

            HStack(spacing: Theme.spacingS) {
                Color.clear
                    .frame(width: Theme.borderThick, height: 28)
                    .background(Theme.accentCyan)
                Text(agent.displayName.uppercased())
                    .font(.system(size: Theme.fontTitle))
                    .foregroundColor(Theme.textPrimary)
            }
            .padding(.horizontal, Theme.spacingL)
            .padding(.bottom, Theme.spacingM)

            TabContainer(
                AgentDetailTab.allCases.map { (label: $0.title, value: $0) },
                selection: $selectedTab
            ) { tab in
                tabContent(tab)
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: AgentDetailTab) -> some View {
        switch tab {
        case .info:
            agentInfoTab
        case .tasks:
            agentTasksTab
        }
    }

    private var agentInfoTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailRow("Name", value: agent.displayName)
                DetailRow("Role", value: agent.role.isEmpty ? "—" : agent.role)
                DetailRow("ID", value: agent.id)
                DetailRow("System", value: agent.isSystem == true ? "YES" : "NO")
            }
            .padding(Theme.spacingL)
            .border(Theme.border, lineWidth: Theme.borderThin)
            .padding(Theme.spacingL)
        }
    }

    private var agentTasksTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingS) {
                if !tasksLoaded {
                    VStack(spacing: Theme.spacingM) {
                        Button("LOAD TASKS") { loadTasks() }
                            .foregroundColor(Theme.accentCyan)
                    }
                    .padding(.vertical, Theme.spacingXL)
                } else if agentTasks.isEmpty {
                    EmptyStateView("No tasks assigned")
                } else {
                    ForEach(agentTasks) { record in
                        HStack(spacing: Theme.spacingM) {
                            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                                Text(record.task.title)
                                    .font(.system(size: Theme.fontBody))
                                    .foregroundColor(Theme.textPrimary)
                                Text(record.projectName.uppercased())
                                    .font(.system(size: Theme.fontMicro))
                                    .foregroundColor(Theme.textMuted)
                            }
                            Spacer()
                            StatusBadge.forTaskStatus(record.task.status)
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

    private func loadTasks() {
        Task { @MainActor in
            let fetched = (try? await apiClient.fetchAgentTasks(agentId: agent.id)) ?? []
            agentTasks = fetched
            tasksLoaded = true
        }
    }
}
