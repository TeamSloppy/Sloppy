import Foundation

public struct CanvasWorkspaceSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var description: String
    public var cover: String?
    public var ownerId: String
    public var projectId: String?
    public var revision: Int
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        description: String = "",
        cover: String? = nil,
        ownerId: String,
        projectId: String? = nil,
        revision: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.cover = cover
        self.ownerId = ownerId
        self.projectId = projectId
        self.revision = revision
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CanvasWorkspaceCreateRequest: Codable, Sendable, Equatable {
    public var title: String
    public var description: String?
    public var projectId: String?
    public var templateId: String?

    public init(
        title: String,
        description: String? = nil,
        projectId: String? = nil,
        templateId: String? = nil
    ) {
        self.title = title
        self.description = description
        self.projectId = projectId
        self.templateId = templateId
    }
}

struct CanvasWorkspaceListResponse: Decodable, Sendable {
    var workspaces: [CanvasWorkspaceSummary]
}
