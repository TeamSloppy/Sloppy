import Foundation
import Testing
@testable import SloppyClient

@Suite("Browser workspace")
@MainActor
struct BrowserWorkspaceTests {
    private func defaults() throws -> (UserDefaults, String) {
        let name = "BrowserWorkspaceTests.\(UUID())"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func restoresModeEngineTabOrderAndSelection() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults)
        #expect(!state.isBrowsing)
        #expect(state.searchEngine == .google)
        let first = try #require(URL(string: "https://example.com/one"))
        let second = try #require(URL(string: "https://example.com/two"))
        state.open(first, inNewTab: true)
        let firstID = try #require(state.selectedID)
        state.open(second, inNewTab: true)
        state.select(firstID)
        state.searchEngine = .duckDuckGo
        state.move(from: IndexSet(integer: 0), to: 2)
        state.checkpoint()
        let restored = BrowserWorkspaceState(defaults: defaults)
        #expect(restored.isBrowsing)
        #expect(restored.searchEngine == .duckDuckGo)
        #expect(restored.tabs.map(\.url) == [second, first])
        #expect(restored.selectedID == firstID)
        #expect(restored.pages.count == 1) // Restore inactive pages lazily.
        restored.isBrowsing = false
        #expect(!BrowserWorkspaceState(defaults: defaults).isBrowsing)
    }

    @Test func closingTabsChoosesANeighborAndDoesNotResurrectClosedPages() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults)
        for index in 0..<3 { state.open(try #require(URL(string: "https://example.com/\(index)")), inNewTab: true) }
        let middle = state.tabs[1].id
        let last = state.tabs[2].id
        state.select(middle)
        let page = try #require(state.selectedPage)
        state.select(last)
        state.select(middle)
        #expect(state.selectedPage === page)
        state.close(middle)
        #expect(state.selectedID == last)
        #expect(state.pages[middle] == nil)
        state.tabs.map(\.id).forEach { state.close($0) }
        #expect(state.selectedID == nil)
        #expect(BrowserWorkspaceState(defaults: defaults).tabs.isEmpty)
    }

    @Test func currentTabNavigationAndSearchPresentationHaveExplicitDestinations() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults)
        let first = try #require(URL(string: "https://example.com/one"))
        let second = try #require(URL(string: "https://example.com/two"))
        state.open(first, inNewTab: false)
        let id = state.selectedID
        state.open(second, inNewTab: false)
        #expect(state.tabs.count == 1)
        #expect(state.selectedID == id)
        #expect(state.selectedTab?.url == second)
        state.presentSearch(newTab: false)
        #expect(state.searchText == second.absoluteString)
        #expect(!state.searchInNewTab)
        state.presentSearch(newTab: true)
        #expect(state.searchText.isEmpty)
        #expect(state.searchInNewTab)
    }

    @Test func searchEncodesQueriesAndRecognizesAddresses() throws {
        let engine = BrowserSearchEngine.google
        #expect(engine.destination(for: "  ") == nil)
        #expect(engine.destination(for: "example.com/docs?q=1#part")?.absoluteString == "https://example.com/docs?q=1#part")
        #expect(engine.destination(for: "localhost:8080")?.host == "localhost")
        #expect(engine.destination(for: "HTTP://example.com")?.scheme?.lowercased() == "http")
        let query = "Swift & WebKit + 日本語"
        for engine in BrowserSearchEngine.allCases {
            let url = try #require(engine.destination(for: query))
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.queryItems?.first?.value == query)
            #expect(url.absoluteString.contains("%2B"))
        }
        #expect(engine.destination(for: "https://user:password@example.com")?.absoluteString == "https://example.com")
        #expect(BrowserSearchEngine.websiteURL(URL(string: "javascript:alert(1)")) == nil)
        #expect(BrowserSearchEngine.websiteURL(URL(string: "file:///etc/passwd")) == nil)
    }

    @Test func namedGroupsAndHomeSurviveRestartWithoutClosingTabs() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults)
        state.open(try #require(URL(string: "https://example.com/research")), inNewTab: true)
        let id = try #require(state.selectedID)
        let group = try #require(state.saveGroup(title: " Research ", tabID: id))
        state.toggleGroup(group)
        state.showHome()
        let restored = BrowserWorkspaceState(defaults: defaults)
        #expect(restored.selectedID == nil)
        #expect(restored.tabs.first?.groupID == group)
        #expect(restored.groups.first?.title == "Research")
        #expect(restored.groups.first?.isCollapsed == true)
        restored.removeGroup(group)
        #expect(restored.tabs.count == 1)
        #expect(restored.tabs.first?.groupID == nil)
        restored.select(id)
        #expect(restored.selectedID == id)
    }

    @Test func legacyTabsMigrateAndBookmarksPersist() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let id = UUID()
        let old = """
        {"tabs":[{"id":"\(id)","url":"https://example.com","title":"Saved"}],"selectedID":"\(id)","isBrowsing":true,"searchEngine":"google"}
        """
        defaults.set(Data(old.utf8), forKey: BrowserWorkspaceState.storageKey)
        let state = BrowserWorkspaceState(defaults: defaults)
        #expect(state.tabs.count == 1)
        #expect(state.selectedID == id)
        #expect(state.groups.isEmpty)
        let url = try #require(state.selectedTab?.url)
        state.library.toggleBookmark(url: url, title: "Saved")
        let restored = BrowserWorkspaceState(defaults: defaults)
        #expect(restored.library.bookmarks.first?.title == "Saved")
        #expect(restored.library.isBookmarked(url))
        restored.library.toggleBookmark(url: url, title: "Saved")
        #expect(restored.library.bookmarks.isEmpty)
    }

    @Test func downloadDestinationsStayInsideTheirDirectoryAndAvoidExistingFiles() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = BrowserLibrary(defaults: defaults, directory: folder)
        let first = try library.availableDestination("../../source.txt")
        #expect(first.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        try Data("existing".utf8).write(to: first)
        let second = try library.availableDestination("source.txt")
        #expect(second.lastPathComponent == "source (1).txt")
        #expect(try String(contentsOf: first, encoding: .utf8) == "existing")
    }

    @Test func launcherFindsTabsBookmarksAndHistoryWithoutDuplicatePages() throws {
        let url = try #require(URL(string: "https://example.com/docs"))
        let savedURL = try #require(URL(string: "https://example.com/saved"))
        let historyURL = try #require(URL(string: "https://example.com/history"))
        let tab = BrowserTabRecord(url: url, title: "Example docs")
        let results = BrowserSearchResult.make(query: "example", engine: .google, tabs: [tab],
            bookmarks: [.init(url: url, title: "Duplicate"), .init(url: savedURL, title: "Example saved")],
            history: [.init(url: savedURL, title: "Duplicate"), .init(url: historyURL, title: "Example history")])
        #expect(results.map(\.category) == ["Web", "Tab", "Bookmark", "History"])
        #expect(results[1].id == "tab-\(tab.id)")
        #expect(results[1].actionTitle == "Switch to tab")
        let empty = BrowserSearchResult.make(query: "", engine: .google, tabs: [tab], bookmarks: [], history: [])
        #expect(empty.count == 1)
        #expect(empty.first?.category == "Tab")
    }

    @Test func launcherWebDestinationRetainsTheChosenEngineAndQuery() throws {
        let results = BrowserSearchResult.make(query: "C++ 日本語", engine: .duckDuckGo, tabs: [], bookmarks: [], history: [])
        guard case .destination(let url) = try #require(results.first).target else {
            Issue.record("The first result must be the explicit web destination")
            return
        }
        #expect(url.host == "duckduckgo.com")
        #expect(url.absoluteString.contains("%2B"))
        #expect(BrowserSearchResult.make(query: "   ", engine: .google, tabs: [], bookmarks: [], history: []).isEmpty)
    }

    @Test func cancellationIsNotPresentedAsAFailedPage() {
        #expect(WorkspaceBrowserNavigationFailure.isCancellation(URLError(.cancelled)))
        #expect(WorkspaceBrowserNavigationFailure.message(for: URLError(.cancelled)) == nil)
        #expect(WorkspaceBrowserNavigationFailure.message(for: URLError(.timedOut))?.contains("too long") == true)
        #expect(!WorkspaceBrowserNavigationFailure.isCancellation(NSError(domain: "Other", code: -999)))
    }

    @Test func securityIndicatorUsesTheLoadedPageAndSecureContent() throws {
        let page = WorkspaceWebViewModel()
        let https = try #require(URL(string: "https://example.com/"))
        let http = try #require(URL(string: "http://example.com/"))
        #expect(page.connectionSecurity(for: nil) == .empty)
        page.currentURL = https
        page.hasOnlySecureContent = true
        #expect(page.connectionSecurity(for: https) == .secure)
        page.isLoading = true
        #expect(page.connectionSecurity(for: https) == .connecting)
        page.isLoading = false
        page.hasOnlySecureContent = false
        #expect(page.connectionSecurity(for: https) == .mixedContent)
        page.currentURL = http
        #expect(page.connectionSecurity(for: http) == .notSecure)
        page.lastError = "Certificate validation failed"
        #expect(page.connectionSecurity(for: https) == .failed)
    }

    @Test func faviconIsLoadedFromTheWebsiteOrigin() throws {
        let page = try #require(URL(string: "https://user:password@example.com:8443/path?q=token#fragment"))
        #expect(BrowserFaviconView.iconURL(for: page)?.absoluteString == "https://example.com:8443/favicon.ico")
        #expect(BrowserFaviconView.iconURL(for: URL(string: "file:///tmp/page.html")) == nil)
    }

    @Test func loopbackAddressesUseHttpWithoutDowngradingExplicitHttpsOrPublicSites() throws {
        for address in ["localhost:25102", "127.0.0.1:25102", "[::1]:25102", "127.0.0.2:8080", "dev.localhost:8080"] {
            let url = try #require(BrowserSearchEngine.google.destination(for: address))
            #expect(url.scheme == "http")
            #expect(try WorkspaceBrowserToolRuntime.resolveURL(address) == url)
        }
        #expect(BrowserSearchEngine.google.destination(for: "https://localhost:25102")?.scheme == "https")
        #expect(BrowserSearchEngine.google.destination(for: "localhost.example.com")?.scheme == "https")
        #expect(BrowserSearchEngine.google.destination(for: "example.com")?.scheme == "https")
        #expect(WorkspaceBrowserAddress.resolve("localhost:25102/path?q=1#top")?.absoluteString == "http://localhost:25102/path?q=1#top")
        #expect(WorkspaceBrowserAddress.httpAlternative(for: URL(string: "https://localhost:25102"))?.absoluteString == "http://localhost:25102")
        #expect(WorkspaceBrowserAddress.httpAlternative(for: URL(string: "https://example.com")) == nil)
        #expect(WorkspaceBrowserAddress.resolve("file:///tmp/page.html") == nil)
        #expect(WorkspaceBrowserAddress.resolve("javascript://alert(1)") == nil)
    }

    @Test func corruptedSnapshotFallsBackToAnEmptyWorkMode() throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("broken".utf8), forKey: BrowserWorkspaceState.storageKey)
        let state = BrowserWorkspaceState(defaults: defaults)
        #expect(state.tabs.isEmpty)
        #expect(state.selectedID == nil)
        #expect(!state.isBrowsing)
    }
}
