#if os(macOS)
import SloppyClientUI
import SwiftUI

@MainActor
struct PlatformMainSidebar: View {
    let viewModel: MainViewModel
    let isOverlay: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                MacSidebarPrimaryActions(viewModel: viewModel)
                SidebarRecentsList(viewModel: viewModel)
            }
        }
        .refreshable { await viewModel.refreshContent() }
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
                icon: .autoAwesome,
                title: "Search chats",
                isSelected: false,
                action: {}
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
