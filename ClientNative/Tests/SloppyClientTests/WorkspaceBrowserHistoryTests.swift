import Foundation
import Testing
@testable import SloppyClient

@Suite("Workspace browser recent sites")
@MainActor
struct WorkspaceBrowserHistoryTests {
    @Test func recentSitesPersistAndRevisitsMoveToTheFront() throws {
        let suite = "WorkspaceBrowserHistoryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = WorkspaceBrowserHistory(defaults: defaults)
        let first = try #require(URL(string: "https://example.com/first"))
        let second = try #require(URL(string: "http://localhost:8765/#/editor"))
        history.record(url: first, title: "First page")
        history.record(url: second, title: "Local editor")
        history.record(url: first, title: " Updated title ")
        #expect(history.sites.map(\.url) == [first, second])
        #expect(history.sites.first?.title == "Updated title")
        #expect(WorkspaceBrowserHistory(defaults: defaults).sites == history.sites)
        #expect(WorkspaceWebViewModel(history: history).history === history)
    }

    @Test func invalidPagesAreIgnoredAndHistoryIsBounded() throws {
        let suite = "WorkspaceBrowserHistoryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = WorkspaceBrowserHistory(defaults: defaults)
        for address in ["about:blank", "file:///tmp/test.html", "javascript:alert(1)"] {
            history.record(url: URL(string: address), title: "Internal page")
        }
        history.record(url: nil, title: nil)
        #expect(history.sites.isEmpty)
        let saved = try (0..<WorkspaceBrowserHistory.maximumCount).reversed().map { index in
            WorkspaceBrowserRecentSite(url: try #require(URL(string: "https://example.com/\(index)")), title: "Site")
        }
        defaults.set(try JSONEncoder().encode(saved), forKey: "workspace.browser.recent-sites")
        let bounded = WorkspaceBrowserHistory(defaults: defaults)
        bounded.record(url: URL(string: "https://example.com/\(WorkspaceBrowserHistory.maximumCount)"), title: nil)
        #expect(bounded.sites.count == WorkspaceBrowserHistory.maximumCount)
        #expect(bounded.sites.first?.url.path == "/\(WorkspaceBrowserHistory.maximumCount)")
        #expect(bounded.sites.last?.url.path == "/1")
        #expect(bounded.sites.first?.title == "example.com")
    }

    @Test func titleUpdatesDoNotAddPagesOrChangeTheirOrder() throws {
        let suite = "WorkspaceBrowserHistoryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = WorkspaceBrowserHistory(defaults: defaults)
        let first = try #require(URL(string: "https://example.com/first"))
        let second = try #require(URL(string: "https://example.com/second"))
        history.record(url: first, title: nil)
        history.record(url: second, title: "Second")
        history.updateTitle(url: first, title: "Loaded title")
        history.updateTitle(url: URL(string: "https://example.com/not-loaded"), title: "Pending")
        #expect(history.sites.map(\.url) == [second, first])
        #expect(history.sites.last?.title == "Loaded title")
        #expect(WorkspaceBrowserHistory(defaults: defaults).sites == history.sites)
    }

    @Test func frequentSitesAggregatePageVisitsAndSurviveRestart() throws {
        let suite = "FrequentSites.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = WorkspaceBrowserHistory(defaults: defaults)
        for address in ["https://a.example/one", "https://a.example/two", "https://b.example/", "https://a.example/one", "https://c.example/"] {
            history.record(url: URL(string: address), title: nil)
        }
        history.updateTitle(url: URL(string: "https://c.example/"), title: "A new title")
        let sites = WorkspaceBrowserHistory(defaults: defaults).frequentSites()
        #expect(sites.map(\.id) == ["a.example", "c.example", "b.example"])
        #expect(sites.first?.visits == 3)
        #expect(sites.first?.url.path == "/one")
        #expect(sites[1].visits == 1)
        history.clear()
        #expect(history.frequentSites().isEmpty)
        #expect(WorkspaceBrowserHistory(defaults: defaults).frequentSites().isEmpty)
    }

    @Test func frequentSitesUseAtMostSixRealDistinctSites() throws {
        let suite = "FrequentSitesLimit.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = WorkspaceBrowserHistory(defaults: defaults)
        #expect(history.frequentSites().isEmpty)
        for index in 0..<8 { history.record(url: URL(string: "https://site\(index).example/"), title: nil) }
        #expect(history.frequentSites().count == 6)
        #expect(history.frequentSites(limit: 3).count == 3)
        #expect(history.frequentSites().first?.id == "site7.example")
    }

    @Test func credentialsAreNotPersistedAndDeepLinksArePreserved() throws {
        let suite = "WorkspaceBrowserHistoryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = WorkspaceBrowserHistory(defaults: defaults)
        history.record(url: URL(string: "https://user:password@example.com/page?mode=edit#/details"), title: "Page")
        #expect(history.sites.first?.url.absoluteString == "https://example.com/page?mode=edit#/details")
        #expect(WorkspaceBrowserHistory(defaults: defaults).sites.first?.url.user == nil)
        #expect(WorkspaceBrowserHistory(defaults: defaults).sites.first?.url.password == nil)
    }
}
