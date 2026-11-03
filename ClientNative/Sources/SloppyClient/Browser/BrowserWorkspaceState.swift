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
    var favoriteID: UUID?
}

enum BrowserTabSwipeDirection: Equatable, Sendable {
    case previous
    case next

    static func resolve(horizontal: CGFloat, vertical: CGFloat) -> Self? {
        guard horizontal.isFinite, vertical.isFinite,
              abs(horizontal) >= 44, abs(horizontal) > abs(vertical) * 1.5 else { return nil }
        return horizontal < 0 ? .next : .previous
    }
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
    let time: BrowserTimeStore
    var sitePermissions: BrowserSitePermissions {
        didSet { for page in pages.values { page.sitePermissions = sitePermissions } }
    }
    let organizer: BrowserOrganizerStore
    let favorites: BrowserFavoritesStore
    let contentBlocker: BrowserContentBlocker
    @ObservationIgnored private var timeTrackingActive = false
    @ObservationIgnored private let timeTrackingID = UUID()
    @ObservationIgnored private let retentionClock: @MainActor () -> Date
    @ObservationIgnored private var hiddenSince: [UUID: Date] = [:]
    @ObservationIgnored private var workspacePresented = true
    @ObservationIgnored private var discardInProgress = false
    @ObservationIgnored private var pressurePending = false
    @ObservationIgnored private var pageMaintenance: BrowserPageMaintenance?
#if os(macOS)
    let extensions: BrowserExtensions
    @ObservationIgnored private(set) var extensionBridge: BrowserExtensionBridge?
#endif
    private(set) var groups: [BrowserTabGroup] = []
    private(set) var tabs: [BrowserTabRecord]
    private(set) var selectedID: UUID?
    private(set) var selectedTabIDs: Set<UUID> = []
    private(set) var splits: [BrowserSplitGroup] = []
    var isBrowsing = false {
        didSet {
            if isBrowsing { prepareVisiblePages() }
            persist()
        }
    }
    var searchEngine = BrowserSearchEngine.google { didSet { persist() } }
    private(set) var pages: [UUID: WorkspaceWebViewModel] = [:]
    var isCollecting = false
    var isSearchPresented = false
    var columnVisibility = NavigationSplitViewVisibility.all
    var sidebarMode = BrowserSidebarMode.sites
    let sidebarDrafts = BrowserSidebarDrafts()
    var searchText = ""
    var searchInNewTab = true

