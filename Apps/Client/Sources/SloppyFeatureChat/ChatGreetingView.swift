import AdaEngine
import SloppyClientUI

public struct ChatGreetingView: View {
    public let agentName: String

    public init(agentName: String) {
        self.agentName = agentName
    }

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let isPhone = idiom == .phone

        return VStack(alignment: .center, spacing: sp.s) {
            Text(agentName.uppercased())
                .font(.system(size: ty.caption))
                .foregroundColor(c.textSecondary)
                .frame(minWidth: 0, maxWidth: .infinity)

            Text("What should we build today?")
                .font(.system(size: isPhone ? ty.heading : ty.title))
                .foregroundColor(c.textPrimary)
                .multilineTextAligment(.center)
                .lineLimit(isPhone ? 3 : 2)
                .frame(minWidth: 0, maxWidth: .infinity)

            Text("Start with a prompt below or pick a project from the sidebar.")
                .font(.system(size: isPhone ? ty.caption : ty.body))
                .foregroundColor(c.textMuted)
                .multilineTextAligment(.center)
                .lineLimit(isPhone ? 3 : 2)
                .frame(minWidth: 0, maxWidth: .infinity)
        }
        .padding(.horizontal, isPhone ? sp.s : sp.m)
    }
}
