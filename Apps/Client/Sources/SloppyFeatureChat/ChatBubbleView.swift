import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct ChatBubbleView: View {
    private static let userBubbleWidth: Float = 560
    private static let userBubbleRadius: Float = 14

    public let message: ChatMessage

    public init(message: ChatMessage) { self.message = message }

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    private var isUser: Bool { message.role == .user }
    private var isAssistant: Bool { message.role == .assistant }
    private var isPhone: Bool { idiom == .phone }

    public var body: some View {
        if isUser {
            userMessage
                .multilineTextAligment(.leading)
        } else if isAssistant {
            assistantMessage
                .multilineTextAligment(.leading)
        } else {
            systemMessage
                .multilineTextAligment(.center)
        }
    }

    @ViewBuilder
    private var userMessage: some View {
        if isPhone {
            phoneUserMessage
        } else {
            desktopUserMessage
        }
    }

    private var desktopUserMessage: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return HStack(spacing: 0) {
            Spacer(minLength: sp.xxl)

            Text(markdown: messageText)
                .font(.system(size: ty.body))
                .foregroundColor(c.textPrimary)
                .frame(width: Self.userBubbleWidth, alignment: .leading)
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)
                .background {
                    RoundedRectangleShape(cornerRadius: Self.userBubbleRadius)
                        .fill(c.surface)
                }
        }
    }

    private var phoneUserMessage: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return Text(markdown: messageText)
            .font(.system(size: ty.body))
            .foregroundColor(c.textPrimary)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, sp.s)
            .padding(.vertical, sp.s)
            .background {
                RoundedRectangleShape(cornerRadius: Self.userBubbleRadius)
                    .fill(c.surface)
            }
    }

    @ViewBuilder
    private var assistantMessage: some View {
        if isPhone {
            phoneAssistantMessage
        } else {
            desktopAssistantMessage
        }
    }

    private var desktopAssistantMessage: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.m) {
            HStack(spacing: sp.s) {
                Text("SLOPPY")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                Icons.symbol(.arrowForward, size: ty.micro)
                    .foregroundColor(c.textMuted)
            }

            Color.clear
                .frame(height: theme.borders.thin)
                .background(c.border.opacity(0.48 as Float))

            Text(markdown: messageText)
                .font(.system(size: ty.body))
                .foregroundColor(c.textPrimary)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var phoneAssistantMessage: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return Text(markdown: messageText)
            .font(.system(size: ty.body))
            .foregroundColor(c.textPrimary)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, sp.s)
            .padding(.vertical, sp.m)
    }

    private var systemMessage: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return HStack(spacing: 0) {
            Spacer(minLength: sp.xl)
            Text(messageText)
                .font(.system(size: ty.caption))
                .foregroundColor(c.textMuted)
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)
                .background(c.surface.opacity(0.68 as Float))
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            Spacer(minLength: sp.xl)
        }
    }

    private var messageText: String {
        message.textContent.isEmpty ? "…" : message.textContent
    }
}
