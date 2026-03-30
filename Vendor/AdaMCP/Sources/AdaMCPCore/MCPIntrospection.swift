import AdaEngine
import Foundation
import MCP

public enum MCPTypeKind: String, Codable, Sendable {
    case component
    case resource
    case asset
    case entityView = "entity_view"
}

public enum MCPSerializationStrategy: String, Codable, Sendable {
    case codable
    case custom
    case descriptorOnly = "descriptor_only"
}

public struct MCPFieldDescriptor: Hashable, Codable, Sendable {
    public let name: String
    public let typeName: String
    public let isOptional: Bool
    public let isEditorExposed: Bool

    public init(
        name: String,
        typeName: String,
        isOptional: Bool = false,
        isEditorExposed: Bool = false
    ) {
        self.name = name
        self.typeName = typeName
        self.isOptional = isOptional
        self.isEditorExposed = isEditorExposed
    }
}

public struct MCPTypeDescriptor: Hashable, Codable, Sendable {
    public let name: String
    public let kind: MCPTypeKind
    public let fields: [MCPFieldDescriptor]
    public let serialization: MCPSerializationStrategy

    public init(
        name: String,
        kind: MCPTypeKind,
        fields: [MCPFieldDescriptor] = [],
        serialization: MCPSerializationStrategy = .custom
    ) {
        self.name = name
        self.kind = kind
        self.fields = fields
        self.serialization = serialization
    }
}

public protocol MCPInspectable {
    static var mcpTypeDescriptor: MCPTypeDescriptor { get }
    func mcpSerializedValue() throws -> Value
}

public extension MCPInspectable where Self: Codable {
    func mcpSerializedValue() throws -> Value {
        try Value(self)
    }
}

@MainActor
public final class MCPIntrospectionRegistry {
    private struct Entry {
        let descriptor: MCPTypeDescriptor
        let serializer: (@Sendable (Any) throws -> Value)?
    }

    private var entriesByName: [String: Entry] = [:]
    private var namesByType: [ObjectIdentifier: String] = [:]

    public init() {}

    public func registerDescriptor(_ descriptor: MCPTypeDescriptor) {
        entriesByName[descriptor.name] = Entry(descriptor: descriptor, serializer: nil)
    }

    public func register<T>(
        _ type: T.Type,
        descriptor: MCPTypeDescriptor,
        serializer: @escaping @Sendable (T) throws -> Value
    ) {
        entriesByName[descriptor.name] = Entry(
            descriptor: descriptor,
            serializer: { anyValue in
                guard let typedValue = anyValue as? T else {
                    throw AdaMCPError.typeMismatch(expected: String(reflecting: T.self))
                }
                return try serializer(typedValue)
            }
        )
        namesByType[ObjectIdentifier(type)] = descriptor.name
    }

    public func register<T: MCPInspectable>(_ type: T.Type) {
        self.register(type, descriptor: T.mcpTypeDescriptor) { value in
            try value.mcpSerializedValue()
        }
    }

    public func registerCodable<T: Codable>(
        _ type: T.Type,
        kind: MCPTypeKind,
        fields: [MCPFieldDescriptor] = []
    ) {
        self.register(
            type,
            descriptor: MCPTypeDescriptor(
                name: String(reflecting: type),
                kind: kind,
                fields: fields,
                serialization: .codable
            )
        ) { value in
            try Value(value)
        }
    }

    public func descriptor(named name: String) -> MCPTypeDescriptor? {
        entriesByName[name]?.descriptor
    }

    public func descriptor(for value: Any) -> MCPTypeDescriptor? {
        let typeID = ObjectIdentifier(type(of: value) as Any.Type)
        guard let name = namesByType[typeID] else {
            return nil
        }
        return entriesByName[name]?.descriptor
    }

    public func serialize(_ value: Any) throws -> Value? {
        let typeID = ObjectIdentifier(type(of: value) as Any.Type)
        guard let name = namesByType[typeID],
              let entry = entriesByName[name] else {
            return nil
        }
        return try entry.serializer?(value)
    }

    public func descriptors(kind: MCPTypeKind? = nil) -> [MCPTypeDescriptor] {
        entriesByName.values
            .map(\.descriptor)
            .filter { descriptor in
                guard let kind else {
                    return true
                }
                return descriptor.kind == kind
            }
            .sorted { $0.name < $1.name }
    }
}

public enum AdaMCPError: LocalizedError {
    case invalidArguments(String)
    case worldNotFound(String)
    case entityNotFound(world: String, entityID: Int)
    case resourceNotFound(String)
    case assetNotFound(String)
    case notInspectable(String)
    case invalidResourceURI(String)
    case screenshotUnavailable(String)
    case typeMismatch(expected: String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .worldNotFound(let world):
            return "World '\(world)' was not found."
        case .entityNotFound(let world, let entityID):
            return "Entity \(entityID) was not found in world '\(world)'."
        case .resourceNotFound(let resource):
            return "Resource '\(resource)' was not found."
        case .assetNotFound(let query):
            return "Asset not found for query '\(query)'."
        case .notInspectable(let typeName):
            return "Type '\(typeName)' is not inspectable through MCP."
        case .invalidResourceURI(let uri):
            return "Unsupported MCP resource URI '\(uri)'."
        case .screenshotUnavailable(let reason):
            return reason
        case .typeMismatch(let expected):
            return "Failed to serialize value as expected type '\(expected)'."
        }
    }
}
