import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct AgentsScreen: View {
    @State private var agents: [APIAgentRecord] = []
    @State private var isLoading = false

    private let apiClient: SloppyAPIClient

    public init(apiClient: SloppyAPIClient = SloppyAPIClient()) {
        self.apiClient = apiClient
    }

    public var body: some View {
        NavigationStack {
            AgentListView(
                agents: agents,
                isLoading: isLoading,
                onRefresh: { loadAgents() }
            )
            .onAppear { loadAgents() }
            .navigate(for: String.self) { agentId in
                if let agent = agents.first(where: { $0.id == agentId }) {
                    AgentDetailView(agent: agent, apiClient: apiClient)
                }
            }
        }
    }

    private func loadAgents() {
        Task { @MainActor in
            isLoading = true
            let fetched = (try? await apiClient.fetchAgents()) ?? []
            agents = fetched
            isLoading = false
        }
    }
}
