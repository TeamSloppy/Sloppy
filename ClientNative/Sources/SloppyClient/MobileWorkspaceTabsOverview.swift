import SwiftUI
import SloppyClientUI

@MainActor
struct MobileWorkspaceTabsOverview: View {
    let tabs: [WorkspaceTab]
    let selectedTabID: WorkspaceTab.ID?
    let onSelect: @MainActor (WorkspaceTab.ID) -> Void
    let onClose: @MainActor (WorkspaceTab.ID) -> Void
    let onCreate: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    @Environment(\.theme) private var theme

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ZStack {
            theme.colors.surface.opacity(0.88 as CGFloat)
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
                                isSelected: selectedTabID == tab.id,
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
        }
    }

}

@MainActor
private struct MobileWorkspaceTabPreviewCard: View {
    private let previewHeight: CGFloat = 132

    let tab: WorkspaceTab
    let isSelected: Bool
    let onSelect: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    MobileWorkspaceTabThumbnail(tab: tab)
                        .frame(height: previewHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: theme.typography.heading))
                            .foregroundColor(theme.colors.textPrimary)
                            .shadow(color: .black.opacity(0.28 as CGFloat), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(theme.spacing.s)
                }

                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(tab.title)
                        .font(.system(size: theme.typography.body, weight: .semibold))
                        .foregroundColor(theme.colors.textPrimary)
                        .lineLimit(1)

                    Text(tab.kind.rawValue)
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.m)
            }
            .frame(maxWidth: .infinity, minHeight: 204, maxHeight: 204, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isSelected ? theme.colors.surfaceRaised : theme.colors.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        isSelected ? theme.colors.accentCyan.opacity(0.48 as CGFloat) : theme.colors.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct MobileWorkspaceTabThumbnail: View {
    let tab: WorkspaceTab

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
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
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: thumbnailIconName)
                .font(.system(size: theme.typography.title, weight: .semibold))
                .foregroundColor(theme.colors.textMuted.opacity(0.32 as CGFloat))
                .padding(theme.spacing.s)
        }
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
