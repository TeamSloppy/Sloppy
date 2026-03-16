import Foundation
import Testing
@testable import Core
@testable import Protocols

// MARK: - Embedding tests

@Test func cosineSimilarityIdenticalVectors() {
    let v: [Float] = [1, 0, 0, 1]
    let score = HybridMemoryStore.cosineSimilarity(v, v)
    #expect(abs(score - 1.0) < 0.001)
}

@Test func cosineSimilarityOrthogonalVectors() {
    let a: [Float] = [1, 0]
    let b: [Float] = [0, 1]
    let score = HybridMemoryStore.cosineSimilarity(a, b)
    #expect(abs(score) < 0.001)
}

@Test func cosineSimilarityOppositeVectors() {
    let a: [Float] = [1, 0]
    let b: [Float] = [-1, 0]
    let score = HybridMemoryStore.cosineSimilarity(a, b)
    #expect(abs(score - (-1.0)) < 0.001)
}

@Test func cosineSimilarityEmptyVectorsReturnsZero() {
    let score = HybridMemoryStore.cosineSimilarity([], [])
    #expect(score == 0)
}

@Test func embeddingPersistedOnManualInject() async throws {
    let config = CoreConfig.test
    let store = HybridMemoryStore(config: config)

    let ref = await store.save(entry: MemoryWriteRequest(note: "test embedding fact"))

    // Manually inject an embedding vector to simulate what EmbeddingService would produce
    await store.persistEmbedding(memoryId: ref.id, vector: [0.1, 0.2, 0.3])

    let exists = await store.hasEmbedding(for: ref.id)
    #expect(exists == true)
}

@Test func embeddingAbsentWhenNotInjected() async throws {
    let config = CoreConfig.test
    let store = HybridMemoryStore(config: config)
    let ref = await store.save(entry: MemoryWriteRequest(note: "no embedding"))
    let exists = await store.hasEmbedding(for: ref.id)
    #expect(exists == false)
}

@Test func recallWorksWithoutEmbeddingService() async throws {
    let config = CoreConfig.test
    let store = HybridMemoryStore(config: config)

    _ = await store.save(entry: MemoryWriteRequest(note: "swift programming language"))
    _ = await store.save(entry: MemoryWriteRequest(note: "unrelated topic about cooking"))

    let hits = await store.recall(request: MemoryRecallRequest(query: "swift programming", limit: 5))
    #expect(!hits.isEmpty)
    #expect(hits.first?.note.contains("swift") == true)
}

@Test func cosineRecallBooststSimilarVector() async throws {
    let config = CoreConfig.test
    let store = HybridMemoryStore(config: config)

    let refA = await store.save(entry: MemoryWriteRequest(note: "zzz111"))
    let refB = await store.save(entry: MemoryWriteRequest(note: "qqq999"))

    // refA and query are co-directional; refB is orthogonal
    let queryVec: [Float] = [1, 0, 0]
    let similarVec: [Float] = [0.9, 0.1, 0]
    let differentVec: [Float] = [0, 1, 0]

    await store.persistEmbedding(memoryId: refA.id, vector: similarVec)
    await store.persistEmbedding(memoryId: refB.id, vector: differentVec)

    let cosineResults = await store.queryCosineMatches(queryVector: queryVec, limit: 5, scope: nil)
    let ids = cosineResults.map(\.0)
    #expect(ids.first == refA.id)
}

// MARK: - Original integration test

@Test
func recallFindsPersistedFactForNaturalLanguageQueryAfterRestart() async throws {
    let config = CoreConfig.test

    let firstStore = HybridMemoryStore(config: config)
    let factRef = await firstStore.save(
        entry: MemoryWriteRequest(
            note: "Пользователя зовут Влад.",
            summary: "Имя пользователя — Влад",
            kind: .fact,
            memoryClass: .semantic,
            scope: .default
        )
    )

    let secondStore = HybridMemoryStore(config: config)
    for _ in 0..<3 {
        _ = await secondStore.save(
            entry: MemoryWriteRequest(
                note: "[bulletin] Active channels: 2 | Workers in progress: 0 | Total workers known: 0",
                summary: "Runtime bulletin: 2 channels, 0 workers",
                kind: .event,
                memoryClass: .bulletin,
                scope: .default
            )
        )
    }

    let hits = await secondStore.recall(
        request: MemoryRecallRequest(
            query: "имя пользователя как зовут пользователя как к нему обращаться",
            limit: 1
        )
    )

    #expect(hits.count == 1)
    #expect(hits.first?.ref.id == factRef.id)
}
