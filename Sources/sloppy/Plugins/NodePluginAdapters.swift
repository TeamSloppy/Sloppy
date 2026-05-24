import AnyLanguageModel
import Foundation
import Logging
import PluginSDK
import Protocols

actor NodeGatewayPlugin: GatewayPlugin {
    nonisolated let id: String
    nonisolated let channelIds: [String]

    private let runtime: NodePluginRuntime
    private var inboundReceiver: (any InboundMessageReceiver)?

    init(
        manifest: PluginManifest,
        pluginDirectory: URL,
        logger: Logger = Logger(label: "sloppy.plugin.node.gateway")
    ) throws {
        self.id = manifest.name
        self.channelIds = manifest.config["channelIds"]?.asArray?.compactMap(\.asString) ?? []
        self.runtime = try NodePluginRuntime(manifest: manifest, pluginDirectory: pluginDirectory, logger: logger)
    }

    func start(inboundReceiver: any InboundMessageReceiver) async throws {
        self.inboundReceiver = inboundReceiver
        _ = try await runtime.callJSON("start", params: [
            "channelIds": .array(channelIds.map { .string($0) })
        ])
    }

    func stop() async {
        _ = try? await runtime.callJSON("stop")
        inboundReceiver = nil
    }

    func send(channelId: String, message: String, topicId: String?) async throws {
        var params: [String: JSONValue] = [
            "channelId": .string(channelId),
            "message": .string(message),
        ]
        if let topicId {
            params["topicId"] = .string(topicId)
        }
        _ = try await runtime.callJSON("send", params: params)
    }
}

actor NodePersistentGatewayPlugin: GatewayPlugin {
    nonisolated let id: String
    nonisolated let channelIds: [String]

    fileprivate let runtime: PersistentNodeGatewayRuntime

    init(
        manifest: PluginManifest,
        pluginDirectory: URL,
        descriptor: NodePluginDescriptor?,
        inboundReceiver: any InboundMessageReceiver,
        logger: Logger = Logger(label: "sloppy.plugin.node.gateway")
    ) throws {
        self.id = manifest.name
        self.channelIds = Self.resolveChannelIds(manifest: manifest, descriptor: descriptor)
        self.runtime = try PersistentNodeGatewayRuntime(
            manifest: manifest,
            pluginDirectory: pluginDirectory,
            inboundReceiver: inboundReceiver,
            logger: logger
        )
    }

    func start(inboundReceiver: any InboundMessageReceiver) async throws {
        _ = try await runtime.callJSON("gateway.start", params: [
            "channelIds": .array(channelIds.map { .string($0) })
        ])
    }

    func stop() async {
        _ = try? await runtime.callJSON("gateway.stop")
        await runtime.stopProcess()
    }

    func send(channelId: String, message: String, topicId: String?) async throws {
        try await sendViaRuntime(runtime, channelId: channelId, message: message, topicId: topicId)
    }

    fileprivate static func resolveChannelIds(manifest: PluginManifest, descriptor: NodePluginDescriptor?) -> [String] {
        let declared = descriptor?.gateways.flatMap(\.channelIds) ?? []
        if !declared.isEmpty {
            return Array(Set(declared)).sorted()
        }
        return manifest.config["channelIds"]?.asArray?.compactMap(\.asString) ?? []
    }

    static func capabilities(descriptor: NodePluginDescriptor?) -> Set<String> {
        Set((descriptor?.gateways.flatMap(\.capabilities) ?? []).map { $0.lowercased() })
    }
}

