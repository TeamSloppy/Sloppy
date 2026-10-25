import Foundation

public enum WorkflowEnvironmentMode: String, Codable, Sendable, CaseIterable {
    case project
    case taskWorktree = "task_worktree"
    case existingWorktree = "existing_worktree"
    case newWorktree = "new_worktree"
}

public struct WorkflowEnvironmentRequest: Codable, Sendable, Equatable {
    public var mode: WorkflowEnvironmentMode
    public var path: String?
    public var baseRef: String?
    public var setupCommand: String?

    public init(mode: WorkflowEnvironmentMode = .project, path: String? = nil, baseRef: String? = nil, setupCommand: String? = nil) {
        self.mode = mode
        self.path = path
        self.baseRef = baseRef
        self.setupCommand = setupCommand
    }
}

public struct WorkflowEnvironmentBinding: Codable, Sendable, Equatable {
    public enum Preparation: String, Codable, Sendable { case pending, creating, setup, ready, blocked, failed }
    public var request: WorkflowEnvironmentRequest
    public var projectRoot: String
    public var workingDirectory: String
    public var providerId: String
    public var baseRevision: String?
    public var branch: String?
    public var preparation: Preparation
    public var error: String?

    public init(request: WorkflowEnvironmentRequest, projectRoot: String, workingDirectory: String, providerId: String,
                baseRevision: String? = nil, branch: String? = nil, preparation: Preparation = .pending) {
        self.request = request
        self.projectRoot = projectRoot
        self.workingDirectory = workingDirectory
        self.providerId = providerId
        self.baseRevision = baseRevision
        self.branch = branch
        self.preparation = preparation
    }
}
