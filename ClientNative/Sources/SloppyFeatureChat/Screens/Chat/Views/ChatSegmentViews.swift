import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import Textual

struct ChatMarkdownTextStack: View {
    let text: String
    var allowsTextSelection = true
    var renderImmediately = true
    var annotationMessageID: String? = nil
    var annotationSegmentIndex = 0

    @Environment(\.theme) private var theme
    @Environment(\.chatTextSelectionActions) private var selectionActions

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        if allowsTextSelection {
            structuredText
                .textual.textSelection(.enabled)
                .textual.textSelectionActions(selectionActions.textualActions(
                    messageID: annotationMessageID, segmentIndex: annotationSegmentIndex))
                .textual.textAnnotations(selectionActions.textAnnotations(
                    messageID: annotationMessageID, segmentIndex: annotationSegmentIndex))
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

        return StructuredText(markdown: text, renderImmediately: renderImmediately)
            .textual.structuredTextStyle(.gitHub)
            .font(.system(size: ty.body))
            .lineSpacing(4)
            .foregroundColor(theme.colors.textPrimary)
            .tint(theme.colors.accentCyan)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ChatSegmentCollapsibleCard: View {
    private static let detailHeight: CGFloat = 260

    let message: ChatMessage
    let segment: ChatMessageSegment
    let isRunning: Bool
    var isInsideActivityScroll = false

    @State private var isExpanded = false
    @Environment(\.theme) private var theme

    var body: some View {
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
                Group {
                    if isInsideActivityScroll {
                        detailContent
                    } else {
                        ScrollView(.vertical) {
                            detailContent
                        }
                        .frame(height: Self.detailHeight)
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, sp.xs)
    }

    @ViewBuilder
    private var detailContent: some View {
        if segment.kind == .toolCall || segment.kind == .toolResult {
            terminalDetail
        } else {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                if let text = segment.text, !text.isEmpty {
                    ChatMarkdownTextStack(text: text, allowsTextSelection: !isRunning)
                }
                metadataRows
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var terminalDetail: some View {
        let c = theme.colors
        let sp = theme.spacing
        let metadata = segment.metadata ?? [:]
        let inputKey = ["cmd", "command", "script", "input"].first { metadata[$0] != nil }

        return VStack(alignment: .leading, spacing: sp.s) {
            Text(segment.kind == .toolCall ? "input" : "output")
                .font(.system(size: theme.typography.micro, design: .monospaced))
                .foregroundColor(c.textMuted)

            if let inputKey, let input = metadata[inputKey] {
                Text(verbatim: "$ \(input)")
                    .foregroundColor(c.textPrimary)
                    .textSelection(.enabled)
            }

            if let text = segment.text, !text.isEmpty {
                Text(verbatim: text)
                    .foregroundColor(c.textSecondary)
                    .textSelection(.enabled)
            }

            metadataRows(excluding: inputKey)
        }
        .font(.system(size: theme.typography.caption, design: .monospaced))
        .lineSpacing(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(sp.m)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(c.surfaceGlow)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(c.borderBold, lineWidth: theme.borders.thin)
                }
        }
    }

    @ViewBuilder
    private var metadataRows: some View {
        metadataRows(excluding: nil)
    }

    @ViewBuilder
    private func metadataRows(excluding excludedKey: String?) -> some View {
        if let metadata = segment.metadata, !metadata.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                ForEach(metadata.keys.sorted().filter { $0 != excludedKey }, id: \.self) { key in
                    HStack(alignment: .top, spacing: theme.spacing.xs) {
                        Text(key)
                            .font(.system(size: theme.typography.micro, design: .monospaced))
                            .foregroundColor(theme.colors.textMuted)
                        metadataValue(metadata[key] ?? "")
                    }
                }
            }
        }
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
#if !os(macOS)
            Image(systemName: segmentSystemImage)
                .font(.system(size: theme.typography.caption))
                .foregroundColor(c.textMuted)
                .frame(width: 18)
#endif

            if isRunning {
                ChatShimmerText(text: segmentTitle)
                    .font(.system(size: theme.typography.caption))
            } else {
                Text(segmentTitle)
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(c.textSecondary)
                    .lineLimit(1)
            }

#if os(macOS)
            if hasExpandableContent {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(c.textMuted)
            }
#endif
            if let durationText {
                Text(durationText)
                    .font(.system(size: theme.typography.micro))
                    .foregroundColor(c.textMuted)
                    .lineLimit(1)
            }

#if !os(macOS)
            Spacer(minLength: 0)
            if hasExpandableContent {
                Icons.symbol(isExpanded ? .collapseContent : .expandMore, size: theme.typography.caption)
                    .foregroundColor(c.textMuted)
            }
#endif
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isExpanded.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(hasExpandableContent ? .isButton : [])
        .accessibilityAction {
            if hasExpandableContent { isExpanded.toggle() }
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

struct ChatShimmerText: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    var body: some View {
        if reduceMotion {
            Text(text)
                .foregroundStyle(theme.colors.textSecondary)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let progress = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.8) / 1.8
                let center = -0.35 + progress * 1.7

                Text(text)
                    .foregroundStyle(theme.colors.textMuted)
                    .overlay {
                        GeometryReader { geometry in
                            LinearGradient(
                                colors: [
                                    theme.colors.textPrimary.opacity(0 as Double),
                                    theme.colors.textPrimary,
                                    theme.colors.textPrimary.opacity(0 as Double),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geometry.size.width * 0.7)
                            .offset(x: geometry.size.width * (center - 0.35))
                        }
                        .mask(Text(text))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
            }
        }
    }
}
