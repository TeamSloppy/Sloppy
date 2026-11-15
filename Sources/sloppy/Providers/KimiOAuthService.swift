import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

struct KimiOAuthStatus: Sendable {
    var hasCredentials: Bool
    var expiresAt: String?
    var refreshable: Bool
}

/// Kimi Code OAuth (RFC 8628 device authorization) used for Kimi membership login.
struct KimiOAuthService: @unchecked Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
    static let codingBaseURL = "https://api.kimi.com/coding/v1"
    private static let deviceEndpoint = URL(string: "https://auth.kimi.com/api/oauth/device_authorization")!
    private static let tokenEndpoint = URL(string: "https://auth.kimi.com/api/oauth/token")!
    private static let refreshSkew: TimeInterval = 120

    struct StoredAuth: Codable, Sendable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
    }

    enum Error: LocalizedError {
        case missingCredentials
        case invalidResponse(String)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .missingCredentials: return "Kimi OAuth credentials are missing. Log in with Kimi first."
            case .invalidResponse(let detail): return "Kimi OAuth returned an unexpected response: \(detail)"
            case .server(let message): return message
            }
        }
    }

    private struct DeviceResponse: Decodable {
        var deviceCode: String
        var userCode: String
        var verificationUri: String?
        var verificationUriComplete: String?
        var expiresIn: Int?
        var interval: Int?

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationUri = "verification_uri"
            case verificationUriComplete = "verification_uri_complete"
            case expiresIn = "expires_in"
            case interval
        }
    }

    private struct TokenResponse: Decodable {
        var accessToken: String?
        var refreshToken: String?
        var expiresIn: Double?
        var error: String?
        var errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case error
            case errorDescription = "error_description"
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
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, http)
        }
        self.now = now
    }

    // MARK: Device flow

    func startDeviceCode() async throws -> KimiDeviceCodeStartResponse {
        let (data, http) = try await post(Self.deviceEndpoint, ["client_id": Self.clientID])
        guard (200..<300).contains(http.statusCode) else {
            throw Error.server(Self.errorMessage(data, status: http.statusCode))
        }
        let device: DeviceResponse
        do { device = try JSONDecoder().decode(DeviceResponse.self, from: data) }
        catch { throw Error.invalidResponse("device authorization") }
        let url = device.verificationUriComplete ?? device.verificationUri ?? "https://www.kimi.com/code/authorize_device"
        return KimiDeviceCodeStartResponse(
            deviceCode: device.deviceCode,
            userCode: device.userCode,
            verificationURL: url,
            interval: max(device.interval ?? 5, 1),
            expiresIn: device.expiresIn ?? 600
        )
    }

    func pollDeviceToken(deviceCode: String) async throws -> KimiDeviceCodePollResponse {
        let (data, http) = try await post(Self.tokenEndpoint, [
            "client_id": Self.clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
        let token = try? JSONDecoder().decode(TokenResponse.self, from: data)
        if (200..<300).contains(http.statusCode), let stored = makeStored(from: token, fallbackRefresh: nil) {
            try save(stored)
            return .init(status: "authorized", ok: true, message: "Kimi login completed.")
        }
        switch token?.error {
        case "authorization_pending":
            return .init(status: "pending", ok: false, message: "Waiting for approval.")
        case "slow_down":
            return .init(status: "slow_down", ok: false, message: "Polling too fast; retry with a longer interval.")
        case "expired_token":
            return .init(status: "expired", ok: false, message: "The login code expired. Start again.")
        case "access_denied":
            return .init(status: "denied", ok: false, message: "Login was denied.")
        default:
            throw Error.server(Self.errorMessage(data, status: http.statusCode))
        }
    }

    // MARK: Credentials

    func currentAccessToken() -> String? {
        guard let stored = try? load(), !stored.accessToken.isEmpty else { return nil }
        return stored.accessToken
    }

    func status() -> KimiOAuthStatus {
        guard let stored = try? load() else { return .init(hasCredentials: false, expiresAt: nil, refreshable: false) }
        return .init(
            hasCredentials: !stored.accessToken.isEmpty,
            expiresAt: stored.expiresAt.map { ISO8601DateFormatter().string(from: $0) },
            refreshable: stored.refreshToken?.isEmpty == false
        )
    }

    func ensureValidToken(forceRefresh: Bool = false) async throws {
        let stored = try load()
        let expiring = stored.expiresAt.map { $0.timeIntervalSince(now()) < Self.refreshSkew } ?? false
        guard forceRefresh || expiring else { return }
        guard let refresh = stored.refreshToken, !refresh.isEmpty else { throw Error.missingCredentials }
        let (data, http) = try await post(Self.tokenEndpoint, [
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refresh,
        ])
        let token = try? JSONDecoder().decode(TokenResponse.self, from: data)
        guard (200..<300).contains(http.statusCode),
              let updated = makeStored(from: token, fallbackRefresh: refresh) else {
            throw Error.server(Self.errorMessage(data, status: http.statusCode))
        }
        try save(updated)
    }

    func disconnect() throws {
        let url = authFileURL()
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    // MARK: Helpers

    private func makeStored(from token: TokenResponse?, fallbackRefresh: String?) -> StoredAuth? {
        guard let access = token?.accessToken, !access.isEmpty else { return nil }
        return StoredAuth(
            accessToken: access,
            refreshToken: token?.refreshToken ?? fallbackRefresh,
            expiresAt: token?.expiresIn.map { now().addingTimeInterval($0) }
        )
    }

    private func post(_ url: URL, _ form: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("sloppy", forHTTPHeaderField: "X-Msh-Platform")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").data(using: .utf8)
        return try await transport(request)
    }

    private static func errorMessage(_ data: Data, status: Int) -> String {
        if let token = try? JSONDecoder().decode(TokenResponse.self, from: data),
           let message = token.errorDescription ?? token.error {
            return "Kimi OAuth error: \(message)"
        }
        return "Kimi OAuth request failed with HTTP \(status)."
    }

    private func save(_ auth: StoredAuth) throws {
        let url = authFileURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(auth).write(to: url, options: .atomic)
    }

    private func load() throws -> StoredAuth {
        let url = authFileURL()
        guard fileManager.fileExists(atPath: url.path) else { throw Error.missingCredentials }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredAuth.self, from: Data(contentsOf: url))
    }

    private func authFileURL() -> URL {
        workspaceRootURL.appendingPathComponent("auth", isDirectory: true)
            .appendingPathComponent("kimi-oauth-auth.json")
    }
}
