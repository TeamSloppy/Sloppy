import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct ChatBubbleView: View {
    private static let bubbleRadius: Float = 22

    public let message: ChatMessage

    public init(message: ChatMessage) { self.message = message }

    @Environment(\.theme) private var theme

    private var isUser: Bool { message.role == .user }

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return HStack(spacing: 0) {
            if isUser { Spacer() }

            VStack(alignment: isUser ? .trailing : .leading, spacing: sp.xs) {
                Text(message.role == .user ? "You" : "Agent")
                    .font(.system(size: ty.micro))
                    .foregroundColor(c.textMuted)

                Text(message.textContent.isEmpty ? "…" : message.textContent)
                    .font(.system(size: ty.body))
                    .foregroundColor(c.textPrimary)
                    .padding(sp.m)
                    .background(isUser ? c.accentCyan.opacity(0.06 as Float) : c.surface.opacity(0.7 as Float))
                    .glassEffect(.regular, in: .rect(cornerRadius: Self.bubbleRadius))
            }

            if !isUser { Spacer() }
        }
    }
}
