import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Pull Requests inbox")
struct CodeReviewSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("decodes provider-neutral review response")
    func decodesResponse() throws {
        let data = Data(
            """
            {
              "items": [{
                "id": "github:TeamSloppy/Sloppy#42",
                "providerId": "github",
                "providerName": "GitHub",
                "repository": "TeamSloppy/Sloppy",
                "number": 42,
                "title": "Add pull request inbox",
                "url": "https://github.com/TeamSloppy/Sloppy/pull/42",
                "author": "vlad",
                "state": "open",
                "isDraft": false,
                "roles": ["authored", "review_requested"],
                "labels": []
              }],
              "providers": [{
                "id": "github",
                "displayName": "GitHub",
                "capabilities": ["list_pull_requests"]
              }],
              "failures": {}
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(CodeReviewInboxResponse.self, from: data)
        #expect(response.items.first?.roles == [.authored, .reviewRequested])
        #expect(response.providers.first?.displayName == "GitHub")
    }

    @Test("API errors expose HTTP status and server details")
    func apiErrorsExposeDetails() {
        let error = APIError.httpError(statusCode: 404, body: #"{"error":"route_not_found"}"#)

        #expect(error.localizedDescription.contains("HTTP 404"))
        #expect(error.localizedDescription.contains("route_not_found"))
    }

    @Test("client and platform navigation expose Pull Requests")
    func navigationWiring() throws {
        let api = try source("Sources/SloppyClientCore/SloppyAPIClient.swift")
        let screen = try source("Sources/SloppyClient/CodeReview/PullRequestsScreen.swift")
        let model = try source("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")
        let macSidebar = try source("Sources/SloppyClient/Navigation/Platforms/macOS/MacMainSidebar.swift")
        let iosSidebar = try source("Sources/SloppyClient/Navigation/Platforms/iOS/IOSMainSidebar.swift")

        #expect(api.contains("/v1/code-reviews?"))
        #expect(screen.contains("PullRequestsScreen"))
        #expect(screen.contains("response.failures"))
        #expect(screen.contains("maxHeight: .infinity, alignment: .topLeading"))
        #expect(screen.contains("Button(\"Try Again\")"))
        #expect(model.contains("case pullRequests"))
        #expect(macSidebar.contains("title: \"Pull Requests\""))
        #expect(iosSidebar.contains("Tab(\"Pull Requests\""))
    }
}
