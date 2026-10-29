import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import Textual

struct ChatTextSelectionActions {
    var addToChat: (@MainActor @Sendable (String) -> Void)?
    var moreDetails: (@MainActor @Sendable (String) -> Void)?
    var askInSideChat: (@MainActor @Sendable (String) -> Void)?
#if os(macOS)
    var addAnnotation: (@MainActor @Sendable (TextSelectionContext, String, Int) -> Void)? = nil
    var annotations: [ChatComposerQuote] = []
    var editAnnotation: (@MainActor @Sendable (UUID, TextSelectionContext) -> Void)? = nil
    var resolveAnnotation: (@MainActor @Sendable (UUID, TextSelectionContext) -> Void)? = nil
#endif

    var textualActions: [TextSelectionAction] {
        [
            addToChat.map { handler in
                TextSelectionAction("Add to chat") { text in
                    // The selection menu still owns first responder while its action runs.
                    DispatchQueue.main.async {
                        handler(text)
                    }
                }
            },
            moreDetails.map { handler in
                TextSelectionAction("More details", showsInToolbar: false) { text in
                    DispatchQueue.main.async {
                        handler(text)
                    }
                }
            },
            askInSideChat.map { handler in
                TextSelectionAction("Ask in side chat", handler: handler)
            },
        ].compactMap { $0 }
    }

#if os(macOS)
    func textualActions(messageID: String?, segmentIndex: Int) -> [TextSelectionAction] {
        guard let addAnnotation, let messageID else { return textualActions }
        return [TextSelectionAction("Add to chat", contextualHandler: { context in
            DispatchQueue.main.async { addAnnotation(context, messageID, segmentIndex) }
        })] + [
            moreDetails.map { handler in
                TextSelectionAction("More details", showsInToolbar: false) { text in
                    DispatchQueue.main.async { handler(text) }
                }
            },
            askInSideChat.map { TextSelectionAction("Ask in side chat", handler: $0) },
        ].compactMap { $0 }
    }

    func textAnnotations(messageID: String?, segmentIndex: Int) -> [TextAnnotation] {
        annotations.compactMap { quote in
            guard let source = quote.source, source.messageID == messageID,
                  source.segmentIndex == segmentIndex else { return nil }
            return TextAnnotation(id: quote.id, location: source.location,
                activate: { editAnnotation?(quote.id, $0) },
                resolve: { resolveAnnotation?(quote.id, $0) })
        }
    }
#endif
}

extension EnvironmentValues {
    @Entry var chatTextSelectionActions = ChatTextSelectionActions()
}

public struct ChatBubbleView: View {
    private static let userBubbleRadius: CGFloat = 18

    public let message: ChatMessage
    public let isActivelyWorking: Bool
    public let userBubbleTint: Color?
    public let onOpenProviderSettings: (@MainActor () -> Void)?
    public let onForkFromMessage: (@MainActor (ChatMessage) -> Void)?
    private let userPresentation: ChatUserMessagePresentation

    public init(
        message: ChatMessage,
        isActivelyWorking: Bool = false,
        userBubbleTint: Color? = nil,
        onOpenProviderSettings: (@MainActor () -> Void)? = nil,
        onForkFromMessage: (@MainActor (ChatMessage) -> Void)? = nil
    ) {
        self.message = message
        self.isActivelyWorking = isActivelyWorking
        self.userBubbleTint = userBubbleTint
        self.onOpenProviderSettings = onOpenProviderSettings
        self.onForkFromMessage = onForkFromMessage
        self.userPresentation = ChatUserMessagePresentation(message: message)
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
        let sp = theme.spacing

        return HStack(spacing: 0) {
            Spacer(minLength: sp.xxl)

            VStack(alignment: .trailing, spacing: sp.s) {
                if !userPresentation.segments.isEmpty || message.peerOrigin != nil {
                    ChatUserMessageContent {
                        if let origin = message.peerOrigin {
                            Label("Agent \(origin.agentId)", systemImage: "bubble.left.and.bubble.right")
                                .font(.caption).foregroundStyle(theme.colors.textSecondary)
                        }
                        renderedSegmentStack(forceCollapsible: false, segments: userPresentation.segments)
                    }
                    .id(message.id)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, sp.m)
                    .padding(.vertical, sp.s)
                    .background {
                        RoundedRectangle(cornerRadius: Self.userBubbleRadius)
                            .fill(userMessageFill)
                            .overlay {
                                RoundedRectangle(cornerRadius: Self.userBubbleRadius)
                                    .stroke(userMessageBorder, lineWidth: theme.borders.thin)
                            }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("chat.user-message.body")
                }
                if !userPresentation.annotations.isEmpty {
                    ChatSentAnnotationsBubble(annotations: userPresentation.annotations)
                }
            }
        }
    }

