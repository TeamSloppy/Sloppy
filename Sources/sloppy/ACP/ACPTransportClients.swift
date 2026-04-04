import ACP
import ACPHTTP
import ACPModel
import Foundation

protocol ACPTransportClient: Sendable {
    func setDelegate(_ delegate: ClientDelegate?) async
    func notificationsStream() async -> AsyncStream<JSONRPCNotification>
    func connect(
        workingDirectory: String,
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo,
        timeout: TimeInterval?
    ) async throws -> InitializeResponse
    func newSession(workingDirectory: String, timeout: TimeInterval?) async throws -> NewSessionResponse
    func loadSession(sessionId: SessionId, cwd: String?) async throws -> LoadSessionResponse
    func sendPrompt(sessionId: SessionId, content: [ContentBlock]) async throws -> SessionPromptResponse
    func cancelSession(sessionId: SessionId) async throws
    func terminate() async
}

struct ACPClientFactory: Sendable {
    typealias Builder = @Sendable (CoreConfig.ACP.Target) throws -> any ACPTransportClient

    let build: Builder

    static let live = ACPClientFactory { target in
        switch target.transport {
        case .stdio:
            return LocalProcessACPClient(
                command: target.command,
                arguments: target.arguments,
                environment: target.environment
            )
        case .ssh:
            return try SSHProcessACPClient(target: target)
        case .websocket:
            return try WebSocketACPClient(target: target)
        }
    }
}

actor LocalProcessACPClient: ACPTransportClient {
    private let client = Client()
    private let command: String
    private let arguments: [String]
    private let environment: [String: String]

    init(command: String, arguments: [String], environment: [String: String]) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
    }

    func setDelegate(_ delegate: ClientDelegate?) async {
        await client.setDelegate(delegate)
    }

    func notificationsStream() async -> AsyncStream<JSONRPCNotification> {
        await client.notifications
    }

    func connect(
        workingDirectory: String,
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo,
        timeout: TimeInterval?
    ) async throws -> InitializeResponse {
        try await client.launch(
            agentPath: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
        return try await client.initialize(
            capabilities: capabilities,
            clientInfo: clientInfo,
            timeout: timeout
        )
    }

    func newSession(workingDirectory: String, timeout: TimeInterval?) async throws -> NewSessionResponse {
        try await client.newSession(workingDirectory: workingDirectory, timeout: timeout)
    }

    func loadSession(sessionId: SessionId, cwd: String?) async throws -> LoadSessionResponse {
        try await client.loadSession(sessionId: sessionId, cwd: cwd)
    }

    func sendPrompt(sessionId: SessionId, content: [ContentBlock]) async throws -> SessionPromptResponse {
        try await client.sendPrompt(sessionId: sessionId, content: content)
    }

    func cancelSession(sessionId: SessionId) async throws {
        try await client.cancelSession(sessionId: sessionId)
    }

    func terminate() async {
        await client.terminate()
    }
}

