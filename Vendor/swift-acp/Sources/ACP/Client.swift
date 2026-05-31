//
//  Client.swift
//  ACP
//
//  Actor-based ACP agent subprocess manager
//

import Foundation
import ACPModel

// MARK: - Debug Message Types

public enum DebugMessageDirection: Sendable {
    case outgoing
    case incoming
}

public struct DebugMessage: Sendable {
    public let direction: DebugMessageDirection
    public let timestamp: Date
    public let rawData: Data
    public let method: String?

    public var jsonString: String? {
        String(data: rawData, encoding: .utf8)
    }
}

public actor Client {
    // MARK: - Properties

    private let logger = Logger.forCategory("Client")

    private let processManager: ACPProcessManager
    private let requestRouter: ACPRequestRouter
    private let errorHandler: ErrorHandler

    private var pendingRequests: [RequestId: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var nextRequestId: Int = 1

    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let notificationStream: AsyncStream<JSONRPCNotification>

    private var debugContinuation: AsyncStream<DebugMessage>.Continuation?
    private var debugStream: AsyncStream<DebugMessage>?

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public weak var delegate: ClientDelegate?

    private enum TimeoutError: Error {
        case requestTimedOut
    }

    // MARK: - Initialization

    public init() {
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        var continuation: AsyncStream<JSONRPCNotification>.Continuation!
        notificationStream = AsyncStream { cont in
            continuation = cont
        }
        notificationContinuation = continuation

        processManager = ACPProcessManager(encoder: encoder, decoder: decoder)
        requestRouter = ACPRequestRouter(encoder: encoder, decoder: decoder)
        errorHandler = ErrorHandler(encoder: encoder)

        Task {
            await processManager.setDataReceivedCallback { [weak self] data in
                await self?.handleMessage(data: data)
            }
            await processManager.setTerminationCallback { [weak self] exitCode in
                await self?.handleTermination(exitCode: exitCode)
            }
        }
    }

    // MARK: - Public API

    public var notifications: AsyncStream<JSONRPCNotification> {
        notificationStream
    }

    public var debugMessages: AsyncStream<DebugMessage>? {
        debugStream
    }

    public func enableDebugStream() {
        guard debugStream == nil else { return }
        var continuation: AsyncStream<DebugMessage>.Continuation!
        debugStream = AsyncStream { cont in
            continuation = cont
        }
        debugContinuation = continuation
    }

    public func disableDebugStream() {
        debugContinuation?.finish()
        debugContinuation = nil
        debugStream = nil
    }

    public func setDelegate(_ delegate: ClientDelegate?) {
        self.delegate = delegate
        Task {
            await requestRouter.setDelegate(delegate)
        }
    }

    public func launch(
        agentPath: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) async throws {
        try await processManager.launch(
            agentPath: agentPath,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
    }

    public func initialize(
        protocolVersion: Int = 1,
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> InitializeResponse {
        let info = clientInfo ?? ClientInfo(
            name: "ACP",
            title: "ACP Client",
            version: "1.0.0"
        )

        let request = InitializeRequest(
            protocolVersion: protocolVersion,
            clientCapabilities: capabilities,
            clientInfo: info
        )

        let response = try await sendRequest(method: "initialize", params: request, timeout: timeout)

        guard let result = response.result else {
            if let error = response.error {
                throw ClientError.agentError(error)
            }
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(InitializeResponse.self, from: data)
    }

    public func newSession(
        workingDirectory: String,
        mcpServers: [MCPServerConfig] = [],
        timeout: TimeInterval? = nil
    ) async throws -> NewSessionResponse {
        let request = NewSessionRequest(
            cwd: workingDirectory,
            mcpServers: mcpServers
        )

        let response = try await sendRequest(method: "session/new", params: request, timeout: timeout)

        guard let result = response.result else {
            if let error = response.error {
                throw ClientError.agentError(error)
            }
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(NewSessionResponse.self, from: data)
    }

    public func sendPrompt(
        sessionId: SessionId,
        content: [ContentBlock]
    ) async throws -> SessionPromptResponse {
        let request = SessionPromptRequest(
            sessionId: sessionId,
            prompt: content
        )

        let response = try await sendRequest(method: "session/prompt", params: request, timeout: nil)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(SessionPromptResponse.self, from: data)
    }

    public func authenticate(
        authMethodId: String,
        credentials: [String: String]? = nil
    ) async throws -> AuthenticateResponse {
        let request = AuthenticateRequest(
            methodId: authMethodId,
            credentials: credentials
        )

        let response = try await sendRequest(method: "authenticate", params: request, timeout: nil)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        if response.result == nil || (response.result?.value is NSNull) {
            return AuthenticateResponse(success: true, error: nil)
        }

        if let dict = response.result?.value as? [String: Any], dict.isEmpty {
            return AuthenticateResponse(success: true, error: nil)
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        do {
            let data = try encoder.encode(result)
            return try decoder.decode(AuthenticateResponse.self, from: data)
        } catch {
            return AuthenticateResponse(success: true, error: nil)
        }
    }

    public func setMode(
        sessionId: SessionId,
        modeId: String
    ) async throws -> SetModeResponse {
        let request = SetModeRequest(
            sessionId: sessionId,
            modeId: modeId
        )

        let response = try await sendRequest(method: "session/set_mode", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        return SetModeResponse(success: true)
    }

    public func setModel(
        sessionId: SessionId,
        modelId: String
    ) async throws -> SetModelResponse {
        let request = SetModelRequest(
            sessionId: sessionId,
            modelId: modelId
        )

        let response = try await sendRequest(method: "session/set_model", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        return SetModelResponse(success: true)
    }

    public func setConfigOption(
        sessionId: SessionId,
        configId: SessionConfigId,
        value: SessionConfigValueId
    ) async throws -> SetSessionConfigOptionResponse {
        return try await setConfigOption(
            sessionId: sessionId,
            configId: configId,
            value: .select(value)
        )
    }

    public func setConfigOption(
        sessionId: SessionId,
        configId: SessionConfigId,
        value: Bool
    ) async throws -> SetSessionConfigOptionResponse {
        return try await setConfigOption(
            sessionId: sessionId,
            configId: configId,
            value: .boolean(value)
        )
    }

    public func setConfigOption(
        sessionId: SessionId,
        configId: SessionConfigId,
        value: SessionConfigOptionValue
    ) async throws -> SetSessionConfigOptionResponse {
        let request = SetSessionConfigOptionRequest(
            sessionId: sessionId,
            configId: configId,
            value: value
        )

        let response = try await sendRequest(method: "session/set_config_option", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(SetSessionConfigOptionResponse.self, from: data)
    }

    public func cancelSession(sessionId: SessionId) async throws {
        try await sendCancelNotification(sessionId: sessionId)
    }

    public func loadSession(
        sessionId: SessionId,
        cwd: String? = nil,
        mcpServers: [MCPServerConfig]? = nil
    ) async throws -> LoadSessionResponse {
        let request = LoadSessionRequest(
            sessionId: sessionId,
            cwd: cwd,
            mcpServers: mcpServers
        )

        let response = try await sendRequest(method: "session/load", params: request)

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

    public func listSessions(
        cwd: String? = nil,
        cursor: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ListSessionsResponse {
        let request = ListSessionsRequest(cwd: cwd, cursor: cursor)
        let response = try await sendRequest(method: "session/list", params: request, timeout: timeout)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(ListSessionsResponse.self, from: data)
    }

    private struct LoadSessionResponsePayload: Decodable {
        let sessionId: SessionId?
        let modes: ModesInfo?
        let models: ModelsInfo?
        let configOptions: [SessionConfigOption]?
    }

    private func extractSessionId(from result: AnyCodable?) -> SessionId? {
        guard let value = result?.value else { return nil }

        if let dict = value as? [String: Any] {
            if let id = dict["sessionId"] as? String ?? dict["session_id"] as? String {
                return SessionId(id)
            }
        }

        if let dict = value as? [String: AnyCodable] {
            if let id = dict["sessionId"]?.value as? String ?? dict["session_id"]?.value as? String {
                return SessionId(id)
            }
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

        if let data = error.data?.value as? [String: Any],
           let details = data["details"] as? String {
            let lower = details.lowercased()
            if lower.contains("already active") || lower.contains("already started") || lower.contains("already exists") {
                return true
            }
        }

        return false
    }

    public func sendRequest<T: Encodable>(
        method: String,
        params: T,
        timeout: TimeInterval? = nil
    ) async throws -> JSONRPCResponse {
        guard await processManager.isRunning() else {
            throw ClientError.processNotRunning
        }

        let requestId = RequestId.number(nextRequestId)
        nextRequestId += 1

        let paramsData = try encoder.encode(params)
        let paramsValue = try decoder.decode(AnyCodable.self, from: paramsData)

        let request = JSONRPCRequest(
            id: requestId,
            method: method,
            params: paramsValue
        )
        return try await withRequestTimeout(seconds: timeout, requestId: requestId) {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await self.registerRequest(id: requestId, continuation: continuation)

                    do {
                        try await self.writeMessageWithDebug(request, method: method)
                    } catch {
                        await self.failRequest(id: requestId, error: error)
                    }
                }
            }
        }
    }

    private func withRequestTimeout<T>(
        seconds: TimeInterval?,
        requestId: RequestId,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        guard let seconds = seconds else {
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

    public func sendCancelNotification(sessionId: SessionId) async throws {
        guard await processManager.isRunning() else {
            throw ClientError.processNotRunning
        }

        struct CancelParams: Encodable {
            let sessionId: SessionId
        }

        let params = CancelParams(sessionId: sessionId)
        let paramsData = try encoder.encode(params)
        let paramsValue = try decoder.decode(AnyCodable.self, from: paramsData)

        let notification = JSONRPCNotification(
            method: "session/cancel",
            params: paramsValue
        )

        try await writeMessageWithDebug(notification, method: "session/cancel")
    }

    public func terminate() async {
        await processManager.terminate()

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: ClientError.processNotRunning)
        }
        pendingRequests.removeAll()

        notificationContinuation.finish()
        debugContinuation?.finish()
        debugContinuation = nil
        debugStream = nil
    }

    // MARK: - Private Methods

    private func handleMessage(data: Data) async {
        guard let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if let continuation = debugContinuation {
            let method = extractMethod(from: data)
            continuation.yield(DebugMessage(
                direction: .incoming,
                timestamp: Date(),
                rawData: data,
                method: method
            ))
        }

        do {
            let message = try decoder.decode(Message.self, from: data)

            switch message {
            case .response(let response):
                await handleResponse(response)

            case .notification(let notification):
                notificationContinuation.yield(notification)

            case .request(let request):
                await handleIncomingRequest(request)
            }
        } catch {
            if let text = String(data: data, encoding: .utf8) {
                logger.warning("Failed to parse message: \(error.localizedDescription)\nData: \(text.prefix(500))")
            } else {
                logger.warning("Failed to parse message: \(error.localizedDescription)")
            }
        }
    }

    private func handleResponse(_ response: JSONRPCResponse) async {
        guard let continuation = pendingRequests.removeValue(forKey: response.id) else {
            let stillPending = pendingRequests.keys.map { String(describing: $0) }
            logger.warning("Received response for unknown request id=\(response.id), no pending request found. Pending: \(stillPending)")
            return
        }
        continuation.resume(returning: response)
    }

    private func handleIncomingRequest(_ request: JSONRPCRequest) async {
        do {
            let response = try await requestRouter.routeRequest(request)
            try await sendSuccessResponse(requestId: request.id, result: response)
        } catch {
            logger.error("Error handling request \(request.method): \(error.localizedDescription)")

            if let clientError = error as? ClientError, case .invalidResponse = clientError {
                try? await sendErrorResponse(
                    requestId: request.id,
                    code: -32601,
                    message: "Method not found: \(request.method)"
                )
            } else {
                try? await sendErrorResponse(
                    requestId: request.id,
                    code: -32603,
                    message: "Internal error: \(error.localizedDescription)"
                )
            }
        }
    }

    private func sendSuccessResponse(requestId: RequestId, result: AnyCodable) async throws {
        let response = JSONRPCResponse(id: requestId, result: result, error: nil)
        try await writeMessageWithDebug(response, method: nil)
    }

    private func sendErrorResponse(requestId: RequestId, code: Int, message: String) async throws {
        let errorResponse = try await errorHandler.createErrorResponse(
            requestId: requestId,
            code: code,
            message: message
        )
        try await writeMessageWithDebug(errorResponse, method: nil)
    }

    private func handleTermination(exitCode: Int32) async {
        logger.info("Agent process terminated with code: \(exitCode)")

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: ClientError.processFailed(exitCode))
        }
        pendingRequests.removeAll()

        notificationContinuation.finish()
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

    private func extractMethod(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["method"] as? String
    }

    private func writeMessageWithDebug<T: Encodable>(_ message: T, method: String? = nil) async throws {
        if let continuation = debugContinuation {
            if let data = try? encoder.encode(message) {
                continuation.yield(DebugMessage(
                    direction: .outgoing,
                    timestamp: Date(),
                    rawData: data,
                    method: method
                ))
            }
        }
        try await processManager.writeMessage(message)
    }
}

// MARK: - Typealiases for backward compatibility

@available(*, deprecated, renamed: "Client")
public typealias ACPClient = Client
