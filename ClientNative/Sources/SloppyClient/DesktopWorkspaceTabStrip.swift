import SwiftUI
import SloppyClientUI

@MainActor
struct DesktopWorkspaceTabStrip: View {
    let viewModel: MainViewModel

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.xs) {
                    ForEach(viewModel.tabs) { tab in
                        DesktopWorkspaceTabButton(
                            tab: tab,
                            isSelected: viewModel.selectedTabID == tab.id,
                            onSelect: { viewModel.selectTab(tab.id) },
                            onClose: { viewModel.closeTab(tab.id) }
                        )
                    }
                }
            }

            Button(action: { viewModel.createBlankChatTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: theme.typography.caption, weight: .semibold))
                    .foregroundColor(theme.colors.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(theme.colors.surfaceRaised.opacity(0.85 as CGFloat))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, theme.spacing.s)
        .padding(.vertical, theme.spacing.xs)
        .background(theme.colors.surface.opacity(0.82 as CGFloat))
    }
}

@MainActor
private struct DesktopWorkspaceTabButton: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    let onSelect: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.xs) {
            Button(action: onSelect) {
                Text(tab.title)
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, theme.spacing.m)
                    .padding(.vertical, theme.spacing.s)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: theme.typography.micro, weight: .bold))
                    .foregroundColor(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(theme.colors.surface.opacity(0.3 as CGFloat))
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, theme.spacing.s)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelected
                        ? theme.colors.surfaceRaised
                        : theme.colors.surface.opacity(0.72 as CGFloat)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.colors.textMuted.opacity(isSelected ? 0.15 as CGFloat : 0.06 as CGFloat))
        )
    }
}
