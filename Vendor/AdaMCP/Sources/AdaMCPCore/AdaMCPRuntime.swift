import AdaEngine
import Foundation
import Logging
import MCP

@MainActor
public struct MCPServerConfiguration: Sendable {
    public var host: String
    public var port: Int
    public var endpoint: String
    public var serverName: String
    public var serverVersion: String
    public var instructions: String?
    public var registerTypes: (@MainActor (MCPIntrospectionRegistry) -> Void)?
    public var captureOverride: RenderCaptureService.CaptureOverride?

    public init(
        host: String = "127.0.0.1",
        port: Int = 0,
        endpoint: String = "/mcp",
        serverName: String = "adaengine-mcp",
        serverVersion: String = "0.1.0",
        instructions: String? = "Inspect live AdaEngine worlds, entities, resources, assets, and render captures.",
        registerTypes: (@MainActor (MCPIntrospectionRegistry) -> Void)? = nil,
        captureOverride: RenderCaptureService.CaptureOverride? = nil
    ) {
        self.host = host
        self.port = port
        self.endpoint = endpoint
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.instructions = instructions
        self.registerTypes = registerTypes
        self.captureOverride = captureOverride
    }
}

@MainActor
public final class AdaMCPRuntime {
    private let appWorlds: AppWorlds
    private let registry: MCPIntrospectionRegistry
    private let renderCaptureService: RenderCaptureService
    private let logger: Logger

    public init(
        appWorlds: AppWorlds,
        registry: MCPIntrospectionRegistry,
        renderCaptureService: RenderCaptureService,
        logger: Logger = Logger(label: "org.adaengine.mcp.runtime")
    ) {
        self.appWorlds = appWorlds
        self.registry = registry
        self.renderCaptureService = renderCaptureService
        self.logger = logger
    }

