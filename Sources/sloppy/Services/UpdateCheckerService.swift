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
    public var deploymentKind: DeploymentKind
    public var currentCommit: String?
    public var currentBranch: String?
    public var currentCommitDate: Date?
    public var latestCommit: String?
    public var latestCommitDate: Date?
    public var latestBranch: String?
    public var updateKind: UpdateKind
}

struct UpdateReleasePayload: Sendable {
    var latestVersion: String
    var releaseUrl: String
    var publishedAt: Date?
}

struct UpdateGitCommitPayload: Sendable {
    var latestCommit: String?
    var latestCommitDate: Date?
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

    private struct GitHubCommitResponse: Decodable {
        struct CommitInfo: Decodable {
            struct Person: Decodable {
                var date: Date?
            }

            var committer: Person?
            var author: Person?
        }

        var sha: String
        var commit: CommitInfo
    }

    private struct GitRemoteCache: Sendable {
        var descriptor: GitHubRemoteDescriptor
        var latestCommit: String?
        var latestCommitDate: Date?
        var lastCheckedAt: Date?
    }

    private var latestVersion: String?
    private var releaseUrl: String?
    private var publishedAt: Date?
    private var releaseLastCheckedAt: Date?
    private var gitCache: GitRemoteCache?
    private let urlSession: URLSession
    private let buildMetadataProvider: @Sendable () -> BuildMetadata
    private let releaseFetcher: @Sendable (URLSession) async -> UpdateReleasePayload?
    private let gitCommitFetcher: @Sendable (GitHubRemoteDescriptor, URLSession) async -> UpdateGitCommitPayload?

    init(
        urlSession: URLSession = .shared,
        buildMetadataProvider: @escaping @Sendable () -> BuildMetadata = { BuildMetadataResolver().resolve() },
        releaseFetcher: @escaping @Sendable (URLSession) async -> UpdateReleasePayload? = UpdateCheckerService.fetchLatestReleaseLive,
        gitCommitFetcher: @escaping @Sendable (GitHubRemoteDescriptor, URLSession) async -> UpdateGitCommitPayload? = UpdateCheckerService.fetchLatestCommitLive
    ) {
        self.urlSession = urlSession
        self.buildMetadataProvider = buildMetadataProvider
        self.releaseFetcher = releaseFetcher
        self.gitCommitFetcher = gitCommitFetcher
    }

    func status() async -> UpdateStatus {
        let build = buildMetadataProvider()
        if build.isReleaseBuild {
            if shouldRefetch(lastCheckedAt: releaseLastCheckedAt) {
                await fetchLatestRelease()
            }
            return buildReleaseStatus(build: build)
        }
        if let descriptor = build.git?.githubRemote,
           shouldRefetch(lastCheckedAt: gitCache?.lastCheckedAt) || gitCache?.descriptor != descriptor {
            await fetchLatestCommit(for: descriptor)
        }
        return buildGitStatus(build: build)
    }

    func forceCheck() async -> UpdateStatus {
        let build = buildMetadataProvider()
        if build.isReleaseBuild {
            await fetchLatestRelease()
            return buildReleaseStatus(build: build)
        }
        if let descriptor = build.git?.githubRemote {
            await fetchLatestCommit(for: descriptor)
        } else if let gitCache {
            self.gitCache = GitRemoteCache(
                descriptor: gitCache.descriptor,
                latestCommit: nil,
                latestCommitDate: nil,
                lastCheckedAt: Date()
            )
        }
        return buildGitStatus(build: build)
    }

    private func shouldRefetch(lastCheckedAt: Date?) -> Bool {
        guard let lastCheckedAt else { return true }
        return Date().timeIntervalSince(lastCheckedAt) > Self.checkInterval
    }

