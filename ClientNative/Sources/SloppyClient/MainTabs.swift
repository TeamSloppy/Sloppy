import Foundation
import CoreGraphics
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyFeatureProjects

struct DesktopTabSplitState: Equatable {
    var primaryTabID: WorkspaceTab.ID
    var secondaryTabID: WorkspaceTab.ID
    var fraction: CGFloat
}

@MainActor
final class WorkspaceTabState {
    let contentState: WorkspaceTabContentState
    var content: AnyView?

    init(contentState: WorkspaceTabContentState, content: AnyView? = nil) {
        self.contentState = contentState
        self.content = content
    }

    var chatState: ChatTabState? {
        guard case .chat(let state) = contentState else {
            return nil
        }
        return state
    }

    var projectKanbanState: ProjectKanbanTabState? {
        guard case .projectKanban(let state) = contentState else {
            return nil
        }
        return state
    }

    var workspaceFilesState: WorkspaceFilesTabState? {
        guard case .workspaceFiles(let state) = contentState else {
            return nil
        }
        return state
    }

    var taskDetailState: TaskDetailTabState? {
        guard case .taskDetail(let state) = contentState else {
            return nil
        }
        return state
    }
}

@MainActor
enum WorkspaceTabContentState {
    case chat(ChatTabState)
    case projectKanban(ProjectKanbanTabState)
    case taskDetail(TaskDetailTabState)
    case workspaceFiles(WorkspaceFilesTabState)
}

@MainActor
final class ChatTabState {
    let viewModel: ChatScreenViewModel

    init(viewModel: ChatScreenViewModel) {
        self.viewModel = viewModel
    }
}

@MainActor
final class ProjectKanbanTabState {
    let viewModel: ProjectKanbanViewModel

    init(viewModel: ProjectKanbanViewModel) {
        self.viewModel = viewModel
    }
}

@MainActor
final class WorkspaceFilesTabState {
    let viewModel: WorkspacePanelViewModel

    init(viewModel: WorkspacePanelViewModel) {
        self.viewModel = viewModel
    }
}

@MainActor
final class TaskDetailTabState {
    let viewModel: TaskDetailViewModel

    init(viewModel: TaskDetailViewModel) {
        self.viewModel = viewModel
    }
}
