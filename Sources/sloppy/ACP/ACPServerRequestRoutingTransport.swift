import ACP
import ACPModel
import Foundation

/// Adds the current ACP session-configuration request to the older server
/// implementation shipped by swift-acp. All other frames continue through to
/// `ACP.Agent` unchanged.
actor ACPServerRequestRoutingTransport: Transport {
    typealias ConfigOptionHandler = @Sendable (SetSessionConfigOptionRequest) async throws -> SetSessionConfigOptionResponse

    private let wrapped: any Transport
    private let continuation: AsyncStream<Data>.Continuation
    nonisolated let messages: AsyncStream<Data>
    private var configOptionHandler: ConfigOptionHandler?
    private var pendingPermissionRequests: [RequestId: CheckedContinuation<RequestPermissionResponse, Error>] = [:]
    private var pumpTask: Task<Void, Never>?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(wrapping wrapped: any Transport) {
        self.wrapped = wrapped
        var continuation: AsyncStream<Data>.Continuation!
        self.messages = AsyncStream { continuation = $0 }
        self.continuation = continuation
        self.encoder.outputFormatting = [.withoutEscapingSlashes]
    }

    var isConnected: Bool {
        get async {
            await wrapped.isConnected
        }
    }

    func setConfigOptionHandler(_ handler: @escaping ConfigOptionHandler) {
        configOptionHandler = handler
    }

    func start() {
        guard pumpTask == nil else { return }
        pumpTask = Task {
            for await data in wrapped.messages {
                await route(data)
            }
            continuation.finish()
        }
    }

    func send(_ data: Data) async throws {
        try await wrapped.send(data)
    }

    func requestPermission(
        _ request: ACPServerPermissionRequest
    ) async throws -> RequestPermissionResponse {
        let id = RequestId.string("sloppy-permission-\(UUID().uuidString)")
        let paramsData = try encoder.encode(request)
        let params = try decoder.decode(AnyCodable.self, from: paramsData)
        let frame = try encoder.encode(
            JSONRPCRequest(id: id, method: "session/request_permission", params: params)
        )
        return try await withCheckedThrowingContinuation { continuation in
            pendingPermissionRequests[id] = continuation
            Task {
                do {
                    try await wrapped.send(frame)
                } catch {
                    failPendingPermissionRequest(id: id, error: error)
                }
            }
        }
    }

    func close() async {
        pumpTask?.cancel()
        pumpTask = nil
        await wrapped.close()
        continuation.finish()
        let pending = pendingPermissionRequests.values
        pendingPermissionRequests.removeAll()
        for continuation in pending {
            continuation.resume(throwing: RoutingError.connectionClosed)
        }
    }

    private func route(_ data: Data) async {
        guard let message = try? decoder.decode(Message.self, from: data) else {
            continuation.yield(data)
            return
        }

        if case .response(let response) = message,
           let pending = pendingPermissionRequests.removeValue(forKey: response.id)
        {
            resolvePermissionResponse(response, continuation: pending)
            return
        }

        guard case .request(let request) = message,
              request.method == "session/set_config_option"
        else {
            continuation.yield(data)
            return
        }

        do {
            guard let configOptionHandler else {
                throw RoutingError.handlerUnavailable
            }
            let params = try decodeParams(SetSessionConfigOptionRequest.self, from: request.params)
            let response = try await configOptionHandler(params)
            try await sendResponse(id: request.id, result: response)
        } catch {
            try? await sendError(id: request.id, error: error)
        }
    }

    private func resolvePermissionResponse(
        _ response: JSONRPCResponse,
        continuation: CheckedContinuation<RequestPermissionResponse, Error>
    ) {
        if let error = response.error {
            continuation.resume(throwing: RoutingError.remote(error.message))
            return
        }
        guard let result = response.result,
              let resultData = try? encoder.encode(result),
              let permissionResponse = try? decoder.decode(RequestPermissionResponse.self, from: resultData)
        else {
            continuation.resume(throwing: RoutingError.invalidResponse)
            return
        }
        continuation.resume(returning: permissionResponse)
    }

    private func failPendingPermissionRequest(id: RequestId, error: Error) {
        pendingPermissionRequests.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func decodeParams<T: Decodable>(_ type: T.Type, from params: AnyCodable?) throws -> T {
        guard let params else { throw RoutingError.invalidParams }
        return try decoder.decode(type, from: encoder.encode(params))
    }

    private func sendResponse<T: Encodable>(id: RequestId, result: T) async throws {
        let resultData = try encoder.encode(result)
        let encodedResult = try decoder.decode(AnyCodable.self, from: resultData)
        try await wrapped.send(try encoder.encode(JSONRPCResponse(id: id, result: encodedResult, error: nil)))
    }

    private func sendError(id: RequestId, error: Error) async throws {
        let response = JSONRPCResponse(
            id: id,
            result: nil,
            error: JSONRPCError(code: -32602, message: error.localizedDescription, data: nil)
        )
        try await wrapped.send(try encoder.encode(response))
    }

    private enum RoutingError: Error, LocalizedError {
        case handlerUnavailable
        case invalidParams
        case invalidResponse
        case connectionClosed
        case remote(String)

        var errorDescription: String? {
            switch self {
            case .handlerUnavailable:
                return "ACP session configuration handler is unavailable."
            case .invalidParams:
                return "ACP session configuration parameters are invalid."
            case .invalidResponse:
                return "ACP client returned an invalid permission response."
            case .connectionClosed:
                return "ACP connection closed while waiting for permission."
            case .remote(let message):
                return message
            }
        }
    }
}

struct ACPServerPermissionRequest: Codable, Sendable {
    struct ToolCall: Codable, Sendable {
        let toolCallId: String
        let title: String
        let kind: String
        let status: String
        let rawInput: AnyCodable
    }

    let sessionId: SessionId
    let toolCall: ToolCall
    let options: [PermissionOption]
}
