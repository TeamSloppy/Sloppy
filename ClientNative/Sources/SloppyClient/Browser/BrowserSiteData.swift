import Foundation
import Observation
import WebKit

@Observable @MainActor
final class BrowserSiteData {
    let origin: BrowserSiteOrigin
    let dataStore: WKWebsiteDataStore
    private(set) var records: [WKWebsiteDataRecord] = []
    private(set) var isBusy = false
    private(set) var hasLoaded = false
    private(set) var status: String?
    var recordNames: String { records.map(\.displayName).sorted().joined(separator: ", ") }

    static var cacheTypes: Set<String> {
        Set([WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache,
             WKWebsiteDataTypeOfflineWebApplicationCache, WKWebsiteDataTypeFetchCache])
            .intersection(WKWebsiteDataStore.allWebsiteDataTypes())
    }

    init(origin: BrowserSiteOrigin, dataStore: WKWebsiteDataStore) {
        self.origin = origin
        self.dataStore = dataStore
    }

    static func matches(host: String, record: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".[]"))
        let record = record.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".[]"))
        return !record.isEmpty && (host == record || host.hasSuffix("." + record))
    }

    private func matchingRecords() async -> [WKWebsiteDataRecord] {
        guard let host = origin.url?.host else { return [] }
        let records = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        return records.filter { Self.matches(host: host, record: $0.displayName) }
    }

    func inspect() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        records = await matchingRecords()
        hasLoaded = true
    }

    @discardableResult
    func clear(includingCookiesAndStorage: Bool) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        let targets = await matchingRecords()
        guard !targets.isEmpty, !Task.isCancelled else { status = "No stored data for this site."; return false }
        let types = includingCookiesAndStorage ? WKWebsiteDataStore.allWebsiteDataTypes() : Self.cacheTypes
        await dataStore.removeData(ofTypes: types, for: targets)
        records = await matchingRecords()
        status = includingCookiesAndStorage ? "Cookies and site data removed. The page reloads when you close settings." : "Cached files removed. Cookies and sign-in data were kept."
        return true
    }
}
