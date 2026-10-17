import Foundation
import Testing
@testable import AgentRuntime
@testable import Protocols

private func hit(_ id: String, _ note: String, kind: MemoryKind = .fact, summary: String? = nil) -> MemoryHit {
    MemoryHit(
        ref: MemoryRef(id: id, score: 0.9, kind: kind, createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
        note: note, summary: summary)
}

@Test
func recalledMemoryLinesCarryNoRecordIdsSoTheyCannotBeMistakenForAnswers() {
    let block = RuntimeSystem.recalledMemoryBlock(
        hits: [hit("5F1C8A2B-1111-4222-8333-944455556666", "The deploy key id of billing is K-77.")], limit: 8, maxCharacters: 6000)

    let line = block.lines.last ?? ""
    #expect(line.hasPrefix("- The deploy key id of billing is K-77."))
    #expect(!line.contains("5F1C8A2B"), "a visible UUID gets returned as the answer to 'what is the deploy key id?'")
    #expect(line.contains("saved 2023-11-14"))
    #expect(block.injectedIDs == ["5F1C8A2B-1111-4222-8333-944455556666"], "ids stay available for diagnostics")
    #expect(block.lines[1].contains("same topic"), "the header says how to correct a fact in one step")
}

@Test
func recalledMemoryLinesShowTheTopicSoACorrectionCanReuseIt() {
    let withTopic = MemoryHit(
        ref: MemoryRef(id: "id-1", score: 0.9, kind: .fact, createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
        note: "The deploy key id of billing is K-77.", topic: "billing deploy key id")

    let block = RuntimeSystem.recalledMemoryBlock(hits: [withTopic, hit("id-2", "No topic here.")], limit: 8, maxCharacters: 6000)

    #expect(block.lines[2].hasPrefix("- [billing deploy key id] The deploy key id of billing is K-77."))
    #expect(block.lines[3].hasPrefix("- No topic here."))
}

@Test
func recalledMemoryBlockRespectsTheLimitAndTheCharacterBudget() {
    let hits = (0..<10).map { hit("id-\($0)", String(repeating: "x", count: 300)) }

    let limited = RuntimeSystem.recalledMemoryBlock(hits: hits, limit: 3, maxCharacters: 6000)
    let budgeted = RuntimeSystem.recalledMemoryBlock(hits: hits, limit: 10, maxCharacters: 1500)

    #expect(limited.injectedIDs == ["id-0", "id-1", "id-2"])
    #expect(budgeted.injectedIDs.count < 10)
    #expect(budgeted.lines.joined(separator: "\n").count <= 1500)
}

@Test
func recalledMemoryBlockWithoutHitsInjectsNothing() {
    #expect(RuntimeSystem.recalledMemoryBlock(hits: [], limit: 8, maxCharacters: 6000).injectedIDs.isEmpty)
}
