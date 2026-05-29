import Foundation
import Protocols

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct GeminiOAuthCredentials: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static let requiredAntigravityScope = "https://www.googleapis.com/auth/cloud-platform"
    static let requiredGenerativeLanguageScope = requiredAntigravityScope

    static let defaultCredentialsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".gemini", isDirectory: true)
        .appendingPathComponent("oauth_creds.json")
    static func sloppyCredentialsURL(workspaceRootURL: URL) -> URL {
        workspaceRootURL
            .appendingPathComponent("auth", isDirectory: true)
            .appendingPathComponent("gemini-oauth-auth.json")
    }

    private static let encodedOAuthClientID = "AWVUXkJFTBZjXFBLUFksAFwDFxwZQSEIHR4AQEtgBBIUUxU1XAwIB0cUAGBZBV4RCV4gSwQdChMvChEWBlwVXj0YCh4EV008CA"
    private static let encodedOAuthClientSecret = "ARQjLCMgIQNnECsVKCQuQlUKVH0dHDQJOUYzDBswCTs0Fgwv"
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    static func oauthClientID() throws -> String {
        try _secretDecode(Self.encodedOAuthClientID)
    }

    static func oauthClientSecret() throws -> String {
        try _secretDecode(Self.encodedOAuthClientSecret)
    }

    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiryDate: Date?
    let scope: String?
    let idToken: String?
    let email: String?
    let projectID: String?
    let managedProjectID: String?

    init(
        accessToken: String,
        refreshToken: String?,
        tokenType: String,
        expiryDate: Date?,
        scope: String? = nil,
        idToken: String? = nil,
        email: String? = nil,
        projectID: String? = nil,
        managedProjectID: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiryDate = expiryDate
        self.scope = scope
        self.idToken = idToken
        self.email = email
        self.projectID = projectID
        self.managedProjectID = managedProjectID
    }

    var authorizationHeaderValue: String {
        "\(tokenType.isEmpty ? "Bearer" : tokenType) \(accessToken)"
    }

    var hasAccessToken: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasRefreshToken: Bool {
        !(refreshToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isUsableForAntigravityCLI: Bool {
        guard let scope, !scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        let scopes = scope
            .split { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }
            .map(String.init)
        return scopes.contains(Self.requiredAntigravityScope)
    }

    var isUsableForGenerativeLanguageAPI: Bool {
        isUsableForAntigravityCLI
    }

    var antigravityScopeDescription: String {
        scope?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? scope!
            : "unknown"
    }

    var generativeLanguageScopeDescription: String {
        antigravityScopeDescription
    }

    static func load(url: URL = defaultCredentialsURL) -> GeminiOAuthCredentials? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(GeminiOAuthCredentials.self, from: data)
    }

    static func load(workspaceRootURL: URL, legacyURL: URL = defaultCredentialsURL) -> GeminiOAuthCredentials? {
        load(url: sloppyCredentialsURL(workspaceRootURL: workspaceRootURL)) ?? load(url: legacyURL)
    }

    func refreshedIfNeeded(
        url: URL = defaultCredentialsURL,
        now: Date = Date(),
        leeway: TimeInterval = 120,
        transport: Transport? = nil
    ) async throws -> GeminiOAuthCredentials {
        if hasAccessToken, let expiryDate, expiryDate.timeIntervalSince(now) > leeway {
            return self
        }
        if hasAccessToken, expiryDate == nil {
            return self
        }

        let refreshToken = (refreshToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refreshToken.isEmpty else {
            if hasAccessToken {
                return self
            }
            throw GeminiOAuthCredentialsError.missingAccessAndRefreshToken
        }

        let refreshed: RefreshTokenResponse
        do {
            refreshed = try await refreshAccessToken(refreshToken: refreshToken, transport: transport)
        } catch let error as GeminiOAuthCredentialsError {
            if error.isInvalidGrant {
                try? Self.clear(url: url)
            }
            throw error
        }
        let nextRefreshToken = refreshed.refreshToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let next = GeminiOAuthCredentials(
            accessToken: refreshed.accessToken,
            refreshToken: nextRefreshToken?.isEmpty == false ? nextRefreshToken : refreshToken,
            tokenType: refreshed.tokenType?.isEmpty == false ? refreshed.tokenType! : tokenType,
            expiryDate: refreshed.expiresIn.map { now.addingTimeInterval(max(60, $0)) },
            scope: refreshed.scope ?? scope,
            idToken: refreshed.idToken ?? idToken,
            email: email,
            projectID: projectID,
            managedProjectID: managedProjectID
        )
        try next.save(url: url)
        return next
    }

    private func refreshAccessToken(refreshToken: String, transport: Transport?) async throws -> RefreshTokenResponse {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formURLEncodedBody([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": try Self.oauthClientID(),
            "client_secret": try Self.oauthClientSecret(),
        ])

        let resolvedTransport = transport ?? Self.defaultTransport
        let (data, response) = try await resolvedTransport(request)
        guard (200..<300).contains(response.statusCode) else {
            throw GeminiOAuthCredentialsError.refreshFailed(
                statusCode: response.statusCode,
                body: Self.sanitizedPayloadSnippet(data)
            )
        }

        return try JSONDecoder().decode(RefreshTokenResponse.self, from: data)
    }

    private func save(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(macOS) || os(Linux)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #endif

        let data: Data
        if Self.usesSloppyStorageFormat(url: url) {
            data = try JSONEncoder().encode(StoredSloppyCredentials(credentials: self))
        } else {
            data = try JSONEncoder().encode(StoredLegacyCredentials(credentials: self))
        }
        try data.write(to: url, options: [.atomic])
        #if os(macOS) || os(Linux)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }

    func saveSloppy(url: URL) throws {
        try save(url: url)
    }

    private static func clear(url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func defaultTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await SloppyURLSessionFactory.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }

    private static func formURLEncodedBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    static func sanitizedPayloadSnippet(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        let text = String(decoding: data.prefix(512), as: UTF8.self)
        return text.replacingOccurrences(
            of: #"(?i)(access_token|refresh_token|id_token|client_secret)"\s*:\s*"[^"]*""#,
            with: #"$1":"[REDACTED]""#,
            options: .regularExpression
        )
    }

    private struct RefreshTokenResponse: Decodable {
        let accessToken: String
        let expiresIn: TimeInterval?
        let tokenType: String?
        let refreshToken: String?
        let scope: String?
        let idToken: String?

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
            case refreshToken = "refresh_token"
            case scope
            case idToken = "id_token"
        }
    }

    private static func usesSloppyStorageFormat(url: URL) -> Bool {
        url.lastPathComponent == "gemini-oauth-auth.json" || url.lastPathComponent == "google_oauth.json"
    }

    private struct RefreshParts: Sendable {
        let refreshToken: String
        let projectID: String?
        let managedProjectID: String?

        static func parse(_ packed: String?) -> RefreshParts {
            let trimmed = packed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                return RefreshParts(refreshToken: "", projectID: nil, managedProjectID: nil)
            }
            let parts = trimmed.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            return RefreshParts(
                refreshToken: String(parts[safe: 0] ?? ""),
                projectID: String(parts[safe: 1] ?? "").nilIfBlank,
                managedProjectID: String(parts[safe: 2] ?? "").nilIfBlank
            )
        }

        func formatted() -> String {
            let token = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return "" }
            let project = projectID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let managedProject = managedProjectID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if project.isEmpty && managedProject.isEmpty {
                return token
            }
            return "\(token)|\(project)|\(managedProject)"
        }
    }

    private struct StoredLegacyCredentials: Encodable {
        let accessToken: String
        let refreshToken: String?
        let tokenType: String
        let expiryDate: Int64?
        let scope: String?
        let idToken: String?

        init(credentials: GeminiOAuthCredentials) {
            accessToken = credentials.accessToken
            refreshToken = credentials.refreshToken
            tokenType = credentials.tokenType.isEmpty ? "Bearer" : credentials.tokenType
            expiryDate = credentials.expiryDate.map { Int64($0.timeIntervalSince1970 * 1000) }
            scope = credentials.scope
            idToken = credentials.idToken
        }

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case tokenType = "token_type"
            case expiryDate = "expiry_date"
            case scope
            case idToken = "id_token"
        }
    }

    private struct StoredSloppyCredentials: Encodable {
        let access: String
        let refresh: String
        let expires: Int64?
        let email: String?

        init(credentials: GeminiOAuthCredentials) {
            access = credentials.accessToken
            refresh = RefreshParts(
                refreshToken: credentials.refreshToken ?? "",
                projectID: credentials.projectID,
                managedProjectID: credentials.managedProjectID
            ).formatted()
            expires = credentials.expiryDate.map { Int64($0.timeIntervalSince1970 * 1000) }
            email = credentials.email
        }
    }
}

