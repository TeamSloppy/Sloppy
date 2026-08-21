import Foundation
import CoreGraphics
import Observation
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

enum ProjectModeSection: String, CaseIterable, Hashable, Identifiable {
    case kanban
    case workspaces
    case automation
    case chats

    var id: Self { self }

    var title: String {
        switch self {
        case .kanban: "Kanban"
        case .workspaces: "Workspaces"
        case .automation: "Automation"
        case .chats: "Chats"
        }
    }

    var systemImage: String {
        switch self {
        case .kanban: "rectangle.split.3x1"
        case .workspaces: "square.grid.2x2"
        case .automation: "gearshape.2"
        case .chats: "bubble.left.and.bubble.right"
        }
    }
}

enum WorkspaceBottomPanelKind: String, CaseIterable, Identifiable {
    case review
    case terminal
    case browser
    case files

    var id: Self { self }

    var title: String {
        switch self {
        case .review: "Review"
        case .terminal: "Terminal"
        case .browser: "Browser"
        case .files: "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .review: "rectangle.and.pencil.and.ellipsis"
        case .terminal: "terminal"
        case .browser: "globe"
        case .files: "folder"
        }
    }
}

@Observable
@MainActor
final class WorkspaceTerminalState {
    var isPresented: Bool
    var height: CGFloat
    var selectedPanel: WorkspaceBottomPanelKind
    var workingDirectory: URL?
    var sessionID: UUID

    init(
        isPresented: Bool = false,
        height: CGFloat = 320,
        selectedPanel: WorkspaceBottomPanelKind = .terminal,
        workingDirectory: URL? = nil,
        sessionID: UUID = UUID()
    ) {
        self.isPresented = isPresented
        self.height = height
        self.selectedPanel = selectedPanel
        self.workingDirectory = workingDirectory
        self.sessionID = sessionID
    }
}

@MainActor
final class WorkspaceTabState {
    let contentState: WorkspaceTabContentState
    let terminalState: WorkspaceTerminalState
    var content: AnyView?

    init(
        contentState: WorkspaceTabContentState,
        terminalState: WorkspaceTerminalState? = nil,
        content: AnyView? = nil
    ) {
        self.contentState = contentState
        self.terminalState = terminalState ?? WorkspaceTerminalState()
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
@Observable
final class ProjectKanbanTabState {
    let viewModel: ProjectKanbanViewModel
    let workspaceViewModel: CanvasWorkspaceViewModel
    let automationViewModel: ProjectAutomationViewModel
    let chatViewModel: ChatScreenViewModel
    var selectedSection: ProjectModeSection

    init(
        viewModel: ProjectKanbanViewModel,
        workspaceViewModel: CanvasWorkspaceViewModel,
        automationViewModel: ProjectAutomationViewModel,
        chatViewModel: ChatScreenViewModel,
        selectedSection: ProjectModeSection
    ) {
        self.viewModel = viewModel
        self.workspaceViewModel = workspaceViewModel
        self.automationViewModel = automationViewModel
        self.chatViewModel = chatViewModel
        self.selectedSection = selectedSection
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
