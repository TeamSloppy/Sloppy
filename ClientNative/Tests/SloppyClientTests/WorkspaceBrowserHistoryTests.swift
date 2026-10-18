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
        for index in 0...WorkspaceBrowserHistory.maximumCount {
            history.record(url: URL(string: "https://example.com/\(index)"), title: nil)
        }
        #expect(history.sites.count == WorkspaceBrowserHistory.maximumCount)
        #expect(history.sites.first?.url.path == "/20")
        #expect(history.sites.last?.url.path == "/1")
        #expect(history.sites.first?.title == "example.com")
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
