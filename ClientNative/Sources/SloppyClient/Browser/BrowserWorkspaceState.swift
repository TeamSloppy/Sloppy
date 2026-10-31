import Foundation
import Observation
import SwiftUI
import WebKit

enum BrowserSearchEngine: String, Codable, CaseIterable, Identifiable {
    case google, duckDuckGo, bing, yandex
    var id: String { rawValue }
    var title: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .yandex: "Yandex"
        }
    }

    func destination(for input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.lowercased().hasPrefix("http:") || text.lowercased().hasPrefix("https:") {
            return Self.websiteURL(URL(string: text))
        }
        if !text.contains(where: \.isWhitespace),
           let candidate = WorkspaceBrowserAddress.resolve(text),
           let host = candidate.host,
           WorkspaceBrowserAddress.isLoopback(host) || host.contains(".") || host.hasPrefix("[") {
            return Self.websiteURL(candidate)
        }
        let endpoint: String = switch self {
        case .google: "https://www.google.com/search"
        case .duckDuckGo: "https://duckduckgo.com/"
        case .bing: "https://www.bing.com/search"
        case .yandex: "https://yandex.com/search/"
        }
        var components = URLComponents(string: endpoint)
        components?.queryItems = [URLQueryItem(name: self == .yandex ? "text" : "q", value: text)]
        // Search endpoints interpret a literal plus as a space in form-style query strings.
        let encodedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = encodedQuery
        return components?.url
    }

    static func websiteURL(_ url: URL?) -> URL? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.user = nil
        components.password = nil
        return components.url
    }
}

struct BrowserTabRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var url: URL?
    var title = "New tab"
    var interactionState: Data?
    var groupID: UUID?
}

struct BrowserTabGroup: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var isCollapsed = false
}

struct BrowserSplitGroup: Codable, Equatable, Identifiable {
    var id = UUID()
    var tabIDs: [UUID]
}

/// Device-local browsing state, independent of a Core instance or chat session.
@Observable
@MainActor
final class BrowserWorkspaceState {
    static let storageKey = "sloppy.browser-workspace.v1"
    private struct Snapshot: Codable {
        var tabs: [BrowserTabRecord]
        var selectedID: UUID?
        var isBrowsing: Bool
        var searchEngine: BrowserSearchEngine
        var groups: [BrowserTabGroup]?
        var splits: [BrowserSplitGroup]?
    }
    private let defaults: UserDefaults
    let history: WorkspaceBrowserHistory
    let library: BrowserLibrary
#if os(macOS)
    let extensions: BrowserExtensions
    @ObservationIgnored private(set) var extensionBridge: BrowserExtensionBridge?
#endif
    private(set) var groups: [BrowserTabGroup] = []
    private(set) var tabs: [BrowserTabRecord]
    private(set) var selectedID: UUID?
    private(set) var selectedTabIDs: Set<UUID> = []
    private(set) var splits: [BrowserSplitGroup] = []
    var isBrowsing = false { didSet { persist() } }
    var searchEngine = BrowserSearchEngine.google { didSet { persist() } }
    private(set) var pages: [UUID: WorkspaceWebViewModel] = [:]
    var isCollecting = false
    var isSearchPresented = false
    var columnVisibility = NavigationSplitViewVisibility.all
    var searchText = ""
    var searchInNewTab = true

    init(defaults: UserDefaults = .standard, history: WorkspaceBrowserHistory? = nil) {
        self.defaults = defaults
        self.history = history ?? .shared
        library = BrowserLibrary(defaults: defaults)
#if os(macOS)
        extensions = BrowserExtensions(defaults: defaults)
#endif
        let saved = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let restoredGroups = saved?.groups ?? []
        groups = restoredGroups
        var seen = Set<UUID>()
        tabs = (saved?.tabs ?? []).filter { seen.insert($0.id).inserted }.map { tab in
            var tab = tab
            tab.url = BrowserSearchEngine.websiteURL(tab.url)
            if !restoredGroups.contains(where: { $0.id == tab.groupID }) { tab.groupID = nil }
            return tab
        }
        selectedID = saved?.selectedID.flatMap { id in tabs.first(where: { $0.id == id })?.id ?? tabs.first?.id }
        selectedTabIDs = Set(selectedID.map { [$0] } ?? [])
        let tabIDs = Set(tabs.map(\.id))
        var assigned = Set<UUID>()
        splits = (saved?.splits ?? []).compactMap { split in
            var members = Set<UUID>()
            let ids = split.tabIDs.filter { tabIDs.contains($0) && !assigned.contains($0) && members.insert($0).inserted }
            guard ids.count >= 2 else { return nil }
            assigned.formUnion(ids)
            return BrowserSplitGroup(id: split.id, tabIDs: ids)
        }
        isBrowsing = saved?.isBrowsing ?? false
        searchEngine = saved?.searchEngine ?? .google
#if os(macOS)
        extensionBridge = BrowserExtensionBridge(state: self)
#endif
        prepareVisiblePages()
    }

