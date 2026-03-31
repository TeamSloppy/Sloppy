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
    case entityNamedNotFound(world: String, entityName: String)
    case componentNotFound(world: String, entityID: Int, componentType: String)
    case resourceNotFound(String)
    case assetNotFound(String)
    case notInspectable(String)
    case invalidResourceURI(String)
    case screenshotUnavailable(String)
    case typeMismatch(expected: String)
    case uiUnavailable
    case uiWindowNotFound(Int)
    case uiNodeNotFound(String)
    case uiNodeAmbiguous(selector: String, candidates: [UINodeSummary])
    case uiScrollContainerNotFound(String)
    case uiNoFocusableNode(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .worldNotFound(let world):
            return "World '\(world)' was not found."
        case .entityNotFound(let world, let entityID):
            return "Entity \(entityID) was not found in world '\(world)'."
        case .entityNamedNotFound(let world, let entityName):
            return "Entity named '\(entityName)' was not found in world '\(world)'."
        case .componentNotFound(let world, let entityID, let componentType):
            return "Component '\(componentType)' was not found on entity \(entityID) in world '\(world)'."
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
        case .uiUnavailable:
            return "AdaUI is unavailable in the current runtime."
        case .uiWindowNotFound(let windowID):
            return "UI window \(windowID) was not found."
        case .uiNodeNotFound(let selector):
            return "UI node was not found for selector '\(selector)'."
        case .uiNodeAmbiguous(let selector, _):
            return "UI selector '\(selector)' matched multiple nodes."
        case .uiScrollContainerNotFound(let selector):
            return "No scroll container ancestor was found for selector '\(selector)'."
        case .uiNoFocusableNode(let selector):
            return "No focusable node was found for selector '\(selector)'."
        }
    }
}

public struct AdaMCPErrorPayload: Codable, Sendable {
    public let code: String
    public let message: String
    public let details: Value?
}

public extension AdaMCPError {
    var payload: AdaMCPErrorPayload {
        switch self {
        case .invalidArguments(let message):
            return .init(code: "invalid_arguments", message: message, details: nil)
        case .worldNotFound(let world):
            return .init(
                code: "world_not_found",
                message: self.errorDescription ?? "",
                details: ["world": .string(world)]
            )
        case .entityNotFound(let world, let entityID):
            return .init(
                code: "entity_not_found",
                message: self.errorDescription ?? "",
                details: ["world": .string(world), "entityId": .int(entityID)]
            )
        case .entityNamedNotFound(let world, let entityName):
            return .init(
                code: "entity_named_not_found",
                message: self.errorDescription ?? "",
                details: ["world": .string(world), "entityName": .string(entityName)]
            )
        case .componentNotFound(let world, let entityID, let componentType):
            return .init(
                code: "component_not_found",
                message: self.errorDescription ?? "",
                details: [
                    "world": .string(world),
                    "entityId": .int(entityID),
                    "componentType": .string(componentType)
                ]
            )
        case .resourceNotFound(let resource):
            return .init(
                code: "resource_not_found",
                message: self.errorDescription ?? "",
                details: ["resourceType": .string(resource)]
            )
        case .assetNotFound(let query):
            return .init(
                code: "asset_not_found",
                message: self.errorDescription ?? "",
                details: ["query": .string(query)]
            )
        case .notInspectable(let typeName):
            return .init(
                code: "not_inspectable",
                message: self.errorDescription ?? "",
                details: ["type": .string(typeName)]
            )
        case .invalidResourceURI(let uri):
            return .init(
                code: "invalid_resource_uri",
                message: self.errorDescription ?? "",
                details: ["uri": .string(uri)]
            )
        case .screenshotUnavailable(let reason):
            return .init(
                code: "screenshot_unavailable",
                message: reason,
                details: nil
            )
        case .typeMismatch(let expected):
            return .init(
                code: "type_mismatch",
                message: self.errorDescription ?? "",
                details: ["expected": .string(expected)]
            )
        case .uiUnavailable:
            return .init(code: "ui_unavailable", message: self.errorDescription ?? "", details: nil)
        case .uiWindowNotFound(let windowID):
            return .init(
                code: "ui_window_not_found",
                message: self.errorDescription ?? "",
                details: ["windowId": .int(windowID)]
            )
        case .uiNodeNotFound(let selector):
            return .init(
                code: "ui_node_not_found",
                message: self.errorDescription ?? "",
                details: ["selector": .string(selector)]
            )
        case .uiNodeAmbiguous(let selector, let candidates):
            return .init(
                code: "ui_node_ambiguous",
                message: self.errorDescription ?? "",
                details: [
                    "selector": .string(selector),
                    "candidates": (try? Value(candidates)) ?? .array([])
                ]
            )
        case .uiScrollContainerNotFound(let selector):
            return .init(
                code: "ui_scroll_container_not_found",
                message: self.errorDescription ?? "",
                details: ["selector": .string(selector)]
            )
        case .uiNoFocusableNode(let selector):
            return .init(
                code: "ui_no_focusable_node",
                message: self.errorDescription ?? "",
                details: ["selector": .string(selector)]
            )
        }
    }
}