    init(defaults: UserDefaults = .standard, history: WorkspaceBrowserHistory? = nil,
         retentionClock: @escaping @MainActor () -> Date = { .now }, startsPageMaintenance: Bool = true,
         contentBlocker: BrowserContentBlocker? = nil) {
        sitePermissions = defaults === UserDefaults.standard ? .shared : BrowserSitePermissions(defaults: defaults)
        self.defaults = defaults
        self.contentBlocker = contentBlocker ?? (defaults === UserDefaults.standard ? .shared : BrowserContentBlocker(defaults: defaults))
        if contentBlocker == nil, defaults !== UserDefaults.standard { self.contentBlocker.setAutomaticUpdates(false) }
        self.retentionClock = retentionClock
        self.history = history ?? .shared
        library = BrowserLibrary(defaults: defaults)
        time = defaults === UserDefaults.standard ? .shared : BrowserTimeStore(defaults: defaults)
        organizer = defaults === UserDefaults.standard ? .shared : BrowserOrganizerStore(defaults: defaults)
        favorites = defaults === UserDefaults.standard ? .shared : BrowserFavoritesStore(defaults: defaults)
#if os(macOS)
        extensions = BrowserExtensions(defaults: defaults)
#endif
        let saved = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let restoredGroups = saved?.groups ?? []
        groups = restoredGroups
        var seen = Set<UUID>()
        var restoredFavorites = Set<UUID>()
        let validFavorites = Set(favorites.entries.filter { $0.kind == .page }.map(\.id))
        tabs = (saved?.tabs ?? []).filter { seen.insert($0.id).inserted }.map { tab in
            var tab = tab
            tab.url = BrowserSearchEngine.websiteURL(tab.url)
            if !restoredGroups.contains(where: { $0.id == tab.groupID }) { tab.groupID = nil }
            if let id = tab.favoriteID,
               !validFavorites.contains(id) || !restoredFavorites.insert(id).inserted { tab.favoriteID = nil }
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
        if startsPageMaintenance { pageMaintenance = BrowserPageMaintenance(state: self) }
    }

    var selectedTab: BrowserTabRecord? { tabs.first { $0.id == selectedID } }
    var selectedPage: WorkspaceWebViewModel? { selectedID.flatMap { pages[$0] } }

    @discardableResult
    func createBlankTab() -> UUID {
        createBlankTab(id: UUID())
    }

    @discardableResult
    func createBlankTab(id: UUID) -> UUID {
        checkpoint()
        isBrowsing = true
        let previous = selectedID
        let tab = BrowserTabRecord(id: id, groupID: selectedTab?.groupID)
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

    @discardableResult
    func selectAdjacentTab(_ direction: BrowserTabSwipeDirection) -> Bool {
        guard let target = tabSwipeTarget(direction) else { return false }
        return activateTabSwipeTarget(target)
    }

    func tabSwipeTarget(_ direction: BrowserTabSwipeDirection, newTabID: UUID = UUID()) -> BrowserTabSwipeTarget? {
        let index = tabs.firstIndex { $0.id == selectedID }
        switch direction {
        case .previous:
            guard let index, index > 0 else { return nil }
            return .existing(tabs[index - 1].id)
        case .next:
            let nextIndex = index.map { $0 + 1 } ?? 0
            if tabs.indices.contains(nextIndex) {
                return .existing(tabs[nextIndex].id)
            }
            return .newTab(newTabID)
        }
    }

    func prepareTabSwipeTarget(_ target: BrowserTabSwipeTarget) {
        if case .existing(let id) = target { preparePage(id) }
    }

    @discardableResult
    func activateTabSwipeTarget(_ target: BrowserTabSwipeTarget) -> Bool {
        switch target {
        case .existing(let id):
            guard tabs.contains(where: { $0.id == id }) else { return false }
            select(id)
        case .newTab(let id):
            guard !tabs.contains(where: { $0.id == id }) else { return false }
            createBlankTab(id: id)
        }
        return true
    }

    func selectTabs(_ ids: Set<UUID>, focusedID: UUID? = nil) {
        let valid = ids.intersection(tabs.map(\.id))
        guard !valid.isEmpty else { return }
        let added = valid.subtracting(selectedTabIDs)
        let target = focusedID.flatMap { valid.contains($0) ? $0 : nil }
            ?? tabs.last(where: { added.contains($0.id) })?.id
            ?? selectedID.flatMap { valid.contains($0) ? $0 : nil }
            ?? tabs.first(where: { valid.contains($0.id) })?.id
        if let target { select(target) }
        selectedTabIDs = valid
    }

    func favoriteID(for tab: BrowserTabRecord) -> UUID? {
        tab.favoriteID.flatMap { favorites.entry($0)?.kind == .page ? $0 : nil }
    }

    var regularTabs: [BrowserTabRecord] { tabs.filter { favoriteID(for: $0) == nil } }
    func tab(forFavorite id: UUID) -> BrowserTabRecord? { tabs.first { $0.favoriteID == id } }

    @discardableResult
    func pinTab(_ id: UUID, in folderID: UUID? = nil) -> UUID? {
        guard let index = tabs.firstIndex(where: { $0.id == id }), let url = tabs[index].url,
              let favorite = favorites.addPage(url: url, title: tabs[index].title, in: folderID) else { return nil }
        if let folderID { _ = favorites.move(favorite, into: folderID) }
        if let existing = tab(forFavorite: favorite), existing.id != id {
            select(existing.id)
        } else {
            tabs[index].favoriteID = favorite
            persist()
        }
        return favorite
    }

    func openFavorite(_ id: UUID) {
        guard let item = favorites.entry(id), item.kind == .page, let url = item.url else { return }
        if let tab = tab(forFavorite: id) { select(tab.id); return }
        if let index = tabs.firstIndex(where: { $0.url == url && favoriteID(for: $0) == nil }) {
            tabs[index].favoriteID = id
            select(tabs[index].id)
            return
        }
        checkpoint()
        isBrowsing = true
        let previous = selectedID
        let tab = BrowserTabRecord(url: url, title: item.title, favoriteID: id)
        tabs.append(tab)
        selectedID = tab.id
        selectedTabIDs = [tab.id]
        preparePage(tab.id)
#if os(macOS)
        extensionBridge?.opened(tab.id)
        extensionBridge?.selectionChanged(from: previous)
#endif
        persist()
    }

    func removeFavorites(_ ids: Set<UUID>) {
        favorites.remove(ids)
        for index in tabs.indices where tabs[index].favoriteID.map(ids.contains) == true { tabs[index].favoriteID = nil }
        persist()
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
        pages[id]?.releaseDiscardedPage()
        pages.removeValue(forKey: id)
        hiddenSince.removeValue(forKey: id)
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
        let indices = tabs.indices.filter { tabs[$0].groupID == groupID && favoriteID(for: tabs[$0]) == nil }
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
        page.sitePermissions = sitePermissions
        page.contentBlocker = contentBlocker
        page.onOpenLinkInNewTab = { [weak self] url in self?.open(url, inNewTab: true) }
        page.onPresentationChange = { [weak self] in self?.updatePageVisibility() }
        page.navigationBlock = { [weak self, weak page] url in
            guard let self, let page else { return nil }
            time.updateClock()
            let reason = time.block(for: url)
            page.applyTimeBlock(reason)
            page.blockedNavigationURL = reason == nil ? nil : url
            return reason?.message
        }
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
        updatePageVisibility()
    }

    private func persist() {
        updatePageVisibility()
        updateTimeUsage()
        let snapshot = Snapshot(tabs: tabs, selectedID: selectedID, isBrowsing: isBrowsing, searchEngine: searchEngine, groups: groups, splits: splits)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.storageKey) }
    }