    var selectedTab: BrowserTabRecord? { tabs.first { $0.id == selectedID } }
    var selectedPage: WorkspaceWebViewModel? { selectedID.flatMap { pages[$0] } }

    @discardableResult
    func createBlankTab() -> UUID {
        checkpoint()
        isBrowsing = true
        let previous = selectedID
        let tab = BrowserTabRecord(groupID: selectedTab?.groupID)
        tabs.append(tab)
        selectedID = tab.id
        selectedTabIDs = [tab.id]
        preparePage(tab.id)
#if os(macOS)
        extensionBridge?.opened(tab.id)
        extensionBridge?.selectionChanged(from: previous)
#endif
        persist()
        return tab.id
    }

    func presentSearch(newTab: Bool) {
        searchInNewTab = newTab
        searchText = newTab ? "" : selectedTab?.url?.absoluteString ?? ""
        isSearchPresented = true
    }

    func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        checkpoint()
        let previous = selectedID
        selectedID = id
        selectedTabIDs = [id]
        prepareVisiblePages()
#if os(macOS)
        extensionBridge?.selectionChanged(from: previous)
#endif
        persist()
    }

    func selectTabs(_ ids: Set<UUID>) {
        let valid = ids.intersection(tabs.map(\.id))
        guard !valid.isEmpty else { return }
        let added = valid.subtracting(selectedTabIDs)
        let target = tabs.last(where: { added.contains($0.id) })?.id
            ?? selectedID.flatMap { valid.contains($0) ? $0 : nil }
            ?? tabs.first(where: { valid.contains($0.id) })?.id
        if let target { select(target) }
        selectedTabIDs = valid
    }

    func open(_ url: URL, inNewTab: Bool) {
        guard let url = BrowserSearchEngine.websiteURL(url) else { return }
        isBrowsing = true
        let previous = selectedID
        if inNewTab || selectedID == nil {
            let tab = BrowserTabRecord(url: url, title: url.host ?? "New tab", groupID: selectedTab?.groupID)
            tabs.append(tab)
            selectedID = tab.id
            preparePage(tab.id)
#if os(macOS)
            extensionBridge?.opened(tab.id)
#endif
        } else if let id = selectedID, let index = tabs.firstIndex(where: { $0.id == id }) {
            tabs[index].url = url
            tabs[index].title = url.host ?? "Page"
            let page = pages[id]
            page?.addressText = url.absoluteString
            page?.openAddress()
        }
        selectedTabIDs = Set(selectedID.map { [$0] } ?? [])
#if os(macOS)
        extensionBridge?.selectionChanged(from: previous)
#endif
        persist()
    }

    func navigate(_ url: URL, inTab id: UUID) {
        guard let url = BrowserSearchEngine.websiteURL(url), let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].url = url
        preparePage(id)
        guard let page = pages[id] else { return }
#if os(macOS)
        _ = page.ensureBrowserRuntime()
#endif
        page.addressText = url.absoluteString
        page.openAddress()
        persist()
    }

    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let splitNeighbor = activeSplit?.tabIDs.first { $0 != id }
        let previous = selectedID
        pages[id]?.nativeWebView?.stopLoading()
        pages.removeValue(forKey: id)
        tabs.remove(at: index)
        removeFromSplits([id])
        selectedTabIDs.remove(id)
        if selectedID == id {
            selectedID = splitNeighbor ?? (tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id)
            prepareVisiblePages()
        }
        if selectedTabIDs.isEmpty, let selectedID { selectedTabIDs = [selectedID] }
#if os(macOS)
        extensionBridge?.selectionChanged(from: previous)
        extensionBridge?.closed(id)
#endif
        persist()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        let previous = tabs.map(\.id)
        let moving = offsets.sorted().map { tabs[$0] }
        for index in offsets.sorted().reversed() { tabs.remove(at: index) }
        tabs.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
#if os(macOS)
        extensionBridge?.reordered(from: previous)
