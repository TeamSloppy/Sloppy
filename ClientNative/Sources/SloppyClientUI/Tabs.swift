//
//  Tabs.swift
//  SloppyClient
//
//  Created by Vladislav Prusakov on 07.07.2026.
//

import Foundation

public enum WorkspaceTabKind: String, Hashable {
    case chat
    case projectKanban
    case taskDetail
    case workspaceFiles
}

public enum WorkspaceTabKey: Hashable {
    case chatSession(String)
    case chatTask(projectId: String, taskId: String)
    case projectKanban(String)
    case taskDetail(projectId: String, taskId: String)
    case workspaceFiles(String)
}

extension WorkspaceTabKey: Identifiable {
    public var id: String {
        switch self {
        case .chatSession(let string):
            string
        case .chatTask(let projectId, let taskId):
            projectId
        case .projectKanban(let string):
            string
        case .taskDetail(let projectId, let taskId):
            projectId
        case .workspaceFiles(let string):
            string
        }
    }
}

public struct ProjectKanbanTabContext: Hashable, Sendable {
    public var projectId: String
    public var projectName: String
    public var projectRootPath: String?

    public init(projectId: String, projectName: String, projectRootPath: String? = nil) {
        self.projectId = projectId
        self.projectName = projectName
        self.projectRootPath = projectRootPath
    }
}

public struct WorkspaceFilesTabContext: Hashable, Sendable {
    public var projectId: String
    public var projectName: String
    public var projectRootPath: String?

    public init(projectId: String, projectName: String, projectRootPath: String? = nil) {
        self.projectId = projectId
        self.projectName = projectName
        self.projectRootPath = projectRootPath
    }
}

public struct TaskDetailTabContext: Hashable, Sendable {
    public var projectId: String
    public var projectName: String
    public var projectRootPath: String?
    public var taskId: String
    public var taskTitle: String
    public var fallbackAgentId: String?

    public init(projectId: String, projectName: String, projectRootPath: String? = nil, taskId: String, taskTitle: String, fallbackAgentId: String? = nil) {
        self.projectId = projectId
        self.projectName = projectName
        self.projectRootPath = projectRootPath
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.fallbackAgentId = fallbackAgentId
    }
}

public enum WorkspaceTabPayload: Hashable {
    case chatSession(sessionID: String, title: String)
    case chatTask(projectId: String, projectName: String, projectRootPath: String?, taskId: String, taskTitle: String, fallbackAgentId: String?)
    case projectKanban(ProjectKanbanTabContext)
    case taskDetail(TaskDetailTabContext)
    case workspaceFiles(WorkspaceFilesTabContext)
}

public struct WorkspaceTab: Identifiable, Hashable {
    public let id: UUID
    public let key: WorkspaceTabKey
    public let kind: WorkspaceTabKind
    public var title: String
    public var payload: WorkspaceTabPayload

    public init(
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
