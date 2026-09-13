import SwiftUI
import SloppyClientUI
import SloppyClientCore

struct TaskExternalMetadataChips: View {
    let metadata: APIProjectTaskExternalMetadata
    var allowsLink = false
    @Environment(\.theme) private var theme

    var body: some View {
        TaskChipFlowLayout {
            if let key = metadata.externalIssueKey ?? metadata.providerId {
                if allowsLink, let rawURL = metadata.externalIssueURL, let url = URL(string: rawURL),
                   ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    Link(destination: url) {
                        TaskMetadataChip(title: key, icon: "arrow.up.right.square", color: theme.colors.accentCyan)
                    }
                } else {
                    TaskMetadataChip(title: key, icon: "arrow.up.right.square", color: theme.colors.accentCyan)
                }
            }
            if let status = metadata.externalStatus?.display {
                TaskMetadataChip(title: status, icon: "arrow.left.arrow.right", color: theme.colors.accentCyan)
            }
            if let sync = metadata.syncState {
                TaskMetadataChip(title: sync, icon: "arrow.triangle.2.circlepath", color: theme.colors.accentCyan)
            }
        }
    }
}

struct TaskMetadataChip: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.4), lineWidth: 1))
    }
}

struct TaskPriorityChip: View {
    let priority: String
    @Environment(\.theme) private var theme

    var body: some View {
        TaskMetadataChip(title: priority.capitalized, icon: "flag", color: color)
    }

    private var color: Color {
        switch priority.lowercased() {
        case "high", "critical": theme.colors.statusBlocked
        case "medium": theme.colors.statusWarning
        case "low": theme.colors.accentCyan
        default: theme.colors.textSecondary
        }
    }
}

struct TaskTagChips: View {
    let tags: [String]
    @Environment(\.theme) private var theme

    var body: some View {
        TaskChipFlowLayout {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                TaskMetadataChip(title: tag, icon: "tag", color: theme.colors.statusReady)
            }
        }
    }
}

/// Wrap chips at their natural width; long tags can still wrap within a chip.
struct TaskChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 600).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                 proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, frames: [CGRect]) {
        let width = max(1, width)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: min(size.width, width), height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
    }
}
