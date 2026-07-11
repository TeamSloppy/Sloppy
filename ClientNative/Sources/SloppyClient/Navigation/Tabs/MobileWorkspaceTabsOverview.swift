import SwiftUI
import SloppyClientUI
#if canImport(UIKit)
import UIKit
typealias MobileWorkspaceTabSnapshotImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias MobileWorkspaceTabSnapshotImage = NSImage
#endif

@MainActor
struct MobileWorkspaceTabsOverview: View {
    let tabs: [WorkspaceTab]
    let selectedTabID: WorkspaceTab.ID?
    let snapshotCache: [WorkspaceTab.ID: MobileWorkspaceTabSnapshotImage]
    let hiddenThumbnailTabID: WorkspaceTab.ID?
    let appearanceProgress: CGFloat
    let onSelect: @MainActor (WorkspaceTab.ID) -> Void
    let onClose: @MainActor (WorkspaceTab.ID) -> Void
    let onCreate: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void
    let onThumbnailFramesChange: @MainActor ([WorkspaceTab.ID: CGRect]) -> Void

    @Environment(\.theme) private var theme

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        let clampedProgress = clamp(appearanceProgress)
        let contentProgress = clamp((clampedProgress - 0.08) / 0.92)

        ZStack {
            theme.colors.surface.opacity(0.88 as CGFloat * clampedProgress)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: theme.spacing.l) {
                HStack {
                    Text("Tabs")
                        .font(.system(size: theme.typography.heading))
                        .foregroundColor(theme.colors.textPrimary)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(theme.colors.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(theme.colors.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    LazyVGrid(columns: columns, spacing: theme.spacing.m) {
                        ForEach(tabs) { tab in
                            MobileWorkspaceTabPreviewCard(
                                tab: tab,
                                snapshotImage: snapshotCache[tab.id],
                                isSelected: selectedTabID == tab.id,
                                isThumbnailHidden: hiddenThumbnailTabID == tab.id,
                                onSelect: { onSelect(tab.id) },
                                onClose: { onClose(tab.id) }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
                        }
                    }
                    .padding(.vertical, theme.spacing.xs)
                }

                Button(action: onCreate) {
                    HStack(spacing: theme.spacing.xs) {
                        Image(systemName: "plus")
                        Text("New Tab")
                    }
                    .font(.system(size: theme.typography.body, weight: .semibold))
                    .foregroundColor(theme.colors.textPrimary)
                    .padding(.horizontal, theme.spacing.l)
                    .padding(.vertical, theme.spacing.m)
                    .background(Capsule().fill(theme.colors.surfaceRaised))
                }
                .buttonStyle(.plain)
            }
            .padding(theme.spacing.l)
            .opacity(Double(contentProgress))
            .scaleEffect(0.96 + (0.04 * contentProgress), anchor: .top)
            .offset(y: (1 - contentProgress) * 20)
        }
        .onPreferenceChange(MobileWorkspaceTabThumbnailFramePreferenceKey.self) { newValue in
            onThumbnailFramesChange(newValue)
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

}

@MainActor
private struct MobileWorkspaceTabPreviewCard: View {
    let tab: WorkspaceTab
    let snapshotImage: MobileWorkspaceTabSnapshotImage?
    let isSelected: Bool
    let isThumbnailHidden: Bool
    let onSelect: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                MobileWorkspaceTabThumbnail(tab: tab, snapshotImage: snapshotImage)
                    .opacity(isThumbnailHidden ? 0.0 : 1.0)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: MobileWorkspaceTabThumbnailFramePreferenceKey.self,
                                    value: [tab.id: proxy.frame(in: .global)]
                                )
                        }
                    }
            }
            .frame(maxWidth: .infinity, minHeight: 204, maxHeight: 204, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isSelected ? theme.colors.surfaceRaised : theme.colors.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(anchor: .topTrailing, content: {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: theme.typography.heading))
                    .foregroundColor(theme.colors.textPrimary)
                    .shadow(color: .black.opacity(0.28 as CGFloat), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .padding(theme.spacing.s)
        })
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isSelected ? theme.colors.accentCyan.opacity(0.48 as CGFloat) : theme.colors.border,
                    lineWidth: isSelected ? 2 : 1
                )
        }
    }
}

private struct MobileWorkspaceTabThumbnailFramePreferenceKey: PreferenceKey {
    static let defaultValue: [WorkspaceTab.ID: CGRect] = [:]

    static func reduce(value: inout [WorkspaceTab.ID: CGRect], nextValue: () -> [WorkspaceTab.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

@MainActor
private struct MobileWorkspaceTabThumbnail: View {
    let tab: WorkspaceTab
    let snapshotImage: MobileWorkspaceTabSnapshotImage?

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let snapshotImage {
                snapshotView(snapshotImage)
            } else {
                LinearGradient(
                    colors: [
                        theme.colors.surfaceRaised,
                        theme.colors.background
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    HStack(spacing: theme.spacing.xs) {
                        Circle()
                            .fill(theme.colors.accentCyan.opacity(0.72 as CGFloat))
                            .frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(theme.colors.textMuted.opacity(0.36 as CGFloat))
                            .frame(width: 54, height: 8)
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(theme.colors.textPrimary.opacity(0.26 as CGFloat))
                            .frame(width: 118, height: 10)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(theme.colors.textSecondary.opacity(0.22 as CGFloat))
                            .frame(width: 88, height: 8)
                    }

                    Spacer(minLength: 0)

                    Text(tab.kind.rawValue)
                        .font(.system(size: theme.typography.micro, weight: .semibold))
                        .foregroundColor(theme.colors.textSecondary)
                        .padding(.horizontal, theme.spacing.xs)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(theme.colors.surface.opacity(0.72 as CGFloat)))
                }
                .padding(theme.spacing.s)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if snapshotImage == nil {
                Image(systemName: thumbnailIconName)
                    .font(.system(size: theme.typography.title, weight: .semibold))
                    .foregroundColor(theme.colors.textMuted.opacity(0.32 as CGFloat))
                    .padding(theme.spacing.s)
            }
        }
    }

    @ViewBuilder
    private func snapshotView(_ image: MobileWorkspaceTabSnapshotImage) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
        #endif
    }

    private var thumbnailIconName: String {
        switch tab.kind {
        case .chat:
            return "text.bubble"
        case .projectKanban:
            return "rectangle.grid.2x2"
        case .taskDetail:
            return "checklist"
        case .workspaceFiles:
            return "folder"
        }
    }
}
