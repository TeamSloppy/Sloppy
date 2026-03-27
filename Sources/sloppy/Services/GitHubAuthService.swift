import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import Protocols

struct GitHubAuthStatus: Sendable {
    var connected: Bool
    var username: String?
    var connectedAt: String?
}

struct GitHubTokenInfo: Sendable {
    var username: String
    var scopes: [String]
}

struct GitHubAuthService: @unchecked Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private static let apiBaseURL = URL(string: "https://api.github.com")!
    private static let logger = Logger(label: "sloppy.core.github-auth")

    private struct StoredAuth: Codable, Sendable {
        var token: String
        var username: String?
        var connectedAt: String
    }

    enum Error: LocalizedError {
        case invalidToken
        case validationFailed(String)
        case missingCredentials
        case storageFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidToken:
                return "GitHub token is empty or invalid."
            case .validationFailed(let msg):
                return "GitHub token validation failed: \(msg)"
            case .missingCredentials:
                return "No GitHub credentials found."
            case .storageFailed(let msg):
                return "Failed to store GitHub credentials: \(msg)"
            }
        }
    }

    private let workspaceRootURL: URL
    private let fileManager: FileManager
    private let transport: Transport

    init(
        workspaceRootURL: URL,
        fileManager: FileManager = .default,
        transport: Transport? = nil
    ) {
        self.workspaceRootURL = workspaceRootURL
        self.fileManager = fileManager
        self.transport = transport ?? { request in
            let (data, response) = try await URLSession(configuration: .default).data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, http)
        }
    }

    // MARK: - Public API

    func connect(token: String) async throws -> GitHubConnectResponse {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Error.invalidToken
        }

        let info = try await validateToken(trimmed)
        let stored = StoredAuth(
            token: trimmed,
            username: info.username,
            connectedAt: Self.iso8601String(from: Date())
        )
        do {
            try saveStoredAuth(stored)
        } catch {
            throw Error.storageFailed(error.localizedDescription)
        }

        Self.logger.info("github_auth.connected", metadata: ["username": .string(info.username)])
        return GitHubConnectResponse(ok: true, message: "GitHub connected as \(info.username).", username: info.username)
    }

    func disconnect() throws {
        let url = authFileURL()
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        Self.logger.info("github_auth.disconnected")
    }

    func currentToken() -> String? {
        if let stored = try? loadStoredAuth() {
            let t = stored.token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        let env = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ""
        return env.isEmpty ? nil : env
    }

    func status() -> GitHubAuthStatus {
        if let stored = try? loadStoredAuth() {
            return GitHubAuthStatus(
                connected: true,
                username: stored.username,
                connectedAt: stored.connectedAt
            )
        }
        let hasEnvToken = !(ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? "").isEmpty
        return GitHubAuthStatus(connected: hasEnvToken, username: nil, connectedAt: nil)
    }

    // MARK: - Private

    private func validateToken(_ token: String) async throws -> GitHubTokenInfo {
        var request = URLRequest(url: Self.apiBaseURL.appendingPathComponent("user"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("sloppy-core", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport(request)

        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw Error.validationFailed("HTTP \(response.statusCode): \(body)")
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = object["login"] as? String
        else {
            throw Error.validationFailed("Unexpected response format.")
        }

        let scopesHeader = response.value(forHTTPHeaderField: "X-OAuth-Scopes") ?? ""
        let scopes = scopesHeader.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return GitHubTokenInfo(username: login, scopes: scopes)
    }

    private func saveStoredAuth(_ auth: StoredAuth) throws {
        let url = authFileURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(auth)
        try data.write(to: url, options: .atomic)
    }

    private func loadStoredAuth() throws -> StoredAuth {
        let url = authFileURL()
        guard fileManager.fileExists(atPath: url.path) else {
            throw Error.missingCredentials
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StoredAuth.self, from: data)
    }

    private func authFileURL() -> URL {
        workspaceRootURL
            .appendingPathComponent("auth", isDirectory: true)
            .appendingPathComponent("github.json")
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
