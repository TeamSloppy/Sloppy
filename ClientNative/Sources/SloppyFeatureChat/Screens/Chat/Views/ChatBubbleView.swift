import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import Textual

struct ChatTextSelectionActions {
    var addToChat: (@MainActor @Sendable (String) -> Void)?
    var moreDetails: (@MainActor @Sendable (String) -> Void)?
    var askInSideChat: (@MainActor @Sendable (String) -> Void)?

    var textualActions: [TextSelectionAction] {
        [
            addToChat.map { handler in
                TextSelectionAction("Add to chat", handler: handler)
            },
            moreDetails.map { handler in
                TextSelectionAction("More details", handler: handler)
            },
            askInSideChat.map { handler in
                TextSelectionAction("Ask in side chat", handler: handler)
            },
        ].compactMap { $0 }
    }
}

extension EnvironmentValues {
    @Entry var chatTextSelectionActions = ChatTextSelectionActions()
}

public struct ChatBubbleView: View {
    private static let userBubbleRadius: CGFloat = 18

    public let message: ChatMessage
    public let isActivelyWorking: Bool
    public let onOpenProviderSettings: (@MainActor () -> Void)?

    public init(
        message: ChatMessage,
        isActivelyWorking: Bool = false,
        onOpenProviderSettings: (@MainActor () -> Void)? = nil
    ) {
        self.message = message
        self.isActivelyWorking = isActivelyWorking
        self.onOpenProviderSettings = onOpenProviderSettings
    }

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme
    private var isStreamingAssistant: Bool { message.id.hasPrefix("streaming-assistant-") }
    private var showsMessageActions: Bool {
        !isStreamingAssistant
            && !isActivelyWorking
            && message.role == .assistant
            && message.segments.contains { $0.kind == .text }
            && message.segments.allSatisfy { $0.kind == .text || $0.kind == .status }
    }

