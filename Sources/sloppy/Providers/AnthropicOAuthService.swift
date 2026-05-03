import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import PluginSDK
import Protocols

struct AnthropicOAuthStatus: Sendable {
    var hasCredentials: Bool
    var source: String?
    var expiresAt: String?
    var refreshable: Bool
}

struct AnthropicOAuthService: @unchecked Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let authorizationEndpoint = URL(string: "https://console.anthropic.com/oauth/authorize")!
    private static let tokenEndpoints = [
        URL(string: "https://platform.claude.com/v1/oauth/token")!,
        URL(string: "https://console.anthropic.com/v1/oauth/token")!,
    ]
    private static let scopes = [
        "user:inference",
        "user:profile",
        "user:sessions:claude_code",
        "offline_access",
    ]
    private static let logger = Logger(label: "sloppy.core.anthropic-oauth")

    private struct PendingSession: Codable, Sendable {
        var state: String
        var codeVerifier: String
        var redirectURI: String
        var createdAt: String
    }

    private struct StoredAuth: Codable, Sendable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Int64?
        var scopes: [String]?
        var source: String
        var lastRefresh: String

        var isRefreshable: Bool {
            !(refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    private struct TokenResponse: Decodable {
        var accessToken: String
        var refreshToken: String?
        var expiresIn: Int?
        var scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case scope
        }
    }

    enum Error: LocalizedError {
        case invalidRedirectURI
        case missingCredentials
        case missingPendingSession
        case invalidCallback
        case stateMismatch
        case missingAuthorizationCode
        case tokenExchangeFailed(String)
        case missingAccessToken
        case missingClaudeCredentials

        var errorDescription: String? {
            switch self {
            case .invalidRedirectURI:
                return "Anthropic OAuth redirect URI is invalid."
            case .missingCredentials:
                return "Anthropic OAuth is not connected yet. Connect Anthropic OAuth, import Claude Code credentials, or paste a setup token."
            case .missingPendingSession:
                return "Anthropic OAuth login session is missing. Start sign-in again."
            case .invalidCallback:
                return "Anthropic OAuth callback is invalid."
            case .stateMismatch:
                return "Anthropic OAuth state mismatch. Start sign-in again."
            case .missingAuthorizationCode:
                return "Anthropic OAuth callback is missing the authorization code."
            case let .tokenExchangeFailed(message):
                return "Anthropic OAuth token exchange failed: \(message)"
            case .missingAccessToken:
                return "Anthropic OAuth token response is missing the access token."
            case .missingClaudeCredentials:
                return "Claude Code credentials were not found in ~/.claude/.credentials.json or .claude/settings.json."
            }
        }
    }

    private let workspaceRootURL: URL
    private let fileManager: FileManager
    private let transport: Transport
    private let now: @Sendable () -> Date

    init(
        workspaceRootURL: URL,
        fileManager: FileManager = .default,
        transport: Transport? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.workspaceRootURL = workspaceRootURL
        self.fileManager = fileManager
        self.transport = transport ?? { request in
            let (data, response) = try await SloppyURLSessionFactory.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, http)
        }
        self.now = now
    }

    func startLogin(redirectURI: String) throws -> AnthropicOAuthStartResponse {
        guard let redirectURL = URL(string: redirectURI), let scheme = redirectURL.scheme, !scheme.isEmpty else {
            throw Error.invalidRedirectURI
        }

        let verifier = Self.randomURLSafeString(byteCount: 48)
        let state = Self.randomURLSafeString(byteCount: 24)
        let challenge = Self.sha256Base64URL(verifier)
        let pending = PendingSession(
            state: state,
            codeVerifier: verifier,
            redirectURI: redirectURI,
            createdAt: Self.iso8601String(from: now())
        )
        try savePendingSession(pending)

        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: Self.clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]

        guard let authorizationURL = components?.url else {
            throw Error.invalidRedirectURI
        }

        return AnthropicOAuthStartResponse(
            authorizationURL: authorizationURL.absoluteString,
            redirectURI: redirectURI,
            state: state
        )
    }

    func completeLogin(request: AnthropicOAuthCompleteRequest) async throws -> AnthropicOAuthCompleteResponse {
        let pending = try loadPendingSession()
        let callback = extractCallbackValues(from: request.callbackURL)
        let code = request.code ?? callback.code
        let state = request.state ?? callback.state

        guard let code, !code.isEmpty else {
            throw Error.missingAuthorizationCode
        }
        guard let state, !state.isEmpty else {
            throw Error.invalidCallback
        }
        guard state == pending.state else {
            throw Error.stateMismatch
        }

        let stored = try await exchangeCode(
            code: code,
            codeVerifier: pending.codeVerifier,
            redirectURI: pending.redirectURI
        )
        try saveStoredAuth(stored)
        try writeClaudeCodeCredentials(auth: stored)
        try removePendingSession()

        return AnthropicOAuthCompleteResponse(
            ok: true,
            message: "Anthropic OAuth connected.",
            source: stored.source,
            expiresAt: Self.iso8601String(fromEpochMilliseconds: stored.expiresAt),
            refreshable: stored.isRefreshable
        )
    }

    func importClaudeCodeCredentials() async throws -> AnthropicOAuthImportClaudeResponse {
        guard var imported = try readClaudeCodeCredentials() else {
            throw Error.missingClaudeCredentials
        }
        if Self.tokenNeedsRefresh(imported.expiresAt, now: now()), imported.isRefreshable {
            imported = try await refresh(stored: imported)
            imported.source = "claude_code_credentials"
            try writeClaudeCodeCredentials(auth: imported)
        }
        try saveStoredAuth(imported)
        return AnthropicOAuthImportClaudeResponse(
            ok: true,
            message: "Claude Code credentials imported.",
            source: imported.source,
            expiresAt: Self.iso8601String(fromEpochMilliseconds: imported.expiresAt),
            refreshable: imported.isRefreshable
        )
    }

    func status() -> AnthropicOAuthStatus {
        if let stored = try? preferredStoredAuth() {
            return AnthropicOAuthStatus(
                hasCredentials: true,
                source: stored.source,
                expiresAt: Self.iso8601String(fromEpochMilliseconds: stored.expiresAt),
                refreshable: stored.isRefreshable
            )
        }
        if claudeSettingsEnvironment().hasAuthToken {
            return AnthropicOAuthStatus(
                hasCredentials: true,
                source: "claude_settings_env",
                expiresAt: nil,
                refreshable: false
            )
        }
        return AnthropicOAuthStatus(
            hasCredentials: false,
            source: nil,
            expiresAt: nil,
            refreshable: false
        )
    }

    func currentAccessToken() -> String? {
        if let stored = try? preferredStoredAuth() {
            return stored.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for environmentKey in ["ANTHROPIC_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_AUTH_TOKEN"] {
            let value = ProcessInfo.processInfo.environment[environmentKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty {
                return value
            }
        }
        let settingsToken = claudeSettingsEnvironment().authToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !settingsToken.isEmpty {
            return settingsToken
        }
        let legacyAPIKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacyAPIKey.isEmpty, Self.isOAuthStyleToken(legacyAPIKey) {
            return legacyAPIKey
        }
        return nil
    }

    func claudeSettingsEnvironment() -> ClaudeSettingsEnvironment {
        ClaudeSettingsEnvironment.load(workspaceRootURL: workspaceRootURL)
    }

    func ensureValidToken() async throws {
        if var stored = try? loadStoredAuth() {
            guard stored.isRefreshable, Self.tokenNeedsRefresh(stored.expiresAt, now: now()) else {
                return
            }
            stored = try await refresh(stored: stored)
            try saveStoredAuth(stored)
            try writeClaudeCodeCredentials(auth: stored)
            return
        }

        if var claude = try readClaudeCodeCredentials(), claude.isRefreshable {
            guard Self.tokenNeedsRefresh(claude.expiresAt, now: now()) else {
                try saveStoredAuth(claude)
                return
            }
            claude = try await refresh(stored: claude)
            claude.source = "claude_code_credentials"
            try saveStoredAuth(claude)
            try writeClaudeCodeCredentials(auth: claude)
        }
    }

    func disconnect() throws {
        try removeStoredAuth()
        try removePendingSession()
        try writeClaudeCodeCredentials(auth: nil)
        Self.logger.info("anthropic_oauth.disconnected")
    }

    func probe(apiURL: URL, manualToken: String?) async -> ProviderProbeResponse {
        do {
            try await ensureValidToken()
        } catch {
            Self.logger.debug("anthropic_oauth.refresh_failed", metadata: ["error": .string(error.localizedDescription)])
        }

        let trimmedManualToken = manualToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = currentAccessToken() ?? (!trimmedManualToken.isEmpty ? trimmedManualToken : nil)
        guard let token, !token.isEmpty else {
            return ProviderProbeResponse(
                providerId: .anthropicOAuth,
                ok: false,
                usedEnvironmentKey: false,
                message: Error.missingCredentials.localizedDescription,
                models: []
            )
        }

        do {
            try await verifyAnthropicKey(apiKey: token, baseURL: apiURL)
            return ProviderProbeResponse(
                providerId: .anthropicOAuth,
                ok: true,
                usedEnvironmentKey: false,
                message: "Connected to Anthropic OAuth.",
                models: ProviderProbeService.anthropicModelCatalog
            )
        } catch {
            return ProviderProbeResponse(
                providerId: .anthropicOAuth,
                ok: false,
                usedEnvironmentKey: false,
                message: "Failed to connect to Anthropic OAuth: \(error.localizedDescription)",
                models: []
            )
        }
    }

    private func verifyAnthropicKey(apiKey: String, baseURL: URL) async throws {
        let endpoint = baseURL.appendingPathComponent("v1/messages")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let authHeaders = OAuthAnthropicAuthHeaders.authenticationHeaders(
            apiKey: apiKey,
            baseURL: baseURL,
            additionalBetas: nil
        )
        for (field, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let body: [String: Any] = [
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) || response.statusCode == 429 else {
            throw URLError(.userAuthenticationRequired)
        }
    }

    private func preferredStoredAuth() throws -> StoredAuth {
        if let stored = try? loadStoredAuth(), stored.isRefreshable {
            return stored
        }
        if let claude = try readClaudeCodeCredentials(), claude.isRefreshable {
            return claude
        }
        if let stored = try? loadStoredAuth() {
            return stored
        }
        if let claude = try readClaudeCodeCredentials() {
            return claude
        }
        throw Error.missingCredentials
    }

    private func refresh(stored: StoredAuth) async throws -> StoredAuth {
        guard let refreshToken = stored.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines), !refreshToken.isEmpty else {
            return stored
        }

        let payload = formEncodedData([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ])

        let token = try await exchangeAgainstTokenEndpoints(payload: payload)
        return makeStoredAuth(from: token, source: stored.source, fallback: stored)
    }

    private func exchangeCode(
        code: String,
        codeVerifier: String,
        redirectURI: String
    ) async throws -> StoredAuth {
        let payload = formEncodedData([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": Self.clientID,
            "code_verifier": codeVerifier,
        ])

        let token = try await exchangeAgainstTokenEndpoints(payload: payload)
        return makeStoredAuth(from: token, source: "sloppy_oauth", fallback: nil)
    }

    private func exchangeAgainstTokenEndpoints(payload: Data) async throws -> TokenResponse {
        var lastError: Swift.Error?
        for endpoint in Self.tokenEndpoints {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.setValue("claude-cli/2.1.74 (external, cli)", forHTTPHeaderField: "User-Agent")
                request.httpBody = payload

                let (data, response) = try await transport(request)
                guard (200..<300).contains(response.statusCode) else {
                    throw Error.tokenExchangeFailed(httpErrorMessage(data: data, statusCode: response.statusCode))
                }

                let token = try JSONDecoder().decode(TokenResponse.self, from: data)
                guard !token.accessToken.isEmpty else {
                    throw Error.missingAccessToken
                }
                return token
            } catch {
                lastError = error
            }
        }
        throw lastError ?? Error.tokenExchangeFailed("No Anthropic OAuth token endpoint succeeded.")
    }

    private func makeStoredAuth(from token: TokenResponse, source: String, fallback: StoredAuth?) -> StoredAuth {
        let scopes = Self.parseScopes(token.scope) ?? fallback?.scopes
        return StoredAuth(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? fallback?.refreshToken,
            expiresAt: Self.expiresAtEpochMilliseconds(expiresIn: token.expiresIn, now: now()) ?? fallback?.expiresAt,
            scopes: scopes,
            source: source,
            lastRefresh: Self.iso8601String(from: now())
        )
    }

    private func readClaudeCodeCredentials() throws -> StoredAuth? {
        let url = claudeCredentialsURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any]
        else {
            return nil
        }

        let accessToken = (oauth["accessToken"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            return nil
        }

        let refreshToken = (oauth["refreshToken"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expiresAt = Self.int64Value(oauth["expiresAt"])
        let scopes = (oauth["scopes"] as? [String])?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return StoredAuth(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scopes: scopes,
            source: "claude_code_credentials",
            lastRefresh: Self.iso8601String(from: now())
        )
    }

    private func writeClaudeCodeCredentials(auth: StoredAuth?) throws {
        let url = claudeCredentialsURL()
        var object: [String: Any] = [:]

        if fileManager.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            object = decoded
        }

        if let auth {
            var oauth: [String: Any] = [
                "accessToken": auth.accessToken,
                "expiresAt": auth.expiresAt ?? 0,
            ]
            if let refreshToken = auth.refreshToken, !refreshToken.isEmpty {
                oauth["refreshToken"] = refreshToken
            }
            if let scopes = auth.scopes, !scopes.isEmpty {
                oauth["scopes"] = scopes
            } else if let existing = object["claudeAiOauth"] as? [String: Any], let scopes = existing["scopes"] {
                oauth["scopes"] = scopes
            }
            object["claudeAiOauth"] = oauth
        } else {
            object.removeValue(forKey: "claudeAiOauth")
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func savePendingSession(_ session: PendingSession) throws {
        try save(session, to: pendingSessionURL())
    }

    private func loadPendingSession() throws -> PendingSession {
        let url = pendingSessionURL()
        guard fileManager.fileExists(atPath: url.path) else {
            throw Error.missingPendingSession
        }
        return try load(PendingSession.self, from: url)
    }

    private func removePendingSession() throws {
        let url = pendingSessionURL()
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func saveStoredAuth(_ auth: StoredAuth) throws {
        try save(auth, to: authFileURL())
    }

    private func loadStoredAuth() throws -> StoredAuth {
        let url = authFileURL()
        guard fileManager.fileExists(atPath: url.path) else {
            throw Error.missingCredentials
        }
        return try load(StoredAuth.self, from: url)
    }

    private func removeStoredAuth() throws {
        let url = authFileURL()
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    private func pendingSessionURL() -> URL {
        oauthDirectoryURL().appendingPathComponent("anthropic-oauth-pending.json")
    }

    private func authFileURL() -> URL {
        oauthDirectoryURL().appendingPathComponent("anthropic-oauth-auth.json")
    }

    private func oauthDirectoryURL() -> URL {
        workspaceRootURL.appendingPathComponent("auth", isDirectory: true)
    }

    private func claudeCredentialsURL() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(".credentials.json")
    }

    private func extractCallbackValues(from callbackURL: String?) -> (code: String?, state: String?) {
        guard let callbackURL = callbackURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !callbackURL.isEmpty,
              let components = URLComponents(string: callbackURL)
        else {
            return (nil, nil)
        }

        let items = components.queryItems ?? []
        return (
            items.first(where: { $0.name == "code" })?.value,
            items.first(where: { $0.name == "state" })?.value
        )
    }

    private func formEncodedData(_ values: [String: String]) -> Data {
        let body = values.map { key, value in
            "\(Self.percentEncode(key))=\(Self.percentEncode(value))"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private func httpErrorMessage(data: Data, statusCode: Int) -> String {
        if let body = String(data: data, encoding: .utf8), !body.isEmpty {
            return "status \(statusCode): \(body)"
        }
        return "status \(statusCode)"
    }

    private static func tokenNeedsRefresh(_ expiresAt: Int64?, now: Date) -> Bool {
        guard let expiresAt else { return false }
        let delta = Double(expiresAt) / 1000.0 - now.timeIntervalSince1970
        return delta < 300
    }

    private static func isOAuthStyleToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("sk-ant-api")
    }

    private static func expiresAtEpochMilliseconds(expiresIn: Int?, now: Date) -> Int64? {
        guard let expiresIn, expiresIn > 0 else { return nil }
        return Int64((now.timeIntervalSince1970 + Double(expiresIn)) * 1000.0)
    }

    private static func parseScopes(_ scope: String?) -> [String]? {
        guard let scope = scope?.trimmingCharacters(in: .whitespacesAndNewlines), !scope.isEmpty else {
            return nil
        }
        let scopes = scope
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        return scopes.isEmpty ? nil : scopes
    }

    private static func int64Value(_ raw: Any?) -> Int64? {
        if let number = raw as? NSNumber {
            return number.int64Value
        }
        if let string = raw as? String {
            return Int64(string)
        }
        return nil
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max) }
        return base64URLEncode(Data(bytes))
    }

    private static func sha256Base64URL(_ value: String) -> String {
        let digest = SHA256Digest.hash(Data(value.utf8))
        return base64URLEncode(Data(digest))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func iso8601String(fromEpochMilliseconds value: Int64?) -> String? {
        guard let value, value > 0 else { return nil }
        return iso8601String(from: Date(timeIntervalSince1970: Double(value) / 1000.0))
    }
}

private enum SHA256Digest {
    private static let initialHash: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hash(_ data: Data) -> [UInt8] {
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        message.append(contentsOf: withUnsafeBytes(of: bitLength.bigEndian, Array.init))

        var hash = initialHash
        var chunk = 0
        while chunk < message.count {
            let chunkBytes = Array(message[chunk..<(chunk + 64)])
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let offset = index * 4
                words[index] =
                    (UInt32(chunkBytes[offset]) << 24) |
                    (UInt32(chunkBytes[offset + 1]) << 16) |
                    (UInt32(chunkBytes[offset + 2]) << 8) |
                    UInt32(chunkBytes[offset + 3])
            }
            for index in 16..<64 {
                let s0 = rotateRight(words[index - 15], by: 7) ^ rotateRight(words[index - 15], by: 18) ^ (words[index - 15] >> 3)
                let s1 = rotateRight(words[index - 2], by: 17) ^ rotateRight(words[index - 2], by: 19) ^ (words[index - 2] >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }

            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]

            for index in 0..<64 {
                let s1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                let choice = (e & f) ^ ((~e) & g)
                let temp1 = h &+ s1 &+ choice &+ k[index] &+ words[index]
                let s0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ majority

                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            hash[0] = hash[0] &+ a
            hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c
            hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e
            hash[5] = hash[5] &+ f
            hash[6] = hash[6] &+ g
            hash[7] = hash[7] &+ h
            chunk += 64
        }

        return hash.flatMap { word in
            [
                UInt8((word >> 24) & 0xff),
                UInt8((word >> 16) & 0xff),
                UInt8((word >> 8) & 0xff),
                UInt8(word & 0xff),
            ]
        }
    }

    private static func rotateRight(_ value: UInt32, by: UInt32) -> UInt32 {
        (value >> by) | (value << (32 - by))
    }
}
