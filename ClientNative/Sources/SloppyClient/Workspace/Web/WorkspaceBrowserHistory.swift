import Foundation
import Observation

struct WorkspaceBrowserRecentSite: Codable, Equatable, Identifiable {
    let url: URL
    var title: String
    var id: String { url.absoluteString }
}

@Observable
@MainActor
final class WorkspaceBrowserHistory {
    static let shared = WorkspaceBrowserHistory()
    static let maximumCount = 20
    private static let storageKey = "workspace.browser.recent-sites"
    private let defaults: UserDefaults
    private(set) var sites: [WorkspaceBrowserRecentSite]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([WorkspaceBrowserRecentSite].self, from: $0) } ?? []
        sites = Array(stored.compactMap { site in
            Self.websiteURL(site.url).map { WorkspaceBrowserRecentSite(url: $0, title: site.title) }
        }.prefix(Self.maximumCount))
    }

    func record(url: URL?, title: String?) {
        guard let url, let url = Self.websiteURL(url) else { return }
        let previous = sites.first { $0.url == url }
        let title = Self.pageTitle(title) ?? previous?.title ?? url.host ?? url.absoluteString
        sites.removeAll { $0.url == url }
        sites.insert(.init(url: url, title: title), at: 0)
        sites = Array(sites.prefix(Self.maximumCount))
        persist()
    }

    func updateTitle(url: URL?, title: String?) {
        guard let url, let url = Self.websiteURL(url), let title = Self.pageTitle(title),
              let index = sites.firstIndex(where: { $0.url == url }), sites[index].title != title else { return }
        sites[index].title = title
        persist()
    }

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
