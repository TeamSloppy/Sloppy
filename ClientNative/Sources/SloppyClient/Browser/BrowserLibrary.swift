import Foundation
import Observation
import WebKit

struct BrowserBookmark: Codable, Equatable, Identifiable {
    var id = UUID()
    var url: URL
    var title: String
}

struct BrowserDownload: Codable, Identifiable {
    enum Status: String, Codable { case downloading, completed, failed, cancelled }
    var id = UUID()
    var sourceURL: URL?
    var filename: String
    var fileURL: URL?
    var status = Status.downloading
    var error: String?
}

@Observable
@MainActor
final class BrowserLibrary: NSObject, WKDownloadDelegate {
    private struct Snapshot: Codable {
        var bookmarks: [BrowserBookmark]
        var downloads: [BrowserDownload]
    }
    private let defaults: UserDefaults
    private let directory: URL
    private(set) var bookmarks: [BrowserBookmark]
    private(set) var downloads: [BrowserDownload]
    @ObservationIgnored private var active: [ObjectIdentifier: (WKDownload, UUID)] = [:]

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
#if os(macOS)
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sloppy/Browser Downloads", isDirectory: true)
#else
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Browser Downloads", isDirectory: true)
#endif
        let saved = defaults.data(forKey: "sloppy.browser-library.v1")
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        bookmarks = (saved?.bookmarks ?? []).filter { BrowserSearchEngine.websiteURL($0.url) != nil }
        downloads = (saved?.downloads ?? []).map {
            var record = $0
            if record.status == .downloading {
                record.status = .failed
                record.error = "Interrupted when the app closed."
            }
            return record
        }
        super.init()
    }

    func isBookmarked(_ url: URL) -> Bool { bookmarks.contains { $0.url == url } }

    func toggleBookmark(url: URL, title: String) {
        guard let url = BrowserSearchEngine.websiteURL(url) else { return }
        if isBookmarked(url) { bookmarks.removeAll { $0.url == url } }
        else { bookmarks.insert(.init(url: url, title: title), at: 0) }
        persist()
    }

    func removeBookmark(_ id: UUID) {
        bookmarks.removeAll { $0.id == id }
        persist()
    }

    func clearFinishedDownloads() {
        downloads.removeAll { $0.status != .downloading }
        persist()
    }

    func cancel(_ id: UUID) {
        guard let key = active.first(where: { $0.value.1 == id })?.key else { return }
        active[key]?.0.cancel { _ in }
        update(id) { $0.status = .cancelled }
        active.removeValue(forKey: key)
    }

    func receive(_ download: WKDownload) {
        let url = BrowserSearchEngine.websiteURL(download.originalRequest?.url)
        let record = BrowserDownload(sourceURL: url, filename: url?.lastPathComponent ?? "Download")
        downloads.insert(record, at: 0)
        active[ObjectIdentifier(download)] = (download, record.id)
        download.delegate = self
        persist()
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        guard let id = active[ObjectIdentifier(download)]?.1 else { return nil }
        do {
            let destination = try availableDestination(suggestedFilename)
            update(id) { $0.filename = destination.lastPathComponent; $0.fileURL = destination }
            return destination
        } catch {
            update(id) { $0.status = .failed; $0.error = error.localizedDescription }
            active.removeValue(forKey: ObjectIdentifier(download))
            return nil
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let (_, id) = active.removeValue(forKey: ObjectIdentifier(download)) else { return }
        update(id) { $0.status = .completed }
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        guard let (_, id) = active.removeValue(forKey: ObjectIdentifier(download)) else { return }
        update(id) { $0.status = .failed; $0.error = error.localizedDescription }
    }

    func availableDestination(_ suggestedFilename: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = URL(fileURLWithPath: suggestedFilename).lastPathComponent
        let base = directory.appendingPathComponent(name.isEmpty || name == "." || name == ".." ? "Download" : name)
        var candidate = base
        var suffix = 1
        let reserved = Set(downloads.filter { $0.status == .downloading }.compactMap(\.fileURL))
        while FileManager.default.fileExists(atPath: candidate.path) || reserved.contains(candidate) {
            let stem = base.deletingPathExtension().lastPathComponent
            let ext = base.pathExtension
            candidate = directory.appendingPathComponent("\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)"))
            suffix += 1
        }
        return candidate
    }

    private func update(_ id: UUID, _ mutation: (inout BrowserDownload) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        mutation(&downloads[index])
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Snapshot(bookmarks: bookmarks, downloads: downloads)) {
            defaults.set(data, forKey: "sloppy.browser-library.v1")
        }
    }
}
