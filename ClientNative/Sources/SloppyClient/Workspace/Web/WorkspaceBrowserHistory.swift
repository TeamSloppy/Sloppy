import Foundation
import Observation

struct WorkspaceBrowserRecentSite: Codable, Equatable, Identifiable {
    let url: URL
    var title: String
    var visitCount: Int? = nil
    var id: String { url.absoluteString }
}

struct BrowserFrequentSite: Identifiable {
    let id: String
    let url: URL
    let title: String
    var visits: Int
    let recentIndex: Int
}

@Observable
@MainActor
final class WorkspaceBrowserHistory {
    static let shared = WorkspaceBrowserHistory()
    static let maximumCount = 2000
    private static let storageKey = "workspace.browser.recent-sites"
    private let defaults: UserDefaults
    private(set) var sites: [WorkspaceBrowserRecentSite]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([WorkspaceBrowserRecentSite].self, from: $0) } ?? []
        sites = Array(stored.compactMap { site in
            Self.websiteURL(site.url).map { WorkspaceBrowserRecentSite(url: $0, title: site.title, visitCount: site.visitCount) }
        }.prefix(Self.maximumCount))
    }

    func record(url: URL?, title: String?) {
        guard let url, let url = Self.websiteURL(url) else { return }
        let previous = sites.first { $0.url == url }
        let title = Self.pageTitle(title) ?? previous?.title ?? url.host ?? url.absoluteString
        sites.removeAll { $0.url == url }
        let visits = previous.map { max(1, min($0.visitCount ?? 1, 1_000_000_000)) } ?? 0
        sites.insert(.init(url: url, title: title, visitCount: visits + 1), at: 0)
        sites = Array(sites.prefix(Self.maximumCount))
        persist()
    }

    func updateTitle(url: URL?, title: String?) {
        guard let url, let url = Self.websiteURL(url), let title = Self.pageTitle(title),
              let index = sites.firstIndex(where: { $0.url == url }), sites[index].title != title else { return }
        sites[index].title = title
        persist()
    }

    func frequentSites(limit: Int = 6) -> [BrowserFrequentSite] {
        var grouped: [String: BrowserFrequentSite] = [:]
        for (index, site) in sites.enumerated() {
            guard let host = site.url.host?.lowercased() else { continue }
            let key = host + (site.url.port.map { ":\($0)" } ?? "")
            let visits = max(1, min(site.visitCount ?? 1, 1_000_000_000))
            if var current = grouped[key] {
                current.visits += visits
                grouped[key] = current
            } else {
                grouped[key] = .init(id: key, url: site.url, title: site.title, visits: visits, recentIndex: index)
            }
        }
        return Array(grouped.values.sorted {
            $0.visits == $1.visits ? $0.recentIndex < $1.recentIndex : $0.visits > $1.visits
        }.prefix(max(0, min(limit, 6))))
    }

    func clear() { sites = []; persist() }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sites) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func pageTitle(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return String(title.prefix(200))
    }

    private static func websiteURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.user = nil
        components.password = nil
        return components.url
    }
}