    public func tools() -> [Tool] {
        [
            Tool(
                name: "world.list_worlds",
                description: "List all live AdaEngine worlds.",
                inputSchema: Self.objectSchema(),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "world.get",
                description: "Get world summary and counts.",
                inputSchema: Self.objectSchema(properties: [
                    "world": .object(["type": "string", "description": "World name, defaults to Main"])
                ]),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "entity.get_by_id",
                description: "Get one entity by numeric identifier.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "world": .object(["type": "string"]),
                        "id": .object(["type": "integer"])
                    ],
                    required: ["id"]
                ),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "entity.get_by_name",
                description: "Get one entity by exact name.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "world": .object(["type": "string"]),
                        "name": .object(["type": "string"])
                    ],
                    required: ["name"]
                ),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "entity.find",
                description: "Find entities by name, active state, or component type.",
                inputSchema: Self.objectSchema(properties: [
                    "world": .object(["type": "string"]),
                    "name": .object(["type": "string"]),
                    "active": .object(["type": "boolean"]),
                    "componentType": .object(["type": "string"])
                ]),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "entity.list_components",
                description: "List inspectable components for an entity.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "world": .object(["type": "string"]),
                        "entityId": .object(["type": "integer"])
                    ],
                    required: ["entityId"]
                ),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "component.get",
                description: "Get one component payload by entity and type name.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "world": .object(["type": "string"]),
                        "entityId": .object(["type": "integer"]),
                        "componentType": .object(["type": "string"])
                    ],
                    required: ["entityId", "componentType"]
                ),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "resource.list",
                description: "List inspectable resources for a world.",
                inputSchema: Self.objectSchema(properties: [
                    "world": .object(["type": "string"])
                ]),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "resource.get",
                description: "Get one resource payload by type name.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "world": .object(["type": "string"]),
                        "resourceType": .object(["type": "string"])
                    ],
                    required: ["resourceType"]
                ),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "asset.find",
                description: "Find cached asset info by path, name, type, or asset ID.",
                inputSchema: Self.objectSchema(properties: [
                    "path": .object(["type": "string"]),
                    "name": .object(["type": "string"]),
                    "type": .object(["type": "string"]),
                    "assetId": .object(["type": "string"])
                ]),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "asset.get",
                description: "Get one cached asset info record.",
                inputSchema: Self.objectSchema(properties: [
                    "path": .object(["type": "string"]),
                    "name": .object(["type": "string"]),
                    "type": .object(["type": "string"]),
                    "assetId": .object(["type": "string"])
                ]),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "runtime.pause",
                description: "Pause AdaEngine simulation updates.",
                inputSchema: Self.objectSchema(properties: [
                    "reason": .object(["type": "string"])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "runtime.resume",
                description: "Resume AdaEngine simulation updates.",
                inputSchema: Self.objectSchema(),
                annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "runtime.step_frame",
                description: "Advance one or more paused simulation frames immediately.",
                inputSchema: Self.objectSchema(properties: [
                    "frames": .object(["type": "integer"])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
            ),
            Tool(
                name: "render.capture_screenshot",
                description: "Pause if needed, render a frame, and save a PNG screenshot.",
                inputSchema: Self.objectSchema(properties: [
                    "cameraEntityId": .object(["type": "integer"]),
                    "cameraName": .object(["type": "string"]),
                    "pauseBeforeCapture": .object(["type": "boolean"])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
            )
        ]
    }

    public func resources() -> [Resource] {
        [
            Resource(name: "World List", uri: "ada://worlds", description: "Live world index", mimeType: "application/json"),
            Resource(name: "World Snapshot", uri: "ada://world/{world}", description: "World summary resource", mimeType: "application/json"),
            Resource(name: "Entity Snapshot", uri: "ada://entity/{world}/{id}", description: "Entity snapshot resource", mimeType: "application/json"),
            Resource(name: "Inspectable Component Types", uri: "ada://types/components", description: "Registered inspectable component descriptors", mimeType: "application/json"),
            Resource(name: "Inspectable Resource Types", uri: "ada://types/resources", description: "Registered inspectable resource descriptors", mimeType: "application/json"),
            Resource(name: "Inspectable Asset Types", uri: "ada://types/assets", description: "Registered inspectable asset descriptors", mimeType: "application/json")
        ]
    }

    public func callTool(name: String, arguments: [String: Value]) async -> CallTool.Result {
        do {
            let payload: Value
            switch name {
            case "world.list_worlds":
                payload = try self.listWorldsPayload()
            case "world.get":
                payload = try self.worldPayload(named: arguments["world"]?.stringValue)
            case "entity.get_by_id":
                payload = try self.entityByIDPayload(arguments: arguments)
            case "entity.get_by_name":
                payload = try self.entityByNamePayload(arguments: arguments)
            case "entity.find":
                payload = try self.findEntitiesPayload(arguments: arguments)
            case "entity.list_components":
                payload = try self.entityComponentsPayload(arguments: arguments)
            case "component.get":
                payload = try self.componentPayload(arguments: arguments)
            case "resource.list":
                payload = try self.listResourcesPayload(arguments: arguments)
            case "resource.get":
                payload = try self.resourcePayload(arguments: arguments)
            case "asset.find":
                payload = try await self.assetFindPayload(arguments: arguments)
            case "asset.get":
                payload = try await self.assetGetPayload(arguments: arguments)
            case "runtime.pause":
                payload = try self.pausePayload(reason: arguments["reason"]?.stringValue)
            case "runtime.resume":
                payload = try self.resumePayload()
            case "runtime.step_frame":
                payload = try await self.stepFramePayload(frames: arguments["frames"]?.intValue ?? 1)
            case "render.capture_screenshot":
                payload = try await self.captureScreenshotPayload(arguments: arguments)
            default:
                return .init(content: [.text("Unknown MCP tool '\(name)'.")], isError: true)
            }

            return try self.jsonToolResult(payload)
        } catch {
            return .init(content: [.text(error.localizedDescription)], isError: true)
        }
    }

    public func readResource(uri: String) async throws -> ReadResource.Result {
        let payload: Value
        guard let url = URL(string: uri), url.scheme == "ada" else {
            throw AdaMCPError.invalidResourceURI(uri)
        }

        switch url.host {
        case "worlds":
            payload = try self.listWorldsPayload()
        case "world":
            let worldName = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            payload = try self.worldPayload(named: worldName)
        case "entity":
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count == 2, let entityID = Int(parts[1]) else {
                throw AdaMCPError.invalidResourceURI(uri)
            }
            payload = try self.entityPayload(worldName: parts[0], entityID: entityID)
        case "types":
            let kind = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            payload = try self.typeListPayload(kind: kind)
        default:
            throw AdaMCPError.invalidResourceURI(uri)
        }

        return try self.jsonResourceResult(payload, uri: uri)
    }

    private static func objectSchema(
        properties: [String: Value] = [:],
        required: [String] = []
    ) -> Value {
        var schema: [String: Value] = [
            "type": "object",
            "properties": .object(properties)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(Value.string))
        }
        return .object(schema)
    }

    private func listWorldsPayload() throws -> Value {
        let worlds = try appWorlds.allWorldNames().map { worldName -> Value in
            guard let worldBuilder = appWorlds.getWorldBuilder(by: worldName) else {
                throw AdaMCPError.worldNotFound(worldName.rawValue)
            }
            return self.makeWorldPayload(worldName: worldName.rawValue, world: worldBuilder.main)
        }
        return ["worlds": .array(worlds)]
    }

    private func worldPayload(named worldName: String?) throws -> Value {
        let resolved = try self.resolveWorld(named: worldName)
        return self.makeWorldPayload(worldName: resolved.name, world: resolved.world.main)
    }

    private func entityByIDPayload(arguments: [String: Value]) throws -> Value {
        guard let entityID = arguments["id"]?.intValue else {
            throw AdaMCPError.invalidArguments("Argument 'id' is required.")
        }
        let worldName = arguments["world"]?.stringValue ?? AppWorldName.main.rawValue
        return try self.entityPayload(worldName: worldName, entityID: entityID)
    }

    private func entityByNamePayload(arguments: [String: Value]) throws -> Value {
        guard let entityName = arguments["name"]?.stringValue, !entityName.isEmpty else {
            throw AdaMCPError.invalidArguments("Argument 'name' is required.")
        }
        let resolved = try self.resolveWorld(named: arguments["world"]?.stringValue)
        guard let entity = resolved.world.main.getEntityByName(entityName) else {
            throw AdaMCPError.assetNotFound(entityName)
        }
        return try self.makeEntityPayload(worldName: resolved.name, world: resolved.world.main, entity: entity)
    }

    private func findEntitiesPayload(arguments: [String: Value]) throws -> Value {
        let resolved = try self.resolveWorld(named: arguments["world"]?.stringValue)
        let nameQuery = arguments["name"]?.stringValue?.lowercased()
        let active = arguments["active"]?.boolValue
        let componentType = arguments["componentType"]?.stringValue

        let entities = try resolved.world.main.getEntities().filter { entity in
            if let nameQuery, !entity.name.lowercased().contains(nameQuery) {
                return false
            }
            if let active, entity.isActive != active {
                return false
            }
            if let componentType, !resolved.world.main.hasComponent(named: componentType, in: entity.id) {
                return false
            }
            return true
        }
        .map { entity in
            try self.makeEntityPayload(worldName: resolved.name, world: resolved.world.main, entity: entity)
        }

        return ["entities": .array(entities)]
    }

    private func entityComponentsPayload(arguments: [String: Value]) throws -> Value {
        guard let entityID = arguments["entityId"]?.intValue else {
            throw AdaMCPError.invalidArguments("Argument 'entityId' is required.")
        }
        let resolved = try self.resolveWorld(named: arguments["world"]?.stringValue)
        guard let entity = resolved.world.main.getEntityByID(entityID) else {
            throw AdaMCPError.entityNotFound(world: resolved.name, entityID: entityID)
        }
        let components = try self.inspectComponents(
            worldName: resolved.name,
            world: resolved.world.main,
            entity: entity
        )
        return ["components": .array(components.payloads), "diagnostics": .array(components.diagnostics)]
    }

    private func componentPayload(arguments: [String: Value]) throws -> Value {
        guard let entityID = arguments["entityId"]?.intValue else {
            throw AdaMCPError.invalidArguments("Argument 'entityId' is required.")
        }
        guard let componentType = arguments["componentType"]?.stringValue, !componentType.isEmpty else {
            throw AdaMCPError.invalidArguments("Argument 'componentType' is required.")
        }
        let resolved = try self.resolveWorld(named: arguments["world"]?.stringValue)
        guard resolved.world.main.getEntityByID(entityID) != nil else {
            throw AdaMCPError.entityNotFound(world: resolved.name, entityID: entityID)
        }
        guard let component = resolved.world.main.getComponent(named: componentType, from: entityID) else {
            throw AdaMCPError.resourceNotFound(componentType)
        }
        return try self.inspectValue(component)
    }

    private func listResourcesPayload(arguments: [String: Value]) throws -> Value {
        let resolved = try self.resolveWorld(named: arguments["world"]?.stringValue)
        var payloads: [Value] = []
        var diagnostics: [Value] = []

        for resource in resolved.world.main.getResources() {
            do {
                payloads.append(try self.inspectValue(resource))
            } catch {
                diagnostics.append(self.diagnosticValue(
                    code: "not_inspectable",
                    message: "Resource \(String(reflecting: type(of: resource))) is not inspectable."
                ))
            }
        }

        return ["resources": .array(payloads), "diagnostics": .array(diagnostics)]
    }

    private func resourcePayload(arguments: [String: Value]) throws -> Value {
        guard let resourceType = arguments["resourceType"]?.stringValue, !resourceType.isEmpty else {
            throw AdaMCPError.invalidArguments("Argument 'resourceType' is required.")
        }
        let resolved = try self.resolveWorld(named: arguments["world"]?.stringValue)
        guard let resource = resolved.world.main.getResource(named: resourceType) else {
            throw AdaMCPError.resourceNotFound(resourceType)
        }
        return try self.inspectValue(resource)
    }

    private func assetFindPayload(arguments: [String: Value]) async throws -> Value {
        let assets = await AssetsManager.cachedAssets().filter { asset in
            if let path = arguments["path"]?.stringValue, !asset.assetPath.contains(path) {
                return false
            }
            if let name = arguments["name"]?.stringValue, !asset.assetName.localizedCaseInsensitiveContains(name) {
                return false
            }
            if let type = arguments["type"]?.stringValue, asset.typeName != type {
                return false
            }
            if let assetID = arguments["assetId"]?.stringValue, asset.assetID != assetID {
                return false
            }
            return true
        }
        return ["assets": .array(assets.map(self.makeAssetPayload))]
    }

    private func assetGetPayload(arguments: [String: Value]) async throws -> Value {
        let assetsValue = try await self.assetFindPayload(arguments: arguments)
        guard let first = assetsValue.objectValue?["assets"]?.arrayValue?.first else {
            let query = arguments.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            throw AdaMCPError.assetNotFound(query)
        }
        return first
    }

    private func pausePayload(reason: String?) throws -> Value {
        let control = appWorlds.main.getOrInitRefResource(SimulationControl.self) {
            SimulationControl()
        }
        control.wrappedValue.mode = .paused
        control.wrappedValue.reason = reason ?? "runtime.pause"
        control.wrappedValue.pendingStepCount = 0
        return try Value(control.wrappedValue)
    }

    private func resumePayload() throws -> Value {
        let control = appWorlds.main.getOrInitRefResource(SimulationControl.self) {
            SimulationControl()
        }
        control.wrappedValue.mode = .running
        control.wrappedValue.reason = nil
        control.wrappedValue.pendingStepCount = 0
        return try Value(control.wrappedValue)
    }

    private func stepFramePayload(frames: Int) async throws -> Value {
        let frameCount = max(frames, 1)
        let control = appWorlds.main.getOrInitRefResource(SimulationControl.self) {
            SimulationControl()
        }
        control.wrappedValue.mode = .paused
        control.wrappedValue.reason = "runtime.step_frame"
        control.wrappedValue.pendingStepCount += frameCount

        for _ in 0..<frameCount {
            try await appWorlds.update()
        }

        return try Value(control.wrappedValue)
    }

    private func captureScreenshotPayload(arguments: [String: Value]) async throws -> Value {
        let result = try await renderCaptureService.capture(
            cameraEntityID: arguments["cameraEntityId"]?.intValue,
            cameraName: arguments["cameraName"]?.stringValue,
            pauseBeforeCapture: arguments["pauseBeforeCapture"]?.boolValue ?? true,
            refreshFrame: true
        )
        return try Value(result)
    }

    private func entityPayload(worldName: String, entityID: Int) throws -> Value {
        let resolved = try self.resolveWorld(named: worldName)
        guard let entity = resolved.world.main.getEntityByID(entityID) else {
            throw AdaMCPError.entityNotFound(world: resolved.name, entityID: entityID)
        }
        return try self.makeEntityPayload(worldName: resolved.name, world: resolved.world.main, entity: entity)
    }

    private func typeListPayload(kind: String) throws -> Value {
        let typeKind: MCPTypeKind
        switch kind {
        case "components":
            typeKind = .component
        case "resources":
            typeKind = .resource
        case "assets":
            typeKind = .asset
        default:
            throw AdaMCPError.invalidResourceURI("ada://types/\(kind)")
        }
        return try Value(registry.descriptors(kind: typeKind))
    }

    private func resolveWorld(named name: String?) throws -> (name: String, world: AppWorlds) {
        let worldName = name?.isEmpty == false ? name! : AppWorldName.main.rawValue
        guard let world = appWorlds.getWorldBuilder(by: AppWorldName(rawValue: worldName)) else {
            throw AdaMCPError.worldNotFound(worldName)
        }
        return (worldName, world)
    }

    private func makeWorldPayload(worldName: String, world: World) -> Value {
        let entities = world.getEntities()
        return [
            "type": "world",
            "name": worldName,
            "world": worldName,
            "summary": [
                "entityCount": entities.count,
                "activeEntityCount": entities.filter(\.isActive).count,
                "resourceCount": world.getResources().count
            ],
            "fields": [
                "id": String(describing: world.id),
                "name": world.name ?? worldName
            ],
            "diagnostics": []
        ]
    }

    private func makeEntityPayload(worldName: String, world: World, entity: Entity) throws -> Value {
        let components = try self.inspectComponents(worldName: worldName, world: world, entity: entity)
        return [
            "type": "entity",
            "id": entity.id,
            "name": entity.name,
            "world": worldName,
            "summary": [
                "isActive": entity.isActive,
                "componentCount": entity.components.count,
                "inspectableComponentCount": components.payloads.count
            ],
            "fields": [
                "isActive": entity.isActive
            ],
            "components": .array(components.payloads),
            "diagnostics": .array(components.diagnostics)
        ]
    }

    private func inspectComponents(
        worldName: String,
        world: World,
        entity: Entity
    ) throws -> (payloads: [Value], diagnostics: [Value]) {
        var payloads: [Value] = []
        var diagnostics: [Value] = []

        for (typeName, component) in world.getComponents(for: entity.id) {
            do {
                payloads.append(try self.inspectValue(component))
            } catch {
                diagnostics.append(self.diagnosticValue(
                    code: "not_inspectable",
                    message: "Component \(typeName) on entity \(entity.id) is not inspectable."
                ))
            }
        }

        return (payloads, diagnostics)
    }

    private func inspectValue(_ value: Any) throws -> Value {
        guard let descriptor = registry.descriptor(for: value) else {
            throw AdaMCPError.notInspectable(String(reflecting: type(of: value)))
        }
        guard let serialized = try registry.serialize(value) else {
            throw AdaMCPError.notInspectable(descriptor.name)
        }
        let fields = serialized.objectValue ?? ["value": serialized]
        return [
            "type": descriptor.name,
            "kind": descriptor.kind.rawValue,
            "summary": [
                "fieldCount": fields.count
            ],
            "fields": .object(fields),
            "diagnostics": []
        ]
    }

    private func makeAssetPayload(_ asset: AssetsManager.CachedAssetInfo) -> Value {
        let diagnostics: [Value]
        if registry.descriptor(named: asset.typeName) == nil {
            diagnostics = [
                self.diagnosticValue(
                    code: "unregistered_asset_descriptor",
                    message: "Asset type \(asset.typeName) has no explicit MCP descriptor."
                )
            ]
        } else {
            diagnostics = []
        }

        return [
            "type": asset.typeName,
            "kind": MCPTypeKind.asset.rawValue,
            "id": asset.assetID.map(Value.string) ?? .null,
            "name": asset.assetName,
            "world": .null,
            "summary": [
                "isLoaded": asset.isLoaded,
                "handleCount": asset.handleCount
            ],
            "fields": [
                "assetPath": asset.assetPath,
                "assetName": asset.assetName,
                "assetID": asset.assetID.map(Value.string) ?? .null,
                "isLoaded": asset.isLoaded,
                "handleCount": asset.handleCount
            ],
            "diagnostics": .array(diagnostics)
        ]
    }

    private func jsonToolResult(_ payload: Value) throws -> CallTool.Result {
        let text = try self.prettyJSONString(payload)
        return .init(content: [.text(text)], isError: false)
    }

    private func jsonResourceResult(_ payload: Value, uri: String) throws -> ReadResource.Result {
        let text = try self.prettyJSONString(payload)
        return .init(contents: [.text(text, uri: uri, mimeType: "application/json")])
    }

    private func prettyJSONString(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func diagnosticValue(code: String, message: String) -> Value {
        [
            "code": code,
            "message": message
        ]
    }
}
