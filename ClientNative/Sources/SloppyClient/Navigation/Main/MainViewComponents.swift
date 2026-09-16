import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureAgents
import SloppyFeatureChat
import SloppyFeatureProjects
import SloppyFeatureSettings
import SloppyFeatureSites

@MainActor
struct DesktopTabsEmptyState: View {
    @Environment(\.theme) var theme

    var body: some View {
        VStack(spacing: theme.spacing.m) {
            Icons.symbol(.folder, size: theme.typography.title)
                .foregroundColor(theme.colors.textMuted)
            Text("No tabs open")
                .font(.system(size: theme.typography.body))
                .foregroundColor(theme.colors.textPrimary)
            Text("Open a project, task, or recent chat from the sidebar.")
                .font(.system(size: theme.typography.caption))
                .foregroundColor(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
struct DesktopTabPlaceholderView: View {
    let title: String
    let detail: String

    @Environment(\.theme) var theme

    var body: some View {
        VStack(spacing: theme.spacing.m) {
            Text(title)
                .font(.system(size: theme.typography.title))
                .foregroundColor(theme.colors.textPrimary)
            Text(detail)
                .font(.system(size: theme.typography.body))
                .foregroundColor(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
struct WorkspaceUnavailableView: View {
    @Environment(\.theme) var theme

    var body: some View {
        VStack(spacing: theme.spacing.m) {
            Icons.symbol(.folder, size: theme.typography.title)
                .foregroundColor(theme.colors.textMuted)
            Text("Workspace is available when a project chat is active.")
                .font(.system(size: theme.typography.body))
                .foregroundColor(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
struct DesktopSplitContentView<Primary: View, Secondary: View>: View {
    let fraction: CGFloat
    let onFractionChange: @MainActor (CGFloat) -> Void
    let onClearSplit: @MainActor () -> Void
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary
    @State var dragStartFraction: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let clampedFraction = min(0.88, max(0.12, fraction))
            let handleWidth: CGFloat = 24
            let primaryWidth = max(0, width * clampedFraction - handleWidth / 2)
            let secondaryWidth = max(0, width - primaryWidth - handleWidth)

            HStack(spacing: 0) {
                primary()
                    .frame(width: primaryWidth)

                DesktopSplitHandle(
                    onClearSplit: onClearSplit,
                    onDrag: { translationWidth in
                        let start = dragStartFraction ?? clampedFraction
                        dragStartFraction = start
                        onFractionChange(start + translationWidth / width)
                    },
                    onDragEnded: { dragStartFraction = nil }
                )
                .frame(width: handleWidth)

                secondary()
                    .frame(width: secondaryWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
struct DesktopSplitHandle: View {
    let onClearSplit: @MainActor () -> Void
    let onDrag: @MainActor (CGFloat) -> Void
    let onDragEnded: @MainActor () -> Void

    @Environment(\.theme) var theme
    @State var isHovered = false

    var body: some View {
        VStack(spacing: theme.spacing.s) {
            Capsule()
                .fill(theme.colors.border)
                .frame(width: 4, height: 48)

            Button(action: onClearSplit) {
                Image(systemName: "rectangle.compress.horizontal")
                    .font(.system(size: theme.typography.micro, weight: .semibold))
                    .foregroundColor(theme.colors.textSecondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isHovered ? theme.colors.surfaceRaised.opacity(0.32 as CGFloat) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    onDrag(value.translation.width)
                }
                .onEnded { _ in onDragEnded() }
        )
    }
}

let chatContentWidth: CGFloat = 840