    func setWorkspacePresented(_ presented: Bool) {
        workspacePresented = presented
        if presented { prepareVisiblePages() }
        updatePageVisibility()
    }

    private var protectedVisiblePages: Set<UUID> {
        let selected = workspacePresented && isBrowsing ? Set(visibleTabs.map(\.id)) : []
        return selected.union(pages.compactMap { $0.value.presentations > 0 ? $0.key : nil })
    }

    private func updatePageVisibility() {
        let visible = protectedVisiblePages
        let now = retentionClock()
        for id in pages.keys {
            if visible.contains(id) { hiddenSince.removeValue(forKey: id) }
            else if hiddenSince[id] == nil { hiddenSince[id] = now }
        }
    }

    var discardedPageIDs: Set<UUID> { Set(tabs.filter { $0.url != nil && pages[$0.id] == nil }.map(\.id)) }

    /// Rechecks visibility and tool ownership after every asynchronous safety probe.
    @discardableResult
    func discardInactivePages(reason: BrowserPageDiscardReason = .idle) async -> Int {
        if discardInProgress {
            if reason == .memoryPressure { pressurePending = true }
            return 0
        }
        discardInProgress = true
        defer { discardInProgress = false; pressurePending = false }
        updatePageVisibility()
        let now = retentionClock()
        let candidates = hiddenSince.sorted { $0.value < $1.value }.map(\.key)
        var discarded = 0
        for id in candidates {
            let minimumAge: TimeInterval = reason == .memoryPressure || pressurePending ? 60 : 3600
            guard let hidden = hiddenSince[id], now.timeIntervalSince(hidden) >= minimumAge,
                  !protectedVisiblePages.contains(id), let page = pages[id], page.automationUses == 0, !page.isLoading else { continue }
#if os(macOS)
            guard !page.annotations.isSelecting, !page.annotations.isCapturing, page.annotations.draft == nil else { continue }
#endif
#if os(macOS) || os(iOS)
            let runtime = page.browserRuntime
            let operation = runtime?.operationRevision
            let revision = runtime?.activity.revision
            if let webView = page.nativeWebView, webView.url != nil {
                guard let runtime, await runtime.safeToDiscard(at: now) else { continue }
            }
            guard pages[id] === page, !protectedVisiblePages.contains(id), page.automationUses == 0,
                  !page.isLoading, page.nativeWebView?.isLoading != true, (runtime?.activeOperations ?? 0) == 0,
                  runtime?.operationRevision == operation, runtime?.activity.revision == revision,
                  let index = tabs.firstIndex(where: { $0.id == id }) else { continue }
            if let webView = page.nativeWebView, webView.url != nil {
                guard let url = BrowserSearchEngine.websiteURL(webView.url),
                      let interaction = webView.interactionState as? Data else { continue }
                tabs[index].url = url
                tabs[index].interactionState = interaction
            }
            page.releaseDiscardedPage()
            pages.removeValue(forKey: id)
            hiddenSince.removeValue(forKey: id)
            discarded += 1
#endif
        }
        if discarded > 0 { persist() }
        return discarded
    }

    func setTimeTrackingActive(_ active: Bool) {
        timeTrackingActive = active
        updateTimeUsage()
    }

    func updateTimeUsage() {
        let url = timeTrackingActive && isBrowsing && !isSearchPresented && selectedPage?.timeBlock == nil
            ? selectedPage?.currentURL : nil
        if timeTrackingActive { time.sample(url: url, owner: timeTrackingID) }
        else { time.stopSampling(owner: timeTrackingID) }
        for (id, page) in pages {
            let target = page.blockedNavigationURL ?? page.currentURL ?? tabs.first(where: { $0.id == id })?.url
            let reason = time.block(for: target)
            if reason != nil, page.timeBlock == nil {
                page.nativeWebView?.stopLoading()
            }
            page.applyTimeBlock(reason)
            if reason == nil, let pending = page.blockedNavigationURL {
                page.blockedNavigationURL = nil
                page.addressText = pending.absoluteString
                page.openAddress()
            }
        }
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
