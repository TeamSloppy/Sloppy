import Foundation

public enum ProjectWorkingTreeChangeKind: String, Codable, Sendable, Equatable {
    case created
    case modified
    case deleted
}

public struct ProjectWorkingTreeChange: Codable, Sendable, Equatable {
    public var path: String
    public var kind: ProjectWorkingTreeChangeKind
    public var sizeBytes: Int?
    public var modifiedAt: Date?

    public init(
        path: String,
        kind: ProjectWorkingTreeChangeKind,
        sizeBytes: Int? = nil,
        modifiedAt: Date? = nil
    ) {
        self.path = path
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }
}

public struct ProjectWorkingTreeChangeBatch: Codable, Sendable, Equatable {
    public var projectId: String
    public var rootPath: String
    public var changes: [ProjectWorkingTreeChange]
    public var createdAt: Date

    public init(
        projectId: String,
        rootPath: String,
        changes: [ProjectWorkingTreeChange],
        createdAt: Date = Date()
    ) {
        self.projectId = projectId
        self.rootPath = rootPath
        self.changes = changes
        self.createdAt = createdAt
    }
}

public struct WorkspaceGitSyncStatus: Codable, Sendable, Equatable {
    public var lastAttemptAt: String?
    public var lastSuccessAt: String?
    public var lastFailureAt: String?
    public var lastError: String?
    public var lastCommit: String?
    public var lastFilesChanged: Int
    public var failedAttempts: Int

    public init(
        lastAttemptAt: String? = nil,
        lastSuccessAt: String? = nil,
        lastFailureAt: String? = nil,
        lastError: String? = nil,
        lastCommit: String? = nil,
        lastFilesChanged: Int = 0,
        failedAttempts: Int = 0
    ) {
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.lastFailureAt = lastFailureAt
        self.lastError = lastError
        self.lastCommit = lastCommit
        self.lastFilesChanged = lastFilesChanged
        self.failedAttempts = failedAttempts
    }
}

public struct WorkspaceGitSyncResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String
    public var branch: String
    public var commit: String?
    public var filesChanged: Int
    public var status: WorkspaceGitSyncStatus?

    public init(
        ok: Bool,
        message: String,
        branch: String,
        commit: String? = nil,
        filesChanged: Int = 0,
        status: WorkspaceGitSyncStatus? = nil
    ) {
        self.ok = ok
        self.message = message
        self.branch = branch
        self.commit = commit
        self.filesChanged = filesChanged
        self.status = status
    }
}

public struct ProjectFileEntry: Codable, Sendable {
    public enum EntryType: String, Codable, Sendable {
        case file
        case directory
    }

    public var name: String
    public var path: String?
    public var type: EntryType
    public var size: Int?

    public init(name: String, path: String? = nil, type: EntryType, size: Int? = nil) {
        self.name = name
        self.path = path
        self.type = type
        self.size = size
    }
}

/// A file or directory path under the project workspace (used by `/files/search`).
public struct ProjectFileSearchEntry: Codable, Sendable {
    public var path: String
    public var type: ProjectFileEntry.EntryType

    public init(path: String, type: ProjectFileEntry.EntryType) {
        self.path = path
        self.type = type
    }
}

public struct ProjectFileContentResponse: Codable, Sendable {
    public var path: String
    public var content: String
    public var sizeBytes: Int

    public init(path: String, content: String, sizeBytes: Int) {
        self.path = path
        self.content = content
        self.sizeBytes = sizeBytes
    }
}

public struct TaskDiffResponse: Codable, Sendable {
    public var diff: String
    public var branchName: String
    public var baseBranch: String
    public var hasChanges: Bool

    public init(diff: String, branchName: String, baseBranch: String, hasChanges: Bool) {
        self.diff = diff
        self.branchName = branchName
        self.baseBranch = baseBranch
        self.hasChanges = hasChanges
    }
}

/// Working-tree diff from the configured source-control provider.
public struct ProjectWorkingTreeSourceControlResponse: Codable, Sendable {
    public var providerId: String
    public var isRepository: Bool
    public var branch: String?
    public var linesAdded: Int
    public var linesDeleted: Int
    public var diff: String
    public var diffTruncated: Bool
    /// Set when the folder is not a repository or source control could not be read.
    public var message: String?

    public init(
        providerId: String,
        isRepository: Bool,
        branch: String? = nil,
        linesAdded: Int = 0,
        linesDeleted: Int = 0,
        diff: String = "",
        diffTruncated: Bool = false,
        message: String? = nil
    ) {
        self.providerId = providerId
        self.isRepository = isRepository
        self.branch = branch
        self.linesAdded = linesAdded
        self.linesDeleted = linesDeleted
        self.diff = diff
        self.diffTruncated = diffTruncated
        self.message = message
    }
}

public struct ProjectSourceControlRestoreRequest: Codable, Sendable {
    /// Project-relative path (POSIX, no `..` segments).
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

public struct ProjectSourceControlRestoreResponse: Codable, Sendable {
    public var ok: Bool

    public init(ok: Bool = true) {
        self.ok = ok
    }
}

public struct ProjectSourceControlCreateWorktreeRequest: Codable, Sendable {
    public var taskId: String

    public init(taskId: String) {
        self.taskId = taskId
    }
}

public struct ProjectSourceControlCreateWorktreeResponse: Codable, Sendable {
    public var worktree: SourceControlWorktreeResult

    public init(worktree: SourceControlWorktreeResult) {
        self.worktree = worktree
    }
}