#endif
        persist()
    }

    func checkpoint() {
        for (id, page) in pages {
            guard let index = tabs.firstIndex(where: { $0.id == id }) else { continue }
            if let webView = page.nativeWebView { tabs[index].interactionState = webView.interactionState as? Data }
        }
        persist()
    }

    func showHome() {
        checkpoint()
        let previous = selectedID
        selectedID = nil
        selectedTabIDs = []
#if os(macOS)
        extensionBridge?.selectionChanged(from: previous)
#endif
        persist()
    }

    @discardableResult
    func saveGroup(title: String, id: UUID? = nil, tabID: UUID? = nil) -> UUID? {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !title.isEmpty else { return nil }
        let groupID: UUID
        if let id, let index = groups.firstIndex(where: { $0.id == id }) {
            groups[index].title = title
            groupID = id
        } else {
            let group = BrowserTabGroup(title: title)
            groups.append(group)
            groupID = group.id
        }
        if let tabID { assign(tabID, to: groupID) }
        persist()
        return groupID
    }

    func assign(_ tabID: UUID, to groupID: UUID?) {
        guard groupID == nil || groups.contains(where: { $0.id == groupID }),
              let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].groupID = groupID
        persist()
    }

    func removeGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        for index in tabs.indices where tabs[index].groupID == id { tabs[index].groupID = nil }
        persist()
    }

    func toggleGroup(_ id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].isCollapsed.toggle()
        persist()
    }

    func move(in groupID: UUID?, from offsets: IndexSet, to destination: Int) {
        let previous = tabs.map(\.id)
        let indices = tabs.indices.filter { tabs[$0].groupID == groupID }
        var items = indices.map { tabs[$0] }
        let moving = offsets.sorted().map { items[$0] }
        for index in offsets.sorted().reversed() { items.remove(at: index) }
        items.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        for (index, tab) in zip(indices, items) { tabs[index] = tab }
#if os(macOS)
        extensionBridge?.reordered(from: previous)
#endif
        persist()
    }

    private func preparePage(_ id: UUID) {
        guard pages[id] == nil, let tab = tabs.first(where: { $0.id == id }) else { return }
        let page = WorkspaceWebViewModel(history: history)
#if os(macOS)
        page.webExtensionController = extensions.controller
        page.onBrowserStateChange = { [weak self] in self?.extensionBridge?.changed(id) }
#endif
        page.onDownload = { [weak library, weak page] download in
            page?.isLoading = false
            library?.receive(download)
        }
        page.addressText = tab.url?.absoluteString ?? ""
        page.onPageChange = { [weak self, weak page] in
            guard let self, let page, let index = tabs.firstIndex(where: { $0.id == id }),
                  let url = BrowserSearchEngine.websiteURL(page.currentURL) else { return }
            tabs[index].url = url
            let title = page.pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            tabs[index].title = title.isEmpty ? url.host ?? "Page" : String(title.prefix(200))
            tabs[index].interactionState = page.nativeWebView?.interactionState as? Data
            persist()
        }
        pages[id] = page
    }

    private func persist() {
        let snapshot = Snapshot(tabs: tabs, selectedID: selectedID, isBrowsing: isBrowsing, searchEngine: searchEngine, groups: groups, splits: splits)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.storageKey) }
    }

    var activeSplit: BrowserSplitGroup? {
        selectedID.flatMap { id in splits.first { $0.tabIDs.contains(id) } }
    }

    var visibleTabs: [BrowserTabRecord] {
        guard let split = activeSplit else { return selectedTab.map { [$0] } ?? [] }
        return split.tabIDs.compactMap { id in tabs.first { $0.id == id } }
    }

    func combineTabsInSplit(_ ids: Set<UUID>) {
        let ordered = tabs.filter { ids.contains($0.id) }.map(\.id)
        guard ordered.count >= 2 else { return }
        checkpoint()
        removeFromSplits(Set(ordered))
        splits.append(BrowserSplitGroup(tabIDs: ordered))
        let active = selectedID.flatMap { ids.contains($0) ? $0 : nil } ?? ordered[0]
        select(active)
        selectedTabIDs = Set(ordered)
    }

    func separateSplit(containing id: UUID) {
        splits.removeAll { $0.tabIDs.contains(id) }
        if let selectedID { selectedTabIDs = [selectedID] }
        persist()
    }

    private func removeFromSplits(_ ids: Set<UUID>) {
        splits = splits.compactMap { split in
            let remaining = split.tabIDs.filter { !ids.contains($0) }
            return remaining.count >= 2 ? BrowserSplitGroup(id: split.id, tabIDs: remaining) : nil
        }
    }

    private func prepareVisiblePages() {
        for tab in visibleTabs { preparePage(tab.id) }
    }
}
