import Foundation
import Protocols

struct SloppyCLILocalAuthSession: Codable, Equatable, Sendable {
    var baseURL: String
    var accessToken: String
    var refreshToken: String
    var accessTokenExpiresAt: Date
    var refreshTokenExpiresAt: Date
    var user: AuthUserProfile
}

enum SloppyCLILocalAuthStore {
    static let relativePath = ".sloppy/auth.json"

    static func authURL(rootURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> URL {
        rootURL
            .appendingPathComponent(".sloppy", isDirectory: true)
            .appendingPathComponent("auth.json")
    }

    static func load(
        baseURL: String,
        rootURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> SloppyCLILocalAuthSession? {
        guard let session = try? load(rootURL: rootURL) else { return nil }
        return normalized(session.baseURL) == normalized(baseURL) ? session : nil
    }

    static func load(rootURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> SloppyCLILocalAuthSession? {
        let url = authURL(rootURL: rootURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SloppyCLILocalAuthSession.self, from: data)
    }

    static func save(
        _ session: SloppyCLILocalAuthSession,
        rootURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws {
        let url = authURL(rootURL: rootURL)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: url, options: [.atomic])
    }

    static func clear(rootURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws {
        let url = authURL(rootURL: rootURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func normalized(_ url: String) -> String {
        url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
