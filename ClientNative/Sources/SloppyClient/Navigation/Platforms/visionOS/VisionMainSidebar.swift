#if os(visionOS)
import SloppyFeatureAgents
import SwiftUI

@MainActor
struct PlatformMainSidebar: View {
    let viewModel: MainViewModel
    let isOverlay: Bool

    var body: some View {
        @Bindable var viewModel = viewModel
        TabView(selection: $viewModel.selectedAppSection) {
            Tab("Agents", systemImage: "person.2", value: MainAppSection.agents) {
                AgentsScreen(apiClient: viewModel.apiClient)
            }
            Tab("Chats", systemImage: "message", value: MainAppSection.chats) {
                ScrollView { SidebarRecentsList(viewModel: viewModel) }
            }
        }
        .refreshable { await viewModel.refreshContent() }
    }
}

#Preview("visionOS Sidebar") {
    PlatformMainSidebar(viewModel: .preview(), isOverlay: false)
}
#endif
