import AdaMCPCore
import Foundation
import Logging
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

actor EmbeddedHTTPMCPServer {
    struct Configuration: Sendable {
        var host: String
        var port: Int
        var endpoint: String
        var sessionTimeout: TimeInterval

        init(
            host: String = "127.0.0.1",
            port: Int = 0,
            endpoint: String = "/mcp",
            sessionTimeout: TimeInterval = 3600
        ) {
            self.host = host
            self.port = port
            self.endpoint = endpoint
            self.sessionTimeout = sessionTimeout
        }
    }

    typealias ServerFactory = @Sendable (String) async throws -> Server

    private let configuration: Configuration
    private let serverFactory: ServerFactory
    nonisolated let logger: Logger

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private var sessions: [String: SessionContext] = [:]

    private struct SessionContext {
        let server: Server
        let transport: StatefulHTTPServerTransport
        let createdAt: Date
        var lastAccessedAt: Date
    }

    init(
        configuration: Configuration,
        serverFactory: @escaping ServerFactory,
        logger: Logger = Logger(label: "org.adaengine.mcp.http")
    ) {
        self.configuration = configuration
        self.serverFactory = serverFactory
        self.logger = logger
    }

    func start() async throws -> URL {
        if let channel {
            return try self.endpointURL(for: channel)
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(app: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        let channel = try await bootstrap.bind(
            host: configuration.host,
            port: configuration.port
        ).get()
        self.eventLoopGroup = group
        self.channel = channel

        Task {
            await self.sessionCleanupLoop()
        }

        return try self.endpointURL(for: channel)
    }

    func stop() async {
        for sessionID in sessions.keys {
            await closeSession(sessionID)
        }
        sessions.removeAll()

        if let channel {
            try? await channel.close().get()
            self.channel = nil
        }

        if let eventLoopGroup {
            try? await self.shutdownEventLoopGroup(eventLoopGroup)
            self.eventLoopGroup = nil
        }
    }

    private func endpointURL(for channel: Channel) throws -> URL {
        guard let address = channel.localAddress, let port = address.port else {
            throw AdaMCPError.screenshotUnavailable("Failed to resolve bound HTTP port.")
        }
        let host = configuration.host == "0.0.0.0" ? "127.0.0.1" : configuration.host
        guard let url = URL(string: "http://\(host):\(port)\(configuration.endpoint)") else {
            throw AdaMCPError.screenshotUnavailable("Failed to construct HTTP endpoint URL.")
        }
        return url
    }

    fileprivate var endpoint: String {
        configuration.endpoint
    }

    private static func isInitializeRequest(_ body: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = json["method"] as? String else {
            return false
        }
        return method == "initialize"
    }

    fileprivate func handleHTTPRequest(_ request: HTTPRequest) async -> HTTPResponse {
        let sessionID = request.header(HTTPHeaderName.sessionID)

        if let sessionID, var session = sessions[sessionID] {
            session.lastAccessedAt = Date()
            sessions[sessionID] = session

            let response = await session.transport.handleRequest(request)
            if request.method.uppercased() == "DELETE" && response.statusCode == 200 {
                sessions.removeValue(forKey: sessionID)
            }
            return response
        }

        if request.method.uppercased() == "POST",
           let body = request.body,
           Self.isInitializeRequest(body) {
            return await createSessionAndHandle(request)
        }

        if sessionID != nil {
            return .error(statusCode: 404, .invalidRequest("Not Found: Session not found or expired"))
        }
        return .error(statusCode: 400, .invalidRequest("Bad Request: Missing \(HTTPHeaderName.sessionID) header"))
    }

    private struct FixedSessionIDGenerator: SessionIDGenerator {
        let sessionID: String

        func generateSessionID() -> String {
            sessionID
        }
    }

    private func createSessionAndHandle(_ request: HTTPRequest) async -> HTTPResponse {
        let sessionID = UUID().uuidString
        let transport = StatefulHTTPServerTransport(
            sessionIDGenerator: FixedSessionIDGenerator(sessionID: sessionID),
            logger: logger
        )

        do {
            let server = try await serverFactory(sessionID)
            try await server.start(transport: transport)

            sessions[sessionID] = SessionContext(
                server: server,
                transport: transport,
                createdAt: Date(),
                lastAccessedAt: Date()
            )

            let response = await transport.handleRequest(request)
            if case .error = response {
                sessions.removeValue(forKey: sessionID)
                await transport.disconnect()
            }
            return response
        } catch let error as MCPError {
            await transport.disconnect()
            return .error(statusCode: 500, error)
        } catch {
            await transport.disconnect()
            return .error(statusCode: 500, .internalError(error.localizedDescription))
        }
    }

    private func closeSession(_ sessionID: String) async {
        guard let session = sessions.removeValue(forKey: sessionID) else {
            return
        }
        await session.transport.disconnect()
    }

    private func sessionCleanupLoop() async {
        while self.channel != nil {
            try? await Task.sleep(for: .seconds(60))
            let now = Date()
            let expired = sessions.filter { _, context in
                now.timeIntervalSince(context.lastAccessedAt) > configuration.sessionTimeout
            }
            for sessionID in expired.keys {
                await closeSession(sessionID)
            }
        }
    }

    private func shutdownEventLoopGroup(_ group: MultiThreadedEventLoopGroup) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            group.shutdownGracefully { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let app: EmbeddedHTTPMCPServer

    private struct RequestState {
        var head: HTTPRequestHead
        var bodyBuffer: ByteBuffer
    }

    private var requestState: RequestState?

    init(app: EmbeddedHTTPMCPServer) {
        self.app = app
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestState = RequestState(
                head: head,
                bodyBuffer: context.channel.allocator.buffer(capacity: 0)
            )
        case .body(var buffer):
            requestState?.bodyBuffer.writeBuffer(&buffer)
        case .end:
            guard let state = requestState else {
                return
            }
            requestState = nil
            nonisolated(unsafe) let context = context
            Task {
                await self.handleRequest(state: state, context: context)
            }
        }
    }

    private func handleRequest(state: RequestState, context: ChannelHandlerContext) async {
        let path = state.head.uri.split(separator: "?").first.map(String.init) ?? state.head.uri
        let endpoint = await app.endpoint

        guard path == endpoint else {
            await writeResponse(
                .error(statusCode: 404, .invalidRequest("Not Found")),
                version: state.head.version,
                context: context
            )
            return
        }

        let request = self.makeHTTPRequest(from: state)
        let response = await app.handleHTTPRequest(request)
        await writeResponse(response, version: state.head.version, context: context)
    }

    private func makeHTTPRequest(from state: RequestState) -> HTTPRequest {
        var headers: [String: String] = [:]
        for (name, value) in state.head.headers {
            if let existing = headers[name] {
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }

        let body: Data?
        if state.bodyBuffer.readableBytes > 0,
           let bytes = state.bodyBuffer.getBytes(at: 0, length: state.bodyBuffer.readableBytes) {
            body = Data(bytes)
        } else {
            body = nil
        }

        let path = state.head.uri.split(separator: "?").first.map(String.init) ?? state.head.uri
        return HTTPRequest(method: state.head.method.rawValue, headers: headers, body: body, path: path)
    }

    private func writeResponse(
        _ response: HTTPResponse,
        version: HTTPVersion,
        context: ChannelHandlerContext
    ) async {
        nonisolated(unsafe) let context = context
        let eventLoop = context.eventLoop

        switch response {
        case .stream(let stream, _):
            eventLoop.execute {
                var head = HTTPResponseHead(version: version, status: .init(statusCode: response.statusCode))
                for (name, value) in response.headers {
                    head.headers.add(name: name, value: value)
                }
                context.write(self.wrapOutboundOut(.head(head)), promise: nil)
                context.flush()
            }

            do {
                for try await chunk in stream {
                    eventLoop.execute {
                        var buffer = context.channel.allocator.buffer(capacity: chunk.count)
                        buffer.writeBytes(chunk)
                        context.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                    }
                }
            } catch {
                return
            }

            eventLoop.execute {
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }

        default:
            let body = response.bodyData
            eventLoop.execute {
                var head = HTTPResponseHead(version: version, status: .init(statusCode: response.statusCode))
                for (name, value) in response.headers {
                    head.headers.add(name: name, value: value)
                }
                context.write(self.wrapOutboundOut(.head(head)), promise: nil)

                if let body {
                    var buffer = context.channel.allocator.buffer(capacity: body.count)
                    buffer.writeBytes(body)
                    context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }

                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
    }
}