extension GeminiOAuthCredentials: Decodable {
    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiryDate = "expiry_date"
        case scope
        case idToken = "id_token"
        case access
        case refresh
        case expires
        case email
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let accessToken = (try container.decodeIfPresent(String.self, forKey: .accessToken)
            ?? container.decodeIfPresent(String.self, forKey: .access))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let packedRefresh = try container.decodeIfPresent(String.self, forKey: .refresh)
        let refreshParts = GeminiOAuthCredentials.RefreshParts.parse(packedRefresh)
        let refreshToken = (try container.decodeIfPresent(String.self, forKey: .refreshToken)
            ?? refreshParts.refreshToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(accessToken ?? "").isEmpty || !(refreshToken ?? "").isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .accessToken,
                in: container,
                debugDescription: "Antigravity CLI OAuth credentials do not contain an access token or refresh token."
            )
        }

        self.accessToken = accessToken ?? ""
        self.refreshToken = refreshToken
        self.tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Bearer"
        self.scope = try container.decodeIfPresent(String.self, forKey: .scope)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.idToken = try container.decodeIfPresent(String.self, forKey: .idToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.projectID = refreshParts.projectID
        self.managedProjectID = refreshParts.managedProjectID

        if let value = try? container.decode(Double.self, forKey: .expiryDate) {
            let seconds = value > 10_000_000_000 ? value / 1000 : value
            self.expiryDate = Date(timeIntervalSince1970: seconds)
        } else if let value = try? container.decode(Double.self, forKey: .expires) {
            let seconds = value > 10_000_000_000 ? value / 1000 : value
            self.expiryDate = Date(timeIntervalSince1970: seconds)
        } else {
            self.expiryDate = nil
        }
    }
}

