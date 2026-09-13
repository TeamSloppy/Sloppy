import SloppyClientCore
import SwiftUI

enum MainSidebarSelection: Hashable {
    case pullRequests
    case scheduled
    case artifacts
    case sites
    case project(String)
    case task(projectId: String, taskId: String)
    case chats
}

@MainActor
struct MainSidebarView: View {
    static let expandedWidth: CGFloat = 348
    static let collapsedWidth: CGFloat = 150
    static let minimumWidth: CGFloat = 340
    static let maximumWidth: CGFloat = 520
    static let rowMinimumHeight: CGFloat = 32

    let viewModel: MainViewModel
    let isOverlay: Bool
    var composerBackdropHeight: CGFloat? = nil
    let canvasWorkspaceViewModel: CanvasWorkspaceViewModel
    let navigationDestination: @MainActor (MainSidebarSelection) -> AnyView

    var body: some View {
        #if os(iOS)
        PlatformMainSidebar(
            viewModel: viewModel,
            isOverlay: isOverlay,
            canvasWorkspaceViewModel: canvasWorkspaceViewModel,
            navigationDestination: navigationDestination
        )
        #elseif os(macOS)
        PlatformMainSidebar(
            viewModel: viewModel,
            isOverlay: isOverlay,
            composerBackdropHeight: composerBackdropHeight
        )
        #else
        PlatformMainSidebar(viewModel: viewModel, isOverlay: isOverlay)
        #endif
    }
}
