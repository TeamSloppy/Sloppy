import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix

private enum DashboardHTTPStatus {
    static let ok = 200
    static let notFound = 404
    static let methodNotAllowed = 405
}

struct DashboardClientConfig: Codable, Equatable, Sendable {
    var apiBase: String?
    var accentColor: String?
}

struct DashboardContentResolver: Sendable {
    let rootURL: URL
    let templateConfigURL: URL?
    let apiBase: String

    func response(for method: String, uri: String) -> CoreRouterResponse {
        switch method.uppercased() {
        case "GET", "HEAD":
            break
        default:
            return CoreRouterResponse(
                status: DashboardHTTPStatus.methodNotAllowed,
                body: Data("Method not allowed".utf8),
                contentType: "text/plain; charset=utf-8"
            )
        }

        let requestPath = normalizedRequestPath(from: uri)
        if requestPath == "/config.json" {
            return runtimeConfigResponse()
        }

        if let assetURL = assetURL(for: requestPath),
           let response = fileResponse(at: assetURL)
        {
            return response
        }

        if shouldServeIndexFallback(for: requestPath),
           let response = fileResponse(at: rootURL.appendingPathComponent("index.html"))
        {
            return response
        }

        return CoreRouterResponse(
            status: DashboardHTTPStatus.notFound,
            body: Data("Not found".utf8),
            contentType: "text/plain; charset=utf-8"
        )
    }

    func runtimeConfigData() -> Data {
        let fileManager = FileManager.default
        let baseConfig: DashboardClientConfig = {
            guard let templateConfigURL,
                  fileManager.fileExists(atPath: templateConfigURL.path),
                  let data = try? Data(contentsOf: templateConfigURL),
                  let decoded = try? JSONDecoder().decode(DashboardClientConfig.self, from: data)
            else {
                return DashboardClientConfig()
            }
            return decoded
        }()

        var runtimeConfig = baseConfig
        runtimeConfig.apiBase = apiBase

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = (try? encoder.encode(runtimeConfig)) ?? Data("{\"apiBase\":\"\(apiBase)\"}".utf8)
        return encoded + Data("\n".utf8)
    }

    private func runtimeConfigResponse() -> CoreRouterResponse {
        CoreRouterResponse(
            status: DashboardHTTPStatus.ok,
            body: runtimeConfigData(),
            contentType: "application/json"
        )
    }

    private func fileResponse(at fileURL: URL) -> CoreRouterResponse? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }

        return CoreRouterResponse(
            status: DashboardHTTPStatus.ok,
            body: data,
            contentType: mimeType(for: fileURL.pathExtension)
        )
    }

    private func assetURL(for requestPath: String) -> URL? {
        let sanitizedPath = requestPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let relativePath = sanitizedPath.isEmpty ? "index.html" : sanitizedPath
        let components = relativePath.split(separator: "/")
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }

        let root = rootURL.standardizedFileURL
        let candidate = components.reduce(root) { partialResult, component in
            partialResult.appendingPathComponent(String(component), isDirectory: false)
        }.standardizedFileURL

        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            return nil
        }

        return candidate
    }

    private func normalizedRequestPath(from uri: String) -> String {
        let rawPath = uri.split(separator: "?", maxSplits: 1).first.map(String.init) ?? uri
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        guard !decoded.isEmpty else {
            return "/"
        }
        return decoded.hasPrefix("/") ? decoded : "/" + decoded
    }

    private func shouldServeIndexFallback(for requestPath: String) -> Bool {
        guard requestPath != "/config.json" else {
            return false
        }
        let lastPathComponent = requestPath.split(separator: "/").last.map(String.init) ?? ""
        return !lastPathComponent.contains(".")
    }

    private func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html":
            return "text/html; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "js", "mjs":
            return "application/javascript; charset=utf-8"
        case "json":
            return "application/json"
        case "svg":
            return "image/svg+xml"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "ico":
            return "image/x-icon"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "map":
            return "application/json"
        case "txt":
            return "text/plain; charset=utf-8"
        default:
            return "application/octet-stream"
        }
    }
}

final class DashboardHTTPServer {
    private let host: String
    private let port: Int
    private let responder: DashboardContentResolver
    private let logger: Logger
    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?

    init(host: String, port: Int, responder: DashboardContentResolver, logger: Logger) {
        self.host = host
        self.port = port
        self.responder = responder
        self.logger = logger
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    func start() throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 128)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [responder, logger] channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(DashboardHTTPHandler(responder: responder, logger: logger))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        channel = try bootstrap.bind(host: host, port: port).wait()
    }

    func shutdown() throws {
        if let channel {
            try channel.close().wait()
        }
        try group.syncShutdownGracefully()
    }

    var boundPort: Int? {
        channel?.localAddress?.port
    }
}

private final class DashboardHTTPHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let responder: DashboardContentResolver
    private let logger: Logger
    private var requestHead: HTTPRequestHead?

    init(responder: DashboardContentResolver, logger: Logger) {
        self.responder = responder
        self.logger = logger
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestHead = head
        case .body:
            break
        case .end:
            guard let head = requestHead else {
                return
            }
            requestHead = nil

            if head.method == .OPTIONS {
                writePreflightResponse(context: context, requestHead: head)
                return
            }

            let response = responder.response(for: head.method.rawValue, uri: head.uri)
            writeResponse(context: context, requestHead: head, response: response)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.warning("Dashboard HTTP error: \(String(describing: error))")
        context.close(promise: nil)
    }

    private func writeResponse(
        context: ChannelHandlerContext,
        requestHead: HTTPRequestHead,
        response: CoreRouterResponse
    ) {
        let keepAlive = requestHead.isKeepAlive
        var headers = defaultHeaders(contentType: response.contentType, contentLength: response.body.count)
        headers.replaceOrAdd(name: "connection", value: keepAlive ? "keep-alive" : "close")

        let responseHead = HTTPResponseHead(
            version: requestHead.version,
            status: HTTPResponseStatus(statusCode: response.status),
            headers: headers
        )

        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: response.body.count)
        buffer.writeBytes(response.body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            if !keepAlive {
                loopBoundContext.value.close(promise: nil)
            }
        }
    }

    private func writePreflightResponse(context: ChannelHandlerContext, requestHead: HTTPRequestHead) {
        var headers = defaultHeaders(contentType: "application/json", contentLength: 0)
        headers.replaceOrAdd(name: "connection", value: requestHead.isKeepAlive ? "keep-alive" : "close")

        let responseHead = HTTPResponseHead(
            version: requestHead.version,
            status: .ok,
            headers: headers
        )

        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            if !requestHead.isKeepAlive {
                loopBoundContext.value.close(promise: nil)
            }
        }
    }

    private func defaultHeaders(contentType: String, contentLength: Int? = nil) -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: contentType)
        if let contentLength {
            headers.add(name: "content-length", value: "\(contentLength)")
        }
        headers.add(name: "access-control-allow-origin", value: "*")
        headers.add(name: "access-control-allow-methods", value: "GET,HEAD,OPTIONS")
        headers.add(name: "access-control-allow-headers", value: "content-type,authorization")
        headers.add(name: "access-control-max-age", value: "600")
        return headers
    }
}