enum GeminiOAuthCredentialsError: Error, LocalizedError {
    case missingAccessAndRefreshToken
    case missingRequiredScope(currentScopes: String)
    case refreshFailed(statusCode: Int, body: String)
    case codeAssistProjectLoadFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingAccessAndRefreshToken:
            return "Antigravity CLI OAuth credentials do not contain an access token or refresh token. Run the Antigravity CLI login again."
        case .missingRequiredScope(let currentScopes):
            return "Antigravity CLI OAuth credentials are missing the required scope \(GeminiOAuthCredentials.requiredAntigravityScope). Current scopes: \(currentScopes). Provide a Gemini API key or re-authenticate Antigravity CLI OAuth."
        case .refreshFailed(let statusCode, let body):
            if body.isEmpty {
                return "Antigravity CLI OAuth token refresh failed with HTTP \(statusCode)."
            }
            return "Antigravity CLI OAuth token refresh failed with HTTP \(statusCode): \(body)"
        case .codeAssistProjectLoadFailed(let statusCode, let body):
            if body.isEmpty {
                return "Antigravity CLI project discovery failed with HTTP \(statusCode)."
            }
            return "Antigravity CLI project discovery failed with HTTP \(statusCode): \(body)"
        }
    }

    var isInvalidGrant: Bool {
        guard case .refreshFailed(_, let body) = self else { return false }
        return body.localizedCaseInsensitiveContains("invalid_grant")
    }
}

enum GeminiAuthCredential: Sendable {
    case oauth(GeminiOAuthCredentials)
    case apiKey(String)
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
