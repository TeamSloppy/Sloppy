import Foundation

public enum SourceControlChangeKind: String, Codable, Sendable, Hashable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case untracked
    case ignored
    case conflicted
    case typeChanged = "type_changed"
    case unknown
}

public struct SourceControlFileChange: Codable, Sendable, Equatable {
    public var path: String
    public var oldPath: String?
    public var kind: SourceControlChangeKind
    public var staged: Bool
    public var unstaged: Bool
    public var linesAdded: Int
    public var linesDeleted: Int

    public init(
        path: String,
        oldPath: String? = nil,
        kind: SourceControlChangeKind = .unknown,
        staged: Bool = false,
        unstaged: Bool = false,
        linesAdded: Int = 0,
        linesDeleted: Int = 0
    ) {
        self.path = path
        self.oldPath = oldPath
        self.kind = kind
        self.staged = staged
        self.unstaged = unstaged
        self.linesAdded = linesAdded
        self.linesDeleted = linesDeleted
    }
}

public struct SourceControlRepositoryInfo: Codable, Sendable, Equatable {
    public var providerId: String
    public var isRepository: Bool
    public var rootPath: String?
    public var branch: String?
    public var head: String?
    public var message: String?

    public init(
        providerId: String,
        isRepository: Bool,
        rootPath: String? = nil,
        branch: String? = nil,
        head: String? = nil,
        message: String? = nil
    ) {
        self.providerId = providerId
        self.isRepository = isRepository
        self.rootPath = rootPath
        self.branch = branch
        self.head = head
        self.message = message
    }
}

public struct SourceControlWorkingTreeStatus: Codable, Sendable, Equatable {
    public var repository: SourceControlRepositoryInfo
    public var files: [SourceControlFileChange]
    public var linesAdded: Int
    public var linesDeleted: Int

    public var hasChanges: Bool {
        !files.isEmpty || linesAdded > 0 || linesDeleted > 0
    }

    public init(
        repository: SourceControlRepositoryInfo,
        files: [SourceControlFileChange] = [],
        linesAdded: Int = 0,
        linesDeleted: Int = 0
    ) {
        self.repository = repository
        self.files = files
        self.linesAdded = linesAdded
        self.linesDeleted = linesDeleted
    }
}

public struct SourceControlDiffResult: Codable, Sendable, Equatable {
    public var providerId: String
    public var baseRef: String?
    public var headRef: String?
    public var text: String
    public var truncated: Bool
    public var files: [SourceControlFileChange]

    public var hasChanges: Bool {
        !text.isEmpty || !files.isEmpty
    }

    public init(
        providerId: String,
        baseRef: String? = nil,
        headRef: String? = nil,
        text: String = "",
        truncated: Bool = false,
        files: [SourceControlFileChange] = []
    ) {
        self.providerId = providerId
        self.baseRef = baseRef
        self.headRef = headRef
        self.text = text
        self.truncated = truncated
        self.files = files
    }
}

public struct SourceControlWorktreeResult: Codable, Sendable, Equatable {
    public var worktreePath: String
    public var branchName: String

    public init(worktreePath: String, branchName: String) {
        self.worktreePath = worktreePath
        self.branchName = branchName
    }
}

public struct SourceControlProviderRecord: Codable, Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var capabilities: [String]

    public init(id: String, displayName: String, capabilities: [String] = []) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
    }
}
