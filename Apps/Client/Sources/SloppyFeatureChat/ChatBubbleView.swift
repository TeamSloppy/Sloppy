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
    private var isStreamingAssistant: Bool { message.id.hasPrefix("streaming-assistant-") }

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

            Text(messageText)
                .textSelection(.enabled)
                .font(.system(size: ty.body))
                .foregroundColor(c.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Self.userBubbleWidth, alignment: .leading)
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)
                .background {
                    RoundedRectangle(cornerRadius: Self.userBubbleRadius)
                        .fill(c.accent.opacity(0.20 as Float))
                }
        }
    }

    private var phoneUserMessage: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return Text(messageText)
            .textSelection(.enabled)
            .font(.system(size: ty.body))
            .foregroundColor(c.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, sp.s)
            .padding(.vertical, sp.s)
            .background {
                RoundedRectangle(cornerRadius: Self.userBubbleRadius)
                    .fill(c.accent.opacity(0.20 as Float))
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
            assistantText
                .font(.system(size: ty.body))
                .foregroundColor(c.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button { UIClipboard.setString(messageText) } label: {
                Text("Copy").font(.system(size: ty.caption)).foregroundColor(c.textMuted).frame(height: 28)
            }.accessibilityIdentifier("chat.message.\(message.id).copy")
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var phoneAssistantMessage: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return assistantText
            .font(.system(size: ty.body))
            .foregroundColor(c.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
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
                .textSelection(.enabled)
                .font(.system(size: ty.caption))
                .foregroundColor(c.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)
                .background(c.surface.opacity(0.68 as Float))
            Spacer(minLength: sp.xl)
        }
    }

    @ViewBuilder
    private var assistantText: some View {
        if isStreamingAssistant {
            Text(messageText)
                .textSelection(.enabled)
        } else {
            Text(markdown: messageText)
                .textSelection(.enabled)
        }
    }

    private var messageText: String {
        message.textContent.isEmpty ? "…" : message.textContent
    }
}
