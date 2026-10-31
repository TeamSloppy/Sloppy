import Foundation
import Observation

struct WorkspaceBrowserRecentSite: Codable, Equatable, Identifiable {
    let url: URL
    var title: String
    var visitCount: Int? = nil
    var lastVisitedAt: Date? = nil
    var modifiedAt: Date? = nil
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
    static let shared = WorkspaceBrowserHistory(cloud: ICloudBrowserHistoryStore())
    static let maximumCount = 2000
    private static let storageKey = "workspace.browser.recent-sites"
    private let defaults: UserDefaults
    private(set) var sites: [WorkspaceBrowserRecentSite]
    @ObservationIgnored let cloud: (any BrowserHistoryCloudStore)?
    @ObservationIgnored private let now: () -> Date
    private var clearedAt: Date
    var syncEnabled: Bool {
        didSet {
            defaults.set(syncEnabled, forKey: "browser.history.sync-enabled")
            if syncEnabled { synchronizeHistory() }
            else {
                cloud?.stop()
                syncMessage = "Enable on each device using the same Apple Account."
            }
        }
    }
    private(set) var syncMessage = "Enable on each device using the same Apple Account."

    init(defaults: UserDefaults = .standard, cloud: (any BrowserHistoryCloudStore)? = nil,
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.cloud = cloud
        self.now = now
        clearedAt = defaults.object(forKey: "browser.history.cleared-at") as? Date ?? .distantPast
        syncEnabled = defaults.bool(forKey: "browser.history.sync-enabled")
        let stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([WorkspaceBrowserRecentSite].self, from: $0) } ?? []
        sites = Array(stored.enumerated().compactMap { index, site in
            Self.websiteURL(site.url).map {
                WorkspaceBrowserRecentSite(url: $0, title: site.title, visitCount: site.visitCount,
                    lastVisitedAt: site.lastVisitedAt ?? Date(timeIntervalSince1970: Double(stored.count - index)), modifiedAt: site.modifiedAt)
            }
        }.prefix(Self.maximumCount))
        cloud?.onChange = { [weak self] reason in
            guard let self, syncEnabled else { return }
            if reason == NSUbiquitousKeyValueStoreAccountChange {
                syncEnabled = false
                syncMessage = "Apple Account changed. Enable sync again to share this device’s history."
            } else if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
                syncMessage = "iCloud storage is full. History is still saved on this device."
            } else { synchronizeHistory() }
        }
        if syncEnabled { synchronizeHistory() }
    }

    func record(url: URL?, title: String?) {
        guard let url, let url = Self.websiteURL(url) else { return }
        let previous = sites.first { $0.url == url }
        let title = Self.pageTitle(title) ?? previous?.title ?? url.host ?? url.absoluteString
        sites.removeAll { $0.url == url }
        let visits = previous.map { max(1, min($0.visitCount ?? 1, 1_000_000_000)) } ?? 0
        sites.insert(.init(url: url, title: title, visitCount: visits + 1, lastVisitedAt: now()), at: 0)
        sites = Array(sites.prefix(Self.maximumCount))
        persist()
    }

    func updateTitle(url: URL?, title: String?) {
        guard let url, let url = Self.websiteURL(url), let title = Self.pageTitle(title),
              let index = sites.firstIndex(where: { $0.url == url }), sites[index].title != title else { return }
        sites[index].title = title
        sites[index].modifiedAt = now()
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

    func clear() {
        clearedAt = max(clearedAt, now())
        defaults.set(clearedAt, forKey: "browser.history.cleared-at")
        sites = []
        persist()
    }

    func synchronizeHistory() {
        guard syncEnabled, let cloud else { return }
        guard cloud.isAvailable else {
            syncMessage = cloud.unavailableMessage
            return
        }
        cloud.start()
        let snapshots = cloud.snapshots.compactMap { key, data -> BrowserHistorySnapshot? in
            guard key.hasPrefix(BrowserHistorySnapshot.keyPrefix), data.count <= BrowserHistorySnapshot.byteLimit else { return nil }
            return try? JSONDecoder().decode(BrowserHistorySnapshot.self, from: data)
        }
        clearedAt = snapshots.reduce(clearedAt) { max($0, $1.clearedAt) }
        sites = BrowserHistorySnapshot.merge(sites + snapshots.flatMap(\.sites), after: clearedAt)
        defaults.set(clearedAt, forKey: "browser.history.cleared-at")
        saveLocally()
        let deviceKey = defaults.string(forKey: "browser.history.device-key")
            ?? BrowserHistorySnapshot.keyPrefix + UUID().uuidString
        defaults.set(deviceKey, forKey: "browser.history.device-key")
        if let data = BrowserHistorySnapshot(sites: sites, clearedAt: clearedAt).encoded() {
            cloud.publish(data, key: deviceKey)
        }
        syncMessage = "Recent history syncs through iCloud. Updates may take a moment. Clearing history applies to synced devices."
    }

    private func persist() {
        saveLocally()
        synchronizeHistory()
    }

    private func saveLocally() {
        guard let data = try? JSONEncoder().encode(sites) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func pageTitle(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return String(title.prefix(200))
    }

    static func websiteURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.user = nil
        components.password = nil
        return components.url
    }
}
