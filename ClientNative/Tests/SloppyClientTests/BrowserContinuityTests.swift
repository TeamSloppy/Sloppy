import Foundation
import Testing
@testable import SloppyClient

@Suite("Browser continuity")
@MainActor
struct BrowserContinuityTests {
    @Test func handoffUsesSelectedPageAndStopsInWorkOrOnBlankTabs() throws {
        let fixture = HistoryFixture()
        defer { fixture.clean() }
        let workspace = BrowserWorkspaceState(defaults: fixture.defaults, history: fixture.history)
        workspace.createBlankTab()
        #expect(BrowserHandoffPage(workspace: workspace) == nil)
        let page = try #require(workspace.selectedPage)
        page.currentURL = URL(string: "https://user:password@example.com/article?q=one#part")
        page.pageTitle = " Article "
        let handoff = try #require(BrowserHandoffPage(workspace: workspace))
        let activity = NSUserActivity(activityType: BrowserHandoffPage.activityType)
        handoff.update(activity)
        #expect(activity.title == "Article")
        #expect(activity.isEligibleForHandoff)
        #expect(!activity.isEligibleForSearch && !activity.isEligibleForPublicIndexing)
        #expect(BrowserHandoffPage.destination(activity)?.absoluteString == "https://example.com/article?q=one#part")
        workspace.isBrowsing = false
        #expect(BrowserHandoffPage(workspace: workspace) == nil)
        workspace.isBrowsing = true
        workspace.createBlankTab()
        #expect(BrowserHandoffPage(workspace: workspace) == nil)
    }

    @Test func handoffRejectsNonWebActivitiesFailuresAndOversizedURLs() throws {
        let fixture = HistoryFixture()
        defer { fixture.clean() }
        let workspace = BrowserWorkspaceState(defaults: fixture.defaults, history: fixture.history)
        workspace.createBlankTab()
        let page = try #require(workspace.selectedPage)
        for address in ["file:///tmp/secret", "about:blank", "javascript:alert(1)", "https://example.com/" + String(repeating: "x", count: 3000)] {
            page.currentURL = URL(string: address)
            #expect(BrowserHandoffPage(workspace: workspace) == nil)
        }
        page.currentURL = URL(string: "https://example.com")
        page.lastError = "Connection failed"
        #expect(BrowserHandoffPage(workspace: workspace) == nil)
        let activity = NSUserActivity(activityType: "other.activity")
        activity.webpageURL = page.currentURL
        #expect(BrowserHandoffPage.destination(activity) == nil)
        let web = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        web.webpageURL = page.currentURL
        #expect(BrowserHandoffPage.destination(web) == page.currentURL)
    }

    @Test func independentOfflineVisitsMergeWithoutDuplicatingOrInflatingCounts() throws {
        let cloud = FakeHistoryCloud()
        let first = HistoryFixture(cloud: cloud), second = HistoryFixture(cloud: cloud)
        defer { first.clean(); second.clean() }
        first.history.record(url: URL(string: "https://a.example"), title: "A")
        second.history.record(url: URL(string: "https://b.example"), title: "B")
        #expect(cloud.snapshots.isEmpty)
        first.history.syncEnabled = true
        second.history.syncEnabled = true
        first.history.synchronizeHistory()
        #expect(first.history.sites == second.history.sites)
        #expect(first.history.sites.count == 2)
        first.history.synchronizeHistory()
        #expect(first.history.sites.allSatisfy { $0.visitCount == 1 })
        #expect(cloud.snapshots.count == 2)
        second.history.syncEnabled = false
        second.history.record(url: URL(string: "https://offline.example"), title: nil)
        second.history.syncEnabled = true
        first.history.synchronizeHistory()
        #expect(first.history.sites.count == 3)
    }

    @Test func clearingHistoryPropagatesAndOfflineDeviceCannotRestoreOldVisits() {
        let cloud = FakeHistoryCloud()
        var time = Date(timeIntervalSince1970: 100)
        let first = HistoryFixture(cloud: cloud, now: { time }), second = HistoryFixture(cloud: cloud, now: { time })
        defer { first.clean(); second.clean() }
        first.history.record(url: URL(string: "https://old.example"), title: nil)
        first.history.syncEnabled = true
        second.history.syncEnabled = true
        second.history.syncEnabled = false
        time = Date(timeIntervalSince1970: 200)
        first.history.clear()
        second.history.syncEnabled = true
        #expect(second.history.sites.isEmpty)
        time = Date(timeIntervalSince1970: 300)
        second.history.record(url: URL(string: "https://new.example"), title: nil)
        first.history.synchronizeHistory()
        #expect(first.history.sites.map(\.url.host) == ["new.example"])
        #expect(WorkspaceBrowserHistory(defaults: first.defaults).sites == first.history.sites)
    }

