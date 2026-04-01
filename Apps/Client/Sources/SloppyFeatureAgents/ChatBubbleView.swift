import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ChatBubbleView: View {
    let message: ChatMessage

    @Environment(\.theme) private var theme

    private var isUser: Bool { message.role == .user }

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return HStack(spacing: 0) {
            if isUser { Spacer() }

            VStack(alignment: isUser ? .trailing : .leading, spacing: sp.xs) {
                Text(message.role == .user ? "YOU" : "AGENT")
                    .font(.system(size: ty.micro))
                    .foregroundColor(c.textMuted)

                Text(message.textContent.isEmpty ? "…" : message.textContent)
                    .font(.system(size: ty.body))
                    .foregroundColor(c.textPrimary)
                    .padding(sp.m)
                    .background(isUser ? c.accentCyan.opacity(0.1 as Float) : c.surface)
                    .border(
                        isUser ? c.accentCyan : c.border,
                        lineWidth: bo.thin
                    )
            }

            if !isUser { Spacer() }
        }
    }
}
