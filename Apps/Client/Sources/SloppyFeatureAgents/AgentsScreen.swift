import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct AgentsScreen: View {
    @State private var agents: [APIAgentRecord] = []
    @State private var selectedAgentId: String?
    @State private var isLoading = false

    private let apiClient: SloppyAPIClient

    public init(apiClient: SloppyAPIClient = SloppyAPIClient()) {
        self.apiClient = apiClient
    }

    public var body: some View {
        if let agentId = selectedAgentId,
           let agent = agents.first(where: { $0.id == agentId }) {
            AgentDetailView(
                agent: agent,
                apiClient: apiClient,
                onBack: { selectedAgentId = nil }
            )
        } else {
            AgentListView(
                agents: agents,
                isLoading: isLoading,
                onSelect: { selectedAgentId = $0.id },
                onRefresh: { loadAgents() }
            )
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
