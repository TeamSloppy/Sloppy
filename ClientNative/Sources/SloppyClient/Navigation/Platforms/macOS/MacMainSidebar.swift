#if os(macOS)
import Foundation
import SloppyClientUI
import SwiftUI

@MainActor
struct PlatformMainSidebar: View {
    let viewModel: MainViewModel
    let isOverlay: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                MacSidebarPrimaryActions(viewModel: viewModel)
                SidebarRecentsList(viewModel: viewModel)
            }
        }
        .refreshable { await viewModel.refreshContent() }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: theme.spacing.s) {
                Text(accountInitials)
                    .font(.system(size: theme.typography.micro, weight: .semibold))
                    .foregroundColor(theme.colors.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(theme.colors.accent, in: Circle())

                Text(accountDisplayName)
                    .font(.system(size: theme.typography.body, weight: .medium))
                    .foregroundColor(theme.colors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: theme.spacing.s)

                Button {
                    viewModel.onOpenSettings(.general)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: theme.typography.heading))
                }
                .accessibilityLabel("Open settings")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, theme.spacing.m)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(theme.colors.surfaceRaised.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(theme.colors.borderBold)
                    .frame(height: theme.borders.thin)
            }
        }
    }

    private var accountDisplayName: String {
        let profileName = viewModel.currentAuthUser?.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let profileName, !profileName.isEmpty {
            return profileName
        }

        let login = viewModel.currentAuthUser?.login
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let login, !login.isEmpty {
            return login
        }

        let localName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return localName.isEmpty ? NSUserName() : localName
    }

    private var accountInitials: String {
        let words = accountDisplayName.split(whereSeparator: \Character.isWhitespace)
        let initials = words.prefix(2).compactMap(\.first)
        guard !initials.isEmpty else { return "?" }
        return String(initials).uppercased()
    }
}

@MainActor
private struct MacSidebarPrimaryActions: View {
    let viewModel: MainViewModel

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarNavigationRow(
                icon: .new,
                title: "New chat",
                isSelected: false,
                navigationValue: .chats,
                action: viewModel.selectNewChat
            )

            SidebarNavigationRow(
                icon: .timer,
                title: "Scheduled",
                isSelected: viewModel.selectedAppSection == .scheduled,
                navigationValue: .scheduled,
                action: viewModel.selectScheduled
            )

            SidebarNavigationRow(
                icon: .workspace,
                title: "Workspace",
                isSelected: viewModel.selectedAppSection == .workspace,
                action: viewModel.selectWorkspace
            )
            
            SidebarNavigationRow(
                icon: .description,
                title: "Artifacts",
                isSelected: viewModel.selectedAppSection == .artifacts,
                navigationValue: .artifacts,
                action: viewModel.selectArtifacts
            )
        }
        .padding(.horizontal, theme.spacing.xs)
    }
}

#Preview("macOS Sidebar") {
    PlatformMainSidebar(viewModel: .preview(), isOverlay: false)
        .frame(width: 348, height: 700)
}
#endif