    public var body: some View {
        switch message.role {
        case .user:
            userMessage
                .multilineTextAlignment(.leading)
                .padding(.bottom, 16)
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
                        .fill(c.surfaceGlow)
                        .overlay {
                            RoundedRectangle(cornerRadius: Self.userBubbleRadius)
                                .stroke(c.border.opacity(0.72), lineWidth: theme.borders.thin)
                        }
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

            if let onOpenProviderSettings {
                Button(action: onOpenProviderSettings) {
                    Label("Provider Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if showsMessageActions {
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
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var systemMessage: some View {
        ChatSystemMessageGroupView(
            messages: [message],
            activeRunMessageIDs: isActivelyWorking ? [message.id] : []
        )
    }

    @ViewBuilder
    private func renderedSegmentStack(forceCollapsible: Bool) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            ForEach(Array(message.segments.enumerated()), id: \.offset) { index, segment in
                if let progress = segment.buildProgress {
                    ChatBuildProgressView(progress: progress)
                } else if shouldRenderAsCollapsible(segment, forceCollapsible: forceCollapsible) {
                    ChatSegmentCollapsibleCard(
                        message: message,
                        segment: segment,
                        isRunning: isSegmentRunning(segment)
                            || (isActivelyWorking && segment.kind == .thinking)
                    )
                } else {
                    ChatMarkdownTextStack(
                        text: segment.text ?? "…",
                        allowsTextSelection: !isStreamingAssistant && !isActivelyWorking
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
        case .thinking, .attachment, .toolCall, .toolResult, .status, .buildProgress:
            return true
        }
    }

    private func isSegmentRunning(_ segment: ChatMessageSegment) -> Bool {
        isActivelyWorking && segment.isExecutionRunning
    }
}

struct ChatSystemMessageGroupView: View {
    let messages: [ChatMessage]
    var activeRunMessageIDs: Set<ChatMessage.ID> = []

    @State private var isExpanded = false
    @Environment(\.theme) private var theme

    var body: some View {
        let items = segmentItems
        let visibleItems = ChatSystemActivityVisibility.visibleItems(
            from: items,
            isExpanded: isExpanded
        )

        VStack(alignment: .leading, spacing: theme.spacing.s) {
            groupHeader(items: items)

            if !visibleItems.isEmpty {
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    ForEach(visibleItems) { item in
                        segmentRow(item)
                    }
                }
                .padding(.leading, 28)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func groupHeader(items: [ChatSystemSegmentItem]) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: theme.spacing.s) {
                Icons.symbol(isExpanded ? .collapseContent : .expandMore, size: theme.typography.caption)
                    .foregroundColor(theme.colors.textMuted)

                Text(summaryTitle(for: items))
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(theme.colors.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse activity" : "Expand activity")
    }

    private func segmentRow(_ item: ChatSystemSegmentItem) -> some View {
        ChatSegmentCollapsibleCard(
            message: item.message,
            segment: item.segment,
            isRunning: item.isRunning
        )
    }

    private var segmentItems: [ChatSystemSegmentItem] {
        messages.flatMap { message in
            message.segments.enumerated().map { index, segment in
                ChatSystemSegmentItem(
                    id: "\(message.id):\(index)",
                    message: message,
                    segment: segment,
                    isRunning: activeRunMessageIDs.contains(message.id)
                        && segment.isExecutionRunning
                )
            }
        }
    }

    private func summaryTitle(for items: [ChatSystemSegmentItem]) -> String {
        let titles = items.compactMap { item -> String? in
            guard let title = item.segment.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return nil
            }
            return title
        }
        return titles.isEmpty ? "Activity" : titles.prefix(3).joined(separator: " · ")
    }
}

struct ChatSystemSegmentItem: Identifiable {
    let id: String
    let message: ChatMessage
    let segment: ChatMessageSegment
    let isRunning: Bool

    init(
        id: String,
        message: ChatMessage,
        segment: ChatMessageSegment,
        isRunning: Bool? = nil
    ) {
        self.id = id
        self.message = message
        self.segment = segment
        self.isRunning = isRunning ?? segment.isExecutionRunning
    }

    var toolExecutionKey: String? {
        guard let title = segment.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        return title
    }
}

enum ChatSystemActivityVisibility {
    static func visibleItems(
        from items: [ChatSystemSegmentItem],
        isExpanded: Bool
    ) -> [ChatSystemSegmentItem] {
        guard !isExpanded else { return items }

        var pendingCallIndicesByTool: [String: [Int]] = [:]
        for (index, item) in items.enumerated() {
            guard let toolKey = item.toolExecutionKey else { continue }

            switch item.segment.kind {
            case .toolCall where item.isRunning:
                pendingCallIndicesByTool[toolKey, default: []].append(index)
            case .toolResult:
                guard pendingCallIndicesByTool[toolKey]?.isEmpty == false else { continue }
                pendingCallIndicesByTool[toolKey]?.removeFirst()
            case .text, .thinking, .attachment, .toolCall, .status, .buildProgress:
                continue
            }
        }

        let pendingIndices = Set(pendingCallIndicesByTool.values.joined())
        return items.enumerated().compactMap { index, item in
            pendingIndices.contains(index) ? item : nil
        }
    }
}

struct ChatThinkingIndicator: View {
    let label: String
    let details: String?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            ChatShimmerText(text: label)
                .font(.system(size: theme.typography.body, weight: .medium))
            Spacer(minLength: 0)
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let details, !details.isEmpty else { return label }
        return "\(label). \(details)"
    }
}

private struct ChatMarkdownTextStack: View {
    let text: String
    var allowsTextSelection = true

    @Environment(\.theme) private var theme
    @Environment(\.chatTextSelectionActions) private var selectionActions

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        if allowsTextSelection {
            structuredText
                .textual.textSelection(.enabled)
                .textual.textSelectionActions(selectionActions.textualActions)
        } else {
            structuredText
        }
        #else
        if allowsTextSelection {
            structuredText
                .textual.textSelection(.enabled)
        } else {
            structuredText
        }
        #endif
    }

    private var structuredText: some View {
        let ty = theme.typography

        return StructuredText(markdown: text)
            .textual.structuredTextStyle(.gitHub)
            .font(.system(size: ty.body))
            .lineSpacing(4)
            .foregroundColor(theme.colors.textPrimary)
            .tint(theme.colors.accentCyan)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ChatSegmentCollapsibleCard: View {
    let message: ChatMessage
    let segment: ChatMessageSegment
    let isRunning: Bool

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
                        ChatMarkdownTextStack(
                            text: text,
                            allowsTextSelection: !isRunning
                        )
                    }

                    if let metadata = segment.metadata, !metadata.isEmpty {
                        VStack(alignment: .leading, spacing: sp.xs) {
                            ForEach(metadata.keys.sorted(), id: \.self) { key in
                                HStack(alignment: .top, spacing: sp.xs) {
                                    Text(key)
                                        .font(.system(size: theme.typography.micro, design: .monospaced))
                                        .foregroundColor(c.textMuted)
                                    metadataValue(metadata[key] ?? "")
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, sp.xs)
    }

    @ViewBuilder
    private func metadataValue(_ value: String) -> some View {
        let text = Text(value)
            .font(.system(size: theme.typography.caption, design: .monospaced))
            .foregroundColor(theme.colors.textSecondary)

        if isRunning {
            text
        } else {
            text.textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func timelineRow(durationText: String?) -> some View {
        let c = theme.colors
        let sp = theme.spacing

        HStack(spacing: sp.s) {
            Image(systemName: segmentSystemImage)
                .font(.system(size: theme.typography.caption))
                .foregroundColor(c.textMuted)
                .frame(width: 18)

            if isRunning {
                ChatShimmerText(text: segmentTitle)
                    .font(.system(size: theme.typography.caption))
            } else {
                Text(segmentTitle)
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(c.textSecondary)
                    .lineLimit(1)
            }

            if let durationText {
                Text(durationText)
                    .font(.system(size: theme.typography.micro))
                    .foregroundColor(c.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if hasExpandableContent {
                Icons.symbol(isExpanded ? .collapseContent : .expandMore, size: theme.typography.caption)
                    .foregroundColor(c.textMuted)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isExpanded.toggle()
            }
        }
    }

    private var hasExpandableContent: Bool {
        if let text = segment.text, !text.isEmpty {
            return true
        }
        return segment.metadata?.isEmpty == false
    }

    private var segmentSystemImage: String {
        switch segment.kind {
        case .text:
            return "text.alignleft"
        case .thinking:
            return "brain.head.profile"
        case .attachment:
            return "paperclip"
        case .toolCall:
            return "terminal"
        case .toolResult:
            return "book.closed"
        case .status:
            return "circle.dotted"
        case .buildProgress:
            return "chart.bar"
        }
    }

    private var segmentTitle: String {
        if let attachmentName = segment.attachment?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !attachmentName.isEmpty {
            return attachmentName
        }
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
        case .buildProgress:
            return "Progress"
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

private struct ChatShimmerText: View {
    let text: String

    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        theme.colors.textMuted,
                        theme.colors.textPrimary,
                        theme.colors.textMuted,
                    ],
                    startPoint: UnitPoint(x: phase - 1, y: 0.5),
                    endPoint: UnitPoint(x: phase, y: 0.5)
                )
            )
        .onAppear {
            guard !reduceMotion else {
                phase = 0.5
                return
            }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 2
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
