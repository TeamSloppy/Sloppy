import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

public struct ChatBubbleView: View {
    private static let userBubbleRadius: CGFloat = 14

    public let message: ChatMessage

    public init(message: ChatMessage) {
        self.message = message
    }

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    private var isPhone: Bool { idiom == .phone }
    private var isStreamingAssistant: Bool { message.id.hasPrefix("streaming-assistant-") }

    public var body: some View {
        switch message.role {
        case .user:
            userMessage
                .multilineTextAlignment(.leading)
        case .system:
            systemMessage
                .multilineTextAlignment(.leading)
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

        return HStack(spacing: 0) {
            Spacer(minLength: sp.xxl)

            renderedSegmentStack(forceCollapsible: false)
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

        return renderedSegmentStack(forceCollapsible: false)
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

            renderedSegmentStack(forceCollapsible: false)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var phoneAssistantMessage: some View {
        let sp = theme.spacing

        return renderedSegmentStack(forceCollapsible: false)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, sp.s)
            .padding(.vertical, sp.m)
    }

    private var systemMessage: some View {
        renderedSegmentStack(forceCollapsible: true)
    }

    @ViewBuilder
    private func renderedSegmentStack(forceCollapsible: Bool) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            ForEach(Array(message.segments.enumerated()), id: \.offset) { index, segment in
                if shouldRenderAsCollapsible(segment, forceCollapsible: forceCollapsible) {
                    ChatSegmentCollapsibleCard(
                        message: message,
                        segment: segment,
                        forceCollapsible: forceCollapsible,
                        isRunning: isSegmentRunning(segment),
                        isStreamingAssistant: isStreamingAssistant
                    )
                } else {
                    ChatMarkdownTextStack(
                        text: segment.text ?? "…",
                        isStreamingAssistant: isStreamingAssistant && index == message.segments.count - 1
                    )
                }
            }
        }
    }

    private func shouldRenderAsCollapsible(_ segment: ChatMessageSegment, forceCollapsible: Bool) -> Bool {
        if forceCollapsible {
            return true
        }

        switch segment.kind {
        case .text:
            return false
        case .thinking, .attachment, .toolCall, .toolResult, .status:
            return true
        }
    }

    private func isSegmentRunning(_ segment: ChatMessageSegment) -> Bool {
        if let status = segment.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return status == "running" || status == "in_progress"
        }
        return segment.startedAt != nil && segment.finishedAt == nil
    }
}

