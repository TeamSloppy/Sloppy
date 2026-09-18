import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct AgentListSnapshot: Sendable {
    var activeTaskCount = 0
    var totalTaskCount = 0
    var sessionCount = 0
    var totalTokens = 0
    var currentTaskTitle: String?
    var currentTaskStatus: String?
}

@MainActor
public struct AgentsScreen: View {
    @State private var agents: [APIAgentRecord] = []
    @State private var snapshots: [String: AgentListSnapshot] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let apiClient: SloppyAPIClient

    public init(apiClient: SloppyAPIClient = SloppyAPIClient()) {
        self.apiClient = apiClient
    }

    public var body: some View {
        NavigationStack {
            AgentListView(
                agents: agents,
                snapshots: snapshots,
                isLoading: isLoading,
                errorMessage: errorMessage,
                onRefresh: { await loadAgents() }
            )
            .navigationDestination(for: String.self) { agentId in
                if let agent = agents.first(where: { $0.id == agentId }) {
                    AgentDetailView(agent: agent, apiClient: apiClient)
                }
            }
        }
        .task { await loadAgents() }
    }

    private func loadAgents() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await apiClient.fetchAgents()
            agents = fetched
            snapshots = await loadSnapshots(for: fetched)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSnapshots(for agents: [APIAgentRecord]) async -> [String: AgentListSnapshot] {
        await withTaskGroup(of: (String, AgentListSnapshot).self) { group in
            for agent in agents {
                group.addTask {
                    async let tasksRequest = try? apiClient.fetchAgentTasks(agentId: agent.id)
                    async let sessionsRequest = try? apiClient.fetchAgentSessions(agentId: agent.id, limit: 500)
                    async let usageRequest = try? apiClient.fetchAgentTokenUsage(agentId: agent.id)

                    let tasks = await tasksRequest ?? []
                    let sessions = await sessionsRequest ?? []
                    let usage = await usageRequest
                    let currentTask = tasks.filter {
                        !["done", "cancelled", "backlog"].contains($0.task.status)
                    }.sorted { lhs, rhs in
                        Self.taskRank(lhs.task.status) < Self.taskRank(rhs.task.status)
                    }.first
                    let activeStatuses = Set(["in_progress", "ready", "needs_review", "pending_approval"])

                    return (
                        agent.id,
                        AgentListSnapshot(
                            activeTaskCount: tasks.count { activeStatuses.contains($0.task.status) },
                            totalTaskCount: tasks.count,
                            sessionCount: sessions.count,
                            totalTokens: usage?.totalTokens ?? 0,
                            currentTaskTitle: currentTask?.task.title,
                            currentTaskStatus: currentTask?.task.status
                        )
                    )
                }
            }

            var values: [String: AgentListSnapshot] = [:]
            for await (agentID, snapshot) in group {
                values[agentID] = snapshot
            }
            return values
        }
    }

    private nonisolated static func taskRank(_ status: String) -> Int {
        switch status {
        case "in_progress": 0
        case "needs_review", "pending_approval": 1
        case "ready": 2
        case "blocked": 3
        case "done": 5
        default: 4
        }
    }
}

#Preview {
    AgentsScreen(apiClient: SloppyAPIClient(baseURL: .debugURL))
}
