import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct AgentListView: View {
    let agents: [APIAgentRecord]
    let isLoading: Bool
    let onRefresh: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return ScrollView {
            VStack(alignment: .leading, spacing: sp.l) {
                if agents.isEmpty {
                    EmptyStateView(isLoading ? "Loading..." : "No agents registered")
                } else {
                    LazyVStack(
                        agents,
                        alignment: .leading,
                        spacing: sp.s,
                        estimatedRowHeight: 68,
                        overscan: 12
                    ) { agent in
                            NavigationLink(value: agent.id) {
                                EntityCard(
                                    title: agent.displayName,
                                    subtitle: agent.role.isEmpty ? "No role" : agent.role,
                                    trailing: agent.isSystem == true ? "SYS" : nil,
                                    accentColor: c.accentCyan
                                )
                            }
                    }
                }
            }
            .padding(sp.l)
        }
        .navigationTitle("Agents")
        .navigationTitlePosition(.leading)
        .navigationBarTrailingItems {
            Button("REFRESH") { onRefresh() }
                .foregroundColor(c.accentCyan)
                .font(.system(size: ty.caption))
        }
    }
}