private struct ChatMarkdownTextStack: View {
    let text: String
    let isStreamingAssistant: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            ForEach(Array(ChatMarkdownBlockParser.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let headingText):
                    headingView(level: level, text: headingText)
                case .paragraph(let paragraphText):
                    paragraphView(paragraphText)
                case .code(let language, let code):
                    ChatCodeBlockView(language: language, code: code)
                }
            }
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let ty = theme.typography
        let fontSize: CGFloat = if level == 1 {
            ty.title
        } else if level == 2 {
            ty.heading
        } else {
            ty.body
        }

        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .font(.system(size: fontSize))
                .foregroundColor(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(.system(size: fontSize))
                .foregroundColor(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func paragraphView(_ text: String) -> some View {
        let ty = theme.typography

        if isStreamingAssistant {
            Text(text)
                .font(.system(size: ty.body))
                .foregroundColor(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .font(.system(size: ty.body))
                .foregroundColor(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .tint(theme.colors.accentCyan)
        } else {
            Text(text)
                .font(.system(size: ty.body))
                .foregroundColor(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ChatCodeBlockView: View {
    let language: String?
    let code: String

    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.system(size: ty.micro))
                    .foregroundColor(c.textMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: ty.caption, design: .monospaced))
                    .foregroundColor(c.textPrimary)
                    .textSelection(.enabled)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.s)
        .background(c.surfaceRaised.opacity(0.72 as Float))
        .glassEffect(.regular.tint(c.surfaceRaised.opacity(0.22 as Float)), in: GlassShape.rect(cornerRadius: 16))
    }
}

private struct ChatSegmentCollapsibleCard: View {
    let message: ChatMessage
    let segment: ChatMessageSegment
    let forceCollapsible: Bool
    let isRunning: Bool
    let isStreamingAssistant: Bool

    @State private var isExpanded = false
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing

        VStack(alignment: .leading, spacing: sp.s) {
            Button {
                isExpanded.toggle()
            } label: {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    HStack(spacing: sp.s) {
                        Icons.symbol(isExpanded ? .collapseContent : .expandMore, size: theme.typography.caption)
                            .foregroundColor(c.textMuted)

                        Text(segmentTitle)
                            .font(.system(size: theme.typography.caption))
                            .foregroundColor(c.textPrimary)
                            .lineLimit(1)

                        if let duration = durationLabel(at: timeline.date) {
                            Text(duration)
                                .font(.system(size: theme.typography.micro))
                                .foregroundColor(c.textMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        if isRunning {
                            ChatShimmerView()
                                .frame(width: 54, height: 10)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: sp.s) {
                    if let text = segment.text, !text.isEmpty {
                        ChatMarkdownTextStack(text: text, isStreamingAssistant: isStreamingAssistant && isRunning)
                    }

                    if let metadata = segment.metadata, !metadata.isEmpty {
                        VStack(alignment: .leading, spacing: sp.xs) {
                            ForEach(metadata.keys.sorted(), id: \.self) { key in
                                HStack(alignment: .top, spacing: sp.xs) {
                                    Text(key)
                                        .font(.system(size: theme.typography.micro, design: .monospaced))
                                        .foregroundColor(c.textMuted)
                                    Text(metadata[key] ?? "")
                                        .font(.system(size: theme.typography.caption, design: .monospaced))
                                        .foregroundColor(c.textSecondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.s)
        .background(c.surfaceRaised.opacity(forceCollapsible ? 0.28 as Float : 0.2 as Float))
        .glassEffect(.regular.tint(c.surfaceRaised.opacity(0.12 as Float)), in: GlassShape.rect(cornerRadius: 16))
    }

    private var segmentTitle: String {
        if let title = segment.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }

        switch segment.kind {
        case .text:
            return message.role == .system ? "System" : "Message"
        case .thinking:
            return "Thinking"
        case .attachment:
            return "Attachment"
        case .toolCall:
            return "Tool call"
        case .toolResult:
            return "Tool result"
        case .status:
            return "Status"
        }
    }

    private func durationLabel(at now: Date) -> String? {
        guard let startedAt = segment.startedAt else { return nil }
        let end = segment.finishedAt ?? now
        return ChatCompactDurationFormatter.string(for: end.timeIntervalSince(startedAt))
    }
}

private struct ChatShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.12 as CGFloat), location: 0),
                .init(color: .white.opacity(0.52 as CGFloat), location: 0.5),
                .init(color: .white.opacity(0.12 as CGFloat), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: phase * 90)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ChatBubbleView(message: .init(role: .user, segments: [
            .init(kind: .text, text: "# Note\n\nPlease read `main.swift`.")
        ]))

        ChatBubbleView(message: .init(role: .system, segments: [
            .init(kind: .status, text: "Waiting for approval", title: "System", status: "running", startedAt: Date().addingTimeInterval(-12))
        ]))

        ChatBubbleView(message: .init(role: .assistant, segments: [
            .init(kind: .thinking, text: "Comparing two implementations", status: "running", startedAt: Date().addingTimeInterval(-8)),
            .init(kind: .toolCall, text: "Sources/App.swift", title: "Read file", status: "running", startedAt: Date().addingTimeInterval(-4)),
            .init(kind: .text, text: "## Result\n\n```swift\nlet value = 42\n```\n\nSee [docs](https://example.com).")
        ]))

        Spacer()
    }
    .padding(.all, 16)
}