actor NodeInteractiveGatewayPlugin: StreamingGatewayPlugin, ToolApprovalGatewayPlugin, PlanInputGatewayPlugin {
    nonisolated let id: String
    nonisolated let channelIds: [String]

    private let runtime: PersistentNodeGatewayRuntime

    init(
        manifest: PluginManifest,
        pluginDirectory: URL,
        descriptor: NodePluginDescriptor?,
        inboundReceiver: any InboundMessageReceiver,
        logger: Logger = Logger(label: "sloppy.plugin.node.gateway")
    ) throws {
        self.id = manifest.name
        self.channelIds = NodePersistentGatewayPlugin.resolveChannelIds(manifest: manifest, descriptor: descriptor)
        self.runtime = try PersistentNodeGatewayRuntime(
            manifest: manifest,
            pluginDirectory: pluginDirectory,
            inboundReceiver: inboundReceiver,
            logger: logger
        )
    }

    func start(inboundReceiver: any InboundMessageReceiver) async throws {
        _ = try await runtime.callJSON("gateway.start", params: [
            "channelIds": .array(channelIds.map { .string($0) })
        ])
    }

    func stop() async {
        _ = try? await runtime.callJSON("gateway.stop")
        await runtime.stopProcess()
    }

    func send(channelId: String, message: String, topicId: String?) async throws {
        try await sendViaRuntime(runtime, channelId: channelId, message: message, topicId: topicId)
    }

    func beginStreaming(channelId: String, userId: String, topicId: String?) async throws -> GatewayOutboundStreamHandle {
        var params: [String: JSONValue] = [
            "channelId": .string(channelId),
            "userId": .string(userId)
        ]
        if let topicId { params["topicId"] = .string(topicId) }
        let result = try await runtime.callJSON("gateway.stream.start", params: params)
        let id = result.asObject?["streamId"]?.asString ?? result.asObject?["id"]?.asString ?? result.asString ?? UUID().uuidString
        return GatewayOutboundStreamHandle(id: id)
    }

    func updateStreaming(handle: GatewayOutboundStreamHandle, channelId: String, content: String) async throws {
        _ = try await runtime.callJSON("gateway.stream.update", params: [
            "streamId": .string(handle.id),
            "channelId": .string(channelId),
            "content": .string(content)
        ])
    }

    func endStreaming(
        handle: GatewayOutboundStreamHandle,
        channelId: String,
        userId: String,
        finalContent: String?
    ) async throws {
        var params: [String: JSONValue] = [
            "streamId": .string(handle.id),
            "channelId": .string(channelId),
            "userId": .string(userId),
            "content": finalContent.map(JSONValue.string) ?? .null
        ]
        params["finalContent"] = finalContent.map(JSONValue.string) ?? .null
        _ = try await runtime.callJSON("gateway.stream.end", params: params)
    }

    func presentToolApproval(_ approval: ToolApprovalRecord) async throws {
        _ = try await runtime.callJSON("gateway.toolApproval.present", params: [
            "approval": encodeJSONValue(approval)
        ])
    }

    func updateToolApproval(_ approval: ToolApprovalRecord) async throws {
        _ = try await runtime.callJSON("gateway.toolApproval.update", params: [
            "approval": encodeJSONValue(approval)
        ])
    }

    func presentPlanInputRequest(
        channelId: String,
        userId: String,
        request: PlanInputRequest,
        topicId: String?
    ) async throws {
        var params: [String: JSONValue] = [
            "channelId": .string(channelId),
            "userId": .string(userId),
            "request": encodeJSONValue(request)
        ]
        if let topicId { params["topicId"] = .string(topicId) }
        _ = try await runtime.callJSON("gateway.planInput.present", params: params)
    }
}

private func sendViaRuntime(
    _ runtime: PersistentNodeGatewayRuntime,
    channelId: String,
    message: String,
    topicId: String?
) async throws {
    var params: [String: JSONValue] = [
        "channelId": .string(channelId),
        "message": .string(message)
    ]
    if let topicId {
        params["topicId"] = .string(topicId)
    }
    _ = try await runtime.callJSON("gateway.send", params: params)
}

struct NodeTaskSyncProvider: TaskSyncProvider {
    let id: String

    private let runtime: NodePluginRuntime

    init(
        manifest: PluginManifest,
        pluginDirectory: URL,
        logger: Logger = Logger(label: "sloppy.plugin.node.task-sync")
    ) throws {
        self.id = manifest.name
        self.runtime = try NodePluginRuntime(manifest: manifest, pluginDirectory: pluginDirectory, logger: logger)
    }

    func parseProjectURL(_ rawURL: String) throws -> TaskSyncProjectDescriptor {
        TaskSyncProjectDescriptor(providerId: id, projectURL: rawURL)
    }

    func resolveProject(
        url: String,
        token: String?,
        defaultRepo: String?
    ) async throws -> TaskSyncProjectDescriptor {
        var params: [String: JSONValue] = ["url": .string(url)]
        if let token { params["token"] = .string(token) }
        if let defaultRepo { params["defaultRepo"] = .string(defaultRepo) }
        return try await runtime.call("resolveProject", params: params, as: TaskSyncProjectDescriptor.self)
    }

    func importTasks(
        settings: ProjectTaskSyncSettings,
        token: String?
    ) async throws -> [TaskSyncExternalTask] {
        var params: [String: JSONValue] = ["settings": encodeJSONValue(settings)]
        if let token { params["token"] = .string(token) }
        return try await runtime.call("importTasks", params: params, as: [TaskSyncExternalTask].self)
    }

    func createOrUpdateTask(
        _ task: ProjectTask,
        settings: ProjectTaskSyncSettings,
        token: String?
    ) async throws -> TaskExternalMetadata {
        var params: [String: JSONValue] = [
            "task": encodeJSONValue(task),
            "settings": encodeJSONValue(settings),
        ]
        if let token { params["token"] = .string(token) }
        return try await runtime.call("createOrUpdateTask", params: params, as: TaskExternalMetadata.self)
    }

