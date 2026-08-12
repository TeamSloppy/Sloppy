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

public enum CanvasJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([CanvasJSONValue])
    case object([String: CanvasJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([CanvasJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: CanvasJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

public enum CanvasWorkspaceElementKind: String, Codable, Sendable, Equatable, CaseIterable {
    case sticky, text, shape, image, table, frame, widget
}

public struct CanvasWorkspaceRect: Codable, Sendable, Equatable {
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

public struct CanvasWorkspaceElement: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: CanvasWorkspaceElementKind
    public var bounds: CanvasWorkspaceRect
    public var rotation: Double
    public var zIndex: Int
    public var parentId: String?
    public var groupId: String?
    public var style: [String: CanvasJSONValue]
    public var data: [String: CanvasJSONValue]
    public var revision: Int

    public init(
        id: String,
        kind: CanvasWorkspaceElementKind,
        bounds: CanvasWorkspaceRect,
        rotation: Double = 0,
        zIndex: Int = 0,
        parentId: String? = nil,
        groupId: String? = nil,
        style: [String: CanvasJSONValue] = [:],
        data: [String: CanvasJSONValue] = [:],
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

    public var title: String {
        data["text"]?.stringValue ?? data["title"]?.stringValue ?? kind.rawValue.capitalized
    }
}

public struct CanvasWorkspaceConnection: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceElementId: String
    public var targetElementId: String
    public var label: String?
    public var style: [String: CanvasJSONValue]
    public var revision: Int
}

public struct CanvasWorkspaceDocument: Codable, Sendable, Equatable {
    public var workspaceId: String
    public var schemaVersion: Int
    public var revision: Int
    public var elements: [CanvasWorkspaceElement]
    public var connections: [CanvasWorkspaceConnection]
}

public enum CanvasWorkspaceOperationKind: String, Codable, Sendable, Equatable {
    case createElement = "element.create"
    case updateElement = "element.update"
    case deleteElement = "element.delete"
}

public struct CanvasWorkspaceOperation: Codable, Sendable, Equatable {
    public var kind: CanvasWorkspaceOperationKind
    public var element: CanvasWorkspaceElement?
    public var targetId: String?

    public init(kind: CanvasWorkspaceOperationKind, element: CanvasWorkspaceElement? = nil, targetId: String? = nil) {
        self.kind = kind
        self.element = element
        self.targetId = targetId
    }
}

public struct CanvasWorkspaceTransactionRequest: Codable, Sendable, Equatable {
    public var id: String
    public var baseRevision: Int
    public var expectedElementRevisions: [String: Int]
    public var operations: [CanvasWorkspaceOperation]
    public var summary: String?

    public init(
        id: String,
        baseRevision: Int,
        expectedElementRevisions: [String: Int] = [:],
        operations: [CanvasWorkspaceOperation],
        summary: String? = nil
    ) {
        self.id = id
        self.baseRevision = baseRevision
        self.expectedElementRevisions = expectedElementRevisions
        self.operations = operations
        self.summary = summary
    }
}

public struct CanvasWorkspaceCommittedTransaction: Codable, Sendable, Equatable {
    public var id: String
    public var workspaceId: String
    public var revision: Int
    public var operations: [CanvasWorkspaceOperation]
}

struct CanvasWorkspaceDocumentResponse: Decodable, Sendable {
    var document: CanvasWorkspaceDocument
}

public struct CanvasWidgetArtifact: Decodable, Sendable, Equatable {
    public var id: String?
    public var html: String
    public var width: Double?
    public var height: Double?
}
