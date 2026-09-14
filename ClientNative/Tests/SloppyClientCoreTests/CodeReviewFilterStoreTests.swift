import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Pull Requests filter persistence")
@MainActor
struct CodeReviewFilterStoreTests {
    @Test("restores state role and provider for the same endpoint")
    func restoresFiltersForSameEndpoint() throws {
        let suite = "code-review-filters-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let endpoint = SloppyInstanceEndpoint.direct(
            baseURL: try #require(URL(string: "http://localhost:25101"))
        )
        let expected = CodeReviewInboxFilters(
            state: .merged,
            role: .reviewRequested,
            providerID: "arcadia-code-review"
        )

        CodeReviewFilterStore(defaults: defaults).save(expected, endpoint: endpoint)
        let reopened = CodeReviewFilterStore(defaults: defaults)

        #expect(reopened.load(endpoint: endpoint) == expected)
    }

    @Test("keeps filters isolated by endpoint and removes defaults")
    func scopesFiltersByEndpoint() throws {
        let suite = "code-review-filters-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let direct = SloppyInstanceEndpoint.direct(
            baseURL: try #require(URL(string: "http://localhost:25101"))
        )
        let relay = SloppyInstanceEndpoint.relay(
            coordinatorBaseURL: try #require(URL(string: "https://mesh.example")),
            targetNodeID: "node:review"
        )
        let store = CodeReviewFilterStore(defaults: defaults)

        store.save(
            CodeReviewInboxFilters(state: .closed, role: .authored, providerID: "github"),
            endpoint: direct
        )

        #expect(store.load(endpoint: relay) == CodeReviewInboxFilters())
        store.save(CodeReviewInboxFilters(), endpoint: direct)
        #expect(store.load(endpoint: direct) == CodeReviewInboxFilters())
    }
}
