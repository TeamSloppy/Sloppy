import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct AgentPickerView: View {
    public let agents: [APIAgentRecord]
    public let selectedAgent: APIAgentRecord?
    public let onSelect: (APIAgentRecord) -> Void
    public let onDismiss: () -> Void

    public init(
        agents: [APIAgentRecord],
        selectedAgent: APIAgentRecord?,
        onSelect: @escaping (APIAgentRecord) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.agents = agents
        self.selectedAgent = selectedAgent
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    @Environment(\.theme) private var theme

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SELECT AGENT")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                Spacer()
                Button("CLOSE") { onDismiss() }
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
            }
            .padding(.horizontal, sp.l)
            .padding(.vertical, sp.m)
            .border(c.border, lineWidth: bo.thin)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(agents) { agent in
                        let isSelected = agent.id == selectedAgent?.id
                        Button(action: { onSelect(agent) }) {
                            HStack(spacing: sp.m) {
                                VStack(alignment: .leading, spacing: sp.xs) {
                                    Text(agent.displayName)
                                        .font(.system(size: ty.body))
                                        .foregroundColor(isSelected ? c.accentCyan : c.textPrimary)
                                    if !agent.role.isEmpty {
                                        Text(agent.role.uppercased())
                                            .font(.system(size: ty.micro))
                                            .foregroundColor(c.textMuted)
                                    }
                                }
                                Spacer()
                                if isSelected {
                                    Text("●")
                                        .font(.system(size: ty.caption))
                                        .foregroundColor(c.accentCyan)
                                }
                            }
                            .padding(.horizontal, sp.l)
                            .padding(.vertical, sp.m)
                            .background(isSelected ? c.accentCyan.opacity(0.05 as Float) : Color.clear)
                        }
                        .border(c.border, lineWidth: bo.thin)
                    }
                }
            }
        }
        .background(c.surface)
    }
}
