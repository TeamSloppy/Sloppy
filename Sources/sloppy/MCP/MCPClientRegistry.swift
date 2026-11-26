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

struct MCPServerStatus: Encodable, Sendable {
    let id: String
    let transport: String
    let enabled: Bool
    let connected: Bool
    let exposeTools: Bool
    let exposeResources: Bool
    let exposePrompts: Bool
    let toolPrefix: String?
    let message: String?
    var protocolVersion: String? = nil
    var advertisedCapabilities: [String: JSONValue]? = nil
}

struct MCPDynamicTool: Sendable {
    let id: String
    let serverID: String
    let toolName: String
    let title: String
    let description: String
    let inputSchema: JSONValue
    let readOnlyHint: Bool

    init(id: String, serverID: String, toolName: String, title: String, description: String, inputSchema: JSONValue, readOnlyHint: Bool = false) {
        self.id = id
        self.serverID = serverID
        self.toolName = toolName
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.readOnlyHint = readOnlyHint
    }
}

private final class DiscoveryTimeoutBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var tasks: [Task<Void, Never>] = []
    private var completed = false

    func setContinuation(_ continuation: CheckedContinuation<T, any Error>) {
        lock.lock()
        if completed {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func setTasks(_ tasks: [Task<Void, Never>]) {
        lock.lock()
        if completed {
            lock.unlock()
            tasks.forEach { $0.cancel() }
            return
        }
        self.tasks = tasks
        lock.unlock()
    }

    func resume(_ result: Result<T, any Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = self.continuation
        let tasks = self.tasks
        self.continuation = nil
        self.tasks = []
        lock.unlock()

        tasks.forEach { $0.cancel() }
        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    func cancel() {
        resume(.failure(CancellationError()))
    }
}

actor ManagedMCPStdioTransport: Transport {
    nonisolated let logger: Logging.Logger

    private let command: String
    private let arguments: [String]
    private let cwd: String?
    private let configuredEnvironment: [String: String]
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var innerTransport: StdioTransport?
    private var relayTask: Task<Void, Never>?
    private let messageStream: AsyncThrowingStream<Data, Error>
    private let messageContinuation: AsyncThrowingStream<Data, Error>.Continuation

    init(command: String, arguments: [String], cwd: String?, environment: [String: String] = [:], logger: Logging.Logger) {
        self.command = command
        self.arguments = arguments
        self.cwd = cwd
        self.configuredEnvironment = environment
        self.logger = logger
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
    }

    func connect() async throws {
        guard innerTransport == nil else {
            return
        }

        let environment = childProcessEnvironment()
        let inputPipe = try makeProcessInputPipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        #if os(Windows)
        try PlatformProcess.configure(process, command: command, arguments: arguments,
                                      environment: childProcessEnvironment(overrides: configuredEnvironment))
        #else
        if command.hasPrefix("/") || command.hasPrefix(".") || command.contains("/") {
            let executableURL = resolveCommandURL(command, cwd: cwd)
            guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
                throw MCPRegistryError.invalidConfiguration("Command not found: \(command)")
            }
            process.executableURL = executableURL
            process.arguments = arguments
        } else {
            guard let executablePath = findExecutable(command, environment: environment) else {
                throw MCPRegistryError.invalidConfiguration("Command not found: \(command)")
            }
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
        }
        #endif

        if let cwd,
           !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        }

        process.environment = childProcessEnvironment(overrides: configuredEnvironment, base: environment)

        do {
            try process.run()
        } catch {
            throw MCPRegistryError.invalidConfiguration(
                "Failed to start MCP command '\(command)': \(error.localizedDescription)"
            )
        }

        #if os(Windows)
        let transport = StdioTransport(input: outputPipe.fileHandleForReading, output: inputPipe.fileHandleForWriting, logger: logger)
        #else
        let transport = StdioTransport(
            input: FileDescriptor(rawValue: outputPipe.fileHandleForReading.fileDescriptor),
            output: FileDescriptor(rawValue: inputPipe.fileHandleForWriting.fileDescriptor),
            logger: logger
        )
        #endif
        try await transport.connect()

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
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
        self.errorPipe = nil
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
        // The SDK reconnects after a clean stream end. Stdio EOF is terminal;
        // throwing prevents it from spinning on this already-finished stream.
        messageContinuation.finish(throwing: MCPRegistryError.invalidResult("MCP server closed its output stream."))
    }

    private func resolveCommandURL(_ command: String, cwd: String?) -> URL {
        if command.hasPrefix("/") {
            return URL(fileURLWithPath: command)
        }
        let base = cwd?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? cwd!
            : FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent(command)
    }

    private func findExecutable(_ command: String, environment: [String: String]) -> String? {
        let path = environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(command)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

struct MCPToolReply: Sendable {
    let content: [MCP.Tool.Content]
    let isError: Bool?
    var structuredContent: JSONValue? = nil
}

actor MCPServerConnection {
    private enum Connection: Sendable {
        case legacy(Client, protocolVersion: String)
        case modern(MCPHTTPDiscovery.Server)
    }

    nonisolated let config: CoreConfig.MCP.Server
    private let logger: Logging.Logger
    private var connection: Connection?
    private var toolHeaders: [String: MCPToolHeaders] = [:]
    private var toolHeadersExpireAt: ContinuousClock.Instant?
    private var subscription: Task<Void, Never>?
    private let catalogChanged: @Sendable () async -> Void
    private var pendingClient: Client?
    private var stdio: MCPModernStdio?
    private var attempt: (id: UUID, task: Task<Connection, any Error>)?

    init(config: CoreConfig.MCP.Server, logger: Logging.Logger, catalogChanged: @escaping @Sendable () async -> Void = {}) {
        self.config = config
        self.logger = logger
        self.catalogChanged = catalogChanged
    }

    func disconnect() async {
        let clientToDisconnect: Client?
        if case .legacy(let client, _) = connection {
            clientToDisconnect = client
        } else {
            clientToDisconnect = pendingClient
        }
        attempt?.task.cancel()
        attempt = nil
        connection = nil
        toolHeaders.removeAll()
        toolHeadersExpireAt = nil
        subscription?.cancel()
        subscription = nil
        pendingClient = nil
        let stdioToDisconnect = stdio
        stdio = nil
        await clientToDisconnect?.disconnect()
        await stdioToDisconnect?.disconnect()
    }

    func listTools(cursor: String? = nil) async throws -> (tools: [MCP.Tool], nextCursor: String?) {
        switch try await ensureConnection() {
        case .legacy(let client, _): return try await client.listTools(cursor: cursor)
        case .modern(let server): return try await listModernTools(cursor: cursor, server: server)
        }
    }

    private func listModernTools(cursor: String?, server: MCPHTTPDiscovery.Server) async throws -> (tools: [MCP.Tool], nextCursor: String?) {
        guard server.capabilities["tools"]?.asObject != nil else { return ([], nil) }
        let raw = try await request("tools/list", params: pagination(cursor), server: server, capability: "tools")
        let result = try decodeComplete(raw, as: ListTools.Result.self)
        let ttl = max(0, min(raw["ttlMs"]?.asNumber ?? 0, Double(Int32.max)))
        let expiry = ContinuousClock.Instant.now + .milliseconds(Int(ttl))
        toolHeadersExpireAt = cursor == nil ? expiry : min(toolHeadersExpireAt ?? expiry, expiry)
        if cursor == nil { toolHeaders.removeAll() }
        let tools = result.tools.filter { tool in
            guard config.transport == .http else { return true }
            do {
                toolHeaders[tool.name] = try MCPToolHeaders(schema: MCPClientRegistry.jsonValue(from: tool.inputSchema))
                return true
            } catch {
                toolHeaders.removeValue(forKey: tool.name)
                logger.warning("MCP tool definition rejected", metadata: ["tool": "\(tool.name)"])
                return false
            }
        }
        return (tools, result.nextCursor)
    }

    func callTool(name: String, arguments: [String: JSONValue], interaction: MCPToolInteraction? = nil) async throws -> MCPToolReply {
        switch try await ensureConnection() {
        case .legacy(let client, _):
            let result = try await client.callTool(name: name, arguments: arguments.mapValues(MCPClientRegistry.mcpValue(from:)))
            return MCPToolReply(content: result.content, isError: result.isError)
        case .modern(let server):
            let params: [String: JSONValue] = ["name": .string(name), "arguments": .object(arguments)]
            let headers = try await mirroredToolHeaders(name: name, arguments: arguments, server: server)
            do {
                let raw: [String: JSONValue]
                do {
                    raw = try await request("tools/call", params: params, server: server, capability: "tools", headers: headers, interaction: interaction)
                } catch let failure as MCPRPCFailure where failure.code == -32020 && config.transport == .http {
                    toolHeaders.removeValue(forKey: name)
                    let refreshed = try await mirroredToolHeaders(name: name, arguments: arguments, server: server)
                    guard refreshed != headers else { throw failure }
                    raw = try await request("tools/call", params: params, server: server, capability: "tools", headers: refreshed, interaction: interaction)
                }
                if raw["resultType"]?.asString == "task", let interaction {
                    return try await interaction.registerTask(raw, config)
                }
                let result = try decodeComplete(raw, as: CallTool.Result.self)
                return MCPToolReply(content: result.content, isError: result.isError, structuredContent: raw["structuredContent"])
            } catch let failure as MCPRPCFailure where failure.rejectedBeforeExecution {
                throw failure
            } catch {
                throw MCPToolOutcomeUnknown()
            }
        }
    }

    private func mirroredToolHeaders(name: String, arguments: [String: JSONValue], server: MCPHTTPDiscovery.Server) async throws -> [String: String] {
        guard config.transport == .http else { return [:] }
        if let expiry = toolHeadersExpireAt, expiry <= .now { toolHeaders.removeAll() }
        var cursor: String?
        var seen: Set<String> = []
        while toolHeaders[name] == nil {
            let page = try await listModernTools(cursor: cursor, server: server)
            guard let next = page.nextCursor, seen.insert(next).inserted, seen.count <= 1_000 else { break }
            cursor = next
        }
        guard let headers = toolHeaders[name] else {
            throw MCPRegistryError.invalidResult("MCP tool has no valid definition.")
        }
        return try headers.encode(arguments)
    }

    func listResources(cursor: String? = nil) async throws -> (resources: [Resource], nextCursor: String?) {
        switch try await ensureConnection() {
        case .legacy(let client, _): return try await client.listResources(cursor: cursor)
        case .modern(let server):
            let raw = try await request("resources/list", params: pagination(cursor), server: server, capability: "resources")
            let result = try decodeComplete(raw, as: ListResources.Result.self)
            return (result.resources, result.nextCursor)
        }
    }

    func readResource(uri: String) async throws -> [Resource.Content] {
        switch try await ensureConnection() {
        case .legacy(let client, _): return try await client.readResource(uri: uri)
        case .modern(let server):
            let raw = try await request("resources/read", params: ["uri": .string(uri)], server: server, capability: "resources")
            return try decodeComplete(raw, as: ReadResource.Result.self).contents
        }
    }

    func listPrompts(cursor: String? = nil) async throws -> (prompts: [Prompt], nextCursor: String?) {
        switch try await ensureConnection() {
        case .legacy(let client, _): return try await client.listPrompts(cursor: cursor)
        case .modern(let server):
            let raw = try await request("prompts/list", params: pagination(cursor), server: server, capability: "prompts")
            let result = try decodeComplete(raw, as: ListPrompts.Result.self)
            return (result.prompts, result.nextCursor)
        }
    }

    func getPrompt(name: String, arguments: [String: String]?) async throws -> (description: String?, messages: [Prompt.Message]) {
        switch try await ensureConnection() {
        case .legacy(let client, _): return try await client.getPrompt(name: name, arguments: arguments)
        case .modern(let server):
            let raw = try await request("prompts/get", params: [
                "name": .string(name), "arguments": .object((arguments ?? [:]).mapValues(JSONValue.string))
            ], server: server, capability: "prompts")
            let result = try decodeComplete(raw, as: GetPrompt.Result.self)
            return (result.description, result.messages)
        }
    }

    private func pagination(_ cursor: String?) -> [String: JSONValue] {
        cursor.map { ["cursor": .string($0)] } ?? [:]
    }

    private func decodeComplete<T: Decodable>(_ raw: [String: JSONValue], as type: T.Type) throws -> T {
        guard raw["resultType"]?.asString == "complete" else {
            throw MCPRegistryError.invalidResult("Unexpected MCP result type.")
        }
        return try JSONDecoder().decode(type, from: JSONEncoder().encode(JSONValue.object(raw)))
    }

    func extensionRequest(_ method: String, extensionID: String, params: [String: JSONValue],
                          capabilities: [String: JSONValue] = [:]) async throws -> [String: JSONValue] {
        guard case .modern(let server) = try await ensureConnection(),
              server.capabilities["extensions"]?.asObject?[extensionID]?.asObject != nil,
              extensionID != MCPRemoteSkill.extensionID || server.capabilities["resources"]?.asObject != nil else {
            throw MCPRegistryError.invalidResult("Server does not advertise the requested MCP extension.")
        }
        return try await sendModern(method, params: params, capabilities: capabilities)
    }

    private func request(
        _ method: String, params: [String: JSONValue], server: MCPHTTPDiscovery.Server, capability: String,
        headers: [String: String] = [:], interaction: MCPToolInteraction? = nil
    ) async throws -> [String: JSONValue] {
        guard server.capabilities[capability]?.asObject != nil else {
            throw MCPRegistryError.invalidResult("Server does not advertise MCP \(capability).")
        }
        var capabilities = interaction?.capabilities ?? [:]
        if server.capabilities["extensions"]?.asObject?[MCPToolInteraction.tasksID] == nil {
            capabilities.removeValue(forKey: "extensions")
        }
        var outgoing = params
        if let interaction {
            outgoing["_meta"] = .object(["progressToken": .string(interaction.progressToken)])
        }
        for round in 0..<32 {
            let result: [String: JSONValue]
            do {
                result = try await sendModern(method, params: outgoing, capabilities: capabilities,
                                              headers: headers, onNotification: interaction?.notification)
            } catch is MCPRPCFailure where method == "tools/call" && round > 0 {
                throw MCPToolOutcomeUnknown()
            }
            guard result["resultType"]?.asString == "input_required" else { return result }
            let state = result["requestState"]?.asString.map(JSONValue.string)
            let requests = result["inputRequests"]?.asObject
            guard state != nil || requests != nil else {
                throw MCPRegistryError.invalidResult("Invalid MCP input-required response.")
            }
            outgoing["requestState"] = state
            outgoing.removeValue(forKey: "inputResponses")
            if let requests, !requests.isEmpty {
                guard let interaction else {
                    throw MCPRegistryError.invalidResult("MCP server requires input unavailable to this caller.")
                }
                outgoing["inputResponses"] = .object(try await interaction.answer(requests))
            }
        }
        throw MCPRegistryError.invalidResult("MCP request exceeded the input round limit.")
    }

    private func sendModern(
        _ method: String, params: [String: JSONValue], capabilities: [String: JSONValue],
        headers: [String: String] = [:], onNotification: (@Sendable ([String: JSONValue]) -> Void)? = nil
    ) async throws -> [String: JSONValue] {
        if let stdio { return try await stdio.request(method, params: params, capabilities: capabilities, onNotification: onNotification) }
        return try await MCPHTTPDiscovery.request(config, method: method, params: params, capabilities: capabilities,
                                                 headers: headers, onNotification: onNotification)
    }

    func probe() async throws -> (version: String, advertisedCapabilities: [String: JSONValue]?) {
        switch try await ensureConnection() {
        case .legacy(_, let version):
            return (version, nil)
        case .modern(let server):
            return (MCPHTTPDiscovery.protocolVersion, server.capabilities)
        }
    }

    private func ensureConnection() async throws -> Connection {
        if let current = stdio, await current.isClosed(), stdio === current, case .modern = connection {
            self.stdio = nil
            connection = nil
            await current.disconnect()
        }
        if stdio == nil, case .modern(let server) = connection, server.expiresAt <= .now { connection = nil }
        if let connection { return connection }
        if let attempt { return try await attempt.task.value }
        let id = UUID()
        let task = Task {
            defer {
                if attempt?.id == id {
                    attempt = nil
                    pendingClient = nil
                }
            }
            let negotiated = try await negotiate()
            guard attempt?.id == id else { throw CancellationError() }
            connection = negotiated
            if case .modern(let server) = negotiated { startSubscription(server) }
            return negotiated
        }
        attempt = (id, task)
        return try await task.value
    }

    private func negotiate() async throws -> Connection {
        if config.transport == .http, let server = try await MCPHTTPDiscovery.probe(config) {
            try Task.checkCancellation()
            return .modern(server)
        }
        if config.transport == .stdio {
            let candidate = MCPModernStdio(transport: try makeTransport(), timeoutMs: config.timeoutMs)
            stdio = candidate
            do {
                if let server = try await candidate.probe() {
                    try Task.checkCancellation()
                    return .modern(server)
                }
            } catch {
                if stdio === candidate { stdio = nil }
                await candidate.disconnect()
                throw error
            }
            if stdio === candidate { stdio = nil }
            await candidate.disconnect()
        }
        try Task.checkCancellation()
        let transport = try makeTransport()
        let candidate = Client(name: "sloppy", version: "1.0.0", capabilities: .init())
        pendingClient = candidate
        do {
            let initialized = try await candidate.connect(transport: transport)
            try Task.checkCancellation()
            return .legacy(candidate, protocolVersion: initialized.protocolVersion)
        } catch {
            await candidate.disconnect()
            throw error
        }
    }

    func toolCatalogExpiry() -> ContinuousClock.Instant? { toolHeadersExpireAt }

    private func startSubscription(_ server: MCPHTTPDiscovery.Server) {
        guard config.transport == .http, subscription == nil else { return }
        var filter: [String: JSONValue] = [:]
        if config.exposeTools, server.capabilities["tools"]?.asObject?["listChanged"]?.asBool == true {
            filter["toolsListChanged"] = .bool(true)
        }
        if config.exposePrompts, server.capabilities["prompts"]?.asObject?["listChanged"]?.asBool == true {
            filter["promptsListChanged"] = .bool(true)
        }
        if config.exposeResources, server.capabilities["resources"]?.asObject?["listChanged"]?.asBool == true {
            filter["resourcesListChanged"] = .bool(true)
        }
        guard !filter.isEmpty else { return }
        let settings = config
        subscription = Task { [weak self] in
            var delay: Double = 1
            while self != nil, !Task.isCancelled {
                do {
                    try await MCPHTTPDiscovery.listen(settings, notifications: filter) { [weak self] packet in
                        guard let method = packet["method"]?.asString,
                              method == "notifications/tools/list_changed" || method == "notifications/subscriptions/acknowledged" else { return }
                        Task { await self?.invalidateTools() }
                    }
                    delay = 1
                } catch let failure as MCPRPCFailure where failure.code == -32601 {
                    return
                } catch {
                    delay = min(60, delay * 2)
                }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    private func invalidateTools() async {
        toolHeaders.removeAll()
        toolHeadersExpireAt = nil
        await catalogChanged()
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
                environment: config.environment,
                logger: logger
            )
        case .http:
            let endpoint = try MCPHTTPDiscovery.endpoint(for: config)
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
    private static let failedDiscoveryRetryInterval: TimeInterval = 30

    private var config: CoreConfig.MCP
    private let logger: Logging.Logger
    private var connections: [String: MCPServerConnection] = [:]
    private var dynamicToolsByID: [String: MCPDynamicTool] = [:]
    private var dynamicDiscoveryLoaded = false
    private var dynamicDiscoveryExpiresAt: ContinuousClock.Instant?
    private var discoveryConfigurationRevision = 0
    private var dynamicDiscoveryLastFailureAt: Date?
    private var toolTraitsByServer: [String: [String: ToolTraits]] = [:]

    static let verificationMetaKey = "sloppy/verification"
    static let verificationKinds: Set<String> = ["build", "test", "lint", "run", "screenshot"]

    init(config: CoreConfig.MCP, logger: Logging.Logger = Logging.Logger.sloppy(label: "sloppy.mcp")) {
        self.config = config
        self.logger = logger
    }

    func updateConfig(_ config: CoreConfig.MCP) async {
        let obsolete = connections.filter { id, connection in
            config.servers.first(where: { $0.id == id }) != connection.config
        }
        for id in obsolete.keys { connections.removeValue(forKey: id) }
        self.config = config
        self.toolTraitsByServer = [:]
        self.dynamicToolsByID = [:]
        self.dynamicDiscoveryLoaded = false
        self.discoveryConfigurationRevision += 1
        self.dynamicDiscoveryLastFailureAt = nil
        for connection in obsolete.values { await connection.disconnect() }
    }

    func disconnectAll() async {
        let disconnected = Array(connections.values)
        connections.removeAll()
        dynamicToolsByID.removeAll()
        invalidateDynamicCatalog()
        for connection in disconnected { await connection.disconnect() }
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

    func serverStatuses() async -> [MCPServerStatus] {
        var statuses: [MCPServerStatus] = []
        statuses.reserveCapacity(config.servers.count)

        for server in config.servers {
            guard server.enabled else {
                statuses.append(
                    MCPServerStatus(
                        id: server.id,
                        transport: server.transport.rawValue,
                        enabled: false,
                        connected: false,
                        exposeTools: server.exposeTools,
                        exposeResources: server.exposeResources,
                        exposePrompts: server.exposePrompts,
                        toolPrefix: server.toolPrefix,
                        message: "disabled"
                    )
                )
                continue
            }

            var probingConnection: MCPServerConnection?
            do {
                let connection = try connection(for: server.id)
                probingConnection = connection
                let probe = try await withDiscoveryTimeout(milliseconds: max(250, server.timeoutMs)) {
                    try await connection.probe()
                }
                statuses.append(
                    MCPServerStatus(
                        id: server.id,
                        transport: server.transport.rawValue,
                        enabled: true,
                        connected: true,
                        exposeTools: server.exposeTools,
                        exposeResources: server.exposeResources,
                        exposePrompts: server.exposePrompts,
                        toolPrefix: server.toolPrefix,
                        message: nil,
                        protocolVersion: probe.version,
                        advertisedCapabilities: probe.advertisedCapabilities
                    )
                )
            } catch {
                await probingConnection?.disconnect()
                statuses.append(
                    MCPServerStatus(
                        id: server.id,
                        transport: server.transport.rawValue,
                        enabled: true,
                        connected: false,
                        exposeTools: server.exposeTools,
                        exposeResources: server.exposeResources,
                        exposePrompts: server.exposePrompts,
                        toolPrefix: server.toolPrefix,
                        message: (error as? MCPRegistryError)?.errorDescription ?? String(describing: error)
                    )
                )
            }
        }

        return statuses
    }

    struct ToolTraits: Sendable, Equatable {
        var verificationKind: String?
        /// `nil` when the server does not say.
        var readOnly: Bool?
    }

    /// Verification kind declared for an MCP tool, from config or the tool's `_meta`; `nil` when none.
    func verificationKind(serverID: String, tool: String) async -> String? {
        await toolTraits(serverID: serverID, tool: tool).verificationKind
    }

    /// Traits of an MCP tool: configured (`verificationTools`, `readOnlyTools`) or declared by the server
    /// (`_meta["sloppy/verification"]`, `annotations.readOnlyHint`).
    func toolTraits(serverID: String, tool: String) async -> ToolTraits {
        let configuredKind = config.verificationTools["\(serverID):\(tool)"] ?? config.verificationTools[tool]
        let configuredReadOnly = config.readOnlyTools.contains("\(serverID):\(tool)") || config.readOnlyTools.contains(tool)
        if let configuredKind, Self.verificationKinds.contains(configuredKind) {
            return ToolTraits(verificationKind: configuredKind, readOnly: configuredReadOnly ? true : nil)
        }
        if configuredReadOnly { return ToolTraits(verificationKind: nil, readOnly: true) }

        if toolTraitsByServer[serverID] == nil {
            var traits: [String: ToolTraits] = [:]
            var cursor: String?
            for _ in 0..<5 {
                guard let page = try? await listTools(serverID: serverID, cursor: cursor) else { break }
                for listed in page.tools {
                    let kind = listed._meta?[Self.verificationMetaKey]?.stringValue
                    traits[listed.name] = ToolTraits(
                        verificationKind: kind.flatMap { Self.verificationKinds.contains($0) ? $0 : nil },
                        readOnly: listed.annotations.readOnlyHint
                    )
                }
                guard let next = page.nextCursor else { break }
                cursor = next
            }
            toolTraitsByServer[serverID] = traits
        }
        return toolTraitsByServer[serverID]?[tool] ?? ToolTraits(verificationKind: nil, readOnly: nil)
    }

    func listTools(serverID: String, cursor: String? = nil) async throws -> (tools: [MCP.Tool], nextCursor: String?) {
        let connection = try connection(for: serverID)
        return try await connection.listTools(cursor: cursor)
    }

    func callTool(serverID: String, name: String, arguments: [String: JSONValue], interaction: MCPToolInteraction? = nil) async throws -> MCPToolReply {
        let connection = try connection(for: serverID)
        return try await connection.callTool(name: name, arguments: arguments, interaction: interaction)
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
        let convertedArguments = arguments.mapValues { jsonValue -> String in
            switch jsonValue {
            case .string(let s): return s
            case .number(let n): return String(n)
            case .bool(let b): return String(b)
            case .array(let arr): return arr.description
            case .object(let obj): return obj.description
            case .null: return ""
            }
        }
        return try await connection.getPrompt(name: name, arguments: convertedArguments)
    }

    /// Read-only snapshot for accounting; measuring usage must not trigger discovery.
    func cachedDynamicTools() -> [MCPDynamicTool] { Array(dynamicToolsByID.values) }

    func dynamicDiscoveryIsComplete() -> Bool { dynamicDiscoveryLoaded }

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

    func invokeDynamicTool(toolID: String, arguments: [String: JSONValue], context: ToolContext? = nil) async throws -> ToolInvocationResult? {
        await refreshDynamicToolsIfNeeded()
        guard let dynamicTool = dynamicToolsByID[toolID] else {
            return nil
        }

        let interaction = await context?.mcpInteraction(serverID: dynamicTool.serverID, toolName: dynamicTool.toolName)
        let result = try await callTool(
            serverID: dynamicTool.serverID,
            name: dynamicTool.toolName,
            arguments: arguments, interaction: interaction
        )
        var fields: [String: JSONValue] = [
            "server": .string(dynamicTool.serverID),
            "tool": .string(dynamicTool.toolName),
            "isError": result.isError.map(JSONValue.bool) ?? .null,
            "content": .array(result.content.map(Self.jsonValue(from:)))
        ]
        fields["structuredContent"] = result.structuredContent
        let payload = JSONValue.object(fields)
        return ToolInvocationResult(
            tool: toolID,
            ok: result.isError != true,
            data: result.isError == true ? nil : payload,
            error: result.isError == true
                ? ToolErrorPayload(
                    code: "mcp_tool_error",
                    message: Self.mcpErrorMessage(
                        toolName: dynamicTool.toolName,
                        serverID: dynamicTool.serverID,
                        detail: Self.flattenText(from: result.content)
                    ),
                    retryable: false
                )
                : nil
        )
    }

    /// Keeps the server's own explanation: without it the model cannot tell a bad argument from a broken server.
    static func mcpErrorMessage(toolName: String, serverID: String, detail: String) -> String {
        let base = "MCP tool '\(toolName)' on server '\(serverID)' returned an error result."
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return "\(base) Server said: \(trimmed.count > 2_000 ? String(trimmed.prefix(2_000)) + "…" : trimmed)"
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

    func connection(for serverID: String) throws -> MCPServerConnection {
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
            logger: Logging.Logger.sloppy(label: "sloppy.mcp.\(serverID)"),
            catalogChanged: { [weak self] in await self?.invalidateDynamicCatalog() }
        )
        connections[serverID] = connection
        return connection
    }

    private func invalidateDynamicCatalog() {
        dynamicDiscoveryLoaded = false
        dynamicDiscoveryExpiresAt = nil
        dynamicDiscoveryLastFailureAt = nil
        discoveryConfigurationRevision += 1
        toolTraitsByServer.removeAll()
    }

    private func refreshDynamicToolsIfNeeded() async {
        if dynamicDiscoveryLoaded, dynamicDiscoveryExpiresAt.map({ $0 > .now }) ?? true {
            return
        }
        if let dynamicDiscoveryLastFailureAt,
           Date().timeIntervalSince(dynamicDiscoveryLastFailureAt) < Self.failedDiscoveryRetryInterval {
            return
        }

        let configurationRevision = discoveryConfigurationRevision
        var discovered: [String: MCPDynamicTool] = [:]
        var failedServers: [String] = []
        var expiresAt: ContinuousClock.Instant?
        for server in config.servers where server.enabled && server.exposeTools {
            do {
                let tools = try await withDiscoveryTimeout(milliseconds: max(250, server.timeoutMs)) {
                    var tools: [MCP.Tool] = []
                    var cursor: String?
                    var seenCursors = Set<String>()
                    repeat {
                        let page = try await self.listTools(serverID: server.id, cursor: cursor)
                        tools += page.tools
                        cursor = page.nextCursor
                        if let cursor, !seenCursors.insert(cursor).inserted || seenCursors.count > 1_000 {
                            throw MCPRegistryError.invalidResult("MCP tools/list pagination did not terminate")
                        }
                    } while cursor != nil
                    return tools
                }
                if let expiry = await connections[server.id]?.toolCatalogExpiry() {
                    expiresAt = min(expiresAt ?? expiry, expiry)
                }
                for tool in tools {
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
                        inputSchema: Self.jsonValue(from: tool.inputSchema),
                        readOnlyHint: tool.annotations.readOnlyHint == true
                    )
                }
            } catch {
                guard configurationRevision == discoveryConfigurationRevision else { return }
                failedServers.append(server.id)
                if let failedConnection = connections.removeValue(forKey: server.id) {
                    await failedConnection.disconnect()
                }
                logger.warning(
                    "Failed to discover MCP tools for server \(server.id): \(String(describing: error))"
                )
            }
        }
        // A config update may have invalidated this discovery while network calls suspended the actor.
        guard configurationRevision == discoveryConfigurationRevision else { return }
        dynamicToolsByID = discovered
        dynamicDiscoveryLoaded = failedServers.isEmpty
        dynamicDiscoveryExpiresAt = expiresAt
        dynamicDiscoveryLastFailureAt = failedServers.isEmpty ? nil : Date()
    }

    private func withDiscoveryTimeout<T: Sendable>(
        milliseconds: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let box = DiscoveryTimeoutBox<T>()
        return try await withTaskCancellationHandler {
            try await withPlatformCheckedThrowingContinuation { continuation in
                box.setContinuation(continuation)
                let operationTask = Task {
                    do {
                        let value = try await operation()
                        box.resume(.success(value))
                    } catch {
                        box.resume(.failure(error))
                    }
                }
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(max(1, milliseconds)) * 1_000_000)
                        operationTask.cancel()
                        box.resume(.failure(MCPRegistryError.invalidResult("Timed out while discovering MCP tools.")))
                    } catch {
                        box.resume(.failure(error))
                    }
                }
                box.setTasks([operationTask, timeoutTask])
            }
        } onCancel: {
            box.cancel()
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
            case .text(let text, _, _):
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
        var dict: [String: JSONValue] = [
            "name": .string(resource.name),
            "uri": .string(resource.uri)
        ]
        if let title = resource.title {
            dict["title"] = .string(title)
        }
        if let description = resource.description {
            dict["description"] = .string(description)
        }
        if let mimeType = resource.mimeType {
            dict["mimeType"] = .string(mimeType)
        }
        var annotationsDict: [String: JSONValue] = [:]
        if let audience = resource.annotations?.audience {
            annotationsDict["audience"] = .array(audience.map { .string($0.rawValue) })
        }
        if let priority = resource.annotations?.priority {
            annotationsDict["priority"] = .number(priority)
        }
        if let lastModified = resource.annotations?.lastModified {
            annotationsDict["lastModified"] = .string(lastModified)
        }
        dict["annotations"] = .object(annotationsDict)
        if let meta = resource._meta {
            dict["_meta"] = jsonValue(from: meta)
        }
        return .object(dict)
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

    static func jsonValue(from content: MCP.Tool.Content) -> JSONValue {
        switch content {
        case .text(let text, _, _):
            return .object([
                "type": .string("text"),
                "text": .string(text)
            ])
        case .image(let data, let mimeType, _, _):
            return .object([
                "type": .string("image"),
                "data": .string(data),
                "mimeType": .string(mimeType)
            ])
        case .audio(let data, let mimeType, _, _):
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

extension MCPClientRegistry: MCPToolDiscovering {}
