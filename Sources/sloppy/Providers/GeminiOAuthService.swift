import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

struct GeminiOAuthStatus: Sendable {
    var hasCredentials: Bool
    var email: String?
    var expiresAt: String?
}

struct GeminiOAuthService: @unchecked Sendable {
    typealias Transport = GeminiOAuthCredentials.Transport

    private static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private static let userInfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v1/userinfo")!
    private static let scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
    ]

    private struct PendingSession: Codable, Sendable {
        var state: String
        var codeVerifier: String
        var redirectURI: String
        var createdAt: String
    }

    private struct TokenResponse: Decodable {
        var accessToken: String
        var refreshToken: String?
        var expiresIn: TimeInterval?
        var tokenType: String?
        var scope: String?
        var idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
            case scope
            case idToken = "id_token"
        }
    }

    enum Error: LocalizedError {
        case invalidRedirectURI
        case missingPendingSession
        case invalidCallback
        case stateMismatch
        case missingAuthorizationCode
        case tokenExchangeFailed(String)
        case missingAccessToken
        case missingRefreshToken

        var errorDescription: String? {
            switch self {
            case .invalidRedirectURI:
                return "Gemini OAuth redirect URI is invalid."
            case .missingPendingSession:
                return "Gemini OAuth login session is missing. Start sign-in again."
            case .invalidCallback:
                return "Gemini OAuth callback is invalid."
            case .stateMismatch:
                return "Gemini OAuth state mismatch. Start sign-in again."
            case .missingAuthorizationCode:
                return "Gemini OAuth callback is missing the authorization code."
            case let .tokenExchangeFailed(message):
                return "Gemini OAuth token exchange failed: \(message)"
            case .missingAccessToken:
                return "Gemini OAuth token response is missing the access token."
            case .missingRefreshToken:
                return "Gemini OAuth token response is missing the refresh token."
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

    func startLogin(redirectURI: String) throws -> GeminiOAuthStartResponse {
        guard let redirectURL = URL(string: redirectURI), let scheme = redirectURL.scheme, !scheme.isEmpty else {
            throw Error.invalidRedirectURI
        }

        let verifier = Self.randomURLSafeString(byteCount: 48)
        let state = Self.randomURLSafeString(byteCount: 24)
        let challenge = Self.sha256Base64URL(verifier)
        try savePendingSession(PendingSession(
            state: state,
            codeVerifier: verifier,
            redirectURI: redirectURI,
            createdAt: Self.iso8601String(from: now())
        ))

        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "client_id", value: try GeminiOAuthCredentials.oauthClientID()),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]

        guard let authorizationURL = components?.url else {
            throw Error.invalidRedirectURI
        }

        return GeminiOAuthStartResponse(
            authorizationURL: authorizationURL.absoluteString + "#sloppy",
            redirectURI: redirectURI,
            state: state
        )
    }

    func completeLogin(request: GeminiOAuthCompleteRequest) async throws -> GeminiOAuthCompleteResponse {
        let pending = try loadPendingSession()
        let callback = extractCallbackValues(from: request.callbackURL)
        let code = request.code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? callback.code
        let state = request.state?.trimmingCharacters(in: .whitespacesAndNewlines) ?? callback.state

        guard let code, !code.isEmpty else {
            throw Error.missingAuthorizationCode
        }
        guard let state, !state.isEmpty else {
            throw Error.invalidCallback
        }
        guard state == pending.state else {
            throw Error.stateMismatch
        }

        let credentials = try await exchangeCode(
            code: code,
            codeVerifier: pending.codeVerifier,
            redirectURI: pending.redirectURI
        )
        try credentials.saveSloppy(url: authFileURL())
        try? removePendingSession()

        return GeminiOAuthCompleteResponse(
            ok: true,
            message: "Gemini OAuth connected.",
            email: credentials.email,
            expiresAt: credentials.expiryDate.map(Self.iso8601String(from:))
        )
    }

    func status() -> GeminiOAuthStatus {
        guard let credentials = currentCredentials() else {
            return GeminiOAuthStatus(hasCredentials: false, email: nil, expiresAt: nil)
        }
        return GeminiOAuthStatus(
            hasCredentials: true,
            email: credentials.email,
            expiresAt: credentials.expiryDate.map(Self.iso8601String(from:))
        )
    }

    func currentCredentials() -> GeminiOAuthCredentials? {
        GeminiOAuthCredentials.load(workspaceRootURL: workspaceRootURL)
    }

    func disconnect() throws {
        try? removePendingSession()
        let url = authFileURL()
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func exchangeCode(code: String, codeVerifier: String, redirectURI: String) async throws -> GeminiOAuthCredentials {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formEncodedData([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": codeVerifier,
            "client_id": try GeminiOAuthCredentials.oauthClientID(),
            "client_secret": try GeminiOAuthCredentials.oauthClientSecret(),
            "redirect_uri": redirectURI,
        ])

        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Error.tokenExchangeFailed(httpErrorMessage(data: data, statusCode: response.statusCode))
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard !token.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.missingAccessToken
        }
        guard let refreshToken = token.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines), !refreshToken.isEmpty else {
            throw Error.missingRefreshToken
        }

        return GeminiOAuthCredentials(
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            tokenType: token.tokenType ?? "Bearer",
            expiryDate: token.expiresIn.map { now().addingTimeInterval(max(60, $0)) },
            scope: token.scope ?? Self.scopes.joined(separator: " "),
            idToken: token.idToken,
            email: await fetchUserEmail(accessToken: token.accessToken),
            projectID: nil,
            managedProjectID: nil
        )
    }

    private func fetchUserEmail(accessToken: String) async -> String? {
        var components = URLComponents(url: Self.userInfoEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "alt", value: "json")]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await transport(request)
            guard (200..<300).contains(response.statusCode),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let email = object["email"] as? String
            else {
                return nil
            }
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
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

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: [.atomic])
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func pendingSessionURL() -> URL {
        workspaceRootURL
            .appendingPathComponent("auth", isDirectory: true)
            .appendingPathComponent("gemini-oauth-pending.json")
    }

    private func authFileURL() -> URL {
        GeminiOAuthCredentials.sloppyCredentialsURL(workspaceRootURL: workspaceRootURL)
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
            return "status \(statusCode): \(GeminiOAuthCredentials.sanitizedPayloadSnippet(data))"
        }
        return "status \(statusCode)"
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max) }
        return base64URLEncode(Data(bytes))
    }

    private static func sha256Base64URL(_ value: String) -> String {
        let digest = GeminiSHA256Digest.hash(Data(value.utf8))
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
}

private enum GeminiSHA256Digest {
    private static let initialHash: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92, 0x92722c85,
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
            var words = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let start = chunk + i * 4
                words[i] = UInt32(message[start]) << 24
                    | UInt32(message[start + 1]) << 16
                    | UInt32(message[start + 2]) << 8
                    | UInt32(message[start + 3])
            }
            for i in 16..<64 {
                let s0 = rotateRight(words[i - 15], by: 7) ^ rotateRight(words[i - 15], by: 18) ^ (words[i - 15] >> 3)
                let s1 = rotateRight(words[i - 2], by: 17) ^ rotateRight(words[i - 2], by: 19) ^ (words[i - 2] >> 10)
                words[i] = words[i - 16] &+ s0 &+ words[i - 7] &+ s1
            }

            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]

            for i in 0..<64 {
                let s1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                let ch = (e & f) ^ ((~e) & g)
                let temp1 = h &+ s1 &+ ch &+ k[i] &+ words[i]
                let s0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj

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
