import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import Textual

public struct ChatBubbleView: View {
    private static let userBubbleRadius: CGFloat = 14

    public let message: ChatMessage

    public init(message: ChatMessage) {
        self.message = message
    }

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme
    private var isStreamingAssistant: Bool { message.id.hasPrefix("streaming-assistant-") }

    public var body: some View {
        switch message.role {
        case .user:
            userMessage
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .padding(.bottom, 16)
        case .system:
            systemMessage
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        case .assistant:
            assistantMessage
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var userMessage: some View {
        desktopUserMessage
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

    @ViewBuilder
    private var assistantMessage: some View {
        desktopAssistantMessage
    }

    private var desktopAssistantMessage: some View {
        let sp = theme.spacing

        return VStack(alignment: .leading, spacing: sp.m) {
            renderedSegmentStack(forceCollapsible: false)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            HStack {
                Button(action: {
                    // TODO: Add copy to clipboard
                }, label: {
                    Image(systemName: "rectangle.on.rectangle")
                        .scaleEffect(x: -1)
                        .padding(.all, 4)
                })
                Button(action: {
                    // TODO: Add fork session from this message
                }, label: {
                    Image(systemName: "arrow.trianglehead.branch")
                        .rotationEffect(.degrees(90))
                        .padding(.all, 4)
                })
            }
            .font(.system(size: theme.typography.body, weight: .semibold))
            .foregroundStyle(theme.colors.textSecondary)
            #if os(visionOS)
            .backportGlassEffect(.regular, in: .capsule)
            #else
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            #endif
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
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
                        text: segment.text ?? "…"
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

    @Environment(\.theme) private var theme

    var body: some View {
        let ty = theme.typography

        StructuredText(markdown: text)
            .textual.structuredTextStyle(.gitHub)
            .font(.system(size: ty.body))
            .foregroundColor(theme.colors.textPrimary)
            .tint(theme.colors.accentCyan)
            .fixedSize(horizontal: false, vertical: true)
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
            if showsLiveDuration {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    timelineRow(durationText: durationLabel(at: timeline.date))
                }
            } else {
                timelineRow(durationText: staticDurationLabel)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: sp.s) {
                    if let text = segment.text, !text.isEmpty {
                        ChatMarkdownTextStack(text: text)
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
        .backportGlassEffect(.clear, in: .rect(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isExpanded.toggle()
            }
        }
    }

    @ViewBuilder
    private func timelineRow(durationText: String?) -> some View {
        let c = theme.colors
        let sp = theme.spacing

        HStack(spacing: sp.s) {
            Icons.symbol(isExpanded ? .collapseContent : .expandMore, size: theme.typography.caption)
                .foregroundColor(c.textMuted)

            Text(segmentTitle)
                .font(.system(size: theme.typography.caption))
                .foregroundColor(c.textPrimary)
                .lineLimit(1)

            if let durationText {
                Text(durationText)
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
        .onTapGesture {
            isExpanded.toggle()
        }
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

    private var showsLiveDuration: Bool {
        isRunning && segment.startedAt != nil && segment.finishedAt == nil
    }

    private var staticDurationLabel: String? {
        durationLabel(at: segment.finishedAt ?? Date())
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
    .environment(\.userInterfaceIdiom, .desktop)
    #if os(macOS)
    .frame(width: 1024, height: 800)
    #endif
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
    .environment(\.userInterfaceIdiom, .phone)
#if os(macOS)
    .frame(width: 1024, height: 800)
#endif
}