actor SSHProcessACPClient: ACPTransportClient {
    private let inner: LocalProcessACPClient

    init(target: CoreConfig.ACP.Target) throws {
        let command = "ssh"
        let arguments = try Self.buildArguments(target: target)
        self.inner = LocalProcessACPClient(
            command: command,
            arguments: arguments,
            environment: [:]
        )
    }

    private static func buildArguments(target: CoreConfig.ACP.Target) throws -> [String] {
        let host = (target.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteCommand = (target.remoteCommand ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw ACPSessionManager.ACPError.invalidTarget("ACP SSH target '\(target.id)' requires a host.")
        }
        guard !remoteCommand.isEmpty else {
            throw ACPSessionManager.ACPError.invalidTarget("ACP SSH target '\(target.id)' requires a remoteCommand.")
        }

        var arguments: [String] = []
        if let port = target.port {
            arguments += ["-p", String(port)]
        }
        if let identityFile = target.identityFile?.trimmingCharacters(in: .whitespacesAndNewlines), !identityFile.isEmpty {
            arguments += ["-i", identityFile]
        }

        let strictValue = target.strictHostKeyChecking ? "yes" : "no"
        arguments += ["-o", "StrictHostKeyChecking=\(strictValue)"]

        let destination: String
        if let user = target.user?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty {
            destination = "\(user)@\(host)"
        } else {
            destination = host
        }

        arguments.append(destination)
        arguments.append(remoteCommand)
        return arguments
    }

    func setDelegate(_ delegate: ClientDelegate?) async {
        await inner.setDelegate(delegate)
    }

    func notificationsStream() async -> AsyncStream<JSONRPCNotification> {
        await inner.notificationsStream()
    }

    func connect(
        workingDirectory: String,
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo,
        timeout: TimeInterval?
    ) async throws -> InitializeResponse {
        try await inner.connect(
            workingDirectory: workingDirectory,
            capabilities: capabilities,
            clientInfo: clientInfo,
            timeout: timeout
        )
    }

    func newSession(workingDirectory: String, timeout: TimeInterval?) async throws -> NewSessionResponse {
        try await inner.newSession(workingDirectory: workingDirectory, timeout: timeout)
    }

    func loadSession(sessionId: SessionId, cwd: String?) async throws -> LoadSessionResponse {
        try await inner.loadSession(sessionId: sessionId, cwd: cwd)
    }

    func sendPrompt(sessionId: SessionId, content: [ContentBlock]) async throws -> SessionPromptResponse {
        try await inner.sendPrompt(sessionId: sessionId, content: content)
    }

    func cancelSession(sessionId: SessionId) async throws {
        try await inner.cancelSession(sessionId: sessionId)
    }

    func terminate() async {
        await inner.terminate()
    }
}

actor WebSocketACPClient: ACPTransportClient {
    private let transport: WebSocketTransport
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var pendingRequests: [RequestId: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var nextRequestId = 1
    private weak var delegate: ClientDelegate?
    private var receiverTask: Task<Void, Never>?
    private var isConnected = false
    private enum TimeoutError: Error {
        case requestTimedOut
    }

    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let notificationStream: AsyncStream<JSONRPCNotification>

    init(target: CoreConfig.ACP.Target) throws {
        let rawURL = (target.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawURL), !rawURL.isEmpty else {
            throw ACPSessionManager.ACPError.invalidTarget("ACP WebSocket target '\(target.id)' requires a valid url.")
        }

        let configuration = URLSessionConfiguration.default
        if !target.headers.isEmpty {
            configuration.httpAdditionalHeaders = target.headers
        }
        let session = URLSession(configuration: configuration)
        self.session = session
        self.transport = WebSocketTransport(url: url, session: session)
        self.encoder.outputFormatting = [.withoutEscapingSlashes]

        var continuation: AsyncStream<JSONRPCNotification>.Continuation!
        self.notificationStream = AsyncStream { cont in
            continuation = cont
        }
        self.notificationContinuation = continuation
    }

    func setDelegate(_ delegate: ClientDelegate?) async {
        self.delegate = delegate
    }

    func notificationsStream() async -> AsyncStream<JSONRPCNotification> {
        notificationStream
    }

    func connect(
        workingDirectory _: String,
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo,
        timeout: TimeInterval?
    ) async throws -> InitializeResponse {
        guard !isConnected else {
            throw ClientError.transportError("Already connected")
        }

        try await transport.connect()
        isConnected = true
        receiverTask = Task { [weak self] in
            guard let self else { return }
            for await data in transport.messages {
                await self.handleMessage(data)
            }
            await self.handleConnectionClosed()
        }

        return try await initialize(
            capabilities: capabilities,
            clientInfo: clientInfo,
            timeout: timeout
        )
    }

    func newSession(workingDirectory: String, timeout: TimeInterval?) async throws -> NewSessionResponse {
        let request = NewSessionRequest(cwd: workingDirectory)
        let response = try await sendRequest(method: "session/new", params: request, timeout: timeout)
        return try decodeResult(response, as: NewSessionResponse.self)
    }

    func loadSession(sessionId: SessionId, cwd: String?) async throws -> LoadSessionResponse {
        let request = LoadSessionRequest(sessionId: sessionId, cwd: cwd, mcpServers: nil)
        let response = try await sendRequest(method: "session/load", params: request, timeout: nil)

        if let error = response.error {
            if isSessionAlreadyActive(error) {
                return LoadSessionResponse(sessionId: sessionId, modes: nil, models: nil, configOptions: nil)
            }
            throw ClientError.agentError(error)
        }

        let extractedSessionId = extractSessionId(from: response.result)
        guard let result = response.result else {
            return LoadSessionResponse(
                sessionId: extractedSessionId ?? sessionId,
                modes: nil,
                models: nil,
                configOptions: nil
            )
        }

        let data = try encoder.encode(result)
        if let payload = try? decoder.decode(LoadSessionResponsePayload.self, from: data) {
            return LoadSessionResponse(
                sessionId: payload.sessionId ?? extractedSessionId ?? sessionId,
                modes: payload.modes,
                models: payload.models,
                configOptions: payload.configOptions
            )
        }
        if let decoded = try? decoder.decode(LoadSessionResponse.self, from: data) {
            return decoded
        }

        return LoadSessionResponse(
            sessionId: extractedSessionId ?? sessionId,
            modes: nil,
            models: nil,
            configOptions: nil
        )
    }

    func sendPrompt(sessionId: SessionId, content: [ContentBlock]) async throws -> SessionPromptResponse {
        let request = SessionPromptRequest(sessionId: sessionId, prompt: content)
        let response = try await sendRequest(method: "session/prompt", params: request, timeout: nil)
        return try decodeResult(response, as: SessionPromptResponse.self)
    }

    func cancelSession(sessionId: SessionId) async throws {
        struct CancelParams: Encodable {
            let sessionId: SessionId
        }

        try await sendNotification(method: "session/cancel", params: CancelParams(sessionId: sessionId))
    }

    func terminate() async {
        receiverTask?.cancel()
        receiverTask = nil
        isConnected = false
        await transport.close()
        session.invalidateAndCancel()

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: ClientError.connectionClosed)
        }
        pendingRequests.removeAll()
        notificationContinuation.finish()
    }

    private func initialize(
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo,
        timeout: TimeInterval?
    ) async throws -> InitializeResponse {
        let request = InitializeRequest(
            protocolVersion: 1,
            clientCapabilities: capabilities,
            clientInfo: clientInfo
        )
        let response = try await sendRequest(method: "initialize", params: request, timeout: timeout)
        return try decodeResult(response, as: InitializeResponse.self)
    }

    private func sendRequest<T: Encodable>(
        method: String,
        params: T,
        timeout: TimeInterval?
    ) async throws -> JSONRPCResponse {
        guard isConnected else {
            throw ClientError.connectionClosed
        }

        let requestId = RequestId.number(nextRequestId)
        nextRequestId += 1

        let paramsData = try encoder.encode(params)
        let paramsValue = try decoder.decode(AnyCodable.self, from: paramsData)
        let request = JSONRPCRequest(id: requestId, method: method, params: paramsValue)

        return try await withRequestTimeout(seconds: timeout, requestId: requestId) {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await self.registerRequest(id: requestId, continuation: continuation)
                    do {
                        try await self.writeMessage(request)
                    } catch {
                        await self.failRequest(id: requestId, error: error)
                    }
                }
            }
        }
    }

    private func sendNotification<T: Encodable>(method: String, params: T) async throws {
        guard isConnected else {
            throw ClientError.connectionClosed
        }

        let paramsData = try encoder.encode(params)
        let paramsValue = try decoder.decode(AnyCodable.self, from: paramsData)
        let notification = JSONRPCNotification(method: method, params: paramsValue)
        try await writeMessage(notification)
    }

    private func withRequestTimeout<T: Sendable>(
        seconds: TimeInterval?,
        requestId: RequestId,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        guard let seconds else {
            return try await operation()
        }

        do {
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    throw TimeoutError.requestTimedOut
                }

                guard let result = try await group.next() else {
                    throw TimeoutError.requestTimedOut
                }
                group.cancelAll()
                return result
            }
        } catch is TimeoutError {
            pendingRequests.removeValue(forKey: requestId)
            throw ClientError.requestTimeout
        }
    }

    private func registerRequest(
        id: RequestId,
        continuation: CheckedContinuation<JSONRPCResponse, Error>
    ) async {
        pendingRequests[id] = continuation
    }

    private func failRequest(id: RequestId, error: Error) async {
        if let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(throwing: error)
        }
    }

    private func writeMessage<T: Encodable>(_ message: T) async throws {
        let data = try encoder.encode(message)
        try await transport.send(data)
    }

    private func handleMessage(_ data: Data) async {
        do {
            let message = try decoder.decode(Message.self, from: data)
            switch message {
            case .response(let response):
                if let continuation = pendingRequests.removeValue(forKey: response.id) {
                    continuation.resume(returning: response)
                }
            case .notification(let notification):
                notificationContinuation.yield(notification)
            case .request(let request):
                await handleIncomingRequest(request)
            }
        } catch {
            // Ignore malformed frames from remote ACP peers.
        }
    }

    private func handleIncomingRequest(_ request: JSONRPCRequest) async {
        do {
            let result = try await routeRequest(request)
            try await sendResponse(JSONRPCResponse(id: request.id, result: result, error: nil))
        } catch let error as ClientError {
            let code: Int
            switch error {
            case .invalidResponse:
                code = -32601
            default:
                code = -32603
            }
            let response = JSONRPCResponse(
                id: request.id,
                result: nil,
                error: JSONRPCError(code: code, message: error.localizedDescription, data: nil)
            )
            try? await sendResponse(response)
        } catch {
            let response = JSONRPCResponse(
                id: request.id,
                result: nil,
                error: JSONRPCError(code: -32603, message: error.localizedDescription, data: nil)
            )
            try? await sendResponse(response)
        }
    }

    private func sendResponse(_ response: JSONRPCResponse) async throws {
        try await writeMessage(response)
    }

    private func routeRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }
        guard let params = request.params else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        switch request.method {
        case "fs/read_text_file":
            let decoded = try decoder.decode(ReadTextFileRequest.self, from: data)
            let response = try await delegate.handleFileReadRequest(
                decoded.path,
                sessionId: decoded.sessionId,
                line: decoded.line,
                limit: decoded.limit
            )
            return try encodeAny(response)
        case "fs/write_text_file":
            let decoded = try decoder.decode(WriteTextFileRequest.self, from: data)
            let response = try await delegate.handleFileWriteRequest(
                decoded.path,
                content: decoded.content,
                sessionId: decoded.sessionId
            )
            return try encodeAny(response)
        case "terminal/create":
            let decoded = try decoder.decode(CreateTerminalRequest.self, from: data)
            let response = try await delegate.handleTerminalCreate(
                command: decoded.command,
                sessionId: decoded.sessionId,
                args: decoded.args,
                cwd: decoded.cwd,
                env: decoded.env,
                outputByteLimit: decoded.outputByteLimit
            )
            return try encodeAny(response)
        case "terminal/output":
            let decoded = try decoder.decode(TerminalOutputRequest.self, from: data)
            return try encodeAny(try await delegate.handleTerminalOutput(terminalId: decoded.terminalId, sessionId: decoded.sessionId))
        case "terminal/wait_for_exit":
            let decoded = try decoder.decode(WaitForExitRequest.self, from: data)
            return try encodeAny(try await delegate.handleTerminalWaitForExit(terminalId: decoded.terminalId, sessionId: decoded.sessionId))
        case "terminal/kill":
            let decoded = try decoder.decode(KillTerminalRequest.self, from: data)
            return try encodeAny(try await delegate.handleTerminalKill(terminalId: decoded.terminalId, sessionId: decoded.sessionId))
        case "terminal/release":
            let decoded = try decoder.decode(ReleaseTerminalRequest.self, from: data)
            return try encodeAny(try await delegate.handleTerminalRelease(terminalId: decoded.terminalId, sessionId: decoded.sessionId))
        case "request_permission", "session/request_permission":
            let decoded = try decoder.decode(RequestPermissionRequest.self, from: data)
            return try encodeAny(try await delegate.handlePermissionRequest(request: decoded))
        default:
            throw ClientError.invalidResponse
        }
    }

    private func encodeAny<T: Encodable>(_ value: T) throws -> AnyCodable {
        let data = try encoder.encode(value)
        return try decoder.decode(AnyCodable.self, from: data)
    }

    private func decodeResult<T: Decodable>(_ response: JSONRPCResponse, as type: T.Type) throws -> T {
        if let error = response.error {
            throw ClientError.agentError(error)
        }
        guard let result = response.result else {
            throw ClientError.invalidResponse
        }
        let data = try encoder.encode(result)
        return try decoder.decode(type, from: data)
    }

    private func handleConnectionClosed() {
        guard isConnected else {
            return
        }
        isConnected = false
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: ClientError.connectionClosed)
        }
        pendingRequests.removeAll()
        notificationContinuation.finish()
    }

    private func extractSessionId(from result: AnyCodable?) -> SessionId? {
        guard let value = result?.value else {
            return nil
        }
        if let dict = value as? [String: Any],
           let id = dict["sessionId"] as? String ?? dict["session_id"] as? String {
            return SessionId(id)
        }
        if let dict = value as? [String: AnyCodable],
           let id = dict["sessionId"]?.value as? String ?? dict["session_id"]?.value as? String {
            return SessionId(id)
        }
        return nil
    }

    private func isSessionAlreadyActive(_ error: JSONRPCError) -> Bool {
        let message = error.message.lowercased()
        if message.contains("already active") || message.contains("already started") || message.contains("already exists") {
            return true
        }
        if let dataString = error.data?.value as? String {
            let lower = dataString.lowercased()
            if lower.contains("already active") || lower.contains("already started") || lower.contains("already exists") {
                return true
            }
        }
        return false
    }

    private struct LoadSessionResponsePayload: Decodable {
        let sessionId: SessionId?
        let modes: ModesInfo?
        let models: ModelsInfo?
        let configOptions: [SessionConfigOption]?
    }
}
