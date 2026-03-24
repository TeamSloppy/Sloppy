import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ChatBubbleView: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(spacing: 0) {
            if isUser { Spacer() }

            VStack(alignment: isUser ? .trailing : .leading, spacing: Theme.spacingXS) {
                Text(message.role == .user ? "YOU" : "AGENT")
                    .font(.system(size: Theme.fontMicro))
                    .foregroundColor(Theme.textMuted)

                Text(message.textContent.isEmpty ? "…" : message.textContent)
                    .font(.system(size: Theme.fontBody))
                    .foregroundColor(Theme.textPrimary)
                    .padding(Theme.spacingM)
                    .background(isUser ? Theme.accentCyan.opacity(0.1 as Float) : Theme.surface)
                    .border(
                        isUser ? Theme.accentCyan : Theme.border,
                        lineWidth: Theme.borderThin
                    )
            }

            if !isUser { Spacer() }
        }
    }
}
