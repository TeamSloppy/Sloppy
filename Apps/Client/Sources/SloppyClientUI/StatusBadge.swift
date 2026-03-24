import AdaEngine

public struct StatusBadge: View {
    let label: String
    let color: Color

    public init(_ label: String, color: Color) {
        self.label = label
        self.color = color
    }

    public var body: some View {
        HStack(spacing: Theme.spacingXS) {
            Color.clear
                .frame(width: 6, height: 6)
                .background(color)

            Text(label.uppercased())
                .font(.system(size: Theme.fontMicro))
                .foregroundColor(color)
        }
        .padding(.horizontal, Theme.spacingS)
        .padding(.vertical, Theme.spacingXS)
        .border(color, lineWidth: Theme.borderThin)
    }

    public static func forTaskStatus(_ status: String) -> StatusBadge {
        switch status {
        case "in_progress":
            StatusBadge("Active", color: Theme.statusActive)
        case "ready":
            StatusBadge("Ready", color: Theme.statusReady)
        case "needs_review":
            StatusBadge("Review", color: Theme.statusWarning)
        case "done":
            StatusBadge("Done", color: Theme.statusDone)
        case "blocked":
            StatusBadge("Blocked", color: Theme.statusBlocked)
        case "cancelled":
            StatusBadge("Off", color: Theme.statusNeutral)
        case "backlog":
            StatusBadge("Backlog", color: Theme.statusNeutral)
        case "pending_approval":
            StatusBadge("Pending", color: Theme.statusWarning)
        default:
            StatusBadge(status, color: Theme.statusNeutral)
        }
    }
}
