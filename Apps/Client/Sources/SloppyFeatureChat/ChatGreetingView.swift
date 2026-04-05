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

        return VStack(alignment: .leading, spacing: sp.l) {
            Text("✦")
                .font(.system(size: ty.hero))
                .foregroundColor(c.accent)

            Text("How can I\nhelp you?")
                .font(.system(size: ty.hero))
                .foregroundColor(c.accent)

            Text("Chatting with \(agentName). Type a message below to start a new session.")
                .font(.system(size: ty.caption))
                .foregroundColor(c.textMuted)
        }
        .padding(sp.xxl)
    }
}
