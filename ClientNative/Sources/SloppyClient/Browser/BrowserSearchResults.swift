import Foundation

struct BrowserSearchResult: Identifiable {
    enum Target {
        case destination(URL), tab(UUID), bookmark(URL), history(URL)
    }
    let id: String
    let title: String
    let subtitle: String
    let target: Target

    var symbol: String {
        switch target {
        case .destination: "magnifyingglass"
        case .tab: "globe"
        case .bookmark: "bookmark"
        case .history: "clock"
        }
    }
    var category: String {
        switch target {
        case .destination: "Web"
        case .tab: "Tab"
        case .bookmark: "Bookmark"
        case .history: "History"
        }
    }
    var actionTitle: String {
        if case .tab = target { return "Switch to tab" }
        return "Open"
    }

    static func make(query: String, engine: BrowserSearchEngine, tabs: [BrowserTabRecord],
                     bookmarks: [BrowserBookmark], history: [WorkspaceBrowserRecentSite]) -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ title: String, _ url: URL?) -> Bool {
            query.isEmpty || title.localizedCaseInsensitiveContains(query)
                || (url?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
        }
        var results: [Self] = []
        var seen = Set<URL>()
        if !query.isEmpty, let url = engine.destination(for: query) {
            results.append(.init(id: "destination", title: query, subtitle: url.host ?? url.absoluteString, target: .destination(url)))
        }
        for tab in tabs where matches(tab.title, tab.url) {
            if let url = tab.url { seen.insert(url) }
            results.append(.init(id: "tab-\(tab.id)", title: tab.title, subtitle: tab.url?.host ?? "New tab", target: .tab(tab.id)))
        }
        for bookmark in bookmarks where matches(bookmark.title, bookmark.url) && seen.insert(bookmark.url).inserted {
            results.append(.init(id: "bookmark-\(bookmark.id)", title: bookmark.title,
                                 subtitle: bookmark.url.host ?? bookmark.url.absoluteString, target: .bookmark(bookmark.url)))
        }
        if !query.isEmpty {
            for site in history where matches(site.title, site.url) && seen.insert(site.url).inserted {
                results.append(.init(id: "history-\(site.id)", title: site.title,
                                     subtitle: site.url.host ?? site.url.absoluteString, target: .history(site.url)))
            }
        }
        return Array(results.prefix(6))
    }
}
