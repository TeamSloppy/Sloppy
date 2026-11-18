import Foundation
import SloppyRemoteProtocol
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

public enum APIError: LocalizedError, Sendable {
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case decodingFailed(String)

    public var statusCode: Int? {
        if case let .httpError(statusCode, _) = self { return statusCode }
        return nil
    }

    public var diagnosticDescription: String {
        switch self {
        case .invalidResponse:
            return "Invalid HTTP response"
        case .httpError(let statusCode, let body):
            if let detail = Self.responseDetail(from: body) {
                return "HTTP \(statusCode): \(detail)"
            }
            return "HTTP \(statusCode)"
        case .decodingFailed(let message):
            return "Response decoding failed: \(message)"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid HTTP response."
        case .httpError:
            return "The server request failed (\(diagnosticDescription))."
        case .decodingFailed(let message):
            return "The server response could not be read: \(message)"
        }
    }

    private static func responseDetail(from body: String?) -> String? {
        guard let body else { return nil }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error", "detail"] {
                if let value = object[key] as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
        }

        guard !trimmed.hasPrefix("<") else { return nil }
        return String(trimmed.prefix(300))
    }
}

public actor BackendHTTPClient {
    public nonisolated let baseURL: URL
    public nonisolated let endpoint: SloppyInstanceEndpoint

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: Logger
    private let authSessionStore: AuthSessionStore
    private var authToken: String

    public init(
        baseURL: URL = URL(string: "http://localhost:25101")!,
        authToken: String = "",
        tlsFingerprint: String? = nil,
        session: URLSession? = nil,
        authSessionStore: AuthSessionStore = .shared,
        logger: Logger = Logger(label: "sloppy.backend-http")
    ) {
        self.init(
            endpoint: .direct(baseURL: baseURL),
            authToken: authToken,
            tlsFingerprint: tlsFingerprint,
            session: session,
            authSessionStore: authSessionStore,
            logger: logger
        )
    }

    public init(
        endpoint: SloppyInstanceEndpoint,
        authToken: String = "",
        tlsFingerprint: String? = nil,
        session: URLSession? = nil,
        authSessionStore: AuthSessionStore = .shared,
        logger: Logger = Logger(label: "sloppy.backend-http")
    ) {
        self.endpoint = endpoint
        self.baseURL = endpoint.coordinatorBaseURL
        self.session = session ?? ClientURLSessionFactory.session(
            for: endpoint.coordinatorBaseURL,
            tlsFingerprint: tlsFingerprint
        )
        self.authSessionStore = authSessionStore
        self.logger = logger
        self.authToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: str) { return date }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func get<T: Decodable>(_ path: String, timeout: TimeInterval? = nil) async throws -> T {
        let data = try await data(method: "GET", path: path, timeout: timeout)
        return try decode(T.self, from: data)
    }

    public func getData(_ path: String, timeout: TimeInterval? = nil) async throws -> Data {
        try await data(method: "GET", path: path, timeout: timeout)
    }

    func getData(_ path: String, timeout: TimeInterval, diagnosticRequestID: UUID?) async throws -> Data {
        try await data(method: "GET", path: path, bodyData: nil, timeout: timeout, diagnosticRequestID: diagnosticRequestID)
    }

    public func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        let data = try await data(method: "POST", path: path, body: body)
        return try decode(T.self, from: data)
    }

    public func post<Body: Encodable>(_ path: String, body: Body) async throws {
        _ = try await data(method: "POST", path: path, body: body)
    }

    public func postData(_ path: String, data bodyData: Data) async throws -> Data {
        try await data(method: "POST", path: path, bodyData: bodyData, contentType: "application/json")
    }

    public func postRaw<T: Decodable>(_ path: String, data bodyData: Data, contentType: String) async throws -> T {
        let data = try await data(method: "POST", path: path, bodyData: bodyData, contentType: contentType)
        return try decode(T.self, from: data)
    }

    public func put<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        let data = try await data(method: "PUT", path: path, body: body)
        return try decode(T.self, from: data)
    }

    public func patch<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        let data = try await data(method: "PATCH", path: path, body: body)
        return try decode(T.self, from: data)
    }

    public func delete(_ path: String) async throws {
        _ = try await data(method: "DELETE", path: path)
    }

    public func setAuthToken(_ token: String) {
        authToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func installAuthSession(_ session: AuthSession) async {
        authToken = session.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        await authSessionStore.save(session, for: baseURL)
    }

    public func installStaticAuthToken(_ token: String) async {
        authToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        await authSessionStore.saveStaticToken(authToken, for: baseURL)
    }

    public func updateAuthSessionUser(_ user: AuthUserProfile) async {
        await authSessionStore.updateUser(user, for: baseURL)
    }

    public func clearAuthSession() async {
        authToken = ""
        await authSessionStore.clear(for: baseURL)
    }

    public func hasStoredAuthSession() async -> Bool {
        await authSessionStore.session(for: baseURL) != nil
    }

    public func currentAccessToken() async -> String? {
        await resolvedAuthToken()
    }

    public nonisolated func url(for path: String) -> URL {
        URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL.appendingPathComponent(path)
    }

    public nonisolated static func encodePathSegment(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    public nonisolated static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func data<Body: Encodable>(
        method: String,
        path: String,
        body: Body? = Optional<EmptyBody>.none,
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        let bodyData = try body.map { try encoder.encode($0) }
        return try await data(method: method, path: path, bodyData: bodyData, timeout: timeout)
    }

    private func data(
        method: String,
        path: String,
        bodyData: Data?,
        timeout: TimeInterval? = nil,
        contentType: String = "application/json",
        diagnosticRequestID: UUID? = nil
    ) async throws -> Data {
        // #region agent debug
#if DEBUG
        let traceStart = ContinuousClock.now
        let traceID = UUID().uuidString
        let traceRoute = path.hasPrefix("/v1/agent-sessions") ? "catalog"
            : path.contains("/sessions") ? "session"
            : path.hasPrefix("/v1/agents") ? "agents"
            : path.hasPrefix("/v1/projects") ? "projects" : "other"
        let traceTopology: String
        switch endpoint {
        case .direct: traceTopology = "direct"
        case .relay: traceTopology = "relay"
        case .managed: traceTopology = "managed"
        }
        ChatLatencyTrace.record("H2", "http.data", "started", data: ["id": traceID, "route": traceRoute, "method": method, "topology": traceTopology])
        defer {
            ChatLatencyTrace.record("H2", "http.data", "finished", data: ["id": traceID, "elapsed_ms": ChatLatencyTrace.milliseconds(since: traceStart)])
        }
#endif
// #endregion
        if case .managed(_, let targetDeviceID) = endpoint {
            ConnectionTraffic.shared.update(endpoint, requests: 1)
            defer { ConnectionTraffic.shared.update(endpoint, requests: -1) }
            let startedAt = Date()
            let response: RemoteCoreResponse
            if await ConsoleRemoteClientRegistry.shared.contains(hostID: targetDeviceID) {
                response = try await ConsoleRemoteClientRegistry.shared.request(hostID: targetDeviceID, method: method, path: normalizedTargetPath(path), body: bodyData, timeout: timeout ?? 30)
            } else {
                response = try await ManagedRemoteConnection.shared.sendCoreRequest(to: targetDeviceID, method: method, path: normalizedTargetPath(path), body: bodyData, timeout: .seconds(timeout ?? 30))
            }
            ConnectionTraffic.shared.update(endpoint, sent: bodyData?.count ?? 0, received: response.body.count)
            logger.info("http.managed.completed", metadata: [
                "duration_ms": .stringConvertible(Int(Date().timeIntervalSince(startedAt) * 1_000)),
                "method": .string(method), "path": .string(url(for: path).path),
                "status": .stringConvertible(response.status), "bytes": .stringConvertible(response.body.count),
            ])
            guard (200..<300).contains(response.status) else {
                throw APIError.httpError(
                    statusCode: response.status,
                    body: String(data: response.body, encoding: .utf8)
                )
            }
            return response.body
        }
        let initialToken = await resolvedAuthToken()
        let initial = try await send(
            method: method,
            path: path,
            bodyData: bodyData,
            timeout: timeout,
            authToken: initialToken,
            contentType: contentType,
            diagnosticRequestID: diagnosticRequestID
        )

        guard statusCode(for: initial.response) == 401,
              shouldAttemptSessionRecovery(for: path) else {
            try validate(response: initial.response, data: initial.data)
            return initial.data
        }

        logger.warning(
            "http.auth.recovery-started",
            metadata: [
                "method": .string(method),
                "path": .string(path),
                "server": .string(Self.serverDescription(baseURL)),
            ]
        )

        let recovery = try await authSessionStore.recoverSession(
            for: baseURL,
            rejectedAccessToken: initialToken,
            refreshSession: { refreshToken in try await self.refreshSession(using: refreshToken) }
        )
        guard recovery != .superseded else { throw CancellationError() }
        try Task.checkCancellation()

        if case .recovered(let refreshedSession) = recovery {
            logger.info(
                "http.auth.recovery-succeeded",
                metadata: [
                    "method": .string(method),
                    "path": .string(path),
                    "server": .string(Self.serverDescription(baseURL)),
                ]
            )
            if authToken.isEmpty || authToken == initialToken {
                authToken = refreshedSession.accessToken
            }
            let retried = try await send(
                method: method,
                path: path,
                bodyData: bodyData,
                timeout: timeout,
                authToken: refreshedSession.accessToken,
                contentType: contentType,
                diagnosticRequestID: diagnosticRequestID
            )
            if statusCode(for: retried.response) == 401 {
                authToken = ""
                await authSessionStore.clear(for: baseURL)
                notifyAuthenticationRequired()
            }
            try validate(response: retried.response, data: retried.data)
            return retried.data
        }

        if authToken == initialToken {
            authToken = ""
        }
        logger.warning(
            "http.auth.recovery-failed",
            metadata: [
                "method": .string(method),
                "path": .string(path),
                "server": .string(Self.serverDescription(baseURL)),
            ]
        )
        notifyAuthenticationRequired()
        try validate(response: initial.response, data: initial.data)
        return initial.data
    }

    private func resolvedAuthToken() async -> String? {
        if !authToken.isEmpty {
            return authToken
        }
        let stored = await authSessionStore.session(for: baseURL)?.accessToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stored?.isEmpty == false ? stored : nil
    }

    private func send(
        method: String,
        path: String,
        bodyData: Data?,
        timeout: TimeInterval?,
        authToken: String?,
        contentType: String,
        diagnosticRequestID: UUID? = nil
    ) async throws -> (data: Data, response: URLResponse) {
        let targetURL = url(for: path)
        var request = try await makeURLRequest(
            method: method,
            path: path,
            targetURL: targetURL,
            bodyData: bodyData,
            timeout: timeout,
            authToken: authToken,
            contentType: contentType
        )

        let requestID = (diagnosticRequestID ?? UUID()).uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Sloppy-Request-ID")
        let startedAt = ContinuousClock.now
        let metadata: Logger.Metadata = [
            "auth": .string(authToken?.isEmpty == false ? "present" : "absent"),
            "body_bytes": .stringConvertible(bodyData?.count ?? 0),
            "method": .string(method),
            "path": .string(targetURL.path.isEmpty ? "/" : targetURL.path),
            "request_id": .string(requestID),
            "server": .string(Self.serverDescription(targetURL)),
        ]
        logger.info("http.request.started", metadata: metadata)

        ConnectionTraffic.shared.update(endpoint, requests: 1)
        defer { ConnectionTraffic.shared.update(endpoint, requests: -1) }
        do {
            // Authentication/request preparation may suspend while the owner closes.
            // Foundation cannot create another task after URLSession invalidation.
            try Task.checkCancellation()
            let rawResult = try await session.data(
                for: request,
                delegate: HTTPRequestTimingLogger(logger: logger, metadata: metadata)
            )
            let result = try decodeRelayedResponseIfNeeded(
                data: rawResult.0,
                response: rawResult.1,
                targetURL: targetURL
            )
            ConnectionTraffic.shared.update(endpoint, sent: bodyData?.count ?? 0, received: result.0.count)
            var responseMetadata = metadata
            responseMetadata["elapsed"] = .stringConvertible(startedAt.duration(to: .now))
            responseMetadata["response_bytes"] = .stringConvertible(result.0.count)
            if let http = rawResult.1 as? HTTPURLResponse {
                responseMetadata["core_timing"] = http.value(forHTTPHeaderField: "Server-Timing").map(Logger.MetadataValue.string)
                responseMetadata["core_route"] = http.value(forHTTPHeaderField: "X-Sloppy-Route").map(Logger.MetadataValue.string)
            }
            if let statusCode = statusCode(for: result.1) {
                responseMetadata["status"] = .stringConvertible(statusCode)
                if statusCode >= 400 {
                    logger.warning("http.request.completed", metadata: responseMetadata)
                } else {
                    logger.info("http.request.completed", metadata: responseMetadata)
                }
            } else {
                logger.error("http.request.invalid-response", metadata: responseMetadata)
            }
            return result
        } catch {
            var failureMetadata = metadata
            failureMetadata["elapsed"] = .stringConvertible(startedAt.duration(to: .now))
            let failure = error as NSError
            failureMetadata["error_domain"] = .string(failure.domain)
            failureMetadata["error_code"] = .stringConvertible(failure.code)
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                logger.debug("http.request.cancelled", metadata: failureMetadata)
            } else {
                logger.warning("http.request.failed", metadata: failureMetadata)
            }
            throw error
        }
    }

    private func makeURLRequest(
        method: String,
        path: String,
        targetURL: URL,
        bodyData: Data?,
        timeout: TimeInterval?,
        authToken: String?,
        contentType: String
    ) async throws -> URLRequest {
        let requestURL: URL
        switch endpoint {
        case .direct:
            requestURL = targetURL
        case .relay(let coordinatorBaseURL, let targetNodeID):
            let encodedNodeID = Self.encodePathSegment(targetNodeID)
            requestURL = URL(
                string: "/v1/node/mesh/nodes/\(encodedNodeID)/core",
                relativeTo: coordinatorBaseURL
            )?.absoluteURL ?? coordinatorBaseURL
        case .managed:
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = endpoint.isDirect ? method : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        if let timeout {
            request.timeoutInterval = timeout
        }

        switch endpoint {
        case .direct:
            if let bodyData {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyData
            }
        case .relay:
            var forwardedHeaders: [String: String] = [:]
            forwardedHeaders["content-type"] = contentType
            if let userID = await authSessionStore.session(for: baseURL)?.user?.id,
               !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                forwardedHeaders["x-sloppy-user-context"] = userID
            }
            let payload = MeshCoreProxyRequest(
                method: method,
                path: normalizedTargetPath(path),
                headers: forwardedHeaders,
                bodyBase64: bodyData?.base64EncodedString()
            )
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(payload)
        case .managed:
            throw APIError.invalidResponse
        }
        return request
    }

    private func decodeRelayedResponseIfNeeded(
        data: Data,
        response: URLResponse,
        targetURL: URL
    ) throws -> (data: Data, response: URLResponse) {
        guard case .relay = endpoint else {
            return (data, response)
        }
        guard let outerHTTP = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(outerHTTP.statusCode) else {
            return (data, response)
        }
        let proxy: MeshCoreProxyResponse
        do {
            proxy = try decoder.decode(MeshCoreProxyResponse.self, from: data)
        } catch {
            throw APIError.decodingFailed("Invalid mesh Core proxy response: \(error.localizedDescription)")
        }
        guard let body = Data(base64Encoded: proxy.bodyBase64),
              let synthetic = HTTPURLResponse(
                url: targetURL,
                statusCode: proxy.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": proxy.contentType]
              ) else {
            throw APIError.invalidResponse
        }
        return (body, synthetic)
    }

    private func normalizedTargetPath(_ path: String) -> String {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return path.hasPrefix("/") ? path : "/\(path)"
        }
        components.scheme = nil
        components.host = nil
        components.port = nil
        let value = components.string ?? path
        return value.hasPrefix("/") ? value : "/\(value)"
    }

    private func refreshSession(using refreshToken: String) async throws -> AuthSession? {
        struct RefreshPayload: Encodable { var refreshToken: String }

        do {
            let bodyData = try encoder.encode(RefreshPayload(refreshToken: refreshToken))
            let result = try await send(
                method: "POST",
                path: "/v1/auth/refresh",
                bodyData: bodyData,
                timeout: nil,
                authToken: nil,
                contentType: "application/json"
            )
            try validate(response: result.response, data: result.data)
            return try decode(AuthSession.self, from: result.data)
        } catch let error as APIError where error.statusCode == 401 || error.statusCode == 403 {
            logger.warning("Could not refresh authentication session: \(error.diagnosticDescription)")
            return nil
        }
    }

    private func shouldAttemptSessionRecovery(for path: String) -> Bool {
        switch path {
        case "/v1/auth/challenge",
             "/v1/auth/login",
             "/v1/auth/refresh",
             "/v1/auth/bootstrap",
             "/v1/auth/device-pairing/redeem",
             "/v1/auth/register",
             "/v1/auth/password-reset",
             "/v1/dashboard/auth/validate":
            return false
        default:
            return true
        }
    }

    private func statusCode(for response: URLResponse) -> Int? {
        (response as? HTTPURLResponse)?.statusCode
    }

    private nonisolated static func serverDescription(_ url: URL) -> String {
        guard let host = url.host else { return "unknown-server" }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    private func notifyAuthenticationRequired() {
        NotificationCenter.default.post(
            name: AuthSessionNotifications.authenticationRequired,
            object: nil,
            userInfo: [AuthSessionNotifications.baseURLUserInfoKey: baseURL.absoluteString]
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = data.isEmpty ? nil : String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }
}

private final class HTTPRequestTimingLogger: NSObject, URLSessionTaskDelegate {
    private let logger: Logger
    private let metadata: Logger.Metadata

    init(logger: Logger, metadata: Logger.Metadata) {
        self.logger = logger
        self.metadata = metadata
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let duration = metrics.taskInterval.duration
        // Keep detailed timings for regressions, failures and health probes.
        guard duration >= 1 || task.error != nil || metadata["path"] == .string("/health") else { return }
        var details = metadata
        details["total_ms"] = Self.milliseconds(duration)
        details["transactions"] = .stringConvertible(metrics.transactionMetrics.count)
        if let transaction = metrics.transactionMetrics.last {
            details["dns_ms"] = Self.elapsed(transaction.domainLookupStartDate, transaction.domainLookupEndDate)
            details["connect_ms"] = Self.elapsed(transaction.connectStartDate, transaction.connectEndDate)
            details["tls_ms"] = Self.elapsed(transaction.secureConnectionStartDate, transaction.secureConnectionEndDate)
            details["first_byte_ms"] = Self.elapsed(transaction.requestEndDate, transaction.responseStartDate)
            details["download_ms"] = Self.elapsed(transaction.responseStartDate, transaction.responseEndDate)
            details["reused_connection"] = .stringConvertible(transaction.isReusedConnection)
        }
        logger.info("http.request.network-timing", metadata: details)
    }

    private static func elapsed(_ start: Date?, _ end: Date?) -> Logger.MetadataValue? {
        guard let start, let end else { return nil }
        return milliseconds(end.timeIntervalSince(start))
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Logger.MetadataValue {
        .stringConvertible(max(0, Int(seconds * 1_000)))
    }
}

private struct MeshCoreProxyRequest: Encodable {
    var method: String
    var path: String
    var headers: [String: String]
    var bodyBase64: String?
}

private struct MeshCoreProxyResponse: Decodable {
    var status: Int
    var contentType: String
    var bodyBase64: String
}

private struct EmptyBody: Encodable {}
