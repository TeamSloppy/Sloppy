import AdaEngine
import Foundation
import Logging
import MCP

public struct MCPServerConfiguration: Sendable {
    public let enableHTTP: Bool
    public let enableStdio: Bool
    public let host: String
    public let port: Int
    public let endpoint: String
    public let serverName: String
    public let serverVersion: String
    public let instructions: String?
    public let registerTypes: (@MainActor (MCPIntrospectionRegistry) -> Void)?
    public let captureOverride: RenderCaptureService.CaptureOverride?

    public init(
        enableHTTP: Bool = true,
        enableStdio: Bool = false,
        host: String = "127.0.0.1",
        port: Int = 0,
        endpoint: String = "/mcp",
        serverName: String = "adaengine-mcp",
        serverVersion: String = "0.1.0",
        instructions: String? = "Inspect live AdaEngine worlds, entities, resources, assets, and render captures.",
        registerTypes: (@MainActor (MCPIntrospectionRegistry) -> Void)? = nil,
        captureOverride: RenderCaptureService.CaptureOverride? = nil
    ) {
        self.enableHTTP = enableHTTP
        self.enableStdio = enableStdio
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
    private let uiInspectionService: AdaUIInspectionService
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
        self.uiInspectionService = AdaUIInspectionService(appWorlds: appWorlds)
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
            ),
            Tool(
                name: "ui.list_windows",
                description: "List live AdaUI windows.",
                inputSchema: Self.objectSchema(),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "ui.get_window",
                description: "Get one AdaUI window snapshot and its root view trees.",
                inputSchema: Self.objectSchema(properties: [
                    "windowId": .object(["type": "integer"])
                ]),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "ui.get_tree",
                description: "Get one AdaUI window tree snapshot.",
                inputSchema: Self.objectSchema(properties: [
                    "windowId": .object(["type": "integer"])
                ]),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "ui.get_node",
                description: "Get one AdaUI node by accessibility identifier or runtime ID.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "windowId": .object(["type": "integer"]),
                        "accessibilityIdentifier": .object(["type": "string"]),
                        "runtimeId": .object(["type": "string"])
                    ]
                ),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "ui.find_nodes",
                description: "Find AdaUI nodes by accessibility identifier or runtime ID.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "windowId": .object(["type": "integer"]),
                        "accessibilityIdentifier": .object(["type": "string"]),
                        "runtimeId": .object(["type": "string"])
                    ]
                ),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "ui.hit_test",
                description: "Resolve the deepest AdaUI node at window coordinates.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "windowId": .object(["type": "integer"]),
                        "x": .object(["type": "number"]),
                        "y": .object(["type": "number"])
                    ],
                    required: ["x", "y"]
                ),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "ui.get_layout_diagnostics",
                description: "Get layout diagnostics for a window or target node.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "windowId": .object(["type": "integer"]),
                        "accessibilityIdentifier": .object(["type": "string"]),
                        "runtimeId": .object(["type": "string"]),
                        "subtreeDepth": .object(["type": "integer"])
                    ]
                ),
                annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "ui.set_debug_overlay",
                description: "Enable or disable AdaUI debug overlay drawing.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "windowId": .object(["type": "integer"]),
                        "mode": .object([
                            "type": "string",
                            "enum": .array([
                                .string(UIDebugOverlayMode.off.rawValue),
                                .string(UIDebugOverlayMode.layoutBounds.rawValue),
                                .string(UIDebugOverlayMode.focusedNode.rawValue),
                                .string(UIDebugOverlayMode.hitTestTarget.rawValue)
                            ])
                        ])
                    ],
                    required: ["mode"]
                ),
                annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "ui.focus_node",
                description: "Move AdaUI focus to a specific node.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "windowId": .object(["type": "integer"]),
                        "accessibilityIdentifier": .object(["type": "string"]),
                        "runtimeId": .object(["type": "string"])
                    ]
                ),
                annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
            ),
            Tool(
                name: "ui.focus_next",
                description: "Move AdaUI focus to the next focusable node.",
                inputSchema: Self.objectSchema(properties: [
                    "windowId": .object(["type": "integer"])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
            ),
            Tool(
                name: "ui.focus_previous",
                description: "Move AdaUI focus to the previous focusable node.",
                inputSchema: Self.objectSchema(properties: [
                    "windowId": .object(["type": "integer"])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
            ),
            Tool(
                name: "ui.scroll_to_node",
                description: "Scroll the nearest AdaUI scroll container to a target node.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "windowId": .object(["type": "integer"]),
                        "accessibilityIdentifier": .object(["type": "string"]),
                        "runtimeId": .object(["type": "string"])
                    ]
                ),
                annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
            ),
            Tool(
                name: "ui.tap_node",
                description: "Perform a deterministic tap/click on a target AdaUI node.",
                inputSchema: Self.objectSchema(
                    properties: [
                        "windowId": .object(["type": "integer"]),
                        "accessibilityIdentifier": .object(["type": "string"]),
                        "runtimeId": .object(["type": "string"])
                    ]
                ),
                annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
            )
        ]
    }

    public func resources() -> [MCP.Resource] {
        var resources = [
            MCP.Resource(
                name: "World List",
                uri: "ada://worlds",
                description: "Live world index.",
                mimeType: "application/json"
            ),
            MCP.Resource(
                name: "Inspectable Component Types",
                uri: "ada://types/components",
                description: "Registered inspectable component descriptors.",
                mimeType: "application/json"
            ),
            MCP.Resource(
                name: "Inspectable Resource Types",
                uri: "ada://types/resources",
                description: "Registered inspectable resource descriptors.",
                mimeType: "application/json"
            ),
            MCP.Resource(
                name: "Inspectable Asset Types",
                uri: "ada://types/assets",
                description: "Registered inspectable asset descriptors.",
                mimeType: "application/json"
            ),
            MCP.Resource(
                name: "UI Windows",
                uri: "ada://ui/windows",
                description: "Live AdaUI window index.",
                mimeType: "application/json"
            )
        ]

        for worldName in appWorlds.allWorldNames().map(\.rawValue).sorted() {
            resources.append(
                MCP.Resource(
                    name: "\(worldName) World Snapshot",
                    uri: "ada://world/\(worldName)",
                    description: "Snapshot of the \(worldName) world.",
                    mimeType: "application/json"
                )
            )
        }

        for window in uiInspectionService.listWindows() {
            resources.append(
                MCP.Resource(
                    name: "UI Window \(window.windowId)",
                    uri: "ada://ui/window/\(window.windowId)",
                    description: "Snapshot of AdaUI window \(window.windowId).",
                    mimeType: "application/json"
                )
            )
            resources.append(
                MCP.Resource(
                    name: "UI Tree \(window.windowId)",
                    uri: "ada://ui/tree/\(window.windowId)",
                    description: "Root AdaUI tree snapshot for window \(window.windowId).",
                    mimeType: "application/json"
                )
            )
        }

        return resources
    }

    public func resourceTemplates() -> [MCP.Resource.Template] {
        [
            MCP.Resource.Template(
                uriTemplate: "ada://entity/{world}/{id}",
                name: "Entity Snapshot",
                title: "Entity Snapshot",
                description: "Entity snapshot by world name and entity identifier.",
                mimeType: "application/json"
            ),
            MCP.Resource.Template(
                uriTemplate: "ada://ui/window/{windowId}",
                name: "UI Window Snapshot",
                title: "UI Window Snapshot",
                description: "AdaUI window snapshot by window identifier.",
                mimeType: "application/json"
            ),
            MCP.Resource.Template(
                uriTemplate: "ada://ui/tree/{windowId}",
                name: "UI Tree Snapshot",
                title: "UI Tree Snapshot",
                description: "AdaUI root tree snapshot by window identifier.",
                mimeType: "application/json"
            ),
            MCP.Resource.Template(
                uriTemplate: "ada://ui/node/{windowId}/{nodeRef}",
                name: "UI Node Snapshot",
                title: "UI Node Snapshot",
                description: "AdaUI node snapshot by window identifier and node selector.",
                mimeType: "application/json"
            )
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
            case "ui.list_windows":
                payload = try self.uiListWindowsPayload()
            case "ui.get_window":
                payload = try self.uiGetWindowPayload(arguments: arguments)
            case "ui.get_tree":
                payload = try self.uiGetTreePayload(arguments: arguments)
            case "ui.get_node":
                payload = try self.uiGetNodePayload(arguments: arguments)
            case "ui.find_nodes":
                payload = try self.uiFindNodesPayload(arguments: arguments)
            case "ui.hit_test":
                payload = try self.uiHitTestPayload(arguments: arguments)
            case "ui.get_layout_diagnostics":
                payload = try self.uiLayoutDiagnosticsPayload(arguments: arguments)
            case "ui.set_debug_overlay":
                payload = try self.uiSetDebugOverlayPayload(arguments: arguments)
            case "ui.focus_node":
                payload = try self.uiFocusNodePayload(arguments: arguments)
            case "ui.focus_next":
                payload = try self.uiFocusNextPayload(arguments: arguments)
            case "ui.focus_previous":
                payload = try self.uiFocusPreviousPayload(arguments: arguments)
            case "ui.scroll_to_node":
                payload = try self.uiScrollToNodePayload(arguments: arguments)
            case "ui.tap_node":
                payload = try self.uiTapNodePayload(arguments: arguments)
            default:
                return .init(content: [.text(text: "Unknown MCP tool '\(name)'.", annotations: nil, _meta: nil)], isError: true)
            }

            return try self.jsonToolResult(payload)
        } catch {
            if let mcpError = error as? AdaMCPError {
                return (try? self.jsonToolResult(Value(mcpError.payload), isError: true))
                    ?? .init(content: [.text(text: mcpError.localizedDescription, annotations: nil, _meta: nil)], isError: true)
            }

            return .init(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
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
        case "ui":
            payload = try self.uiResourcePayload(url: url, uri: uri)
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
            throw AdaMCPError.entityNamedNotFound(world: resolved.name, entityName: entityName)
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
        let components = try self.inspectComponents(world: resolved.world.main, entity: entity)
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
            throw AdaMCPError.componentNotFound(
                world: resolved.name,
                entityID: entityID,
                componentType: componentType
            )
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

    private func uiListWindowsPayload() throws -> Value {
        ["windows": try Value(self.uiInspectionService.listWindows())]
    }

    private func uiGetWindowPayload(arguments: [String: Value]) throws -> Value {
        try Value(self.uiInspectionService.getWindow(windowID: arguments["windowId"]?.intValue))
    }

    private func uiGetTreePayload(arguments: [String: Value]) throws -> Value {
        try Value(self.uiInspectionService.getTree(windowID: arguments["windowId"]?.intValue))
    }

    private func uiGetNodePayload(arguments: [String: Value]) throws -> Value {
        try Value(
            self.uiInspectionService.getNode(
                windowID: arguments["windowId"]?.intValue,
                selector: try self.resolveUINodeSelector(arguments: arguments)
            )
        )
    }

    private func uiFindNodesPayload(arguments: [String: Value]) throws -> Value {
        guard let selector = self.resolveOptionalUINodeSelector(arguments: arguments) else {
            throw AdaMCPError.invalidArguments("Argument 'accessibilityIdentifier' or 'runtimeId' is required.")
        }
        let nodes = try self.uiInspectionService.findNodes(
            windowID: arguments["windowId"]?.intValue,
            selector: selector
        )
        return ["nodes": try Value(nodes)]
    }

    private func uiHitTestPayload(arguments: [String: Value]) throws -> Value {
        let x = arguments["x"]?.doubleValue ?? arguments["x"]?.intValue.map(Double.init)
        let y = arguments["y"]?.doubleValue ?? arguments["y"]?.intValue.map(Double.init)
        guard let x, let y else {
            throw AdaMCPError.invalidArguments("Arguments 'x' and 'y' are required.")
        }

        return try Value(
            self.uiInspectionService.hitTest(
                windowID: arguments["windowId"]?.intValue,
                point: Point(Float(x), Float(y))
            )
        )
    }

    private func uiLayoutDiagnosticsPayload(arguments: [String: Value]) throws -> Value {
        try Value(
            self.uiInspectionService.getLayoutDiagnostics(
                windowID: arguments["windowId"]?.intValue,
                selector: self.resolveOptionalUINodeSelector(arguments: arguments),
                subtreeDepth: arguments["subtreeDepth"]?.intValue
            )
        )
    }

    private func uiSetDebugOverlayPayload(arguments: [String: Value]) throws -> Value {
        guard let rawMode = arguments["mode"]?.stringValue,
              let mode = UIDebugOverlayMode(rawValue: rawMode) else {
            throw AdaMCPError.invalidArguments("Argument 'mode' must be one of off, layout_bounds, focused_node, hit_test_target.")
        }
        return try Value(
            self.uiInspectionService.setDebugOverlay(
                windowID: arguments["windowId"]?.intValue,
                mode: mode
            )
        )
    }

    private func uiFocusNodePayload(arguments: [String: Value]) throws -> Value {
        try Value(
            self.uiInspectionService.focusNode(
                windowID: arguments["windowId"]?.intValue,
                selector: try self.resolveUINodeSelector(arguments: arguments)
            )
        )
    }

    private func uiFocusNextPayload(arguments: [String: Value]) throws -> Value {
        try Value(self.uiInspectionService.focusNext(windowID: arguments["windowId"]?.intValue))
    }

    private func uiFocusPreviousPayload(arguments: [String: Value]) throws -> Value {
        try Value(self.uiInspectionService.focusPrevious(windowID: arguments["windowId"]?.intValue))
    }

    private func uiScrollToNodePayload(arguments: [String: Value]) throws -> Value {
        try Value(
            self.uiInspectionService.scrollToNode(
                windowID: arguments["windowId"]?.intValue,
                selector: try self.resolveUINodeSelector(arguments: arguments)
            )
        )
    }

    private func uiTapNodePayload(arguments: [String: Value]) throws -> Value {
        try Value(
            self.uiInspectionService.tapNode(
                windowID: arguments["windowId"]?.intValue,
                selector: try self.resolveUINodeSelector(arguments: arguments)
            )
        )
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
        return .object([
            "type": "world",
            "name": .string(worldName),
            "world": .string(worldName),
            "summary": .object([
                "entityCount": .int(entities.count),
                "activeEntityCount": .int(entities.filter(\.isActive).count),
                "resourceCount": .int(world.getResources().count)
            ]),
            "fields": .object([
                "id": .string(String(describing: world.id)),
                "name": .string(world.name ?? worldName)
            ]),
            "diagnostics": .array([])
        ])
    }

    private func makeEntityPayload(worldName: String, world: World, entity: Entity) throws -> Value {
        let components = try self.inspectComponents(world: world, entity: entity)
        return .object([
            "type": "entity",
            "id": .int(entity.id),
            "name": .string(entity.name),
            "world": .string(worldName),
            "summary": .object([
                "isActive": .bool(entity.isActive),
                "componentCount": .int(entity.components.count),
                "inspectableComponentCount": .int(components.payloads.count)
            ]),
            "fields": .object([
                "isActive": .bool(entity.isActive)
            ]),
            "components": .array(components.payloads),
            "diagnostics": .array(components.diagnostics)
        ])
    }

    private func inspectComponents(
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
        return .object([
            "type": .string(descriptor.name),
            "kind": .string(descriptor.kind.rawValue),
            "summary": .object([
                "fieldCount": .int(fields.count)
            ]),
            "fields": .object(fields),
            "diagnostics": .array([])
        ])
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

        return .object([
            "type": .string(asset.typeName),
            "kind": .string(MCPTypeKind.asset.rawValue),
            "id": asset.assetID.map(Value.string) ?? .null,
            "name": .string(asset.assetName),
            "world": .null,
            "summary": .object([
                "isLoaded": .bool(asset.isLoaded),
                "handleCount": .int(asset.handleCount)
            ]),
            "fields": .object([
                "assetPath": .string(asset.assetPath),
                "assetName": .string(asset.assetName),
                "assetID": asset.assetID.map(Value.string) ?? .null,
                "isLoaded": .bool(asset.isLoaded),
                "handleCount": .int(asset.handleCount)
            ]),
            "diagnostics": .array(diagnostics)
        ])
    }

    private func uiResourcePayload(url: URL, uri: String) throws -> Value {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let kind = parts.first else {
            throw AdaMCPError.invalidResourceURI(uri)
        }

        switch kind {
        case "windows":
            return try self.uiListWindowsPayload()
        case "window":
            guard parts.count == 2, let windowID = Int(parts[1]) else {
                throw AdaMCPError.invalidResourceURI(uri)
            }
            return try Value(self.uiInspectionService.getWindow(windowID: windowID))
        case "tree":
            guard parts.count == 2, let windowID = Int(parts[1]) else {
                throw AdaMCPError.invalidResourceURI(uri)
            }
            return try Value(self.uiInspectionService.getTree(windowID: windowID))
        case "node":
            guard parts.count >= 3, let windowID = Int(parts[1]) else {
                throw AdaMCPError.invalidResourceURI(uri)
            }
            let nodeRef = parts.dropFirst(2).joined(separator: "/")
            return try Value(
                self.uiInspectionService.getNode(
                    windowID: windowID,
                    selector: try self.parseUINodeRef(nodeRef)
                )
            )
        default:
            throw AdaMCPError.invalidResourceURI(uri)
        }
    }

    private func resolveOptionalUINodeSelector(arguments: [String: Value]) -> UINodeSelector? {
        if let accessibilityIdentifier = arguments["accessibilityIdentifier"]?.stringValue, !accessibilityIdentifier.isEmpty {
            return .accessibilityIdentifier(accessibilityIdentifier)
        }
        if let runtimeID = arguments["runtimeId"]?.stringValue, !runtimeID.isEmpty {
            return .runtimeID(runtimeID)
        }
        return nil
    }

    private func resolveUINodeSelector(arguments: [String: Value]) throws -> UINodeSelector {
        guard let selector = self.resolveOptionalUINodeSelector(arguments: arguments) else {
            throw AdaMCPError.invalidArguments("Argument 'accessibilityIdentifier' or 'runtimeId' is required.")
        }
        return selector
    }

    private func parseUINodeRef(_ value: String) throws -> UINodeSelector {
        if value.hasPrefix("accessibility:") {
            return .accessibilityIdentifier(String(value.dropFirst("accessibility:".count)))
        }
        if value.hasPrefix("runtime:") {
            return .runtimeID(String(value.dropFirst("runtime:".count)))
        }
        throw AdaMCPError.invalidResourceURI("ada://ui/node/{windowId}/\(value)")
    }

    private func jsonToolResult(_ payload: Value, isError: Bool = false) throws -> CallTool.Result {
        let text = try self.prettyJSONString(payload)
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: isError)
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
        .object([
            "code": .string(code),
            "message": .string(message)
        ])
    }
}
