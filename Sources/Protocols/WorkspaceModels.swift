import Foundation

public enum WorkspaceElementKind: String, Codable, Sendable, Equatable, CaseIterable {
    case sticky
    case text
    case shape
    case image
    case table
    case frame
    case widget
}

public struct WorkspaceRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct WorkspaceElement: Codable, Sendable, Equatable {
    public var id: String
    public var kind: WorkspaceElementKind
    public var bounds: WorkspaceRect
    public var rotation: Double
    public var zIndex: Int
    public var parentId: String?
    public var groupId: String?
    public var style: [String: JSONValue]
    public var data: [String: JSONValue]
    public var revision: Int

    public init(
        id: String,
        kind: WorkspaceElementKind,
        bounds: WorkspaceRect,
        rotation: Double = 0,
        zIndex: Int = 0,
        parentId: String? = nil,
        groupId: String? = nil,
        style: [String: JSONValue] = [:],
        data: [String: JSONValue] = [:],
        revision: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.bounds = bounds
        self.rotation = rotation
        self.zIndex = zIndex
        self.parentId = parentId
        self.groupId = groupId
        self.style = style
        self.data = data
        self.revision = revision
    }
}

public struct WorkspaceConnection: Codable, Sendable, Equatable {
    public var id: String
    public var sourceElementId: String
    public var targetElementId: String
    public var label: String?
    public var style: [String: JSONValue]
    public var revision: Int

    public init(
        id: String,
        sourceElementId: String,
        targetElementId: String,
        label: String? = nil,
        style: [String: JSONValue] = [:],
        revision: Int = 0
    ) {
        self.id = id
        self.sourceElementId = sourceElementId
        self.targetElementId = targetElementId
        self.label = label
        self.style = style
        self.revision = revision
    }
}

public struct WorkspaceDocument: Codable, Sendable, Equatable {
    public var workspaceId: String
    public var schemaVersion: Int
    public var revision: Int
    public var elements: [WorkspaceElement]
    public var connections: [WorkspaceConnection]

    public init(
        workspaceId: String,
        schemaVersion: Int = 1,
        revision: Int = 0,
        elements: [WorkspaceElement] = [],
        connections: [WorkspaceConnection] = []
    ) {
        self.workspaceId = workspaceId
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.elements = elements
        self.connections = connections
    }
}

public struct WorkspaceRecord: Codable, Sendable, Equatable {
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

public struct WorkspaceCreateRequest: Codable, Sendable, Equatable {
    public var title: String
    public var description: String?
    public var projectId: String?
    public var templateId: String?

    public init(title: String, description: String? = nil, projectId: String? = nil, templateId: String? = nil) {
        self.title = title
        self.description = description
        self.projectId = projectId
        self.templateId = templateId
    }
}

public struct WorkspaceUpdateRequest: Codable, Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var cover: String?
    public var projectId: String?
    public var clearProject: Bool?

    public init(
        title: String? = nil,
        description: String? = nil,
        cover: String? = nil,
        projectId: String? = nil,
        clearProject: Bool? = nil
    ) {
        self.title = title
        self.description = description
        self.cover = cover
        self.projectId = projectId
        self.clearProject = clearProject
    }
}

public enum WorkspacePrincipalKind: String, Codable, Sendable, Equatable {
    case user
    case agent
}

public enum WorkspaceMemberRole: String, Codable, Sendable, Equatable, CaseIterable {
    case owner
    case editor
    case viewer

    public var canEdit: Bool {
        self == .owner || self == .editor
    }
}

public struct WorkspaceMember: Codable, Sendable, Equatable {
    public var workspaceId: String
    public var principalKind: WorkspacePrincipalKind
    public var principalId: String
    public var role: WorkspaceMemberRole
    public var createdAt: Date

    public init(
        workspaceId: String,
        principalKind: WorkspacePrincipalKind,
        principalId: String,
        role: WorkspaceMemberRole,
        createdAt: Date = Date()
    ) {
        self.workspaceId = workspaceId
        self.principalKind = principalKind
        self.principalId = principalId
        self.role = role
        self.createdAt = createdAt
    }
}

public enum WorkspaceOperationKind: String, Codable, Sendable, Equatable {
    case createElement = "element.create"
    case updateElement = "element.update"
    case moveElement = "element.move"
    case resizeElement = "element.resize"
    case groupElement = "element.group"
    case ungroupElement = "element.ungroup"
    case assignFrame = "element.frame_assign"
    case reorderElement = "element.z_order"
    case deleteElement = "element.delete"
    case createConnection = "connection.create"
    case connect = "element.connect"
    case updateConnection = "connection.update"
    case deleteConnection = "connection.delete"
    case disconnect = "element.disconnect"
}

public struct WorkspaceOperation: Codable, Sendable, Equatable {
    public var kind: WorkspaceOperationKind
    public var element: WorkspaceElement?
    public var connection: WorkspaceConnection?
    public var targetId: String?

    public init(
        kind: WorkspaceOperationKind,
        element: WorkspaceElement? = nil,
        connection: WorkspaceConnection? = nil,
        targetId: String? = nil
    ) {
        self.kind = kind
        self.element = element
        self.connection = connection
        self.targetId = targetId
    }
}