    private var userMessageFill: Color {
#if os(macOS)
        theme.colors.surfaceRaised
#else
        userBubbleTint?.opacity(0.22) ?? theme.colors.surfaceGlow
#endif
    }

    private var userMessageBorder: Color {
#if os(macOS)
        .clear
#else
        userBubbleTint?.opacity(0.45) ?? theme.colors.border.opacity(0.72)
#endif
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
                        UIClipboard.setString(message.textContent)
                    }, label: {
                        Image(systemName: "rectangle.on.rectangle")
                            .scaleEffect(x: -1)
                            .padding(.all, 4)
                    })
                    .accessibilityLabel("Copy response")

                    Button(action: {
                        onForkFromMessage?(message)
                    }, label: {
                        Image(systemName: "arrow.trianglehead.branch")
                            .rotationEffect(.degrees(90))
                            .padding(.all, 4)
                    })
                    .disabled(onForkFromMessage == nil)
                    .accessibilityLabel("Fork session from this response")
                }
                .font(.system(size: theme.typography.body, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
                #if os(macOS)
                .buttonStyle(.plain)
                #elseif os(visionOS)
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
    private func renderedSegmentStack(forceCollapsible: Bool, segments: [ChatMessageSegment]? = nil) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            ForEach(Array((segments ?? message.segments).enumerated()), id: \.offset) { index, segment in
                if let progress = segment.buildProgress {
                    ChatBuildProgressView(progress: progress)
                } else if message.role == .user, let attachment = segment.attachment,
                          ChatAttachmentThumbnail.isImage(attachment) {
                    ChatSentImagePreview(attachment: attachment)
                } else if message.role == .user, let attachment = segment.attachment {
                    Label(attachment.name, systemImage: "doc")
                        .font(.caption)
                        .textSelection(.enabled)
                } else if shouldRenderAsCollapsible(segment, forceCollapsible: forceCollapsible) {
                    ChatSegmentCollapsibleCard(
                        message: message,
                        segment: segment,
                        isRunning: isSegmentRunning(segment)
                            || (isActivelyWorking && segment.kind == .thinking)
                    )
                } else if message.role == .user {
                    if let text = segment.text,
                       text.hasPrefix("> ") || !ChatComposerCodeFence.ranges(in: text).isEmpty
                        || !ChatSessionReference.parseLinks(in: text).isEmpty {
                        ChatMarkdownTextStack(text: text)
                    } else {
                        // Plain user input has an intrinsic size before markdown parses.
                        Text(verbatim: segment.text ?? "…")
                            .font(.system(size: theme.typography.body))
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ChatMarkdownTextStack(
                        text: segment.text ?? "…",
                        allowsTextSelection: !isStreamingAssistant && !isActivelyWorking,
                        renderImmediately: !isStreamingAssistant,
                        annotationMessageID: message.id,
                        annotationSegmentIndex: index
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

/// Measures the rendered content so wrapping, markdown and multiple segments share one budget.
struct ChatUserMessageContent<Content: View>: View {
    static var previewLineLimit: Int { 12 }

    @ViewBuilder let content: () -> Content
    @State private var isExpanded = false
    @State private var contentHeight: CGFloat = 0
    @State private var lineHeight: CGFloat = 0
    @Environment(\.theme) private var theme

    private var previewHeight: CGFloat {
        let measuredLineHeight = lineHeight > 0 ? lineHeight : ceil(theme.typography.body * 1.3)
        return measuredLineHeight * CGFloat(Self.previewLineLimit)
            + 4 * CGFloat(Self.previewLineLimit - 1)
    }

    private var canCollapse: Bool { contentHeight > previewHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            content()
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    contentHeight = height
                }
                .frame(maxHeight: isExpanded ? nil : previewHeight, alignment: .top)
                .clipped()

            if canCollapse {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label(isExpanded ? "Show less" : "Show more",
                          systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: theme.typography.caption))
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.user-message.toggle-expansion")
            }
        }
        .background(alignment: .topLeading) {
            // SwiftUI's line metrics differ from AppKit/UIKit's font metrics.
            Text("Ag")
                .font(.system(size: theme.typography.body))
                .fixedSize()
                .hidden()
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    lineHeight = height
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
