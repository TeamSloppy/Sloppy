import Foundation
import SloppyClientCore
import SloppyClientUI
import SwiftUI

struct ChatConversationWaypoint: Identifiable, Equatable {
    let id: ChatMessage.ID
    let targetItemID: String
    let title: String
    var responsePreview: String?

    static func build(from messages: [ChatMessage]) -> [Self] {
        var waypoints: [Self] = []

        for message in messages {
            switch message.role {
            case .user:
                waypoints.append(Self(
                    id: message.id,
                    targetItemID: "entry:message:\(message.id)",
                    title: previewText(message.textContent, fallback: "User message"),
                    responsePreview: nil
                ))
            case .assistant:
                guard !waypoints.isEmpty else { continue }
                let text = previewText(message.textContent, fallback: "")
                guard !text.isEmpty else { continue }
                if let existing = waypoints[waypoints.index(before: waypoints.endIndex)].responsePreview {
                    waypoints[waypoints.index(before: waypoints.endIndex)].responsePreview = previewText(
                        existing + " " + text,
                        fallback: existing
                    )
                } else {
                    waypoints[waypoints.index(before: waypoints.endIndex)].responsePreview = text
                }
            case .system:
                continue
            }
        }

        return waypoints
    }

    private static func previewText(_ value: String, fallback: String) -> String {
        let normalized = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !normalized.isEmpty else { return fallback }
        let limit = 360
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

struct ChatTranscriptScrollTarget: Equatable {
    let itemID: String
    let requestID: UInt
}

#if os(macOS)
@MainActor
struct ChatConversationNavigator: View {
    let waypoints: [ChatConversationWaypoint]
    let activeWaypointID: ChatConversationWaypoint.ID?
    let onSelect: @MainActor (ChatConversationWaypoint) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @State private var hoveredWaypointID: ChatConversationWaypoint.ID?

    private var hoveredWaypoint: ChatConversationWaypoint? {
        waypoints.first { $0.id == hoveredWaypointID }
    }

    var body: some View {
        HStack(spacing: theme.spacing.xs) {
            markerRail

            if let hoveredWaypoint {
                previewCard(hoveredWaypoint)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hoveredWaypointID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conversation navigation")
    }

    private var markerRail: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(Array(waypoints.enumerated()), id: \.element.id) { index, waypoint in
                    marker(for: waypoint, index: index)
                }
            }
            .padding(.vertical, 2)
            .frame(width: 26, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(width: 30)
        .frame(height: railHeight)
    }

    private func marker(for waypoint: ChatConversationWaypoint, index: Int) -> some View {
        let isActive = waypoint.id == activeWaypointID
        let isHovered = waypoint.id == hoveredWaypointID
        let markerWidth: CGFloat = isActive ? 18 : isHovered ? 14 : idleMarkerWidth(at: index)

        return Button {
            onSelect(waypoint)
        } label: {
            Capsule(style: .continuous)
                .fill(isActive ? theme.colors.textPrimary : theme.colors.textMuted.opacity(isHovered ? 0.82 : 0.50))
                .frame(width: markerWidth, height: isActive ? 3 : 2)
                .frame(width: 26, height: 4, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            if isHovered {
                hoveredWaypointID = waypoint.id
            } else if hoveredWaypointID == waypoint.id {
                hoveredWaypointID = nil
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: markerWidth)
        .accessibilityLabel("Conversation turn \(index + 1): \(waypoint.title)")
        .accessibilityValue(isActive ? "Current" : "")
    }

    private func previewCard(_ waypoint: ChatConversationWaypoint) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(waypoint.title)
                .font(.system(size: theme.typography.caption, weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)

            if let responsePreview = waypoint.responsePreview {
                Divider()
                    .overlay(theme.colors.borderBold.opacity(0.72))

                Text(responsePreview)
                    .font(.system(size: theme.typography.caption))
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(theme.spacing.s)
        .frame(width: 260, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.colors.surfaceRaised.opacity(0.96))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.colors.borderBold.opacity(0.72), lineWidth: theme.borders.thin)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func idleMarkerWidth(at index: Int) -> CGFloat {
        switch index % 4 {
        case 0: 8
        case 1: 12
        case 2: 7
        default: 10
        }
    }

    private var railHeight: CGFloat {
        min(240, max(20, CGFloat(waypoints.count * 4 + 4)))
    }
}
#endif
