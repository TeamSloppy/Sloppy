import Foundation
import CryptoKit
import Observation
import WebKit

@Observable @MainActor
final class BrowserContentBlocker {
    static let shared = BrowserContentBlocker()
    private struct Preferences: Codable {
        var enabled = true
        var automaticUpdates = true
        var disabledSites: Set<String> = []
    }
    private final class Attachment {
        weak var webView: WKWebView?
        var installed: WKContentRuleList?
        init(_ webView: WKWebView) { self.webView = webView }
    }
    private static let preferencesKey = "sloppy.browser.content-blocker.v1"
    private let defaults: UserDefaults
    private let repository: BrowserFilterRepository
    private let ruleStore: WKContentRuleListStore
    private let identifierPrefix: String
    private var preferences: Preferences
    private var snapshot: BrowserFilterRepository.Snapshot?
    @ObservationIgnored private var attachments: [Attachment] = []
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var rebuilding: Task<Void, Never>?
    @ObservationIgnored private var updating: Task<Void, Never>?
    @ObservationIgnored private var compiled: WKContentRuleList?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var appliedRevision = -1
    @ObservationIgnored private var lastAutomaticAttempt: Date?
    private(set) var isUpdating = false
    private(set) var isApplying = false
    private(set) var lastError: String?
    private(set) var lastCheckedAt: Date?
    private(set) var ruleCount = 0
    private(set) var isReady = false

    var isEnabled: Bool { preferences.enabled }
    var automaticUpdates: Bool { preferences.automaticUpdates }
    var disabledSites: [String] { preferences.disabledSites.sorted() }

    static var bundledFilterURL: URL? {
#if SWIFT_PACKAGE
        Bundle.module.url(forResource: "BrowserEasyList", withExtension: "json")
#else
        Bundle.main.url(forResource: "BrowserEasyList", withExtension: "json")
#endif
    }

    init(defaults: UserDefaults = .standard, repository: BrowserFilterRepository? = nil,
         ruleStore: WKContentRuleListStore? = nil, identifierPrefix: String = "sloppy.easylist.v1.") {
        self.defaults = defaults
        self.ruleStore = ruleStore ?? .default()
        self.identifierPrefix = identifierPrefix
        self.repository = repository ?? BrowserFilterRepository(
            cacheURL: URL.cachesDirectory.appending(path: "Sloppy/ContentBlocker/easylist.json"),
            bundledURL: Self.bundledFilterURL)
        preferences = defaults.data(forKey: Self.preferencesKey)
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
    }

