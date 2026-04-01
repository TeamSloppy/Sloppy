import AdaEngine
import SloppyClientCore
import SloppyClientUI

enum AgentDetailTab: String, CaseIterable, Hashable {
    case info
    case tasks
    case chat

    var title: String {
        switch self {
        case .info: "INFO"
        case .tasks: "TASKS"
        case .chat: "CHAT"
        }
    }
}

struct AgentDetailView: View {
    let agent: APIAgentRecord
    let apiClient: SloppyAPIClient

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var selectedTab: AgentDetailTab = .info
    @State private var agentTasks: [APIAgentTaskRecord] = []
    @State private var tasksLoaded = false

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: sp.m) {
                BackButton("Agents", action: { dismiss() })
                Spacer()
            }
            .padding(.horizontal, sp.l)
            .padding(.vertical, sp.m)

            HStack(spacing: sp.s) {
                Color.clear
                    .frame(width: bo.thick, height: 28)
                    .background(c.accentCyan)
                Text(agent.displayName.uppercased())
                    .font(.system(size: ty.title))
                    .foregroundColor(c.textPrimary)
            }
            .padding(.horizontal, sp.l)
            .padding(.bottom, sp.m)

            TabView(selection: $selectedTab) {
                Tab(AgentDetailTab.info.title, value: AgentDetailTab.info) { tabContent(.info) }
                Tab(AgentDetailTab.tasks.title, value: AgentDetailTab.tasks) { tabContent(.tasks) }
                Tab(AgentDetailTab.chat.title, value: AgentDetailTab.chat) { tabContent(.chat) }
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
        case .chat:
            AgentChatView(agent: agent, apiClient: apiClient)
        }
    }

    private var agentInfoTab: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailRow("Name", value: agent.displayName)
                DetailRow("Role", value: agent.role.isEmpty ? "—" : agent.role)
                DetailRow("ID", value: agent.id)
                DetailRow("System", value: agent.isSystem == true ? "YES" : "NO")
            }
            .padding(sp.l)
            .border(c.border, lineWidth: bo.thin)
            .padding(sp.l)
        }
    }

    private var agentTasksTab: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return ScrollView {
            VStack(alignment: .leading, spacing: sp.s) {
                if !tasksLoaded {
                    VStack(spacing: sp.m) {
                        Button("LOAD TASKS") { loadTasks() }
                            .foregroundColor(c.accentCyan)
                    }
                    .padding(.vertical, sp.xl)
                } else if agentTasks.isEmpty {
                    EmptyStateView("No tasks assigned")
                } else {
                    ForEach(agentTasks) { record in
                        HStack(spacing: sp.m) {
                            VStack(alignment: .leading, spacing: sp.xs) {
                                Text(record.task.title)
                                    .font(.system(size: ty.body))
                                    .foregroundColor(c.textPrimary)
                                Text(record.projectName.uppercased())
                                    .font(.system(size: ty.micro))
                                    .foregroundColor(c.textMuted)
                            }
                            Spacer()
                            StatusBadge.forTaskStatus(record.task.status)
                        }
                        .padding(sp.m)
                        .background(c.surface)
                        .border(c.border, lineWidth: bo.thin)
                    }
                }
            }
            .padding(sp.l)
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
