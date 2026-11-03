import Foundation

@MainActor
enum BrowserDomainSuggestions {
    static func hosts(query: String, history: [WorkspaceBrowserRecentSite], excluding: Set<String> = []) -> [String] {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = (BrowserTimeStore.normalizedHost(input) ?? input).lowercased()
        var seen = Set<String>()
        var matches: [(host: String, rank: Int, index: Int)] = []
        for (index, site) in history.enumerated() {
            guard let host = BrowserTimeStore.host(for: site.url), !excluding.contains(host),
                  needle.isEmpty || host.contains(needle) || site.title.localizedCaseInsensitiveContains(input),
                  seen.insert(host).inserted else { continue }
            matches.append((host, host.hasPrefix(needle) ? 0 : 1, index))
        }
        return matches.sorted { $0.rank == $1.rank ? $0.index < $1.index : $0.rank < $1.rank }
            .prefix(6).map(\.host)
    }
}
