import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import MCP
import Protocols
#if canImport(System)
import System
#else
@preconcurrency import SystemPackage
#endif

enum MCPRegistryError: Error, LocalizedError {
    case unknownServer(String)
    case disabledServer(String)
    case invalidConfiguration(String)
    case invalidResult(String)

    var errorDescription: String? {
        switch self {
        case .unknownServer(let serverID):
            return "Unknown MCP server '\(serverID)'."
        case .disabledServer(let serverID):
            return "MCP server '\(serverID)' is disabled."
        case .invalidConfiguration(let message):
            return message
        case .invalidResult(let message):
            return message
        }
    }
}

struct MCPServerSummary: Sendable {
    let id: String
    let transport: String
    let enabled: Bool
    let exposeTools: Bool
    let exposeResources: Bool
    let exposePrompts: Bool
    let toolPrefix: String?
}

struct MCPDynamicTool: Sendable {
    let id: String
    let serverID: String
    let toolName: String
    let title: String
    let description: String
    let inputSchema: JSONValue
}

actor ManagedMCPStdioTransport: Transport {
    nonisolated let logger: Logger

    private let command: String
    private let arguments: [String]
    private let cwd: String?
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var innerTransport: StdioTransport?
    private var relayTask: Task<Void, Never>?
    private let messageStream: AsyncThrowingStream<Data, Error>
    private let messageContinuation: AsyncThrowingStream<Data, Error>.Continuation

    init(command: String, arguments: [String], cwd: String?, logger: Logger) {
        self.command = command
        self.arguments = arguments
        self.cwd = cwd
        self.logger = logger
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
    }

    func connect() async throws {
        guard innerTransport == nil else {
            return
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let process = Process()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError

        if command.hasPrefix("/") || command.hasPrefix(".") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }

        if let cwd,
           !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        }

        try process.run()

        let transport = StdioTransport(
            input: FileDescriptor(rawValue: outputPipe.fileHandleForReading.fileDescriptor),
            output: FileDescriptor(rawValue: inputPipe.fileHandleForWriting.fileDescriptor),
            logger: logger
        )
        try await transport.connect()

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.innerTransport = transport
        self.relayTask = Task { [weak self] in
            let stream = await transport.receive()
            do {
                for try await data in stream {
                    await self?.yieldMessage(data)
                }
                await self?.finishMessages()
            } catch {
                await self?.finishMessages()
            }
        }
    }

    func disconnect() async {
        relayTask?.cancel()
        relayTask = nil
        if let innerTransport {
            await innerTransport.disconnect()
        }

        if let process, process.isRunning {
            process.terminate()
        }

        self.process = nil
        self.inputPipe = nil
        self.outputPipe = nil
        self.innerTransport = nil
        messageContinuation.finish()
    }

    func send(_ data: Data) async throws {
        guard let innerTransport else {
            throw MCPRegistryError.invalidConfiguration("MCP stdio transport is not connected.")
        }
        try await innerTransport.send(data)
    }

    func receive() -> AsyncThrowingStream<Data, Error> {
        messageStream
    }

    private func yieldMessage(_ data: Data) {
        messageContinuation.yield(data)
    }

    private func finishMessages() {
        messageContinuation.finish()
    }
}