    @Test func titleUpdatesTravelWithoutChangingVisitOrder() {
        let cloud = FakeHistoryCloud()
        var time = Date(timeIntervalSince1970: 100)
        let first = HistoryFixture(cloud: cloud, now: { time }), second = HistoryFixture(cloud: cloud, now: { time })
        defer { first.clean(); second.clean() }
        let url = URL(string: "https://example.com")!
        first.history.record(url: url, title: "Loading")
        first.history.syncEnabled = true
        second.history.syncEnabled = true
        time = Date(timeIntervalSince1970: 200)
        second.history.record(url: url, title: "Revisited")
        time = Date(timeIntervalSince1970: 300)
        first.history.updateTitle(url: url, title: "Loaded title")
        second.history.synchronizeHistory()
        #expect(second.history.sites.first?.title == "Loaded title")
        #expect(second.history.sites.first?.lastVisitedAt == Date(timeIntervalSince1970: 200))
        #expect(second.history.sites.first?.visitCount == 2)
    }

    @Test func missingICloudAndAccountChangeKeepHistoryLocal() {
        let cloud = FakeHistoryCloud()
        cloud.isAvailable = false
        let fixture = HistoryFixture(cloud: cloud)
        defer { fixture.clean() }
        fixture.history.syncEnabled = true
        fixture.history.record(url: URL(string: "https://example.com"), title: nil)
        #expect(cloud.snapshots.isEmpty)
        #expect(fixture.history.sites.count == 1)
        cloud.isAvailable = true
        fixture.history.synchronizeHistory()
        #expect(cloud.snapshots.count == 1)
        cloud.onChange?(NSUbiquitousKeyValueStoreAccountChange)
        #expect(!fixture.history.syncEnabled)
        #expect(fixture.history.sites.count == 1)
        #expect(!WorkspaceBrowserHistory(defaults: fixture.defaults).syncEnabled)
    }

    @Test func snapshotsAreBoundedAndUntrustedEntriesAreSanitized() throws {
        let sites = (0..<500).map { index in
            WorkspaceBrowserRecentSite(url: URL(string: "https://user:password@example.com/\(index)")!,
                title: String(repeating: "Title", count: 40), visitCount: -1,
                lastVisitedAt: Date(timeIntervalSince1970: Double(index + 1)))
        }
        let merged = BrowserHistorySnapshot.merge(sites, after: .distantPast)
        #expect(merged.allSatisfy { $0.url.user == nil && $0.url.password == nil && $0.visitCount == 1 })
        let data = try #require(BrowserHistorySnapshot(sites: merged, clearedAt: .distantPast).encoded())
        #expect(data.count <= BrowserHistorySnapshot.byteLimit)
        let decoded = try JSONDecoder().decode(BrowserHistorySnapshot.self, from: data)
        #expect(decoded.sites.count <= BrowserHistorySnapshot.sharedCount)
        #expect(decoded.sites.first?.url.path == "/499")
        #expect(BrowserHistorySnapshot.merge([.init(url: URL(string: "file:///tmp/secret")!, title: "secret",
            lastVisitedAt: Date())], after: .distantPast).isEmpty)
    }

    @Test func legacyHistoryMigratesInOrderAndCorruptCloudDataDoesNotEraseIt() throws {
        let cloud = FakeHistoryCloud()
        let fixture = HistoryFixture(cloud: cloud)
        defer { fixture.clean() }
        let legacy = Data("[{\"url\":\"https://first.example\",\"title\":\"First\"},{\"url\":\"https://second.example\",\"title\":\"Second\"}]".utf8)
        fixture.defaults.set(legacy, forKey: "workspace.browser.recent-sites")
        cloud.snapshots[BrowserHistorySnapshot.keyPrefix + "broken"] = Data("broken".utf8)
        let history = WorkspaceBrowserHistory(defaults: fixture.defaults, cloud: cloud)
        history.syncEnabled = true
        #expect(history.sites.map(\.title) == ["First", "Second"])
        #expect(history.sites.allSatisfy { $0.lastVisitedAt != nil })
    }
}

@MainActor
private final class FakeHistoryCloud: BrowserHistoryCloudStore {
    var isAvailable = true
    var snapshots: [String: Data] = [:]
    var onChange: ((Int) -> Void)?
    func start() {}
    func stop() {}
    func publish(_ data: Data, key: String) { snapshots[key] = data }
}

@MainActor
private struct HistoryFixture {
    let suite = "BrowserContinuity.\(UUID())"
    let defaults: UserDefaults
    let history: WorkspaceBrowserHistory
    init(cloud: (any BrowserHistoryCloudStore)? = nil, now: @escaping () -> Date = Date.init) {
        defaults = UserDefaults(suiteName: suite)!
        history = WorkspaceBrowserHistory(defaults: defaults, cloud: cloud, now: now)
    }
    func clean() { defaults.removePersistentDomain(forName: suite) }
}
