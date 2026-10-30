#if os(macOS)
import Foundation
import AppKit
import Observation
import WebKit

struct BrowserExtensionRecord: Codable, Identifiable {
    var id = UUID()
    var bookmark: Data
    var relativePath: String
    var sourcePath: String
    var name: String
    var version: String
    var enabled = false
    var permissions: [String]
    var sites: [String]
    var allowedPermissions: [String] = []
    var allowedSites: [String] = []
}

/// Each Browse workspace has one controller, shared by its tabs. Safari's grants
/// are deliberately not imported: every permission here belongs to Sloppy.
@Observable @MainActor
final class BrowserExtensions: NSObject {
    static let storageKey = "sloppy.browser-extensions.v1"
    let controller = WKWebExtensionController()
    private(set) var records: [BrowserExtensionRecord]
    private(set) var errors: [UUID: String] = [:]
    var lastError: String?
    var isImporting = false
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var contexts: [UUID: WKWebExtensionContext] = [:]
    @ObservationIgnored private var scopedURLs: [UUID: URL] = [:]
    @ObservationIgnored private var restored = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([BrowserExtensionRecord].self, from: $0) } ?? []
        super.init()
    }

    deinit {
        for url in scopedURLs.values { url.stopAccessingSecurityScopedResource() }
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        for record in records {
            do {
                var stale = false
                let root = try URL(resolvingBookmarkData: record.bookmark, options: [.withSecurityScope],
                                   relativeTo: nil, bookmarkDataIsStale: &stale)
                let scoped = root.startAccessingSecurityScopedResource()
                do {
                    let context = try await makeContext(root: root, relativePath: record.relativePath, id: record.id)
                    guard records.contains(where: { $0.id == record.id }) else {
                        if scoped { root.stopAccessingSecurityScopedResource() }
                        continue
                    }
                    contexts[record.id] = context
                    if scoped { scopedURLs[record.id] = root }
                    if stale, let index = records.firstIndex(where: { $0.id == record.id }) {
                        records[index].bookmark = try bookmark(for: root)
                        persist()
                    }
                    applyPermissions(record, to: context)
                    if record.enabled { try controller.load(context) }
                } catch {
                    contexts.removeValue(forKey: record.id)
                    scopedURLs.removeValue(forKey: record.id)
                    if scoped { root.stopAccessingSecurityScopedResource() }
                    throw error
                }
            } catch { errors[record.id] = error.localizedDescription }
        }
    }

    func chooseImport() async {
        let panel = NSOpenPanel()
        panel.title = "Add Safari Web Extension"
        panel.message = "Choose a Safari extension app, an .appex bundle, or a folder containing manifest.json."
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        guard await panel.begin() == .OK, let url = panel.url else { return }
        isImporting = true
        defer { isImporting = false }
        do { try await importExtensions(at: url) }
        catch { lastError = error.localizedDescription }
    }

    func importExtensions(at root: URL) async throws {
        guard !records.contains(where: { $0.sourcePath == root.standardizedFileURL.path }) else {
            throw ImportError.alreadyAdded
        }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let paths = try Self.extensionPaths(in: root)
        let data = try bookmark(for: root)
        // Parse every extension before installing any: a failed import is atomic.
        var additions: [(BrowserExtensionRecord, WKWebExtensionContext)] = []
        for path in paths {
            let id = UUID()
            let context = try await makeContext(root: root, relativePath: path, id: id)
            let ext = context.webExtension
            let record = BrowserExtensionRecord(id: id, bookmark: data, relativePath: path, sourcePath: root.standardizedFileURL.path,
                name: ext.displayName ?? "Web Extension", version: ext.displayVersion ?? "",
                permissions: ext.requestedPermissions.union(ext.optionalPermissions).map(\.rawValue).sorted(),
                sites: ext.allRequestedMatchPatterns.map(\.string).sorted())
            additions.append((record, context))
        }
        for (record, context) in additions {
            records.append(record)
            contexts[record.id] = context
            if root.startAccessingSecurityScopedResource() { scopedURLs[record.id] = root }
        }
        persist()
    }

    static func extensionPaths(in root: URL) throws -> [String] {
        if root.pathExtension == "app" {
            let plugins = root.appendingPathComponent("Contents/PlugIns", isDirectory: true)
            let bundles = try FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
                .filter { url in
                    Bundle(url: url)?.object(forInfoDictionaryKey: "NSExtension")
                        .flatMap { $0 as? [String: Any] }?["NSExtensionPointIdentifier"] as? String == "com.apple.Safari.web-extension"
                }
            guard !bundles.isEmpty else { throw ImportError.noWebExtensions }
            return bundles.map { "Contents/PlugIns/\($0.lastPathComponent)" }.sorted()
        }
        if root.pathExtension == "appex" { return [""] }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path) else {
            throw ImportError.noWebExtensions
        }
        return [""]
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        guard let context = contexts[id] else {
            if !enabled { records[index].enabled = false; persist() }
            return
        }
        do {
            if enabled, !context.isLoaded { try controller.load(context) }
            else if context.isLoaded { try controller.unload(context) }
            records[index].enabled = enabled
            errors[id] = nil
            persist()
        } catch { errors[id] = error.localizedDescription }
    }

    func setPermission(_ permission: String, allowed: Bool, id: UUID, website: Bool) {
        guard let index = records.firstIndex(where: { $0.id == id }), let context = contexts[id] else { return }
        if website {
            guard records[index].sites.contains(permission) else { return }
            records[index].allowedSites.removeAll { $0 == permission }
            if allowed { records[index].allowedSites.append(permission) }
            if let pattern = try? WKWebExtension.MatchPattern(string: permission) {
                context.setPermissionStatus(allowed ? .grantedExplicitly : .deniedExplicitly, for: pattern)
            }
        } else {
            guard records[index].permissions.contains(permission) else { return }
            records[index].allowedPermissions.removeAll { $0 == permission }
            if allowed { records[index].allowedPermissions.append(permission) }
            context.setPermissionStatus(allowed ? .grantedExplicitly : .deniedExplicitly,
                                        for: WKWebExtension.Permission(rawValue: permission))
        }
        persist()
    }

    func remove(_ id: UUID) {
        if let context = contexts[id], context.isLoaded {
            do { try controller.unload(context) }
            catch { errors[id] = error.localizedDescription; return }
        }
        contexts.removeValue(forKey: id)
        scopedURLs.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        errors[id] = nil
        records.removeAll { $0.id == id }
        persist()
    }

    func saveGrants(for context: WKWebExtensionContext) {
        guard let index = records.firstIndex(where: { contexts[$0.id] === context }) else { return }
        let permissions = context.grantedPermissions.keys.map(\.rawValue)
        let sites = context.grantedPermissionMatchPatterns.keys.map(\.string)
        records[index].permissions = Array(Set(records[index].permissions + permissions)).sorted()
        records[index].sites = Array(Set(records[index].sites + sites)).sorted()
        records[index].allowedPermissions = permissions.sorted()
        records[index].allowedSites = sites.sorted()
        persist()
    }

    private func makeContext(root: URL, relativePath: String, id: UUID) async throws -> WKWebExtensionContext {
        let url = relativePath.isEmpty ? root : root.appendingPathComponent(relativePath)
        let ext: WKWebExtension
        if url.pathExtension == "appex", let bundle = Bundle(url: url) {
            ext = try await WKWebExtension(appExtensionBundle: bundle)
        } else { ext = try await WKWebExtension(resourceBaseURL: url) }
        let context = WKWebExtensionContext(for: ext)
        context.uniqueIdentifier = id.uuidString
        if let baseURL = URL(string: "webkit-extension://\(id.uuidString.lowercased())/") { context.baseURL = baseURL }
        return context
    }

    private func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                             includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func applyPermissions(_ record: BrowserExtensionRecord, to context: WKWebExtensionContext) {
        for permission in record.allowedPermissions where record.permissions.contains(permission) {
            context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: permission))
        }
        for site in record.allowedSites where record.sites.contains(site) {
            if let pattern = try? WKWebExtension.MatchPattern(string: site) { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.storageKey) }
    }

    enum ImportError: LocalizedError {
        case noWebExtensions, alreadyAdded
        var errorDescription: String? {
            switch self {
            case .noWebExtensions:
                "Choose a Safari Web Extension app or a folder containing manifest.json. Legacy Safari App Extensions are not supported."
            case .alreadyAdded:
                "This extension is already added. Manage it in Web Extensions."
            }
        }
    }
}
#endif
