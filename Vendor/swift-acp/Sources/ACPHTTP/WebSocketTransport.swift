//
//  WebSocketTransport.swift
//  ACPHTTP
//
//  WebSocket-based transport for network communication
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ACP
import ACPModel

/// Transport implementation using WebSocket for network communication.
/// Works on all Apple platforms (iOS, macOS, tvOS, watchOS).
public actor WebSocketTransport: Transport {
    // MARK: - Properties

    private var webSocket: URLSessionWebSocketTask?
    private let session: URLSession
    private let url: URL
    private let logger: Logger

    private var messageContinuation: AsyncStream<Data>.Continuation?
    private let messageStream: AsyncStream<Data>

    private var connected = false

    // MARK: - Transport Protocol

    public nonisolated var messages: AsyncStream<Data> {
        messageStream
    }

    public var isConnected: Bool {
        connected
    }

    // MARK: - Initialization

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
        self.logger = Logger.forCategory("WebSocketTransport")

        var continuation: AsyncStream<Data>.Continuation!
        self.messageStream = AsyncStream { cont in
            continuation = cont
        }
        self.messageContinuation = continuation
    }

    // MARK: - Connection

    /// Connect to the WebSocket server
    public func connect() async throws {
        guard webSocket == nil else {
            throw ClientError.transportError("Already connected")
        }

        let task = session.webSocketTask(with: url)
        webSocket = task
        task.resume()

        connected = true
        startReceiving()
    }

    public func send(_ data: Data) async throws {
        guard let webSocket, connected else {
            throw ClientError.transportError("Not connected")
        }

        let message = URLSessionWebSocketTask.Message.data(data)
        try await webSocket.send(message)
    }

    public func close() async {
        connected = false
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        messageContinuation?.finish()
    }

    // MARK: - Private Methods

    private func startReceiving() {
        guard let webSocket else { return }

        Task {
            do {
                while connected {
                    let message = try await webSocket.receive()

                    switch message {
                    case .data(let data):
                        messageContinuation?.yield(data)

                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            messageContinuation?.yield(data)
                        }

                    @unknown default:
                        logger.warning("Unknown WebSocket message type")
                    }
                }
            } catch {
                if connected {
                    logger.error("WebSocket receive error: \(error.localizedDescription)")
                    connected = false
                    messageContinuation?.finish()
                }
            }
        }
    }
}

// MARK: - WebSocket Client

/// Convenience wrapper for using WebSocket transport with the ACP Client
public actor WebSocketClient {
    private let transport: WebSocketTransport
    private let client: Client
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(url: URL) {
        self.transport = WebSocketTransport(url: url)
        self.client = Client()
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    /// Connect to the WebSocket server and initialize the client
    public func connect(
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo? = nil
    ) async throws -> InitializeResponse {
        try await transport.connect()

        // Start message handling
        Task {
            for await data in transport.messages {
                await handleMessage(data)
            }
        }

        // Send initialize request
        return try await initialize(capabilities: capabilities, clientInfo: clientInfo)
    }

    public func close() async {
        await transport.close()
        await client.terminate()
    }

    // MARK: - Private

    private func handleMessage(_ data: Data) async {
        // Forward to client's message handling
        // This would need integration with the client's internal message handling
    }

    private func initialize(
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo?
    ) async throws -> InitializeResponse {
        let info = clientInfo ?? ClientInfo(
            name: "ACP",
            title: "ACP WebSocket Client",
            version: "1.0.0"
        )

        let request = InitializeRequest(
            protocolVersion: 1,
            clientCapabilities: capabilities,
            clientInfo: info
        )

        let paramsData = try encoder.encode(request)
        let params = try decoder.decode(AnyCodable.self, from: paramsData)

        let rpcRequest = JSONRPCRequest(
            id: .number(1),
            method: "initialize",
            params: params
        )

        let requestData = try encoder.encode(rpcRequest)
        try await transport.send(requestData)

        // Wait for response
        for await data in transport.messages {
            let message = try decoder.decode(Message.self, from: data)
            if case .response(let response) = message {
                if let result = response.result {
                    let resultData = try encoder.encode(result)
                    return try decoder.decode(InitializeResponse.self, from: resultData)
                } else if let error = response.error {
                    throw ClientError.agentError(error)
                }
            }
        }

        throw ClientError.connectionClosed
    }
}
