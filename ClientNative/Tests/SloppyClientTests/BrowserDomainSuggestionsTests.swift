import Foundation
import Testing
@testable import SloppyClient

@Suite("Browser domain suggestions")
@MainActor
struct BrowserDomainSuggestionsTests {
    @Test func matchesHistoryDomainsAndTitlesWithoutDuplicatePathsOrConfiguredSites() throws {
        let history = try [
            ("https://www.example.com/new", "Recent article"),
            ("https://docs.swift.org/guide", "Swift guide"),
            ("https://example.com/old", "Old article"),
            ("https://other.test", "Example handbook"),
            ("https://configured.test", "Configured"),
            ("file:///tmp/example.html", "Example local file"),
        ].map { WorkspaceBrowserRecentSite(url: try #require(URL(string: $0.0)), title: $0.1) }
        #expect(BrowserDomainSuggestions.hosts(query: "", history: history, excluding: ["configured.test"])
            == ["example.com", "docs.swift.org", "other.test"])
        #expect(BrowserDomainSuggestions.hosts(query: "EXAMPLE", history: history) == ["example.com", "other.test"])
        #expect(BrowserDomainSuggestions.hosts(query: "https://www.EXAMPLE.com/path", history: history) == ["example.com"])
        #expect(BrowserDomainSuggestions.hosts(query: "Swift guide", history: history) == ["docs.swift.org"])
        #expect(BrowserDomainSuggestions.hosts(query: "unvisited.test", history: history).isEmpty)
    }

    @Test func prefersDomainPrefixesAndCapsRecentSuggestions() throws {
        let history = try ["notexample.test", "example.test", "one.test", "two.test", "three.test", "four.test", "five.test"]
            .map { WorkspaceBrowserRecentSite(url: try #require(URL(string: "https://\($0)")), title: $0) }
        #expect(BrowserDomainSuggestions.hosts(query: "example", history: history) == ["example.test", "notexample.test"])
        #expect(BrowserDomainSuggestions.hosts(query: "", history: history).count == 6)
    }
}
