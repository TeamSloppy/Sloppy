#if os(macOS)
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
            HStack {

                Spacer()

                Button {
                    viewModel.onOpenSettings(.general)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: theme.typography.heading))
                }
            }
            .buttonStyle(.borderless)
            .padding()
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(colors: [
                    Color.black.opacity(0.01),
                    Color.black.opacity(0.1),
                    Color.black.opacity(0.1),
                ], startPoint: .top, endPoint: .bottom)
                .blur(radius: 4)
            )
        }
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
                title: "Артефакты",
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
