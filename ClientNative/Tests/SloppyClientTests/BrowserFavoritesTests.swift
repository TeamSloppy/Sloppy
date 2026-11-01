import Foundation
import Testing
@testable import SloppyClient

@Suite("Browser Favorites")
@MainActor
struct BrowserFavoritesTests {
    private func fixture(_ run: (BrowserWorkspaceState, UserDefaults) throws -> Void) throws {
        let name = "BrowserFavorites.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try run(BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults)), defaults)
    }

    @Test func pinningMovesTheExistingTabWithoutReplacingItsPageAndRestores() throws {
        try fixture { state, defaults in
            let url = try #require(URL(string: "https://example.com/release"))
            state.open(url, inNewTab: true)
            let tab = try #require(state.selectedTab)
            let page = try #require(state.selectedPage)
            let folder = try #require(state.favorites.createFolder(title: "Work"))
            let favorite = try #require(state.pinTab(tab.id, in: folder))
            #expect(state.regularTabs.isEmpty)
            #expect(state.selectedID == tab.id)
            #expect(state.selectedPage === page)
            #expect(state.favorites.entry(favorite)?.parentID == folder)
            #expect(state.favorites.entry(favorite)?.url == url)
            let restored = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
            #expect(restored.favoriteID(for: try #require(restored.selectedTab)) == favorite)
            #expect(restored.regularTabs.isEmpty)
            #expect(restored.favorites.children(in: folder).map(\.id) == [favorite])
        }
    }

