import Foundation
import Testing
@testable import SloppyClient

@MainActor
struct BrowserSplitTests {
    private func makeState() throws -> (BrowserWorkspaceState, UserDefaults, String) {
        let name = "BrowserSplitTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults)), defaults, name)
    }

    private func openTabs(_ count: Int, in state: BrowserWorkspaceState) throws -> [UUID] {
        for index in 0..<count { state.open(try #require(URL(string: "https://example.test/\(index)")), inNewTab: true) }
        return state.tabs.map(\.id)
    }

    @Test func multipleSelectionTracksTheAddedTabAndHomeClearsIt() throws {
        let (state, defaults, name) = try makeState()
        defer { defaults.removePersistentDomain(forName: name) }
        let ids = try openTabs(3, in: state)
        state.select(ids[0])
        state.selectTabs([ids[0], ids[1], UUID()])
        #expect(state.selectedTabIDs == [ids[0], ids[1]])
        #expect(state.selectedID == ids[1])
        #expect(state.activeSplit == nil)
        state.selectTabs([ids[0]])
        #expect(state.selectedID == ids[0])
        state.showHome()
        #expect(state.selectedTabIDs.isEmpty)
        #expect(state.selectedID == nil)
    }

    @Test func splitsRestoreAndReselectTogetherWithoutDiscardingPages() throws {
        let (state, defaults, name) = try makeState()
        defer { defaults.removePersistentDomain(forName: name) }
        let ids = try openTabs(3, in: state)
        let firstPage = try #require(state.pages[ids[0]])
        state.selectTabs([ids[0], ids[1]])
        state.combineTabsInSplit(state.selectedTabIDs)
        #expect(state.visibleTabs.map(\.id) == [ids[0], ids[1]])
        #expect(state.pages[ids[0]] === firstPage)
        state.select(ids[2])
        #expect(state.visibleTabs.map(\.id) == [ids[2]])
        state.select(ids[0])
        #expect(state.visibleTabs.map(\.id) == [ids[0], ids[1]])
        let restored = BrowserWorkspaceState(defaults: defaults)
        #expect(restored.visibleTabs.map(\.id) == [ids[0], ids[1]])
        #expect(Set(restored.pages.keys) == [ids[0], ids[1]])
        restored.separateSplit(containing: ids[1])
        #expect(restored.splits.isEmpty)
        #expect(restored.tabs.map(\.id) == ids)
        #expect(BrowserWorkspaceState(defaults: defaults).splits.isEmpty)
    }

    @Test func recombiningAndClosingSplitTabsKeepsMembershipValid() throws {
        let (state, defaults, name) = try makeState()
        defer { defaults.removePersistentDomain(forName: name) }
        let ids = try openTabs(5, in: state)
        state.combineTabsInSplit(Set(ids.prefix(3)))
        state.combineTabsInSplit([ids[2], ids[4]])
        #expect(state.splits.map(\.tabIDs) == [[ids[0], ids[1]], [ids[2], ids[4]]])
        state.select(ids[2])
        state.close(ids[2])
        #expect(state.selectedID == ids[4])
        #expect(state.visibleTabs.map(\.id) == [ids[4]])
        #expect(state.splits.map(\.tabIDs) == [[ids[0], ids[1]]])
        state.select(ids[0])
        state.close(ids[1])
        #expect(state.splits.isEmpty)
        #expect(state.selectedID == ids[0])
        #expect(state.selectedTabIDs == [ids[0]])
        state.combineTabsInSplit([ids[0], UUID()])
        #expect(state.splits.isEmpty)
    }

    @Test func restoreDropsMissingDuplicateAndOverlappingSplitMembers() throws {
        let (state, defaults, name) = try makeState()
        defer { defaults.removePersistentDomain(forName: name) }
        let ids = try openTabs(3, in: state)
        let data = try #require(defaults.data(forKey: BrowserWorkspaceState.storageKey))
        var snapshot = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        snapshot["splits"] = [
            ["id": UUID().uuidString, "tabIDs": [ids[0], ids[0], ids[1], UUID()].map(\.uuidString)],
            ["id": UUID().uuidString, "tabIDs": [ids[1], ids[2]].map(\.uuidString)],
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: snapshot), forKey: BrowserWorkspaceState.storageKey)
        let restored = BrowserWorkspaceState(defaults: defaults)
        #expect(restored.splits.map(\.tabIDs) == [[ids[0], ids[1]]])
        #expect(restored.tabs.map(\.id) == ids)
    }
}