actor MCPServerConnection {
    private let config: CoreConfig.MCP.Server
    private let logger: Logger
    private var client: Client?
    private var transport: (any Transport)?

    init(config: CoreConfig.MCP.Server, logger: Logger) {
        self.config = config
        self.logger = logger
    }

    func disconnect() async {
        if let client {
            await client.disconnect()
        } else if let transport {
            await transport.disconnect()
        }
        client = nil
        transport = nil
    }

    func listTools(cursor: String? = nil) async throws -> (tools: [MCP.Tool], nextCursor: String?) {
        let client = try await ensureClient()
        return try await client.listTools(cursor: cursor)
    }

    func callTool(name: String, arguments: [String: Value]?) async throws -> (content: [MCP.Tool.Content], isError: Bool?) {
        let client = try await ensureClient()
        return try await client.callTool(name: name, arguments: arguments)
    }

    func listResources(cursor: String? = nil) async throws -> (resources: [Resource], nextCursor: String?) {
        let client = try await ensureClient()
        return try await client.listResources(cursor: cursor)
    }

    func readResource(uri: String) async throws -> [Resource.Content] {
        let client = try await ensureClient()
        return try await client.readResource(uri: uri)
    }

    func listPrompts(cursor: String? = nil) async throws -> (prompts: [Prompt], nextCursor: String?) {
        let client = try await ensureClient()
        return try await client.listPrompts(cursor: cursor)
    }

    func getPrompt(name: String, arguments: [String: Value]?) async throws -> (description: String?, messages: [Prompt.Message]) {
        let client = try await ensureClient()
        return try await client.getPrompt(name: name, arguments: arguments)
    }

    private func ensureClient() async throws -> Client {
        if let client {
            return client
        }

        let transport = try makeTransport()
        let client = Client(
            name: "sloppy",
            version: "1.0.0",
            capabilities: .init()
        )
        _ = try await client.connect(transport: transport)
        self.client = client
        self.transport = transport
        return client
    }

    private func makeTransport() throws -> any Transport {
        switch config.transport {
        case .stdio:
            let command = config.command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !command.isEmpty else {
                throw MCPRegistryError.invalidConfiguration("MCP server '\(config.id)' uses stdio but command is missing.")
            }
            return ManagedMCPStdioTransport(
                command: command,
                arguments: config.arguments,
                cwd: config.cwd,
                logger: logger
            )
        case .http:
            let endpointRaw = config.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let endpoint = URL(string: endpointRaw), !endpointRaw.isEmpty else {
                throw MCPRegistryError.invalidConfiguration("MCP server '\(config.id)' uses http but endpoint is missing.")
            }
            let sessionConfiguration = URLSessionConfiguration.default
            sessionConfiguration.timeoutIntervalForRequest = TimeInterval(max(config.timeoutMs, 250)) / 1_000
            let headers = config.headers
            return HTTPClientTransport(
                endpoint: endpoint,
                configuration: sessionConfiguration,
                streaming: true,
                requestModifier: { request in
                    var request = request
                    for (name, value) in headers {
                        request.setValue(value, forHTTPHeaderField: name)
                    }
                    return request
                },
                logger: logger
            )
        }
    }
}

