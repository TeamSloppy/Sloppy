import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

enum MCPHTTPDiscovery {
    static let protocolVersion = "2026-07-28"

    struct Server: Sendable {
        let capabilities: [String: JSONValue]
        let expiresAt: ContinuousClock.Instant
    }

    private struct Envelope: Decodable {
        struct RPCError: Decodable {
            let code: Int
            let data: JSONValue?
        }

        let jsonrpc: String
        let id: String?
        let result: [String: JSONValue]?
        let error: RPCError?
    }

    static func endpoint(for config: CoreConfig.MCP.Server) throws -> URL {
        let raw = config.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            throw MCPRegistryError.invalidConfiguration("MCP server '\(config.id)' uses http but endpoint is missing.")
        }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else {
            throw MCPRegistryError.invalidConfiguration("MCP server '\(config.id)' needs an HTTP or HTTPS endpoint.")
        }
        return url
    }

    /// Returns nil when the endpoint should be tried with the legacy handshake.
    static func probe(_ config: CoreConfig.MCP.Server) async throws -> Server? {
        let requestID = UUID().uuidString
        let reply = try await send(config, method: "server/discover", id: requestID)
        return try interpret(reply, requestID: requestID, allowHTTPFallback: true)
    }

    static func request(
        _ config: CoreConfig.MCP.Server, method: String, params: [String: JSONValue],
        capabilities: [String: JSONValue] = [:], headers: [String: String] = [:],
        onNotification: (@Sendable ([String: JSONValue]) -> Void)? = nil
    ) async throws -> [String: JSONValue] {
        let id = UUID().uuidString
        let reply = try await send(config, method: method, id: id, params: params,
                                   capabilities: capabilities, headers: headers, onNotification: onNotification)
        return try decodeResult(reply, id: id)
    }

    static func listen(_ config: CoreConfig.MCP.Server, notifications: [String: JSONValue],
                       onNotification: @escaping @Sendable ([String: JSONValue]) -> Void) async throws {
        _ = try await request(config, method: "subscriptions/listen", params: ["notifications": .object(notifications)],
                              onNotification: onNotification)
    }

    static func body(method: String, id: String, params: [String: JSONValue], capabilities: [String: JSONValue]) throws -> Data {
        var params = params
        var metadata = params["_meta"]?.asObject ?? [:]
        metadata["io.modelcontextprotocol/protocolVersion"] = .string(protocolVersion)
        metadata["io.modelcontextprotocol/clientCapabilities"] = .object(capabilities)
        metadata["io.modelcontextprotocol/clientInfo"] = .object(["name": .string("sloppy"), "version": .string("1.0.0")])
        params["_meta"] = .object(metadata)
        return try JSONEncoder().encode(JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .string(id), "method": .string(method), "params": .object(params)
        ]))
    }

    static func headerValue(_ value: String) -> String {
        let sentinel = value.hasPrefix("=?base64?") && value.hasSuffix("?=")
        let hasPadding = value != value.trimmingCharacters(in: .whitespaces)
        let validASCII = value.utf8.allSatisfy { $0 == 9 || (32...126).contains($0) }
        guard sentinel || hasPadding || !validASCII else { return value }
        return "=?base64?\(Data(value.utf8).base64EncodedString())?="
    }

    private static func send(
        _ config: CoreConfig.MCP.Server, method: String, id: String, params: [String: JSONValue] = [:],
        capabilities: [String: JSONValue] = [:], headers: [String: String] = [:],
        onNotification: (@Sendable ([String: JSONValue]) -> Void)? = nil
    ) async throws -> Reply {
        let subscription = method == "subscriptions/listen"
        let timeout = subscription ? 120 : TimeInterval(max(250, config.timeoutMs)) / 1_000
        var request = URLRequest(url: try endpoint(for: config), timeoutInterval: timeout)
        request.httpMethod = "POST"
        for (name, value) in config.headers where !name.lowercased().hasPrefix("mcp-param-") {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        request.setValue(method, forHTTPHeaderField: "Mcp-Method")
        let name = switch method {
        case "tools/call", "prompts/get": params["name"]?.asString
        case "resources/read": params["uri"]?.asString
        case "tasks/get", "tasks/update", "tasks/cancel": params["taskId"]?.asString
        default: nil as String?
        }
        request.setValue(name.map(headerValue), forHTTPHeaderField: "Mcp-Name")
        request.setValue(nil, forHTTPHeaderField: "Mcp-Session-Id")
        request.setValue(nil, forHTTPHeaderField: "Last-Event-ID")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try body(method: method, id: id, params: params, capabilities: capabilities)

        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForResource = subscription ? 3_600 : timeout
        let (stream, continuation) = AsyncThrowingStream<Reply, any Error>.makeStream()
        let delegate = ResponseReader(requestID: id, continuation: continuation,
                                      requestedNotifications: subscription ? params["notifications"]?.asObject : nil,
                                      onNotification: onNotification)
        let session = URLSession(configuration: settings, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: request).resume()

        var replies = stream.makeAsyncIterator()
        guard let reply = try await replies.next() else {
            try Task.checkCancellation()
            throw MCPRegistryError.invalidResult("MCP HTTP request ended without a response.")
        }
        return reply
    }

    static func discoverStdio(_ data: Data, id: String) throws -> Server? {
        try interpret(Reply(statusCode: 200, body: data), requestID: id, allowHTTPFallback: false)
    }

    static func decodeStdio(_ data: Data, id: String) throws -> [String: JSONValue] {
        try decodeResult(Reply(statusCode: 200, body: data), id: id)
    }

    private static func decodeResult(_ reply: Reply, id: String) throws -> [String: JSONValue] {
        if reply.statusCode == 401 || reply.statusCode == 403 {
            throw MCPRegistryError.invalidResult("MCP request was denied (HTTP \(reply.statusCode)).")
        }
        let envelope = try? JSONDecoder().decode(Envelope.self, from: reply.body)
        if let envelope, envelope.jsonrpc == "2.0", envelope.id == id || envelope.id == nil, let error = envelope.error {
            throw MCPRPCFailure(code: error.code)
        }
        guard reply.statusCode == 200, let envelope, envelope.jsonrpc == "2.0", envelope.id == id,
              let result = envelope.result else {
            throw MCPRegistryError.invalidResult("Invalid MCP response (HTTP \(reply.statusCode)).")
        }
        return result
    }

    private static func interpret(_ reply: Reply, requestID: String, allowHTTPFallback: Bool) throws -> Server? {
        let envelope = try? JSONDecoder().decode(Envelope.self, from: reply.body)
        let rpc = envelope.flatMap { $0.jsonrpc == "2.0" && ($0.id == requestID || $0.id == nil) ? $0 : nil }
        let status = reply.statusCode
        if status == 401 || status == 403 {
            throw MCPRegistryError.invalidResult("MCP HTTP discovery was denied (HTTP \(status)). Check the server's configured credentials.")
        }
        switch rpc?.error?.code {
        case -32022:
            let versions = rpc?.error?.data?.asObject?["supported"]?.asArray?.compactMap(\.asString) ?? []
            throw incompatibleVersion(versions)
        case -32021:
            throw MCPRegistryError.invalidResult("MCP HTTP discovery requires a client capability Sloppy did not advertise.")
        case -32020:
            throw MCPRegistryError.invalidResult("MCP HTTP discovery headers did not match the request metadata.")
        default:
            break
        }

        // Some initialize-based servers report an unknown or pre-initialize
        // method as a JSON-RPC error on HTTP 200 instead of HTTP 400.
        if !allowHTTPFallback {
            if rpc?.error != nil { return nil }
            if let result = rpc?.result, result["resultType"] == nil, result["supportedVersions"] == nil {
                return nil
            }
        }
        if status == 400 || (status == 200 && rpc?.id == requestID
            && [-32600, -32601, -32602, -32000].contains(rpc?.error?.code ?? 0)) {
            return nil
        }
        guard status == 200 else {
            throw MCPRegistryError.invalidResult("MCP HTTP discovery failed (HTTP \(status)).")
        }
        guard rpc?.id == requestID, rpc?.error == nil,
              let result = rpc?.result, result["resultType"]?.asString == "complete",
              let capabilities = result["capabilities"]?.asObject else {
            throw MCPRegistryError.invalidResult("MCP HTTP discovery returned an invalid server/discover response.")
        }
        let versions = result["supportedVersions"]?.asArray?.compactMap(\.asString) ?? []
        guard versions.contains(protocolVersion) else { throw incompatibleVersion(versions) }
        let ttl = max(0, min(result["ttlMs"]?.asNumber ?? 0, Double(Int32.max)))
        return Server(capabilities: capabilities, expiresAt: .now + .milliseconds(Int(ttl)))
    }

    private static func incompatibleVersion(_ versions: [String]) -> MCPRegistryError {
        let dates = versions.filter { $0.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil }
        let offered = dates.isEmpty ? "none reported" : dates.prefix(8).joined(separator: ", ")
        return .invalidResult("MCP HTTP discovery found no supported protocol version (Sloppy: \(protocolVersion); server: \(offered)).")
    }

    private struct Reply: Sendable {
        let statusCode: Int
        let body: Data
    }

    // A serial URLSession delegate stops reading when the matching SSE reply
    // arrives. Endpoints may leave the stream open after sending it.
    private final class ResponseReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let requestID: String
        private let continuation: AsyncThrowingStream<Reply, any Error>.Continuation
        private let onNotification: (@Sendable ([String: JSONValue]) -> Void)?
        private let requestedNotifications: [String: JSONValue]?
        private var acceptedNotifications: [String: JSONValue]?
        private let maxResponseBytes = 8 * 1024 * 1024
        private var statusCode: Int?
        private var isEventStream = false
        private var bytesReceived = 0
        private var body = Data()
        private var line = Data()
        private var eventLines: [String] = []
        private var lastByteWasCR = false
        private var finished = false

        init(requestID: String, continuation: AsyncThrowingStream<Reply, any Error>.Continuation,
             requestedNotifications: [String: JSONValue]?, onNotification: (@Sendable ([String: JSONValue]) -> Void)?) {
            self.requestID = requestID
            self.continuation = continuation
            self.onNotification = onNotification
            self.requestedNotifications = requestedNotifications
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            statusCode = (response as? HTTPURLResponse)?.statusCode
            isEventStream = response.mimeType?.lowercased() == "text/event-stream"
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            guard var original = task.originalRequest, let source = original.url, let destination = request.url,
                  source.scheme?.lowercased() == destination.scheme?.lowercased(),
                  source.host?.lowercased() == destination.host?.lowercased(),
                  effectivePort(source) == effectivePort(destination) else {
                completionHandler(nil)
                return
            }
            original.url = destination
            completionHandler(original)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard !finished else { return }
            guard data.count <= maxResponseBytes - bytesReceived else {
                finish(throwing: MCPRegistryError.invalidResult("MCP HTTP response exceeded 8 MiB."))
                dataTask.cancel()
                return
            }
            bytesReceived += data.count
            if isEventStream {
                if let response = readEventStream(data) {
                    body = response
                    finish()
                    dataTask.cancel()
                }
            } else {
                body.append(data)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            finish(throwing: error)
        }

        private func effectivePort(_ url: URL) -> Int {
            url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
        }

        private func readEventStream(_ data: Data) -> Data? {
            for byte in data {
                let wasCR = lastByteWasCR
                lastByteWasCR = byte == 13
                if byte == 10 && wasCR { continue }
                guard byte == 10 || byte == 13 else {
                    line.append(byte)
                    continue
                }
                let text = String(decoding: line, as: UTF8.self)
                line.removeAll(keepingCapacity: true)
                if text.hasPrefix("data:") {
                    let field = text.dropFirst(5)
                    eventLines.append(String(field.first == " " ? field.dropFirst() : field))
                } else if text.isEmpty {
                    if requestedNotifications != nil { bytesReceived = 0 }
                    guard !eventLines.isEmpty else { continue }
                    let payload = Data(eventLines.joined(separator: "\n").utf8)
                    eventLines.removeAll(keepingCapacity: true)
                    if let envelope = try? JSONDecoder().decode(Envelope.self, from: payload),
                       envelope.id == requestID || (statusCode != 200 && envelope.id == nil && envelope.error != nil) {
                        return payload
                    }
                    if let packet = (try? JSONDecoder().decode(JSONValue.self, from: payload))?.asObject,
                       packet["jsonrpc"]?.asString == "2.0", packet["id"] == nil,
                       packet["method"]?.asString != nil {
                        deliverNotification(packet)
                    }
                }
            }
            return nil
        }

        private func deliverNotification(_ packet: [String: JSONValue]) {
            guard let requestedNotifications else { onNotification?(packet); return }
            guard let params = packet["params"]?.asObject,
                  params["_meta"]?.asObject?["io.modelcontextprotocol/subscriptionId"]?.asString == requestID else { return }
            let method = packet["method"]?.asString
            if method == "notifications/subscriptions/acknowledged", acceptedNotifications == nil {
                acceptedNotifications = (params["notifications"]?.asObject ?? [:]).filter { requestedNotifications[$0.key] == $0.value }
                onNotification?(packet)
                return
            }
            let flag = switch method {
            case "notifications/tools/list_changed": "toolsListChanged"
            case "notifications/prompts/list_changed": "promptsListChanged"
            case "notifications/resources/list_changed": "resourcesListChanged"
            default: nil as String?
            }
            if let flag, acceptedNotifications?[flag]?.asBool == true { onNotification?(packet) }
        }

        private func finish(throwing error: (any Error)? = nil) {
            guard !finished else { return }
            finished = true
            if let error {
                continuation.finish(throwing: error)
            } else if let statusCode {
                continuation.yield(Reply(statusCode: statusCode, body: body))
                continuation.finish()
            } else {
                continuation.finish(throwing: MCPRegistryError.invalidResult("MCP discovery did not receive an HTTP response."))
            }
        }
    }
}

struct MCPRPCFailure: LocalizedError {
    let code: Int
    var rejectedBeforeExecution: Bool { [-32600, -32601, -32602, -32020, -32021, -32022].contains(code) }
    var errorDescription: String? { "MCP server returned JSON-RPC error \(code)." }
}


struct MCPToolOutcomeUnknown: LocalizedError {
    static let code = "mcp_tool_outcome_unknown"

    var errorDescription: String? {
        "The MCP call may have produced side effects. Check its remote outcome before replaying it."
    }

    func result(tool: String) -> ToolInvocationResult {
        toolFailure(tool: tool, code: Self.code, message: localizedDescription, retryable: false)
    }
}
