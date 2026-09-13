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

    @Test("GitHub provider loads metadata, comments, inline hunks, and a bounded diff")
    func githubLoadsDetail() async throws {
        let provider = GitHubCodeReviewProvider(
            tokenProvider: { "github-token" },
            transport: { request in
                let url = try #require(request.url)
                let accept = request.value(forHTTPHeaderField: "Accept") ?? ""
                let data: Data
                if accept == "application/vnd.github.v3.diff" {
                    data = Data(
                        "diff --git a/Sources/File.swift b/Sources/File.swift\n-old\n+new".utf8
                    )
                } else {
                    let json: String
                    switch url.path {
                    case "/repos/TeamSloppy/Sloppy/pulls/42":
                        json = """
                        {
                          "number": 42,
                          "title": "Provider-neutral reviews",
                          "html_url": "https://github.com/TeamSloppy/Sloppy/pull/42",
                          "body": "Review description",
                          "state": "open",
                          "draft": false,
                          "created_at": "2026-09-01T10:00:00Z",
                          "updated_at": "2026-09-04T10:00:00Z",
                          "user": {"login": "vlad"},
                          "labels": [],
                          "head": {"ref": "feature/reviews"},
                          "base": {"ref": "main"},
                          "requested_reviewers": [{"login": "reviewer"}]
                        }
                        """
                    case "/repos/TeamSloppy/Sloppy/pulls/42/comments":
                        json = """
                        [{
                          "id": 100,
                          "user": {"login": "reviewer"},
                          "body": "Please add a test",
                          "path": "Sources/File.swift",
                          "line": 12,
                          "side": "RIGHT",
                          "diff_hunk": "@@ -12 +12 @@\\n-old\\n+new",
                          "created_at": "2026-09-04T11:00:00Z"
                        }]
                        """
                    case "/repos/TeamSloppy/Sloppy/issues/42/comments":
                        json = "[]"
                    case "/repos/TeamSloppy/Sloppy/pulls/42/reviews":
                        json = "[]"
                    default:
                        throw GitHubCodeReviewProvider.ProviderError.invalidResponse
                    }
                    data = Data(json.utf8)
                }
                let response = try #require(
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )
                )
                return (data, response)
            }
        )

        let detail = try await provider.codeReviewDetail(
            id: "github:TeamSloppy/Sloppy#42",
            maxDiffBytes: 1_024,
            credential: nil
        )

        #expect(detail.description == "Review description")
        #expect(detail.sourceBranch == "feature/reviews")
        #expect(detail.targetBranch == "main")
        #expect(detail.reviewers == ["reviewer"])
        #expect(detail.comments.first?.diffHunk?.contains("+new") == true)
        #expect(detail.comments.first?.line == 12)
        #expect(detail.diff.contains("diff --git"))
        #expect(!detail.diffTruncated)
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

    @Test("Core delegates a pull-request detail request to its provider")
    func coreLoadsDetail() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.registerCodeReviewProvider(FixedCodeReviewProvider(id: "arcadia", shouldFail: false))

        let detail = try await service.codeReviewDetail(providerID: "arcadia", reviewID: "15674740", maxDiffBytes: 64)

        #expect(detail.item.id == "arcadia:team/repo#1")
        #expect(detail.comments.map(\.body) == ["Please add a test"])
        #expect(detail.diff == "+new")
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

    func codeReviewDetail(id: String, maxDiffBytes: Int, credential: String?) async throws -> CodeReviewDetail {
        CodeReviewDetail(
            item: CodeReviewItem(
                id: "\(self.id):team/repo#1",
                providerId: self.id,
                providerName: displayName,
                repository: "team/repo",
                number: 1,
                title: "Review me",
                url: "https://reviews.example/team/repo/1",
                roles: [.reviewRequested]
            ),
            sourceBranch: "users/vlad-prusakov/feature",
            targetBranch: "trunk",
            reviewers: ["reviewer"],
            comments: [CodeReviewComment(id: "comment-1", author: "reviewer", body: "Please add a test")],
            diff: "+new"
        )
    }
}
