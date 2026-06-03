//
//  Agent.swift
//  ACP
//
//  Agent runtime for building ACP-compliant agents (server mode)
//

import ACPModel
import Foundation

/// Protocol for handling agent operations
public protocol AgentDelegate: AnyObject, Sendable {
    /// Handle initialization request from client
    func handleInitialize(_ request: InitializeRequest) async throws -> InitializeResponse

    /// Handle authorization request
    func handleAuthorization(_ request: AuthorizationRequest) async throws -> AuthorizationResponse

    /// Handle authentication request
    func handleAuthenticate(_ request: AuthenticateRequest) async throws -> AuthenticateResponse

    /// Handle new session request
    func handleNewSession(_ request: NewSessionRequest) async throws -> NewSessionResponse

    /// Handle prompt request - the main interaction point
    func handlePrompt(_ request: SessionPromptRequest) async throws -> SessionPromptResponse

    /// Handle session cancellation
    func handleCancel(_ sessionId: SessionId) async throws

    /// Handle session load request
    func handleLoadSession(_ request: LoadSessionRequest) async throws -> LoadSessionResponse

    /// Handle session listing request
    func handleListSessions(_ request: ListSessionsRequest) async throws -> ListSessionsResponse

    /// Handle model selection request
    func handleSetModel(_ request: SetModelRequest) async throws -> SetModelResponse
}

/// Default implementations for optional delegate methods
extension AgentDelegate {
    public func handleAuthenticate(
        _ request: AuthenticateRequest
    ) async throws -> AuthenticateResponse {
        AuthenticateResponse(success: true)
    }

    public func handleCancel(_ sessionId: SessionId) async throws {
        // Default: no-op
    }

    public func handleLoadSession(
        _ request: LoadSessionRequest
    ) async throws -> LoadSessionResponse {
        throw ClientError.invalidResponse
    }

    public func handleListSessions(
        _ request: ListSessionsRequest
    ) async throws -> ListSessionsResponse {
        throw ClientError.invalidResponse
    }

    public func handleSetModel(
        _ request: SetModelRequest
    ) async throws -> SetModelResponse {
        SetModelResponse(success: false)
    }
}

/// Incoming request from a client that the agent must handle
public struct AgentRequest: Sendable {
    public let id: RequestId
    public let method: String
    public let params: AnyCodable?

    public init(id: RequestId, method: String, params: AnyCodable?) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// Agent runtime that receives requests from clients and sends responses/updates
public actor Agent {
    // MARK: - Properties

    private let transport: any Transport
    private let logger: Logger
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private weak var delegate: AgentDelegate?

    private var requestContinuation: AsyncStream<AgentRequest>.Continuation?
    private let requestStream: AsyncStream<AgentRequest>

    // MARK: - Public API

    /// Stream of incoming requests from the client
    public nonisolated var requests: AsyncStream<AgentRequest> {
        requestStream
    }

    // MARK: - Initialization

    public init(transport: any Transport) {
        self.transport = transport
        self.logger = Logger.forCategory("Agent")
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.withoutEscapingSlashes]
        self.decoder = JSONDecoder()

        var continuation: AsyncStream<AgentRequest>.Continuation!
        self.requestStream = AsyncStream { cont in
            continuation = cont
        }
        self.requestContinuation = continuation
    }

    public func setDelegate(_ delegate: AgentDelegate?) {
        self.delegate = delegate
    }

    /// Start processing incoming messages from the transport
    public func start() async {
        for await data in transport.messages {
            await handleMessage(data)
        }
        requestContinuation?.finish()
    }

    /// Send a session update notification to the client
    public func sendUpdate(sessionId: SessionId, update: SessionUpdate) async throws {
        let notification = SessionUpdateNotification(sessionId: sessionId, update: update)
        let paramsData = try encoder.encode(notification)
        let params = try decoder.decode(AnyCodable.self, from: paramsData)

        let message = JSONRPCNotification(method: "session/update", params: params)
        let data = try encoder.encode(message)
        try await transport.send(data)
    }

    /// Send an agent message chunk update
    public func sendMessageChunk(sessionId: SessionId, text: String) async throws {
        let content = ContentBlock.text(TextContent(text: text))
        let update = SessionUpdate.agentMessageChunk(content)
        try await sendUpdate(sessionId: sessionId, update: update)
    }

