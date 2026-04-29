import AdaEngine
import SloppyClientCore
import SloppyClientUI

@MainActor
public struct AgentsScreen: View {
    @State private var agents: [APIAgentRecord] = []
    @State private var isLoading = false
    @State private var didLoadAgents = false

    private let apiClient: SloppyAPIClient

    public init(apiClient: SloppyAPIClient = SloppyAPIClient()) {
        self.apiClient = apiClient
    }

    public var body: some View {
        NavigationStack {
            AgentListView(
                agents: agents,
                isLoading: isLoading,
                onRefresh: { loadAgents(force: true) }
            )
            .onAppear { loadAgents() }
            .navigate(for: String.self) { agentId in
                if let agent = agents.first(where: { $0.id == agentId }) {
                    AgentDetailView(agent: agent, apiClient: apiClient)
                }
            }
        }
    }

    private func loadAgents(force: Bool = false) {
        guard force || !didLoadAgents else { return }
        guard !isLoading else { return }

        isLoading = true
        Task { @MainActor in
            defer {
                didLoadAgents = true
                isLoading = false
            }
            let fetched = (try? await apiClient.fetchAgents()) ?? []
            agents = fetched
        }
    }
}
