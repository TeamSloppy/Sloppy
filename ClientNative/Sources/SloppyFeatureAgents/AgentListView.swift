import Foundation
import SwiftUI
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
                        .padding(sp.l)
                } else {
                    LazyVStack(alignment: .leading, spacing: sp.s) {
                        ForEach(agents) { agent in
                            NavigationLink(value: agent.id) {
                                EntityCard(
                                    title: agent.displayName,
                                    subtitle: agent.role.isEmpty ? "No role" : agent.role,
                                    trailing: agent.isSystem == true ? "SYS" : nil,
                                    accentColor: c.accentCyan
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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


#Preview {
    AgentListView(
        agents: [
            APIAgentRecord.random(),
            APIAgentRecord.random(),
            APIAgentRecord.random(),
            APIAgentRecord.random()
        ],
        isLoading: false,
        onRefresh: {

        }
    )
}

#Preview {
    AgentListView(
        agents: [
            APIAgentRecord.random()
        ],
        isLoading: true,
        onRefresh: {

        }
    )
}

extension APIAgentRecord {
    static func random() -> APIAgentRecord {
        .init(id: UUID().uuidString, displayName: String(UUID().uuidString.prefix(5)))
    }
}
