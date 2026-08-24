import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

public enum APIError: Error, Sendable {
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
        case .httpError(let statusCode, _):
            return "HTTP \(statusCode)"
        case .decodingFailed(let message):
            return "Response decoding failed: \(message)"
        }
    }
}

public actor BackendHTTPClient {
    public nonisolated let baseURL: URL

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: Logger
    private let authSessionStore: AuthSessionStore
    private var authToken: String

    public init(
        baseURL: URL = URL(string: "http://localhost:25101")!,
        authToken: String = "",
        session: URLSession = .shared,
        authSessionStore: AuthSessionStore = .shared,
        logger: Logger = Logger(label: "sloppy.backend-http")
    ) {
        self.baseURL = baseURL
        self.session = session
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

    public func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        let data = try await data(method: "POST", path: path, body: body)
        return try decode(T.self, from: data)
    }

    public func post<Body: Encodable>(_ path: String, body: Body) async throws {
        _ = try await data(method: "POST", path: path, body: body)
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
        let initialToken = await resolvedAuthToken()
        let initial = try await send(
            method: method,
            path: path,
            bodyData: bodyData,
            timeout: timeout,
            authToken: initialToken
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

        let recovery = await authSessionStore.recoverSession(
            for: baseURL,
            rejectedAccessToken: initialToken
        ) { [weak self] refreshToken in
            await self?.refreshSession(using: refreshToken)
        }

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
                authToken: refreshedSession.accessToken
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
        authToken: String?
    ) async throws -> (data: Data, response: URLResponse) {
        let url = url(for: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        if let timeout {
            request.timeoutInterval = timeout
        }
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        let requestID = String(UUID().uuidString.prefix(8)).lowercased()
        let startedAt = Date()
        let metadata: Logger.Metadata = [
            "auth": .string(authToken?.isEmpty == false ? "present" : "absent"),
            "body_bytes": .stringConvertible(bodyData?.count ?? 0),
            "method": .string(method),
            "path": .string(url.path.isEmpty ? "/" : url.path),
            "request_id": .string(requestID),
            "server": .string(Self.serverDescription(url)),
        ]
        logger.info("http.request.started", metadata: metadata)

        do {
            let result = try await session.data(for: request)
            var responseMetadata = metadata
            responseMetadata["duration_ms"] = .stringConvertible(
                max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            )
            responseMetadata["response_bytes"] = .stringConvertible(result.0.count)
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
            failureMetadata["duration_ms"] = .stringConvertible(
                max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            )
            failureMetadata["error"] = .string(String(describing: error))
            logger.error("http.request.failed", metadata: failureMetadata)
            throw error
        }
    }

    private func refreshSession(using refreshToken: String) async -> AuthSession? {
        struct RefreshPayload: Encodable { var refreshToken: String }

        do {
            let bodyData = try encoder.encode(RefreshPayload(refreshToken: refreshToken))
            let result = try await send(
                method: "POST",
                path: "/v1/auth/refresh",
                bodyData: bodyData,
                timeout: nil,
                authToken: nil
            )
            try validate(response: result.response, data: result.data)
            return try decode(AuthSession.self, from: result.data)
        } catch {
            let description = (error as? APIError)?.diagnosticDescription
                ?? (error as NSError).localizedDescription
            logger.warning("Could not refresh authentication session: \(description)")
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

private struct EmptyBody: Encodable {}
