import Foundation
import Protocols

public struct TaskSyncProjectDescriptor: Codable, Sendable, Equatable {
    public var providerId: String
    public var projectURL: String
    public var title: String?
    public var projectNodeId: String?
    public var defaultRepo: String?
    public var statusOptions: [String]

    public init(
        providerId: String,
        projectURL: String,
        title: String? = nil,
        projectNodeId: String? = nil,
        defaultRepo: String? = nil,
        statusOptions: [String] = []
    ) {
        self.providerId = providerId
        self.projectURL = projectURL
        self.title = title
        self.projectNodeId = projectNodeId
        self.defaultRepo = defaultRepo
        self.statusOptions = statusOptions
    }
}

public struct TaskSyncExternalTask: Codable, Sendable, Equatable {
    public var title: String
    public var description: String
    public var status: String?
    public var metadata: TaskExternalMetadata
    public var tags: [String]
    public var priority: String?
    public var comments: [TaskSyncExternalComment]

    public init(
        title: String,
        description: String = "",
        status: String? = nil,
        metadata: TaskExternalMetadata,
        tags: [String] = [],
        priority: String? = nil,
        comments: [TaskSyncExternalComment] = []
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.metadata = metadata
        self.tags = tags
        self.priority = priority
        self.comments = comments
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, status, metadata, tags, priority, comments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status)
        metadata = try container.decode(TaskExternalMetadata.self, forKey: .metadata)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        comments = try container.decodeIfPresent([TaskSyncExternalComment].self, forKey: .comments) ?? []
    }
}

public struct TaskSyncExternalComment: Codable, Sendable, Equatable {
    public var body: String
    public var author: String
    public var metadata: TaskExternalMetadata
    public var createdAt: Date?
    public var version: Int?

    public init(
        body: String,
        author: String,
        metadata: TaskExternalMetadata,
        createdAt: Date? = nil,
        version: Int? = nil
    ) {
        self.body = body
        self.author = author
        self.metadata = metadata
        self.createdAt = createdAt
        self.version = version
    }
}

public protocol TaskSyncProvider: Sendable {
    var id: String { get }

    func parseProjectURL(_ rawURL: String) throws -> TaskSyncProjectDescriptor
    func resolveProject(
        url: String,
        token: String?,
        defaultRepo: String?
    ) async throws -> TaskSyncProjectDescriptor
    func importTasks(
        settings: ProjectTaskSyncSettings,
        token: String?
    ) async throws -> [TaskSyncExternalTask]
    func createOrUpdateTask(
        _ task: ProjectTask,
        settings: ProjectTaskSyncSettings,
        token: String?
    ) async throws -> TaskExternalMetadata
    func mirrorComment(
        _ comment: TaskComment,
        task: ProjectTask,
        settings: ProjectTaskSyncSettings,
        token: String?
    ) async throws -> TaskExternalMetadata
}
