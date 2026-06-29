import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

public struct ChatBubbleView: View {
    private static let userBubbleRadius: CGFloat = 14

    public let message: ChatMessage

    public init(message: ChatMessage) { self.message = message }

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    private var isUser: Bool { message.role == .user }
    private var isAssistant: Bool { message.role == .assistant }
    private var isPhone: Bool { idiom == .phone }
    private var isStreamingAssistant: Bool { message.id.hasPrefix("streaming-assistant-") }

    public var body: some View {
        switch message.role {
        case .user:
            userMessage
                .multilineTextAlignment(.leading)
        case .system:
            systemMessage
                .multilineTextAlignment(.center)
        case .assistant:
            assistantMessage
                .multilineTextAlignment(.leading)
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
                .font(.system(size: ty.body))
                .foregroundColor(c.textPrimary)
                .frame(alignment: .leading)
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)
                .background {
                    RoundedRectangle(cornerRadius: Self.userBubbleRadius)
                        .fill(c.surfaceRaised)
                }
        }
    }

    private var phoneUserMessage: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return Text(messageText)
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
            HStack(spacing: sp.s) {
                Text("SLOPPY")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.accentCyan)
                    .padding(.horizontal, sp.s)
                    .padding(.vertical, sp.xs)
                    .background(c.accentCyan.opacity(0.08 as Float))
                    .glassEffect(.regular.tint(c.accentCyan.opacity(0.06 as Float)), in: GlassShape.rect(cornerRadius: 999))
                Icons.symbol(.arrowForward, size: ty.micro)
                    .foregroundColor(c.textMuted)
            }

            Color.clear
                .frame(height: theme.borders.thin)
                .background(c.border.opacity(0.48 as Float))

            assistantText
                .font(.system(size: ty.body))
                .foregroundColor(c.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
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
            Color.clear
                .frame(height: theme.borders.thin)
                .background(c.border.opacity(0.88 as Float))

            Text(messageText)
                .font(.system(size: ty.caption))
                .foregroundColor(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)
            Color.clear
                .frame(height: theme.borders.thin)
                .background(c.border.opacity(0.88 as Float))
        }
    }

    @ViewBuilder
    private var assistantText: some View {
        if isStreamingAssistant {
            Text(messageText)
        } else if let attributed = try? AttributedString(markdown: messageText) {
            Text(attributed)
        } else {
            Text(messageText)
        }
    }

    private var messageText: String {
        message.textContent.isEmpty ? "…" : message.textContent
    }
}

#Preview {
    VStack {
        ChatBubbleView(message: .init(role: .user, segments: [
            .init(kind: .text, text: "oeqinf[owinef[oqwne[f qwe fqwef")
        ]))

        ChatBubbleView(message: .init(role: .system, segments: [
            .init(kind: .text, text: "oeqinf[owinef[qwefqwefqefq[f qwe fqwef")
        ]))

        ChatBubbleView(message: .init(role: .assistant, segments: [
            .init(kind: .text, text: "oeqinf[owinef[oweiufbiqw fuwe fqpweiuf qwefuqwe fqwiuefqpwie fqpwevfu qwefqwuie fqpiweu fqwqwne[f qwe fqwef")
        ]))

        Spacer()
    }
    .padding(.all, 16)

}
