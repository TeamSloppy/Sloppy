import Foundation
import AsyncHTTPClient
import Logging
import NIOPosix

/// Console's native API uses bearer tokens, so neither transport follows redirects
/// or carries cookies to another origin. TLS certificate validation stays enabled.
actor ConsoleHTTPTransport {
    typealias Send = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let primary: Send
    private let http2: Send
    private let clock = ContinuousClock()
    private let logger = Logger(label: "sloppy.console-http")
    private var prefersHTTP2 = false

    init(primary: @escaping Send, http2: @escaping Send = ConsoleHTTP2Transport.send) {
        self.primary = primary
        self.http2 = http2
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        guard request.timeoutInterval.isFinite, request.timeoutInterval > 0 else { throw URLError(.timedOut) }
        // A failed POST can already have changed server state. Choose TCP before
        // sending it, rather than replaying enrollment, login or token rotation.
        let method = request.httpMethod ?? "GET"
        guard !prefersHTTP2, method == "GET" || method == "HEAD" else {
            prefersHTTP2 = true
            return try await sendHTTP2(request)
        }

        let startedAt = clock.now
        var probe = request
        probe.timeoutInterval = min(request.timeoutInterval, 2)
        do {
            return try await primary(probe)
        } catch {
            try Task.checkCancellation()
            guard Self.canFallBack(error) else { throw error }
            prefersHTTP2 = true
            let elapsed = startedAt.duration(to: clock.now).components
            let elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            let remaining = request.timeoutInterval - elapsedSeconds
            guard remaining > 0 else { throw URLError(.timedOut) }
            var fallback = request
            fallback.timeoutInterval = remaining
            logger.warning("console.http2.fallback", metadata: [
                "path": .string(request.url?.path ?? "unknown"),
                "error_code": .stringConvertible((error as NSError).code),
            ])
            return try await sendHTTP2(fallback)
        }
    }

    private func sendHTTP2(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do { return try await http2(request) }
        catch {
            let detail = (error as? HTTPClientError)?.description
                ?? (error as? NIOConnectionError)?.description ?? error.localizedDescription
            logger.warning("console.http2.failed", metadata: [
                "path": .string(request.url?.path ?? "unknown"), "error": .string(detail),
            ])
            throw error
        }
    }

    private static func canFallBack(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return error.code == .timedOut || error.code == .networkConnectionLost
            || error.code == .cannotConnectToHost
    }
}

enum ConsoleHTTP2Transport {
    // The client negotiates h2 over TLS/TCP and supports HTTP/1.1 for origins
    // without h2. It never negotiates HTTP/3, even after an Alt-Svc response.
    private static let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private static let client = HTTPClient(eventLoopGroupProvider: .shared(group), configuration: makeConfiguration())

    static func makeConfiguration() -> HTTPClient.Configuration {
        var configuration = HTTPClient.Configuration(redirectConfiguration: .disallow,
            timeout: .init(connect: .seconds(20), read: .seconds(20)))
        configuration.tlsConfiguration = .makeClientConfiguration()
        configuration.tlsConfiguration?.minimumTLSVersion = .tlsv12
        configuration.tlsConfiguration?.certificateVerification = .fullVerification
        configuration.http2ConnectionDebugInitializer = { channel in
            Logger(label: "sloppy.console-http").info("console.http2.connected", metadata: [
                "remote": .string(String(describing: channel.remoteAddress)),
            ])
            return channel.eventLoop.makeSucceededFuture(())
        }
        return configuration
    }

    static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.scheme == "https",
              url.host == ConsoleAccountClient.consoleURL.host,
              url.port == nil || url.port == 443,
              url.user == nil, url.password == nil else { throw URLError(.badURL) }
        try Task.checkCancellation()
        let startedAt = Date()
        var outbound = HTTPClientRequest(url: url.absoluteString)
        outbound.method = .init(rawValue: request.httpMethod ?? "GET")
        for (name, value) in request.allHTTPHeaderFields ?? [:] {
            outbound.headers.add(name: name, value: value)
        }
        if let body = request.httpBody { outbound.body = .bytes(body) }
        let response = try await client.execute(outbound,
            timeout: .milliseconds(Int64(max(1, request.timeoutInterval * 1_000))))
        Logger(label: "sloppy.console-http").info("console.http2.response", metadata: [
            "path": .string(url.path), "status": .stringConvertible(response.status.code),
            "protocol": .string(response.version.major == 2 ? "h2" : "http/1.1"),
            "authority": .string(url.host ?? "unknown"),
            "connect_host": .string(url.host ?? "unknown"),
        ])
        let body = try await response.body.collect(upTo: 8 * 1_024 * 1_024)
        var headers: [String: String] = [:]
        for (name, value) in response.headers { headers[name] = value }
        guard let http = HTTPURLResponse(url: url, statusCode: Int(response.status.code),
            httpVersion: "HTTP/\(response.version.major).\(response.version.minor)", headerFields: headers) else {
            throw URLError(.badServerResponse)
        }
        Logger(label: "sloppy.console-http").info("console.http2.completed", metadata: [
            "path": .string(url.path), "status": .stringConvertible(http.statusCode),
            "protocol": .string(response.version.major == 2 ? "h2" : "http/1.1"),
            "duration_ms": .stringConvertible(Int(Date().timeIntervalSince(startedAt) * 1_000)),
        ])
        return (Data(body.readableBytesView), http)
    }

}
