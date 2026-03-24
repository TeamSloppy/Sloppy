import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct AgentListView: View {
    let agents: [APIAgentRecord]
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingL) {
                HStack {
                    SectionHeader("Agents", accentColor: Theme.accentCyan)
                    Spacer()
                    Button("REFRESH") { onRefresh() }
                        .foregroundColor(Theme.accentCyan)
                }

                if agents.isEmpty {
                    EmptyStateView(isLoading ? "Loading..." : "No agents registered")
                } else {
                    VStack(alignment: .leading, spacing: Theme.spacingS) {
                        ForEach(agents) { agent in
                            NavigationLink(value: agent.id) {
                                EntityCard(
                                    title: agent.displayName,
                                    subtitle: agent.role.isEmpty ? "No role" : agent.role,
                                    trailing: agent.isSystem == true ? "SYS" : nil,
                                    accentColor: Theme.accentCyan
                                )
                            }
                        }
                    }
                }
            }
            .padding(Theme.spacingL)
        }
    }
}
