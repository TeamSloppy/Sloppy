import Foundation
import Protocols
import Logging

actor TextSearchService {
    private let root: URL
    private var reader: TextSearchDatabase?
    private var task: Task<Void, Never>?
    private var indexing = true
    private var indexedSources = 0
    private var failedSources = 0
    private let logger = Logger.sloppy(label: "sloppy.search")

    init(root: URL) { self.root = root }

    deinit { task?.cancel() }

    func start() throws {
        guard task == nil else { return }
        let url = root.appendingPathComponent("search/index.sqlite")
        let writer = try TextSearchDatabase(url: url)
        reader = try TextSearchDatabase(url: url, readOnly: true)
        let root = self.root
        task = Task.detached(priority: .utility) { [weak self] in
            let indexer = TextSearchIndexer(root: root, database: writer)
            while !Task.isCancelled {
                await self?.willSynchronize()
                do {
                    let result = try indexer.synchronize()
                    await self?.didSynchronize(result)
                } catch is CancellationError { return }
                catch { await self?.didFail(error) }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    func stop() async {
        task?.cancel()
        await task?.value
        task = nil
        reader = nil
    }

    func search(query: String, mode: TextSearchMode, agentID: String?, projectID: String?, limit: Int, offset: Int) async throws -> TextSearchResponse {
        guard query.count <= 1_000, (1...100).contains(limit), (0...10_000).contains(offset) else { throw TextSearchDatabase.Failure.invalidQuery }
        try start()
        let start = ContinuousClock.now
        guard let reader else { throw TextSearchDatabase.Failure.sqlite("Search is unavailable") }
        let hits = try await Task.detached(priority: .userInitiated) {
            try reader.search(query: query, mode: mode, agentID: agentID, projectID: projectID, limit: limit + 1, offset: offset)
        }.value
        let duration = start.duration(to: .now)
        let milliseconds = Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        return TextSearchResponse(items: Array(hits.prefix(limit)), hasMore: hits.count > limit && offset + limit <= 10_000, indexing: indexing,
            indexedSources: indexedSources, failedSources: failedSources, durationMs: milliseconds)
    }

    func document(id: String) async throws -> TextSearchDocumentResponse? {
        try start()
        guard let reader else { return nil }
        return try await Task.detached(priority: .userInitiated) { try reader.document(id: id) }.value
    }

    private func willSynchronize() { indexing = true }

    private func didSynchronize(_ result: TextSearchIndexer.ScanResult) {
        indexing = false
        indexedSources = result.indexed
        failedSources = result.failed
    }

    private func didFail(_ error: Error) {
        indexing = false
        failedSources = max(1, failedSources)
        logger.error("Search index synchronization failed", metadata: ["error": .string(String(describing: error))])
    }
}