    @Test func closingAPinnedPageKeepsItsFavoriteAndReopensTheAnchor() throws {
        try fixture { state, _ in
            state.open(try #require(URL(string: "https://example.com")), inNewTab: true)
            let original = try #require(state.selectedID)
            let favorite = try #require(state.pinTab(original))
            state.close(original)
            #expect(state.tabs.isEmpty)
            #expect(state.favorites.entry(favorite) != nil)
            state.openFavorite(favorite)
            let reopened = try #require(state.selectedID)
            let page = try #require(state.selectedPage)
            #expect(reopened != original)
            #expect(state.tabs.count == 1)
            #expect(state.selectedTab?.url?.host == "example.com")
            state.openFavorite(favorite)
            #expect(state.selectedID == reopened)
            #expect(state.selectedPage === page)
            #expect(state.tabs.count == 1)
        }
    }

    @Test func duplicatePinsReuseOneFavoriteAndDoNotDiscardEitherTab() throws {
        try fixture { state, _ in
            let url = try #require(URL(string: "https://example.com"))
            state.open(url, inNewTab: true)
            let first = try #require(state.selectedID)
            let favorite = try #require(state.pinTab(first))
            state.open(url, inNewTab: true)
            let second = try #require(state.selectedID)
            let page = try #require(state.selectedPage)
            #expect(state.pinTab(second) == favorite)
            #expect(state.favorites.entries.count == 1)
            #expect(state.tabs.count == 2)
            #expect(state.selectedID == first)
            state.close(first)
            state.openFavorite(favorite)
            #expect(state.selectedID == second)
            #expect(state.selectedPage === page)
            #expect(state.tabs.count == 1)
        }
    }

    @Test func nestedFoldersMoveAndRejectCyclesAndInvalidParents() throws {
        try fixture { state, defaults in
            let root = try #require(state.favorites.createFolder(title: "Work"))
            let nested = try #require(state.favorites.createFolder(title: "Research", in: root))
            let page = try #require(state.favorites.addPage(url: URL(string: "https://example.com")!, title: "Docs", in: nested))
            #expect(state.favorites.folderPath(nested) == "Work / Research")
            #expect(!state.favorites.move(root, into: nested))
            #expect(!state.favorites.move(root, into: root))
            #expect(!state.favorites.move(nested, into: page))
            #expect(!state.favorites.move(page, into: UUID()))
            #expect(state.favorites.move(page, into: root))
            state.favorites.rename(nested, title: "  Reference  ")
            state.favorites.setCollapsed(root, true)
            let restored = BrowserFavoritesStore(defaults: defaults)
            #expect(restored.entry(root)?.isCollapsed == true)
            #expect(restored.folderPath(nested) == "Work / Reference")
            #expect(restored.entry(page)?.parentID == root)
        }
    }

    @Test func removingFoldersKeepsAllTheirRemainingPagesAndSubfolders() throws {
        try fixture { state, _ in
            let root = try #require(state.favorites.createFolder(title: "Work"))
            let nested = try #require(state.favorites.createFolder(title: "Research", in: root))
            let page = try #require(state.favorites.addPage(url: URL(string: "https://example.com")!, title: "Docs", in: nested))
            state.removeFavorites([root])
            #expect(state.favorites.entry(nested)?.parentID == nil)
            #expect(state.favorites.entry(page)?.parentID == nested)
            state.removeFavorites([nested])
            #expect(state.favorites.entry(page)?.parentID == nil)
            #expect(state.favorites.entries.count == 1)
        }
    }

    @Test func unpinningRestoresTheLiveTabAndItsOriginalGroup() throws {
        try fixture { state, _ in
            state.open(try #require(URL(string: "https://example.com")), inNewTab: true)
            let tab = try #require(state.selectedID)
            let page = try #require(state.selectedPage)
            let group = try #require(state.saveGroup(title: "Original group", tabID: tab))
            let favorite = try #require(state.pinTab(tab))
            state.removeFavorites([favorite])
            #expect(state.regularTabs.map(\.id) == [tab])
            #expect(state.selectedTab?.groupID == group)
            #expect(state.selectedPage === page)
            #expect(state.favorites.entries.isEmpty)
        }
    }

    @Test func ordinaryTabReorderingIgnoresPinnedRows() throws {
        try fixture { state, _ in
            var ids: [UUID] = []
            for host in ["first.test", "pinned.test", "last.test"] {
                state.open(try #require(URL(string: "https://\(host)")), inNewTab: true)
                ids.append(try #require(state.selectedID))
            }
            _ = try #require(state.pinTab(ids[1]))
            state.move(in: nil, from: IndexSet(integer: 0), to: 2)
            #expect(state.regularTabs.map(\.id) == [ids[2], ids[0]])
            #expect(state.tabs[1].id == ids[1])
        }
    }

    @Test func siblingOrderPersistsAndUnsafePagesAreRejected() throws {
        try fixture { state, defaults in
            let folder = try #require(state.favorites.createFolder(title: "Folder"))
            let first = try #require(state.favorites.addPage(url: URL(string: "https://user:secret@example.com/a#section")!, title: "A", in: folder))
            let second = try #require(state.favorites.addPage(url: URL(string: "https://example.com/b")!, title: "B", in: folder))
            #expect(state.favorites.addPage(url: URL(string: "file:///tmp/example")!, title: "Local") == nil)
            #expect(state.favorites.entry(first)?.url?.user == nil)
            #expect(state.favorites.entry(first)?.url?.password == nil)
            #expect(state.favorites.entry(first)?.url?.fragment == "section")
            state.favorites.reorder(in: folder, from: IndexSet(integer: 1), to: 0)
            #expect(BrowserFavoritesStore(defaults: defaults).children(in: folder).map(\.id) == [second, first])
        }
    }

    @Test func oldTabSnapshotsRestoreWithoutFavorites() throws {
        try fixture { _, defaults in
            let id = UUID()
            let snapshot: [String: Any] = ["tabs": [["id": id.uuidString, "url": "https://example.com", "title": "Legacy"]],
                "selectedID": id.uuidString, "isBrowsing": true, "searchEngine": "google"]
            defaults.set(try JSONSerialization.data(withJSONObject: snapshot), forKey: BrowserWorkspaceState.storageKey)
            let restored = BrowserWorkspaceState(defaults: defaults)
            #expect(restored.regularTabs.map(\.id) == [id])
            #expect(restored.favorites.entries.isEmpty)
        }
    }

    @Test func damagedFolderGraphsRestoreAsReachableAcyclicEntries() throws {
        try fixture { _, defaults in
            let first = UUID(), second = UUID()
            let records = [BrowserFavoriteEntry(id: first, kind: .folder, title: "A", parentID: second),
                BrowserFavoriteEntry(id: second, kind: .folder, title: "B", parentID: first),
                BrowserFavoriteEntry(kind: .page, title: "Page", url: URL(string: "https://example.com"), parentID: UUID()),
                BrowserFavoriteEntry(kind: .page, title: "Unsafe", url: URL(string: "file:///tmp/private"))]
            defaults.set(try JSONEncoder().encode(records), forKey: BrowserFavoritesStore.storageKey)
            let restored = BrowserFavoritesStore(defaults: defaults)
            #expect(restored.entries.count == 3)
            #expect(restored.children(in: nil).count == 3)
            #expect(restored.entries.allSatisfy { $0.parentID == nil })
        }
    }
}