    static func host(for url: URL?) -> String? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    func isSiteEnabled(_ url: URL?) -> Bool {
        guard let host = Self.host(for: url) else { return true }
        return !preferences.disabledSites.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func prepare() async {
        if let preparation { await preparation.value; return }
        let task = Task { @MainActor in
            if let cached = await repository.cached() {
                snapshot = cached
                await rebuild()
            }
            // A valid JSON cache may still be incompatible with this version of WebKit.
            if compiled == nil {
                do {
                    snapshot = try await repository.bundled()
                    revision += 1
                    await rebuild()
                } catch { lastError = error.localizedDescription }
            }
        }
        preparation = task
        await task.value
    }

    func attach(to webView: WKWebView) async {
        await prepare()
        attachments.removeAll { $0.webView == nil }
        if !attachments.contains(where: { $0.webView === webView }) {
            attachments.append(Attachment(webView))
        }
        applyToPages()
        scheduleAutomaticUpdate()
    }

    func detach(from webView: WKWebView) {
        for attachment in attachments where attachment.webView === webView {
            if let installed = attachment.installed { webView.configuration.userContentController.remove(installed) }
        }
        attachments.removeAll { $0.webView == nil || $0.webView === webView }
    }

    func setEnabled(_ enabled: Bool) async {
        preferences.enabled = enabled
        persist()
        applyToPages()
        await prepare()
        if enabled { await rebuild(); scheduleAutomaticUpdate() }
    }

    func setAutomaticUpdates(_ enabled: Bool) {
        preferences.automaticUpdates = enabled
        persist()
        if enabled { scheduleAutomaticUpdate() }
    }

    func setSiteEnabled(_ enabled: Bool, for url: URL) async {
        guard let host = Self.host(for: url) else { return }
        if enabled {
            // Removing a parent exception also re-enables its subdomains.
            preferences.disabledSites = preferences.disabledSites.filter { host != $0 && !host.hasSuffix("." + $0) }
        } else { preferences.disabledSites.insert(host) }
        revision += 1
        persist()
        await prepare()
        await rebuild()
    }

    func removeException(_ host: String) async {
        preferences.disabledSites.remove(host)
        revision += 1
        persist()
        await prepare()
        await rebuild()
    }

    func scheduleAutomaticUpdate(now: Date = .now) {
        guard isEnabled, automaticUpdates, snapshot != nil,
              now.timeIntervalSince(lastCheckedAt ?? .distantPast) >= 24 * 60 * 60,
              now.timeIntervalSince(lastAutomaticAttempt ?? .distantPast) >= 60 * 60 else { return }
        lastAutomaticAttempt = now
        Task { await update(now: now) }
    }

    func update(now: Date = .now) async {
        if let updating { await updating.value; return }
        let task = Task { @MainActor in
            isUpdating = true
            defer { isUpdating = false }
            await prepare()
            guard let previous = snapshot else { return }
            do {
                let candidate = try await repository.updated(from: previous, now: now)
                // Compile before changing either the active list or the on-disk cache.
                _ = try await compile(candidate.json, sites: [])
                try await repository.save(candidate)
                snapshot = candidate
                revision += 1
                await rebuild()
            } catch { lastError = error.localizedDescription }
        }
        updating = task
        await task.value
        updating = nil
    }

    private func rebuild() async {
        if let rebuilding { await rebuilding.value; return }
        let task = Task { @MainActor in
            isApplying = true
            defer { isApplying = false }
            while let snapshot, appliedRevision != revision {
                let requestedRevision = revision
                do {
                    let result = try await compile(snapshot.json, sites: disabledSites)
                    let count = await repository.ruleCount(in: snapshot)
                    guard requestedRevision == revision else { continue }
                    compiled = result
                    ruleCount = count
                    lastCheckedAt = snapshot.checkedAt
                    lastError = nil
                    appliedRevision = requestedRevision
                    isReady = true
                    applyToPages()
                    await removeObsoleteCompilations(keeping: result.identifier)
                } catch { lastError = error.localizedDescription; return }
            }
        }
        rebuilding = task
        await task.value
        rebuilding = nil
    }

    private func compile(_ json: String, sites: [String]) async throws -> WKContentRuleList {
        let (encoded, digest) = try await Task.detached {
            let encoded = try Self.rules(json, excluding: sites)
            let digest = SHA256.hash(data: Data(encoded.utf8)).map { String(format: "%02x", $0) }.joined()
            return (encoded, digest)
        }.value
        let identifier = identifierPrefix + digest
        if let existing = try? await ruleStore.contentRuleList(forIdentifier: identifier) { return existing }
        guard let result = try await ruleStore.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: encoded) else {
            throw BrowserFilterRepository.Failure.invalidRules
        }
        return result
    }

    nonisolated static func rules(_ json: String, excluding sites: [String]) throws -> String {
        guard var rules = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] else {
            throw BrowserFilterRepository.Failure.invalidRules
        }
        if !sites.isEmpty {
            let patterns = sites.sorted().map { host in
                "^https?://([a-z0-9-]+\\.)*" + NSRegularExpression.escapedPattern(for: host) + "\\.?(:[0-9]+)?/"
            }
            rules.append(["trigger": ["url-filter": ".*", "if-top-url": patterns],
                          "action": ["type": "ignore-previous-rules"]])
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]), as: UTF8.self)
    }

    private func applyToPages() {
        attachments.removeAll { $0.webView == nil }
        for attachment in attachments {
            guard let controller = attachment.webView?.configuration.userContentController else { continue }
            let desired = isEnabled ? compiled : nil
            guard attachment.installed?.identifier != desired?.identifier else { continue }
            if let installed = attachment.installed { controller.remove(installed) }
            if let desired { controller.add(desired) }
            attachment.installed = desired
        }
    }

    private func removeObsoleteCompilations(keeping identifier: String) async {
        let identifiers = await ruleStore.availableIdentifiers() ?? []
        for old in identifiers where old.hasPrefix(identifierPrefix) && old != identifier {
            try? await ruleStore.removeContentRuleList(forIdentifier: old)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.preferencesKey) }
    }
}