    /// Send a tool call update
    public func sendToolCall(sessionId: SessionId, toolCall: ToolCallUpdate) async throws {
        let update = SessionUpdate.toolCall(toolCall)
        try await sendUpdate(sessionId: sessionId, update: update)
    }

    /// Send a session metadata update notification
    public func sendSessionInfoUpdate(sessionId: SessionId, info: SessionInfoUpdate) async throws {
        try await sendUpdate(sessionId: sessionId, update: .sessionInfoUpdate(info))
    }

    /// Send a session usage update notification
    public func sendUsageUpdate(sessionId: SessionId, usage: UsageUpdate) async throws {
        try await sendUpdate(sessionId: sessionId, update: .usageUpdate(usage))
    }

    /// Close the agent
    public func close() async {
        await transport.close()
        requestContinuation?.finish()
    }

    // MARK: - Private Methods

    private func handleMessage(_ data: Data) async {
        do {
            let message = try decoder.decode(Message.self, from: data)

            switch message {
            case .request(let request):
                await handleRequest(request)
            case .notification(let notification):
                await handleNotification(notification)
            case .response:
                // Agents typically don't receive responses
                logger.warning("Unexpected response received by agent")
            }
        } catch {
            logger.error("Failed to decode message: \(error.localizedDescription)")
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async {
        do {
            let response = try await routeRequest(request)
            try await sendResponse(id: request.id, result: response)
        } catch {
            try? await sendErrorResponse(
                id: request.id,
                code: -32603,
                message: error.localizedDescription
            )
        }
    }

    private func routeRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        switch request.method {
        case "initialize":
            let params = try decodeParams(InitializeRequest.self, from: request.params)
            let response = try await delegate.handleInitialize(params)
            return try encodeResult(response)

        case "authenticate":
            let params = try decodeParams(AuthenticateRequest.self, from: request.params)
            let response = try await delegate.handleAuthenticate(params)
            return try encodeResult(response)

        case "session/new":
            let params = try decodeParams(NewSessionRequest.self, from: request.params)
            let response = try await delegate.handleNewSession(params)
            return try encodeResult(response)

        case "session/prompt":
            let params = try decodeParams(SessionPromptRequest.self, from: request.params)
            let response = try await delegate.handlePrompt(params)
            return try encodeResult(response)

        case "session/load":
            let params = try decodeParams(LoadSessionRequest.self, from: request.params)
            let response = try await delegate.handleLoadSession(params)
            return try encodeResult(response)

        case "session/list":
            let params = try decodeParams(ListSessionsRequest.self, from: request.params)
            let response = try await delegate.handleListSessions(params)
            return try encodeResult(response)

        case "session/set_model":
            let params = try decodeParams(SetModelRequest.self, from: request.params)
            let response = try await delegate.handleSetModel(params)
            return try encodeResult(response)

        default:
            // Emit to request stream for custom handling
            requestContinuation?.yield(
                AgentRequest(
                    id: request.id,
                    method: request.method,
                    params: request.params
                ))
            throw ClientError.invalidResponse
        }
    }

    private func handleNotification(_ notification: JSONRPCNotification) async {
        switch notification.method {
        case "session/cancel":
            if let params = notification.params,
                let dict = params.value as? [String: Any],
                let sessionIdValue = dict["sessionId"] as? String
            {
                let sessionId = SessionId(sessionIdValue)
                try? await delegate?.handleCancel(sessionId)
            }
        default:
            logger.debug("Unhandled notification: \(notification.method)")
        }
    }

    private func sendResponse(id: RequestId, result: AnyCodable) async throws {
        let response = JSONRPCResponse(id: id, result: result, error: nil)
        let data = try encoder.encode(response)
        try await transport.send(data)
    }

    private func sendErrorResponse(id: RequestId, code: Int, message: String) async throws {
        let error = JSONRPCError(code: code, message: message, data: nil)
        let response = JSONRPCResponse(id: id, result: nil, error: error)
        let data = try encoder.encode(response)
        try await transport.send(data)
    }

    private func decodeParams<T: Decodable>(_ type: T.Type, from params: AnyCodable?) throws -> T {
        guard let params else {
            throw ClientError.invalidResponse
        }
        let data = try encoder.encode(params)
        return try decoder.decode(type, from: data)
    }

    private func encodeResult<T: Encodable>(_ result: T) throws -> AnyCodable {
        let data = try encoder.encode(result)
        return try decoder.decode(AnyCodable.self, from: data)
    }
}