    private func buildReleaseStatus(build: BuildMetadata) -> UpdateStatus {
        let currentVersion = build.releaseVersion ?? build.displayVersion
        let updateAvailable = latestVersion.map {
            SloppyVersion.isNewer($0, than: currentVersion)
        } ?? false

        return UpdateStatus(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            updateAvailable: updateAvailable,
            releaseUrl: releaseUrl,
            publishedAt: publishedAt,
            lastCheckedAt: releaseLastCheckedAt,
            isReleaseBuild: true,
            deploymentKind: build.deploymentKind,
            currentCommit: build.git?.currentCommit,
            currentBranch: build.git?.currentBranch,
            currentCommitDate: build.git?.currentCommitDate,
            latestCommit: nil,
            latestCommitDate: nil,
            latestBranch: nil,
            updateKind: .release
        )
    }

    private func buildGitStatus(build: BuildMetadata) -> UpdateStatus {
        let cachedRemote = build.git?.githubRemote.flatMap { descriptor -> GitRemoteCache? in
            guard gitCache?.descriptor == descriptor else { return nil }
            return gitCache
        }
        let localDate = build.git?.currentCommitDate
        let remoteDate = cachedRemote?.latestCommitDate
        let updateAvailable = {
            guard let localDate, let remoteDate else { return false }
            return remoteDate > localDate
        }()

        return UpdateStatus(
            currentVersion: build.displayVersion,
            latestVersion: nil,
            updateAvailable: updateAvailable,
            releaseUrl: nil,
            publishedAt: nil,
            lastCheckedAt: cachedRemote?.lastCheckedAt,
            isReleaseBuild: false,
            deploymentKind: build.deploymentKind,
            currentCommit: build.git?.currentCommit,
            currentBranch: build.git?.currentBranch,
            currentCommitDate: build.git?.currentCommitDate,
            latestCommit: cachedRemote?.latestCommit,
            latestCommitDate: cachedRemote?.latestCommitDate,
            latestBranch: cachedRemote?.descriptor.branch ?? build.git?.upstreamBranch,
            updateKind: .git
        )
    }

    private func fetchLatestRelease() async {
        releaseLastCheckedAt = Date()
        guard let payload = await releaseFetcher(urlSession) else {
            return
        }
        latestVersion = payload.latestVersion
        releaseUrl = payload.releaseUrl
        publishedAt = payload.publishedAt
    }

    private func fetchLatestCommit(for descriptor: GitHubRemoteDescriptor) async {
        let checkedAt = Date()
        let payload = await gitCommitFetcher(descriptor, urlSession)
        gitCache = GitRemoteCache(
            descriptor: descriptor,
            latestCommit: payload?.latestCommit,
            latestCommitDate: payload?.latestCommitDate,
            lastCheckedAt: checkedAt
        )
    }

    private static func fetchLatestReleaseLive(urlSession: URLSession) async -> UpdateReleasePayload? {
        guard let url = URL(string: Self.apiURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("sloppy-updater/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let release = try decoder.decode(GitHubRelease.self, from: data)
            var tag = release.tagName
            if tag.hasPrefix("v") { tag = String(tag.dropFirst()) }
            return UpdateReleasePayload(
                latestVersion: tag,
                releaseUrl: release.htmlUrl,
                publishedAt: release.publishedAt
            )
        } catch {
            return nil
        }
    }

    private static func fetchLatestCommitLive(
        descriptor: GitHubRemoteDescriptor,
        urlSession: URLSession
    ) async -> UpdateGitCommitPayload? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(descriptor.owner)/\(descriptor.repo)/commits"
        components.queryItems = [
            .init(name: "sha", value: descriptor.branch),
            .init(name: "per_page", value: "1")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("sloppy-updater/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let commits = try decoder.decode([GitHubCommitResponse].self, from: data)
            let first = commits.first
            return UpdateGitCommitPayload(
                latestCommit: first.map { String($0.sha.prefix(12)) },
                latestCommitDate: first?.commit.committer?.date ?? first?.commit.author?.date
            )
        } catch {
            return nil
        }
    }
}
