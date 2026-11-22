import Foundation
import Protocols
import Testing
@testable import sloppy

@Test
func turnDiffCombinesEditsAndOmitsRevertedChanges() throws {
    let changes = AgentTurnFileChanges()
    let original = (1...24).map { "line \($0)\n" }.joined()
    let first = original.replacingOccurrences(of: "line 2\n", with: "first edit\n")
    let last = first.replacingOccurrences(of: "line 22\n", with: "second edit\n")
    record(changes, "/checkout/a.txt", original, first)
    record(changes, "/checkout/a.txt", first, last)
    record(changes, "/other-checkout/a.txt", "base", "temporary")
    record(changes, "/other-checkout/a.txt", "temporary", "base")
    record(changes, "/checkout/empty", nil, "")

    let diff = try #require(changes.finish())
    #expect(!diff.truncated)
    #expect(diff.files.map(\.path) == ["/checkout/a.txt", "/checkout/empty"])
    let edited = diff.files[0]
    let patch = try #require(edited.patch)
    #expect(edited.attribution == .verified)
    #expect(edited.additions == 2)
    #expect(edited.deletions == 2)
    #expect(patch.contains("+first edit"))
    #expect(patch.contains("+second edit"))
    #expect(patch.split(separator: "\n").filter { $0.hasPrefix("@@ ") }.count == 2)
    #expect(diff.files[1].patch?.contains("--- /dev/null") == true)
}

@Test
func turnDiffDoesNotAttributeInterleavedWritesToTheAgent() throws {
    let changes = AgentTurnFileChanges()
    record(changes, "/checkout/shared.txt", "baseline\n", "first edit\n")
    record(changes, "/checkout/shared.txt", "first edit\nuser change\n", "first edit\nuser change\nsecond edit\n")
    record(changes, "/checkout/clean.txt", "before", "after")
    let diff = try #require(changes.finish())
    let shared = try #require(diff.files.first(where: { $0.path.hasSuffix("shared.txt") }))
    let clean = try #require(diff.files.first(where: { $0.path.hasSuffix("clean.txt") }))
    #expect(shared.attribution == .interleaved)
    #expect(shared.patch == nil)
    #expect(clean.attribution == .verified)
    #expect(clean.patch?.contains("+after\n\\ No newline at end of file") == true)
}

@Test
func tuiTurnDiffSummaryExpandsTheSavedPatch() {
    let diff = AgentTurnDiff(files: [
        .init(path: "/checkout/A.swift", attribution: .verified, patch: "+let value = 1", additions: 1),
        .init(path: "/checkout/B.swift", attribution: .interleaved)
    ], truncated: false)
    let compact = SloppyTUITurnDiffDisplay.lines(diff, expanded: false, width: 100)
    let expanded = SloppyTUITurnDiffDisplay.lines(diff, expanded: true, width: 100)
    #expect(compact.contains { $0.contains("Changes this turn") })
    #expect(!compact.contains { $0.contains("let value") })
    #expect(expanded.contains { $0.contains("let value") })
    #expect(expanded.contains { $0.contains("changed outside this turn") })
}

private func record(_ changes: AgentTurnFileChanges, _ path: String, _ before: String?, _ after: String) {
    let old = before.map { Data($0.utf8) }
    let new = Data(after.utf8)
    changes.record(path: path, before: old, beforeHash: old.map(TaskSyncCrypto.sha256Hex),
        after: new, afterHash: TaskSyncCrypto.sha256Hex(new))
}