public enum WorkspaceActorKind: String, Codable, Sendable, Equatable {
    case user
    case agent
    case system
}

public struct WorkspaceActor: Codable, Sendable, Equatable {
    public var kind: WorkspaceActorKind
    public var id: String
    public var displayName: String?

    public init(kind: WorkspaceActorKind, id: String, displayName: String? = nil) {
        self.kind = kind
        self.id = id
        self.displayName = displayName
    }
}

public struct WorkspaceTransactionRequest: Codable, Sendable, Equatable {
    public var id: String
    public var baseRevision: Int
    public var expectedElementRevisions: [String: Int]
    public var operations: [WorkspaceOperation]
    public var summary: String?

    public init(
        id: String,
        baseRevision: Int,
        expectedElementRevisions: [String: Int] = [:],
        operations: [WorkspaceOperation],
        summary: String? = nil
    ) {
        self.id = id
        self.baseRevision = baseRevision
        self.expectedElementRevisions = expectedElementRevisions
        self.operations = operations
        self.summary = summary
    }
}

public struct WorkspaceCommittedTransaction: Codable, Sendable, Equatable {
    public var id: String
    public var workspaceId: String
    public var revision: Int
    public var actor: WorkspaceActor
    public var operations: [WorkspaceOperation]
    public var inverseOperations: [WorkspaceOperation]
    public var summary: String?
    public var createdAt: Date

    public init(
        id: String,
        workspaceId: String,
        revision: Int,
        actor: WorkspaceActor,
        operations: [WorkspaceOperation],
        inverseOperations: [WorkspaceOperation],
        summary: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.revision = revision
        self.actor = actor
        self.operations = operations
        self.inverseOperations = inverseOperations
        self.summary = summary
        self.createdAt = createdAt
    }
}

public enum WorkspaceTemplateVisibility: String, Codable, Sendable, Equatable {
    case builtin
    case personal
    case team
}

public struct WorkspaceTemplate: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var description: String
    public var category: String
    public var visibility: WorkspaceTemplateVisibility
    public var ownerId: String?
    public var document: WorkspaceDocument
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        description: String,
        category: String,
        visibility: WorkspaceTemplateVisibility,
        ownerId: String? = nil,
        document: WorkspaceDocument,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.visibility = visibility
        self.ownerId = ownerId
        self.document = document
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WorkspaceTemplateCreateRequest: Codable, Sendable, Equatable {
    public var title: String
    public var description: String
    public var category: String
    public var visibility: WorkspaceTemplateVisibility
    public var document: WorkspaceDocument

    public init(
        title: String,
        description: String = "",
        category: String = "custom",
        visibility: WorkspaceTemplateVisibility = .personal,
        document: WorkspaceDocument
    ) {
        self.title = title
        self.description = description
        self.category = category
        self.visibility = visibility
        self.document = document
    }
}

public struct WorkspacePresence: Codable, Sendable, Equatable {
    public var actor: WorkspaceActor
    public var cursorX: Double?
    public var cursorY: Double?
    public var selectedElementIds: [String]
    public var status: String?

    public init(
        actor: WorkspaceActor,
        cursorX: Double? = nil,
        cursorY: Double? = nil,
        selectedElementIds: [String] = [],
        status: String? = nil
    ) {
        self.actor = actor
        self.cursorX = cursorX
        self.cursorY = cursorY
        self.selectedElementIds = selectedElementIds
        self.status = status
    }
}

public enum WorkspaceRealtimeMessageKind: String, Codable, Sendable, Equatable {
    case ready
    case transaction
    case transactionCommitted = "transaction_committed"
    case transactionRejected = "transaction_rejected"
    case presence
    case agentStatus = "agent_status"
    case ping
    case pong
}

public struct WorkspaceRealtimeMessage: Codable, Sendable, Equatable {
    public var kind: WorkspaceRealtimeMessageKind
    public var document: WorkspaceDocument?
    public var transactions: [WorkspaceCommittedTransaction]?
    public var transactionRequest: WorkspaceTransactionRequest?
    public var transaction: WorkspaceCommittedTransaction?
    public var presence: WorkspacePresence?
    public var latestRevision: Int?
    public var conflictElementIds: [String]?
    public var message: String?

    public init(
        kind: WorkspaceRealtimeMessageKind,
        document: WorkspaceDocument? = nil,
        transactions: [WorkspaceCommittedTransaction]? = nil,
        transactionRequest: WorkspaceTransactionRequest? = nil,
        transaction: WorkspaceCommittedTransaction? = nil,
        presence: WorkspacePresence? = nil,
        latestRevision: Int? = nil,
        conflictElementIds: [String]? = nil,
        message: String? = nil
    ) {
        self.kind = kind
        self.document = document
        self.transactions = transactions
        self.transactionRequest = transactionRequest
        self.transaction = transaction
        self.presence = presence
        self.latestRevision = latestRevision
        self.conflictElementIds = conflictElementIds
        self.message = message
    }
}

public struct WorkspaceRealtimeTicketResponse: Codable, Sendable, Equatable {
    public var ticket: String
    public var expiresAt: Date

    public init(ticket: String, expiresAt: Date) {
        self.ticket = ticket
        self.expiresAt = expiresAt
    }
}