actor MCPClientRegistry {
    private var config: CoreConfig.MCP
    private let logger: Logger
    private var connections: [String: MCPServerConnection] = [:]
    private var dynamicToolsByID: [String: MCPDynamicTool] = [:]

    init(config: CoreConfig.MCP, logger: Logger = Logger(label: "sloppy.mcp")) {
        self.config = config
        self.logger = logger
    }

    func updateConfig(_ config: CoreConfig.MCP) async {
        let nextIDs = Set(config.servers.map(\.id))
        let obsolete = connections.keys.filter { !nextIDs.contains($0) }
        for serverID in obsolete {
            if let connection = connections.removeValue(forKey: serverID) {
                await connection.disconnect()
            }
        }
        self.config = config
        self.dynamicToolsByID = [:]
    }

    func listServers() -> [MCPServerSummary] {
        config.servers.map { server in
            MCPServerSummary(
                id: server.id,
                transport: server.transport.rawValue,
                enabled: server.enabled,
                exposeTools: server.exposeTools,
                exposeResources: server.exposeResources,
                exposePrompts: server.exposePrompts,
                toolPrefix: server.toolPrefix
            )
        }
    }

    func listTools(serverID: String, cursor: String? = nil) async throws -> (tools: [MCP.Tool], nextCursor: String?) {
        let connection = try connection(for: serverID)
        return try await connection.listTools(cursor: cursor)
    }

    func callTool(serverID: String, name: String, arguments: [String: JSONValue]) async throws -> (content: [MCP.Tool.Content], isError: Bool?) {
        let connection = try connection(for: serverID)
        let convertedArguments = arguments.mapValues(Self.mcpValue(from:))
        return try await connection.callTool(name: name, arguments: convertedArguments)
    }

    func listResources(serverID: String, cursor: String? = nil) async throws -> (resources: [Resource], nextCursor: String?) {
        let connection = try connection(for: serverID)
        return try await connection.listResources(cursor: cursor)
    }

    func readResource(serverID: String, uri: String) async throws -> [Resource.Content] {
        let connection = try connection(for: serverID)
        return try await connection.readResource(uri: uri)
    }

    func listPrompts(serverID: String, cursor: String? = nil) async throws -> (prompts: [Prompt], nextCursor: String?) {
        let connection = try connection(for: serverID)
        return try await connection.listPrompts(cursor: cursor)
    }

    func getPrompt(serverID: String, name: String, arguments: [String: JSONValue]) async throws -> (description: String?, messages: [Prompt.Message]) {
        let connection = try connection(for: serverID)
        let convertedArguments = arguments.mapValues(Self.mcpValue(from:))
        return try await connection.getPrompt(name: name, arguments: convertedArguments)
    }

    func dynamicTools() async -> [MCPDynamicTool] {
        await refreshDynamicToolsIfNeeded()
        return dynamicToolsByID.values.sorted { $0.id < $1.id }
    }

    func dynamicToolIDs() async -> Set<String> {
        Set(await dynamicTools().map(\.id))
    }

    func isDynamicToolID(_ toolID: String) async -> Bool {
        await refreshDynamicToolsIfNeeded()
        return dynamicToolsByID[toolID] != nil
    }

    func dynamicTool(for toolID: String) async -> MCPDynamicTool? {
        await refreshDynamicToolsIfNeeded()
        return dynamicToolsByID[toolID]
    }

    func invokeDynamicTool(toolID: String, arguments: [String: JSONValue]) async throws -> ToolInvocationResult? {
        await refreshDynamicToolsIfNeeded()
        guard let dynamicTool = dynamicToolsByID[toolID] else {
            return nil
        }

        let result = try await callTool(
            serverID: dynamicTool.serverID,
            name: dynamicTool.toolName,
            arguments: arguments
        )
        let payload: JSONValue = .object([
            "server": .string(dynamicTool.serverID),
            "tool": .string(dynamicTool.toolName),
            "isError": result.isError.map(JSONValue.bool) ?? .null,
            "content": .array(result.content.map(Self.jsonValue(from:)))
        ])
        return ToolInvocationResult(
            tool: toolID,
            ok: result.isError != true,
            data: result.isError == true ? nil : payload,
            error: result.isError == true
                ? ToolErrorPayload(
                    code: "mcp_tool_error",
                    message: "MCP tool '\(dynamicTool.toolName)' on server '\(dynamicTool.serverID)' returned an error result.",
                    retryable: false
                )
                : nil
        )
    }

    func decodeJSONTextResult<T: Decodable>(serverID: String, toolName: String, arguments: [String: JSONValue], as type: T.Type) async throws -> T {
        let result = try await callTool(serverID: serverID, name: toolName, arguments: arguments)
        guard result.isError != true else {
            throw MCPRegistryError.invalidResult("MCP tool '\(toolName)' on server '\(serverID)' returned an error result.")
        }
        let textPayload = Self.flattenText(from: result.content)
        guard let data = textPayload.data(using: .utf8) else {
            throw MCPRegistryError.invalidResult("MCP tool '\(toolName)' on server '\(serverID)' returned empty text.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func connection(for serverID: String) throws -> MCPServerConnection {
        guard let server = config.servers.first(where: { $0.id == serverID }) else {
            throw MCPRegistryError.unknownServer(serverID)
        }
        guard server.enabled else {
            throw MCPRegistryError.disabledServer(serverID)
        }
        if let existing = connections[serverID] {
            return existing
        }
        let connection = MCPServerConnection(
            config: server,
            logger: Logger(label: "sloppy.mcp.\(serverID)")
        )
        connections[serverID] = connection
        return connection
    }

    private func refreshDynamicToolsIfNeeded() async {
        if !dynamicToolsByID.isEmpty {
            return
        }

        var discovered: [String: MCPDynamicTool] = [:]
        for server in config.servers where server.enabled && server.exposeTools {
            do {
                let response = try await withDiscoveryTimeout(milliseconds: max(250, server.timeoutMs)) {
                    try await self.listTools(serverID: server.id)
                }
                for tool in response.tools {
                    let toolID = Self.dynamicToolID(
                        serverID: server.id,
                        toolName: tool.name,
                        prefix: server.toolPrefix
                    )
                    discovered[toolID] = MCPDynamicTool(
                        id: toolID,
                        serverID: server.id,
                        toolName: tool.name,
                        title: tool.title ?? tool.name,
                        description: tool.description ?? "MCP tool from server '\(server.id)'",
                        inputSchema: Self.jsonValue(from: tool.inputSchema)
                    )
                }
            } catch {
                logger.warning(
                    "Failed to discover MCP tools for server \(server.id): \(String(describing: error))"
                )
            }
        }
        dynamicToolsByID = discovered
    }

    private func withDiscoveryTimeout<T: Sendable>(
        milliseconds: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(1, milliseconds)) * 1_000_000)
                throw MCPRegistryError.invalidResult("Timed out while discovering MCP tools.")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    static func dynamicToolID(serverID: String, toolName: String, prefix: String?) -> String {
        let base = prefix?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBase = (base?.isEmpty == false ? base! : "mcp.\(serverID)")
        return "\(normalizedBase).\(toolName)"
    }

    static func mcpValue(from value: JSONValue) -> Value {
        switch value {
        case .string(let string):
            return .string(string)
        case .number(let number):
            if number.rounded(.towardZero) == number {
                return .int(Int(number))
            }
            return .double(number)
        case .bool(let bool):
            return .bool(bool)
        case .object(let object):
            return .object(object.mapValues(mcpValue(from:)))
        case .array(let array):
            return .array(array.map(mcpValue(from:)))
        case .null:
            return .null
        }
    }

    static func jsonValue(from value: Value) -> JSONValue {
        switch value {
        case .null:
            return .null
        case .bool(let bool):
            return .bool(bool)
        case .int(let int):
            return .number(Double(int))
        case .double(let double):
            return .number(double)
        case .string(let string):
            return .string(string)
        case .data(let mimeType, let data):
            return .object([
                "mimeType": mimeType.map(JSONValue.string) ?? .null,
                "data": .string(data.base64EncodedString())
            ])
        case .array(let array):
            return .array(array.map(jsonValue(from:)))
        case .object(let object):
            return .object(object.mapValues(jsonValue(from:)))
        }
    }

    static func flattenText(from content: [MCP.Tool.Content]) -> String {
        content.compactMap { item -> String? in
            switch item {
            case .text(let text):
                return text
            case .resource(let resource, _, _):
                return resource.text
            default:
                return nil
            }
        }
        .joined(separator: "\n")
    }

    static func jsonValue(from tool: MCP.Tool) -> JSONValue {
        .object([
            "name": .string(tool.name),
            "title": tool.title.map(JSONValue.string) ?? .null,
            "description": tool.description.map(JSONValue.string) ?? .null,
            "inputSchema": jsonValue(from: tool.inputSchema),
            "outputSchema": tool.outputSchema.map(jsonValue(from:)) ?? .null,
            "annotations": .object([
                "title": tool.annotations.title.map(JSONValue.string) ?? .null,
                "readOnlyHint": tool.annotations.readOnlyHint.map(JSONValue.bool) ?? .null,
                "destructiveHint": tool.annotations.destructiveHint.map(JSONValue.bool) ?? .null,
                "idempotentHint": tool.annotations.idempotentHint.map(JSONValue.bool) ?? .null,
                "openWorldHint": tool.annotations.openWorldHint.map(JSONValue.bool) ?? .null
            ])
        ])
    }

    static func jsonValue(from resource: Resource) -> JSONValue {
        .object([
            "name": .string(resource.name),
            "title": resource.title.map(JSONValue.string) ?? .null,
            "uri": .string(resource.uri),
            "description": resource.description.map(JSONValue.string) ?? .null,
            "mimeType": resource.mimeType.map(JSONValue.string) ?? .null,
            "metadata": .object((resource.metadata ?? [:]).mapValues(JSONValue.string))
        ])
    }

    static func jsonValue(from resourceContent: Resource.Content) -> JSONValue {
        .object([
            "uri": .string(resourceContent.uri),
            "mimeType": resourceContent.mimeType.map(JSONValue.string) ?? .null,
            "text": resourceContent.text.map(JSONValue.string) ?? .null,
            "blob": resourceContent.blob.map(JSONValue.string) ?? .null
        ])
    }

    static func jsonValue(from prompt: Prompt) -> JSONValue {
        .object([
            "name": .string(prompt.name),
            "title": prompt.title.map(JSONValue.string) ?? .null,
            "description": prompt.description.map(JSONValue.string) ?? .null,
            "arguments": .array((prompt.arguments ?? []).map { argument in
                .object([
                    "name": .string(argument.name),
                    "title": argument.title.map(JSONValue.string) ?? .null,
                    "description": argument.description.map(JSONValue.string) ?? .null,
                    "required": argument.required.map(JSONValue.bool) ?? .null
                ])
            })
        ])
    }

    static func jsonValue(from message: Prompt.Message) -> JSONValue {
        .object([
            "role": .string(message.role.rawValue),
            "content": jsonValue(from: message.content)
        ])
    }

    static func jsonValue(from content: Prompt.Message.Content) -> JSONValue {
        switch content {
        case .text(let text):
            return .object([
                "type": .string("text"),
                "text": .string(text)
            ])
        case .image(let data, let mimeType):
            return .object([
                "type": .string("image"),
                "data": .string(data),
                "mimeType": .string(mimeType)
            ])
        case .audio(let data, let mimeType):
            return .object([
                "type": .string("audio"),
                "data": .string(data),
                "mimeType": .string(mimeType)
            ])
        case .resource(let resource, _, _):
            return .object([
                "type": .string("resource"),
                "resource": jsonValue(from: resource)
            ])
        }
    }

    static func jsonValue(from content: MCP.Tool.Content) -> JSONValue {
        switch content {
        case .text(let text):
            return .object([
                "type": .string("text"),
                "text": .string(text)
            ])
        case .image(let data, let mimeType, let metadata):
            return .object([
                "type": .string("image"),
                "data": .string(data),
                "mimeType": .string(mimeType),
                "metadata": metadata.map(jsonValue(from:)) ?? .null
            ])
        case .audio(let data, let mimeType):
            return .object([
                "type": .string("audio"),
                "data": .string(data),
                "mimeType": .string(mimeType)
            ])
        case .resource(let resource, _, _):
            return .object([
                "type": .string("resource"),
                "resource": jsonValue(from: resource)
            ])
        case .resourceLink(let uri, let name, let title, let description, let mimeType, _):
            return .object([
                "type": .string("resource_link"),
                "uri": .string(uri),
                "name": .string(name),
                "title": title.map(JSONValue.string) ?? .null,
                "description": description.map(JSONValue.string) ?? .null,
                "mimeType": mimeType.map(JSONValue.string) ?? .null
            ])
        }
    }

    static func jsonValue(from metadata: Metadata) -> JSONValue {
        .object(metadata.fields.mapValues(jsonValue(from:)))
    }
}
