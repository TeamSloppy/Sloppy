import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct UpdateStatus: Sendable {
    public var currentVersion: String
    public var latestVersion: String?
    public var updateAvailable: Bool
    public var releaseUrl: String?
    public var publishedAt: Date?
    public var lastCheckedAt: Date?
    public var isReleaseBuild: Bool
}

actor UpdateCheckerService {
    private struct GitHubRelease: Decodable {
        var tagName: String
        var htmlUrl: String
        var publishedAt: Date?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case publishedAt = "published_at"
        }
    }

    private static let checkInterval: TimeInterval = 2 * 24 * 60 * 60
    private static let apiURL = "https://api.github.com/repos/TeamSloppy/Sloppy/releases/latest"

    private var latestVersion: String?
    private var releaseUrl: String?
    private var publishedAt: Date?
    private var lastCheckedAt: Date?
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func status() async -> UpdateStatus {
        guard SloppyVersion.isReleaseBuild else {
            return devStatus()
        }
        if shouldRefetch() {
            await fetchLatestRelease()
        }
        return buildStatus()
    }

    func forceCheck() async -> UpdateStatus {
        guard SloppyVersion.isReleaseBuild else {
            return devStatus()
        }
        await fetchLatestRelease()
        return buildStatus()
    }

    private func devStatus() -> UpdateStatus {
        UpdateStatus(
            currentVersion: SloppyVersion.current,
            latestVersion: nil,
            updateAvailable: false,
            releaseUrl: nil,
            publishedAt: nil,
            lastCheckedAt: nil,
            isReleaseBuild: false
        )
    }

    private func shouldRefetch() -> Bool {
        guard let lastCheckedAt else { return true }
        return Date().timeIntervalSince(lastCheckedAt) > Self.checkInterval
    }

    private func buildStatus() -> UpdateStatus {
        let updateAvailable = latestVersion.map {
            SloppyVersion.isNewer($0, than: SloppyVersion.current)
        } ?? false

        return UpdateStatus(
            currentVersion: SloppyVersion.current,
            latestVersion: latestVersion,
            updateAvailable: updateAvailable,
            releaseUrl: releaseUrl,
            publishedAt: publishedAt,
            lastCheckedAt: lastCheckedAt,
            isReleaseBuild: true
        )
    }

    private func fetchLatestRelease() async {
        guard let url = URL(string: Self.apiURL) else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("sloppy-updater/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        lastCheckedAt = Date()

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let release = try decoder.decode(GitHubRelease.self, from: data)
            var tag = release.tagName
            if tag.hasPrefix("v") { tag = String(tag.dropFirst()) }
            latestVersion = tag
            releaseUrl = release.htmlUrl
            publishedAt = release.publishedAt
        } catch {
            // Retain cached value; silently ignore transient network errors
        }
    }
}
