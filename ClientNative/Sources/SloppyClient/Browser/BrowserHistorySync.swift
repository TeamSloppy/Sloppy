import Foundation
#if os(macOS)
import Security
#endif

@MainActor
protocol BrowserHistoryCloudStore: AnyObject {
    var isAvailable: Bool { get }
    var unavailableMessage: String { get }
    var snapshots: [String: Data] { get }
    var onChange: ((Int) -> Void)? { get set }
    func start()
    func stop()
    func publish(_ data: Data, key: String)
}

extension BrowserHistoryCloudStore {
    var unavailableMessage: String { "Sign in to iCloud to sync. History is saved on this device." }
}

/// Separate device keys preserve concurrent/offline writes. A clear timestamp travels
/// with every snapshot so an old device cannot resurrect deleted visits.
struct BrowserHistorySnapshot: Codable {
    static let keyPrefix = "browser.history.v1."
    static let byteLimit = 32 * 1024
    static let sharedCount = 200
    var sites: [WorkspaceBrowserRecentSite]
    var clearedAt: Date

    @MainActor
    static func merge(_ sites: [WorkspaceBrowserRecentSite], after clearedAt: Date) -> [WorkspaceBrowserRecentSite] {
        var unique: [String: WorkspaceBrowserRecentSite] = [:]
        for var site in sites {
            guard let date = site.lastVisitedAt, date > clearedAt,
                  let url = WorkspaceBrowserHistory.websiteURL(site.url), url.absoluteString.utf8.count <= 8192 else { continue }
            site = .init(url: url, title: WorkspaceBrowserHistory.pageTitle(site.title) ?? url.host ?? "Page",
                visitCount: max(1, min(site.visitCount ?? 1, 1_000_000_000)), lastVisitedAt: date, modifiedAt: site.modifiedAt)
            if let previous = unique[site.id] {
                let visits = max(previous.visitCount ?? 1, site.visitCount ?? 1)
                let titleSource = (previous.modifiedAt ?? previous.lastVisitedAt ?? .distantPast) >= (site.modifiedAt ?? date) ? previous : site
                if (previous.lastVisitedAt ?? .distantPast) >= date { site = previous }
                site.title = titleSource.title
                site.modifiedAt = titleSource.modifiedAt
                site.visitCount = visits
            }
            unique[site.id] = site
        }
        return Array(unique.values.sorted {
            $0.lastVisitedAt == $1.lastVisitedAt ? $0.id < $1.id : ($0.lastVisitedAt ?? .distantPast) > ($1.lastVisitedAt ?? .distantPast)
        }.prefix(WorkspaceBrowserHistory.maximumCount))
    }

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var bounded = BrowserHistorySnapshot(sites: [], clearedAt: clearedAt)
        for site in sites.prefix(Self.sharedCount) {
            bounded.sites.append(site)
            guard let data = try? encoder.encode(bounded), data.count <= Self.byteLimit else {
                bounded.sites.removeLast()
                continue
            }
        }
        return try? encoder.encode(bounded)
    }
}

@MainActor
final class ICloudBrowserHistoryStore: BrowserHistoryCloudStore {
    var onChange: ((Int) -> Void)?
    private var observer: (any NSObjectProtocol)?
    private var store: NSUbiquitousKeyValueStore { .default }
    private var hasCloudEntitlement: Bool {
#if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.ubiquity-kvstore-identifier" as CFString, nil) as? String else { return false }
        return !value.isEmpty && !value.contains("$(")
#else
        return true
#endif
    }
    var isAvailable: Bool { hasCloudEntitlement && FileManager.default.ubiquityIdentityToken != nil }
    var unavailableMessage: String {
        hasCloudEntitlement ? "Sign in to iCloud to sync. History is saved on this device."
            : "This build needs an iCloud provisioning profile to sync. History is saved on this device."
    }
    var snapshots: [String: Data] {
        store.dictionaryRepresentation.compactMapValues { $0 as? Data }
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main) { [weak self] notification in
                let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int ?? 0
                MainActor.assumeIsolated { self?.onChange?(reason) }
            }
        store.synchronize()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func publish(_ data: Data, key: String) {
        guard store.data(forKey: key) != data else { return }
        // At most 16 × 32 KiB, leaving ample room below iCloud's 1 MiB quota.
        let others = snapshots.filter { $0.key.hasPrefix(BrowserHistorySnapshot.keyPrefix) && $0.key != key }
            .sorted { lhs, rhs in
                func latest(_ data: Data) -> Date {
                    guard let value = try? JSONDecoder().decode(BrowserHistorySnapshot.self, from: data) else { return .distantPast }
                    return max(value.clearedAt, value.sites.first?.lastVisitedAt ?? .distantPast)
                }
                let left = latest(lhs.value), right = latest(rhs.value)
                return left == right ? lhs.key < rhs.key : left > right
            }
        for entry in others.dropFirst(15) { store.removeObject(forKey: entry.key) }
        store.set(data, forKey: key)
    }
}
