import SloppyClientCore
import SwiftUI

enum MainSidebarSelection: Hashable {
    case scheduled
    case artifacts
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
    let canvasWorkspaceViewModel: CanvasWorkspaceViewModel

    var body: some View {
        #if os(iOS)
        PlatformMainSidebar(
            viewModel: viewModel,
            isOverlay: isOverlay,
            canvasWorkspaceViewModel: canvasWorkspaceViewModel
        )
        #else
        PlatformMainSidebar(viewModel: viewModel, isOverlay: isOverlay)
        #endif
    }
}
