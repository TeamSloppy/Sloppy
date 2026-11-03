import Foundation
import Observation

struct BrowserSiteOrigin: Codable, Hashable, Identifiable {
    let id: String
    init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        let port = url.port
        parts.port = port == (scheme == "https" ? 443 : 80) ? nil : port
        guard let origin = parts.url?.absoluteString else { return nil }
        id = origin
    }
    var url: URL? { URL(string: id) }
}

enum BrowserSiteResource: String, Codable, CaseIterable, Identifiable {
    case http, camera, microphone, location
    var id: String { rawValue }
    var title: String {
        switch self { case .http: "Insecure HTTP"; case .camera: "Camera"; case .microphone: "Microphone"; case .location: "Location" }
    }
}

enum BrowserSiteDecision: String, Codable, CaseIterable, Identifiable {
    case ask, allow, block
    var id: String { rawValue }
    var title: String {
        switch self { case .ask: "Ask"; case .allow: "Allow"; case .block: "Block" }
    }
}

enum BrowserSiteConsent: Sendable { case once, always, cancel }

@Observable @MainActor
final class BrowserSitePermissions {
    static let shared = BrowserSitePermissions()
    private static let key = "sloppy.browser.site-permissions.v1"
#if os(macOS) || os(iOS)
    private let runtimes = NSHashTable<WorkspaceBrowserToolRuntime>.weakObjects()
    func register(_ runtime: WorkspaceBrowserToolRuntime) { runtimes.add(runtime) }
    func unregister(_ runtime: WorkspaceBrowserToolRuntime) { runtimes.remove(runtime) }
    private func revoke(_ origin: BrowserSiteOrigin, resource: BrowserSiteResource) {
        for runtime in runtimes.allObjects { runtime.revokePermission(for: origin, resource: resource) }
    }
#endif
    private let defaults: UserDefaults
    private var revisions: [String: Int] = [:]
    private var rules: [String: [String: BrowserSiteDecision]]
    var savedOrigins: [String] { rules.keys.sorted() }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rules = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: [String: BrowserSiteDecision]].self, from: $0) } ?? [:]
    }
    func decision(for origin: BrowserSiteOrigin, resource: BrowserSiteResource) -> BrowserSiteDecision {
        rules[origin.id]?[resource.rawValue] ?? .ask
    }
    func revision(for origin: BrowserSiteOrigin, resource: BrowserSiteResource) -> Int {
        revisions[origin.id + "|" + resource.rawValue] ?? 0
    }
    private func bump(_ origin: BrowserSiteOrigin, resource: BrowserSiteResource) {
        revisions[origin.id + "|" + resource.rawValue, default: 0] += 1
    }
    func set(_ decision: BrowserSiteDecision, for origin: BrowserSiteOrigin, resource: BrowserSiteResource) {
        bump(origin, resource: resource)
        if decision == .ask { rules[origin.id]?[resource.rawValue] = nil }
        else { rules[origin.id, default: [:]][resource.rawValue] = decision }
        if rules[origin.id]?.isEmpty == true { rules[origin.id] = nil }
        persist()
#if os(macOS) || os(iOS)
        if decision != .allow { revoke(origin, resource: resource) }
#endif
    }
    func reset(_ origin: BrowserSiteOrigin) {
        rules[origin.id] = nil
        for resource in BrowserSiteResource.allCases { bump(origin, resource: resource) }
        persist()
#if os(macOS) || os(iOS)
        for resource in BrowserSiteResource.allCases { revoke(origin, resource: resource) }
#endif
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: Self.key) }
    }
    func authorize(_ origin: BrowserSiteOrigin, resource: BrowserSiteResource,
                   prompt: @MainActor () async -> BrowserSiteConsent) async -> Bool {
        switch decision(for: origin, resource: resource) {
        case .allow: return true
        case .block: return false
        case .ask:
            let version = revision(for: origin, resource: resource)
            let choice = await prompt()
            guard !Task.isCancelled, version == revision(for: origin, resource: resource) else { return false }
            // A settings change while the prompt was visible takes precedence.
            if decision(for: origin, resource: resource) == .block { return false }
            switch choice {
            case .once: return true
            case .always: set(.allow, for: origin, resource: resource); return true
            case .cancel: return false
            }
        }
    }
}
