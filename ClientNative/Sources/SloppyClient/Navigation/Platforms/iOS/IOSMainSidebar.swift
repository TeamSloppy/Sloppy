#if os(iOS)
import SloppyClientUI
import SloppyFeatureAgents
import SwiftUI

@MainActor
struct PlatformMainSidebar: View {
    let viewModel: MainViewModel
    let isOverlay: Bool

    @Environment(\.theme) private var theme
    @Environment(\.userInterfaceIdiom) private var idiom

    var body: some View {
        @Bindable var viewModel = viewModel
        TabView(selection: $viewModel.selectedAppSection) {
            Tab("Agents", systemImage: "person.2", value: MainAppSection.agents) {
                AgentsScreen(apiClient: viewModel.apiClient)
            }
            Tab("Chats", systemImage: "message", value: MainAppSection.chats) {
                ScrollView { SidebarRecentsList(viewModel: viewModel) }
            }
            Tab("Workspace", systemImage: "square.grid.2x2", value: MainAppSection.workspace) {
                Color.clear
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .refreshable { await viewModel.refreshContent() }
        .overlay(alignment: .bottomTrailing) {
            if idiom == .phone {
                Button(action: viewModel.selectNewChat) {
                    Image(systemName: "plus").frame(width: 48, height: 48)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .padding(.bottom, isOverlay ? theme.spacing.xl + theme.spacing.s : theme.spacing.m)
                .padding(.trailing, theme.spacing.s)
            }
        }
    }
}

#Preview("iOS Sidebar") {
    PlatformMainSidebar(viewModel: .preview(), isOverlay: false)
}
#endif
