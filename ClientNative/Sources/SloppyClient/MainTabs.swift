import Foundation
import SloppyClientCore
import SloppyFeatureChat
import SloppyFeatureProjects

enum WorkspaceTabKind: String, Hashable {
    case chat
    case projectKanban
    case workspaceFiles
}

enum WorkspaceTabKey: Hashable {
    case chatSession(String)
    case chatTask(projectId: String, taskId: String)
    case projectKanban(String)
    case workspaceFiles(String)
}

struct ProjectKanbanTabContext: Hashable, Sendable {
    var projectId: String
    var projectName: String
}

struct WorkspaceFilesTabContext: Hashable, Sendable {
    var projectId: String
    var projectName: String
}

enum WorkspaceTabPayload: Hashable {
    case chatSession(sessionID: String, title: String)
    case chatTask(projectId: String, projectName: String, taskId: String, taskTitle: String, fallbackAgentId: String?)
    case projectKanban(ProjectKanbanTabContext)
    case workspaceFiles(WorkspaceFilesTabContext)
}

struct WorkspaceTab: Identifiable, Hashable {
    let id: UUID
    let key: WorkspaceTabKey
    let kind: WorkspaceTabKind
    var title: String
    var payload: WorkspaceTabPayload

    init(
        id: UUID = UUID(),
        key: WorkspaceTabKey,
        kind: WorkspaceTabKind,
        title: String,
        payload: WorkspaceTabPayload
    ) {
        self.id = id
        self.key = key
        self.kind = kind
        self.title = title
        self.payload = payload
    }
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
