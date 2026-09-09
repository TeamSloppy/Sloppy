import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PluginSDK
import Protocols
import Testing
@testable import sloppy

@Suite("Code review providers")
struct CodeReviewProviderTests {
    @Test("GitHub provider merges authored and review-requested roles")
    func githubMergesRoles() async throws {
        let provider = GitHubCodeReviewProvider(
            tokenProvider: { "github-token" },
            transport: { request in
                let requestURL = try #require(request.url)
                let query = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "q" })?
                    .value ?? ""
                #expect(query.contains("is:pr"))
                #expect(query.contains("is:open"))
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer github-token")

                let body = Data(
                    """
                    {
                      "items": [{
                        "number": 42,
                        "title": "Provider-neutral pull requests",
                        "html_url": "https://github.com/TeamSloppy/Sloppy/pull/42",
                        "repository_url": "https://api.github.com/repos/TeamSloppy/Sloppy",
                        "state": "open",
                        "draft": false,
                        "created_at": "2026-09-01T10:00:00Z",
                        "updated_at": "2026-09-04T10:00:00Z",
                        "user": {"login": "vlad"},
                        "labels": [{"name": "feature"}],
                        "pull_request": {}
                      }]
                    }
                    """.utf8
                )
                let response = try #require(
                    HTTPURLResponse(
                        url: requestURL,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )
                )
                return (body, response)
            }
        )

        let items = try await provider.listCodeReviews(
            query: CodeReviewQuery(state: .open, roles: CodeReviewRole.allCases)
        )

        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.repository == "TeamSloppy/Sloppy")
        #expect(item.number == 42)
        #expect(item.roles == [.authored, .reviewRequested])
        #expect(item.labels == ["feature"])
    }

    @Test("GitHub provider reports missing account connection")
    func githubRequiresToken() async {
        let provider = GitHubCodeReviewProvider(tokenProvider: { nil })
        await #expect(throws: GitHubCodeReviewProvider.ProviderError.self) {
            try await provider.listCodeReviews(query: CodeReviewQuery())
        }
    }

    @Test("Core keeps successful providers when another provider fails")
    func coreReturnsPartialInbox() async {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.registerCodeReviewProvider(FixedCodeReviewProvider(id: "gitlab", shouldFail: false))
        await service.registerCodeReviewProvider(FixedCodeReviewProvider(id: "broken", shouldFail: true))

        let response = await service.codeReviewInbox(
            query: CodeReviewQuery(limit: 20),
            providerIDs: ["gitlab", "broken"]
        )

        #expect(response.items.map(\.providerId) == ["gitlab"])
        #expect(response.failures["broken"] == "Provider unavailable")
        #expect(response.providers.contains(where: { $0.id == "github" }))
        #expect(response.providers.contains(where: { $0.id == "gitlab" }))
    }
}

private struct FixedCodeReviewProvider: CodeReviewProvider {
    struct Unavailable: LocalizedError {
        var errorDescription: String? { "Provider unavailable" }
    }

    let id: String
    let shouldFail: Bool
    var displayName: String { id.capitalized }

    func listCodeReviews(query: CodeReviewQuery) async throws -> [CodeReviewItem] {
        if shouldFail { throw Unavailable() }
        return [
            CodeReviewItem(
                id: "\(id):team/repo#1",
                providerId: id,
                providerName: displayName,
                repository: "team/repo",
                number: 1,
                title: "Review me",
                url: "https://reviews.example/team/repo/1",
                roles: [.reviewRequested]
            )
        ]
    }
}
