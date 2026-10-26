import Foundation
import Observation
import SloppyClientCore

struct LocatedTextSearchHit: Identifiable, Sendable {
    let hit: TextSearchHit
    let endpoint: SloppyInstanceEndpoint
    var id: String { String(describing: endpoint) + ":" + hit.id }
}

@Observable
@MainActor
final class SessionTextSearchState {
    var items: [LocatedTextSearchHit] = []
    var isLoading = false
    var isIndexing = false
    var hasMore = false
    var error: String?
    var failedSources = 0
    private var generation = UUID()

    func search(_ query: String, endpoints: [SloppyInstanceEndpoint], primaryClient: SloppyAPIClient? = nil, mode: TextSearchMode = .text, offset: Int = 0) async {
        let request = UUID()
        generation = request
        items = []
        error = nil
        hasMore = false
        isIndexing = false
        failedSources = 0
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { isLoading = false; return }
        isLoading = true
        do { try await Task.sleep(for: .milliseconds(100)) }
        catch { return }
        repeat {
            let results = await withTaskGroup(of: (SloppyInstanceEndpoint, TextSearchResponse?, String?).self) { group in
                for endpoint in endpoints {
                    group.addTask {
                        let client: SloppyAPIClient
                        if let primaryClient, primaryClient.endpoint == endpoint { client = primaryClient }
                        else { client = SloppyAPIClient(endpoint: endpoint) }
                        do { return (endpoint, try await client.searchText(query, mode: mode, offset: offset), nil) }
                        catch { return (endpoint, nil, error.localizedDescription) }
                    }
                }
                var batches: [(SloppyInstanceEndpoint, TextSearchResponse?, String?)] = []
                for await result in group {
                    guard generation == request, !Task.isCancelled else { group.cancelAll(); return batches }
                    batches.append(result)
                    install(batches)
                }
                return batches
            }
            guard generation == request, !Task.isCancelled else { return }
            install(results)
            isLoading = false
            guard isIndexing else { return }
            do { try await Task.sleep(for: .milliseconds(700)) }
            catch { return }
        } while !Task.isCancelled
    }

    private func install(_ results: [(SloppyInstanceEndpoint, TextSearchResponse?, String?)]) {
        items = results.flatMap { endpoint, response, _ in
            (response?.items ?? []).map { LocatedTextSearchHit(hit: $0, endpoint: endpoint) }
        }.sorted { $0.hit.createdAt > $1.hit.createdAt }
        isIndexing = results.contains { $0.1?.indexing == true }
        hasMore = results.contains { $0.1?.hasMore == true }
        failedSources = results.reduce(0) { $0 + ($1.1?.failedSources ?? 0) }
        let failures = results.compactMap(\.2)
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
}

extension MainViewModel {
    func openTextSearchSession(_ item: LocatedTextSearchHit) {
        guard let agentID = item.hit.agentId else { return }
        let summary = ChatSessionSummary(id: item.hit.sessionId, agentId: agentID, title: item.hit.title, projectId: item.hit.projectId)
        openSessionChatTab(summary, endpointOverride: item.endpoint)
    }

    var textSearchEndpoints: [SloppyInstanceEndpoint] {
        guard settings.instanceSelection == .all else { return [endpoint] }
        var result: [SloppyInstanceEndpoint] = []
        for instance in settings.discoveredInstances where !result.contains(instance.endpoint) { result.append(instance.endpoint) }
        return result.isEmpty ? [endpoint] : result
    }
}
