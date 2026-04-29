import AdaEngine
import SloppyClientUI

public struct ChatGreetingView: View {
    public let agentName: String

    public init(agentName: String) {
        self.agentName = agentName
    }

    @Environment(\.theme) private var theme

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .center, spacing: sp.s) {
            Text(agentName.uppercased())
                .font(.system(size: ty.caption))
                .foregroundColor(c.textSecondary)

            Text("What should we build today?")
                .font(.system(size: ty.title))
                .foregroundColor(c.textPrimary)

            Text("Start with a prompt below or pick a project from the sidebar.")
                .font(.system(size: ty.body))
                .foregroundColor(c.textMuted)
        }
        .padding(.horizontal, sp.xxl)
    }
}
