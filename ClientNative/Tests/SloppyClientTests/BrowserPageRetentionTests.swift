import Foundation
import Testing
@testable import SloppyClient

@MainActor
final class BrowserRetentionTestClock {
    var now = Date()
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@Suite("Browser page retention")
@MainActor
struct BrowserPageRetentionTests {
    private func fixture(_ run: @MainActor (BrowserWorkspaceState, BrowserRetentionTestClock) async throws -> Void) async throws {
        let name = "BrowserPageRetention.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let clock = BrowserRetentionTestClock()
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults), retentionClock: { clock.now }, startsPageMaintenance: false)
        try await run(state, clock)
    }

    private func open(_ host: String, in state: BrowserWorkspaceState) throws -> UUID {
        state.open(try #require(URL(string: "https://\(host)")), inNewTab: true)
        return try #require(state.selectedID)
    }

    @Test func discardsOnlyBackgroundPagesAfterAnHourAndKeepsTabRecords() async throws {
        try await fixture { state, clock in
            let first = try open("first.test", in: state)
            let original = try #require(state.pages[first])
            let second = try open("second.test", in: state)
            let active = try open("active.test", in: state)
            clock.advance(3599)
            #expect(await state.discardInactivePages() == 0)
            clock.advance(1)
            #expect(await state.discardInactivePages() == 2)
            #expect(state.tabs.count == 3)
            #expect(state.discardedPageIDs == [first, second])
            #expect(state.pages[active] != nil)
            state.select(first)
            #expect(state.pages[first] != nil)
            #expect(state.pages[first] !== original)
            #expect(state.selectedTab?.url?.host == "first.test")
        }
    }

    @Test func visitingATabRestartsItsInactivityInterval() async throws {
        try await fixture { state, clock in
            let first = try open("first.test", in: state)
            let second = try open("second.test", in: state)
            clock.advance(3500)
            state.select(first)
            state.select(second)
            clock.advance(100)
            #expect(await state.discardInactivePages() == 0)
            clock.advance(3500)
            #expect(await state.discardInactivePages() == 1)
            #expect(state.pages[first] == nil)
            #expect(state.selectedID == second)
        }
    }

    @Test func splitViewsPresentationsLoadingAndAgentBindingsStayResident() async throws {
        try await fixture { state, clock in
            let first = try open("first.test", in: state)
            let second = try open("second.test", in: state)
            let background = try open("background.test", in: state)
            let page = try #require(state.pages[background])
            state.combineTabsInSplit([first, second])
            page.beginAutomation()
            clock.advance(3601)
            #expect(await state.discardInactivePages() == 0)
            page.endAutomation()
            page.isLoading = true
            #expect(await state.discardInactivePages() == 0)
            page.isLoading = false
            page.beginPresentation()
            #expect(await state.discardInactivePages() == 0)
            page.endPresentation()
            clock.advance(3601)
            #expect(await state.discardInactivePages() == 1)
            #expect(state.pages[first] != nil)
            #expect(state.pages[second] != nil)
            #expect(state.pages[background] == nil)
        }
    }

    @Test func memoryPressureUsesAShorterGraceAndKeepsTheCurrentPage() async throws {
        try await fixture { state, clock in
            let oldest = try open("oldest.test", in: state)
            clock.advance(30)
            let recent = try open("recent.test", in: state)
            clock.advance(30)
            let active = try open("active.test", in: state)
            clock.advance(40)
            #expect(await state.discardInactivePages() == 0)
            #expect(await state.discardInactivePages(reason: .memoryPressure) == 1)
            #expect(state.pages[oldest] == nil)
            #expect(state.pages[recent] != nil)
            clock.advance(30)
            #expect(await state.discardInactivePages(reason: .memoryPressure) == 1)
            #expect(state.pages[active] != nil)
        }
    }

    @Test func hiddenWorkspaceRestoresItsSelectedFavoriteOnReturn() async throws {
        try await fixture { state, clock in
            let id = try open("favorite.test", in: state)
            let favorite = try #require(state.pinTab(id))
            state.setWorkspacePresented(false)
            clock.advance(3601)
            #expect(await state.discardInactivePages() == 1)
            #expect(state.selectedID == id)
            #expect(state.favorites.entry(favorite) != nil)
            state.setWorkspacePresented(true)
            #expect(state.selectedPage != nil)
            #expect(state.selectedTab?.favoriteID == favorite)
        }
    }

    @Test func maintenanceDoesNotKeepAWorkspaceAlive() throws {
        let name = "BrowserPageRetentionLifetime.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var state: BrowserWorkspaceState? = BrowserWorkspaceState(defaults: defaults)
        weak var weakState = state
        state = nil
        #expect(weakState == nil)
    }
}
