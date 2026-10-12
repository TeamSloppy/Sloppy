import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import Textual

struct ChatSystemMessageGroupView: View {
    private static let activityHeight: CGFloat = 260

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

            if isExpanded && !visibleItems.isEmpty {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: theme.spacing.xs) {
                        ForEach(visibleItems) { item in
                            segmentRow(item, insideScroll: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: Self.activityHeight)
                .padding(.leading, 28)
            } else if !visibleItems.isEmpty {
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    ForEach(visibleItems) { item in
                        segmentRow(item, insideScroll: false)
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

                if items.contains(where: \.isRunning) {
                    ChatShimmerText(text: "Activity")
                        .font(.system(size: theme.typography.caption))
                } else {
                    Text("Activity")
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textSecondary)
                }

                Text(summaryTitle(for: items))
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(theme.colors.textMuted)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse activity" : "Expand activity")
    }

    private func segmentRow(_ item: ChatSystemSegmentItem, insideScroll: Bool) -> some View {
        ChatSegmentCollapsibleCard(
            message: item.message,
            segment: item.segment,
            isRunning: item.isRunning,
            isInsideActivityScroll: insideScroll
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
                        && (segment.isExecutionRunning || segment.kind == .thinking)
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
        var seen: Set<String> = []
        return titles.filter { seen.insert($0).inserted }.prefix(3).joined(separator: " · ")
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
