import Foundation
import Testing
@testable import Core
@testable import Protocols

@Test
func recallFindsPersistedFactForNaturalLanguageQueryAfterRestart() async throws {
    let sqlitePath = FileManager.default.temporaryDirectory
        .appendingPathComponent("core-memory-recall-\(UUID().uuidString).sqlite")
        .path

    var config = CoreConfig.default
    config.sqlitePath = sqlitePath

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
