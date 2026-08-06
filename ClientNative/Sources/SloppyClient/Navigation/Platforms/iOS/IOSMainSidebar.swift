#if os(iOS)
import SloppyClientUI
import SloppyFeatureAgents
import SwiftUI

@MainActor
struct PlatformMainSidebar: View {
    let viewModel: MainViewModel
    let isOverlay: Bool
    let canvasWorkspaceViewModel: CanvasWorkspaceViewModel

    @Environment(\.userInterfaceIdiom) private var idiom

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                mainTabs
                    .tabViewBottomAccessory {
                        if idiom == .phone, viewModel.selectedAppSection == .chats {
                            newChatAccessory
                        }
                    }
            } else {
                mainTabs
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .refreshable { await viewModel.refreshContent() }
    }

    private var mainTabs: some View {
        @Bindable var viewModel = viewModel
        return TabView(selection: $viewModel.selectedAppSection) {
            Tab("Agents", systemImage: "person.2", value: MainAppSection.agents) {
                AgentsScreen(apiClient: viewModel.apiClient)
            }
            Tab("Chats", systemImage: "message", value: MainAppSection.chats) {
                NavigationStack {
                    ScrollView {
                        SidebarRecentsList(viewModel: viewModel)
                    }
                    .navigationTitle("Chats")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        if #unavailable(iOS 26.0) {
                            ToolbarItem(placement: .topBarTrailing) {
                                newChatToolbarButton
                            }
                        }
                    }
                }
            }
            Tab("Workspace", systemImage: "square.grid.2x2", value: MainAppSection.workspace) {
                if idiom == .phone {
                    NavigationStack {
                        CanvasWorkspaceSurface(viewModel: canvasWorkspaceViewModel)
                    }
                } else {
                    Color.clear
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private var newChatAccessory: some View {
        Button(action: viewModel.selectNewChat) {
            ViewThatFits(in: .horizontal) {
                Label("New Chat", systemImage: "square.and.pencil")
                    .lineLimit(1)
                Image(systemName: "square.and.pencil")
            }
        }
        .accessibilityLabel("New chat")
        .accessibilityIdentifier("sidebar.new-chat")
    }

    private var newChatToolbarButton: some View {
        Button(action: viewModel.selectNewChat) {
            Label("New Chat", systemImage: "square.and.pencil")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("New chat")
        .accessibilityIdentifier("sidebar.new-chat")
    }
}

#Preview("iOS Sidebar") {
    PlatformMainSidebar(
        viewModel: .preview(),
        isOverlay: false,
        canvasWorkspaceViewModel: CanvasWorkspaceViewModel()
    )
}
#endif