    func mirrorComment(
        _ comment: TaskComment,
        task: ProjectTask,
        settings: ProjectTaskSyncSettings,
        token: String?
    ) async throws -> TaskExternalMetadata {
        var params: [String: JSONValue] = [
            "comment": encodeJSONValue(comment),
            "task": encodeJSONValue(task),
            "settings": encodeJSONValue(settings),
        ]
        if let token { params["token"] = .string(token) }
        return try await runtime.call("mirrorComment", params: params, as: TaskExternalMetadata.self)
    }
}

struct NodeToolPlugin: ToolPlugin {
    let id: String
    let supportedTools: [String]
    let toolDefinitions: [ToolPluginToolDefinition]

    private let runtime: NodePluginRuntime
    private let manifest: PluginManifest

    init(
        manifest: PluginManifest,
        pluginDirectory: URL,
        descriptor: NodePluginDescriptor? = nil,
        logger: Logger = Logger(label: "sloppy.plugin.node.tool")
    ) throws {
        self.id = manifest.name
        if manifest.isNodePluginAPIV2 {
            let tools = descriptor?.tools ?? []
            self.supportedTools = tools.map(\.name)
            self.toolDefinitions = tools.map { tool in
                ToolPluginToolDefinition(
                    name: tool.name,
                    title: tool.title ?? tool.name,
                    description: tool.description ?? "",
                    inputSchema: tool.effectiveSchema,
                    status: tool.status ?? "fully_functional"
                )
            }
        } else {
            self.supportedTools = manifest.config["supportedTools"]?.asArray?.compactMap(\.asString) ?? []
            self.toolDefinitions = supportedTools.map { tool in
                ToolPluginToolDefinition(
                    name: tool,
                    title: tool,
                    description: "",
                    inputSchema: .object(["type": .string("object")])
                )
            }
        }
        self.runtime = try NodePluginRuntime(manifest: manifest, pluginDirectory: pluginDirectory, logger: logger)
        self.manifest = manifest
    }

    func invoke(tool: String, arguments: [String: JSONValue]) async throws -> JSONValue {
        try await runtime.callJSON(manifest.isNodePluginAPIV2 ? "tool.invoke" : "invoke", params: [
            "tool": .string(tool),
            "arguments": .object(arguments),
        ])
    }
}

struct NodeMemoryPlugin: MemoryPlugin {
    let id: String

    private let runtime: NodePluginRuntime

    init(
        manifest: PluginManifest,
        pluginDirectory: URL,
        logger: Logger = Logger(label: "sloppy.plugin.node.memory")
    ) throws {
        self.id = manifest.name
        self.runtime = try NodePluginRuntime(manifest: manifest, pluginDirectory: pluginDirectory, logger: logger)
    }

    func recall(query: String, limit: Int) async throws -> [MemoryRef] {
        try await runtime.call(
            "recall",
            params: ["query": .string(query), "limit": .number(Double(limit))],
            as: [MemoryRef].self
        )
    }

    func save(note: String) async throws -> MemoryRef {
        try await runtime.call("save", params: ["note": .string(note)], as: MemoryRef.self)
    }
}

struct NodeModelProvider: ModelProvider {
    let id: String
    let supportedModels: [String]
    let systemInstructions: String?
    let tools: [any Tool] = []

    private let runtime: NodePluginRuntime

    init(
        manifest: PluginManifest,
        pluginDirectory: URL,
        logger: Logger = Logger(label: "sloppy.plugin.node.model-provider")
    ) throws {
        self.id = manifest.name
        self.supportedModels = manifest.config["supportedModels"]?.asArray?.compactMap(\.asString) ?? []
        self.systemInstructions = manifest.config["systemInstructions"]?.asString
        self.runtime = try NodePluginRuntime(manifest: manifest, pluginDirectory: pluginDirectory, logger: logger)
    }

    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        NodeLanguageModel(modelName: modelName, runtime: runtime)
    }

    func generationOptions(for modelName: String, maxTokens: Int, reasoningEffort: ReasoningEffort?) -> GenerationOptions {
        GenerationOptions(maximumResponseTokens: maxTokens)
    }
}

private struct NodeLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    let modelName: String
    let runtime: NodePluginRuntime

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let result = try await runtime.callJSON("respond", params: [
            "model": .string(modelName),
            "prompt": .string(prompt.description),
            "includeSchemaInPrompt": .bool(includeSchemaInPrompt),
        ])
        let text = result.asObject?["content"]?.asString ?? result.asString ?? ""
        let rawContent = GeneratedContent(text)
        let content = try Content(rawContent)
        return LanguageModelSession.Response(
            content: content,
            rawContent: rawContent,
            transcriptEntries: []
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            Task {
                do {
                    let response = try await respond(
                        within: session,
                        to: prompt,
                        generating: type,
                        includeSchemaInPrompt: includeSchemaInPrompt,
                        options: options
                    )
                    continuation.yield(.init(content: response.content.asPartiallyGenerated(), rawContent: response.rawContent))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return LanguageModelSession.ResponseStream(stream: stream)
    }
}
