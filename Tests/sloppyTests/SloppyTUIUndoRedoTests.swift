import Foundation
import Testing
@testable import sloppy

@Test
func tuiUndoRedoRestoresModifiedFile() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("note.txt")
    try Data("before".utf8).write(to: fileURL)

    var manager = SloppyTUIUndoManager()
    let baseline = manager.makeBaseline(rootURL: root)
    try Data("after".utf8).write(to: fileURL)

    #expect(manager.recordChanges(rootURL: root, baseline: baseline) == .recorded(paths: ["note.txt"]))
    #expect(try manager.undo(rootURL: root).paths == ["note.txt"])
    #expect(try String(contentsOf: fileURL, encoding: .utf8) == "before")
    #expect(try manager.redo(rootURL: root).paths == ["note.txt"])
    #expect(try String(contentsOf: fileURL, encoding: .utf8) == "after")
}

@Test
func tuiUndoRedoRestoresCreatedFile() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("created.bin")

    var manager = SloppyTUIUndoManager()
    let baseline = manager.makeBaseline(rootURL: root)
    try Data([0, 1, 2, 3]).write(to: fileURL)

    #expect(manager.recordChanges(rootURL: root, baseline: baseline) == .recorded(paths: ["created.bin"]))
    _ = try manager.undo(rootURL: root)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    _ = try manager.redo(rootURL: root)
    #expect(try Data(contentsOf: fileURL) == Data([0, 1, 2, 3]))
}

@Test
func tuiUndoRedoRestoresDeletedFile() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("deleted.txt")
    try Data("keep me".utf8).write(to: fileURL)

    var manager = SloppyTUIUndoManager()
    let baseline = manager.makeBaseline(rootURL: root)
    try FileManager.default.removeItem(at: fileURL)

    #expect(manager.recordChanges(rootURL: root, baseline: baseline) == .recorded(paths: ["deleted.txt"]))
    _ = try manager.undo(rootURL: root)
    #expect(try String(contentsOf: fileURL, encoding: .utf8) == "keep me")
    _ = try manager.redo(rootURL: root)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
}

@Test
func tuiUndoRedoClearsRedoAfterNewRecordedTurn() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("note.txt")
    try Data("one".utf8).write(to: fileURL)

    var manager = SloppyTUIUndoManager()
    var baseline = manager.makeBaseline(rootURL: root)
    try Data("two".utf8).write(to: fileURL)
    _ = manager.recordChanges(rootURL: root, baseline: baseline)
    _ = try manager.undo(rootURL: root)
    #expect(manager.canRedo)

    baseline = manager.makeBaseline(rootURL: root)
    try Data("three".utf8).write(to: fileURL)
    _ = manager.recordChanges(rootURL: root, baseline: baseline)

    #expect(!manager.canRedo)
}

@Test
func tuiUndoRedoRefusesWhenCurrentFileConflicts() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("note.txt")
    try Data("before".utf8).write(to: fileURL)

    var manager = SloppyTUIUndoManager()
    let baseline = manager.makeBaseline(rootURL: root)
    try Data("after".utf8).write(to: fileURL)
    _ = manager.recordChanges(rootURL: root, baseline: baseline)
    try Data("manual".utf8).write(to: fileURL)

    #expect(throws: SloppyTUIUndoManager.Error.conflict(path: "note.txt")) {
        _ = try manager.undo(rootURL: root)
    }
    #expect(try String(contentsOf: fileURL, encoding: .utf8) == "manual")
}

@Test
func tuiUndoRedoSkipsOversizedChangedFile() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("large.bin")
    try Data("small".utf8).write(to: fileURL)

    var manager = SloppyTUIUndoManager()
    let baseline = manager.makeBaseline(rootURL: root)
    try Data(repeating: 7, count: SloppyTUIUndoManager.maxFileBytes + 1).write(to: fileURL)

    let result = manager.recordChanges(rootURL: root, baseline: baseline)
    guard case .skipped(let message) = result else {
        Issue.record("Expected oversized change to be skipped, got \(result)")
        return
    }
    #expect(message.contains("large.bin"))
    #expect(!manager.canUndo)
}

@Test
func tuiUndoRedoHistoryIsScopedBySession() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let firstURL = root.appendingPathComponent("first.txt")
    let secondURL = root.appendingPathComponent("second.txt")
    try Data("one-before".utf8).write(to: firstURL)
    try Data("two-before".utf8).write(to: secondURL)

    var managers = SloppyTUISessionUndoManagers()
    let firstBaseline = managers.makeBaseline(sessionID: "session-one", rootURL: root)
    try Data("one-after".utf8).write(to: firstURL)
    _ = managers.recordChanges(firstBaseline)

    let secondBaseline = managers.makeBaseline(sessionID: "session-two", rootURL: root)
    try Data("two-after".utf8).write(to: secondURL)
    _ = managers.recordChanges(secondBaseline)

    #expect(managers.canUndo(sessionID: "session-one"))
    #expect(managers.canUndo(sessionID: "session-two"))

    _ = try managers.undo(sessionID: "session-two", rootURL: root)
    #expect(try String(contentsOf: secondURL, encoding: .utf8) == "two-before")
    #expect(try String(contentsOf: firstURL, encoding: .utf8) == "one-after")

    _ = try managers.undo(sessionID: "session-one", rootURL: root)
    #expect(try String(contentsOf: firstURL, encoding: .utf8) == "one-before")
}

@Test
func tuiSessionDiffIncludesOnlyRecordedSessionPaths() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let sessionURL = root.appendingPathComponent("session.txt")
    let unrelatedURL = root.appendingPathComponent("unrelated.txt")
    try Data("before\n".utf8).write(to: sessionURL)
    try Data("clean\n".utf8).write(to: unrelatedURL)

    var manager = SloppyTUIUndoManager()
    let baseline = manager.makeBaseline(rootURL: root)
    try Data("after\n".utf8).write(to: sessionURL)

    #expect(manager.recordChanges(rootURL: root, baseline: baseline) == .recorded(paths: ["session.txt"]))
    try Data("dirty\n".utf8).write(to: unrelatedURL)

    let diff = try manager.sessionDiff(rootURL: root)
    #expect(diff.paths == ["session.txt"])
    #expect(diff.linesAdded == 1)
    #expect(diff.linesDeleted == 1)
    #expect(diff.diff.contains("diff --git a/session.txt b/session.txt"))
    #expect(diff.diff.contains("-before"))
    #expect(diff.diff.contains("+after"))
    #expect(!diff.diff.contains("unrelated.txt"))
    #expect(!diff.truncated)
}

@Test
func tuiSessionDiffComparesEarliestRecordedStateToCurrentFile() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("note.txt")
    try Data("one\n".utf8).write(to: fileURL)

    var manager = SloppyTUIUndoManager()
    var baseline = manager.makeBaseline(rootURL: root)
    try Data("two\n".utf8).write(to: fileURL)
    _ = manager.recordChanges(rootURL: root, baseline: baseline)

    baseline = manager.makeBaseline(rootURL: root)
    try Data("three\n".utf8).write(to: fileURL)
    _ = manager.recordChanges(rootURL: root, baseline: baseline)

    let diff = try manager.sessionDiff(rootURL: root)
    #expect(diff.paths == ["note.txt"])
    #expect(diff.diff.contains("-one"))
    #expect(diff.diff.contains("+three"))
    #expect(!diff.diff.contains("-two"))
}

@Test
func tuiUndoSnapshotHonorsGitIgnoresAndKeepsTrackedAndUntrackedFiles() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try undoGit(root, ["init", "-q"])
    try Data("cache/\n".utf8).write(to: root.appendingPathComponent(".gitignore"))
    let cache = root.appendingPathComponent("cache", isDirectory: true)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let tracked = cache.appendingPathComponent("tracked.txt")
    let ignored = cache.appendingPathComponent("generated.txt")
    let unusualName = "new file\n日本語.txt"
    let untracked = root.appendingPathComponent(unusualName)
    for url in [tracked, ignored, untracked] { try Data("before".utf8).write(to: url) }
    try undoGit(root, ["add", "-f", "cache/tracked.txt"])

    var manager = SloppyTUIUndoManager()
    let baseline = manager.makeBaseline(rootURL: root)
    for url in [tracked, ignored, untracked] { try Data("after".utf8).write(to: url) }
    #expect(manager.recordChanges(rootURL: root, baseline: baseline) == .recorded(paths: ["cache/tracked.txt", unusualName]))
    _ = try manager.undo(rootURL: root)
    #expect(try String(contentsOf: tracked, encoding: .utf8) == "before")
    #expect(try String(contentsOf: untracked, encoding: .utf8) == "before")
    #expect(try String(contentsOf: ignored, encoding: .utf8) == "after")
    _ = try manager.redo(rootURL: root)
    #expect(try String(contentsOf: tracked, encoding: .utf8) == "after")
}

@Test
func tuiUndoSnapshotIncludesNestedRepositoriesWithTheirIgnoreRules() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let nested = root.appendingPathComponent("nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try undoGit(root, ["init", "-q"])
    try undoGit(nested, ["init", "-q"])
    try Data("generated.txt\n".utf8).write(to: nested.appendingPathComponent(".gitignore"))
    let source = nested.appendingPathComponent("source.txt")
    let ignored = nested.appendingPathComponent("generated.txt")
    for url in [source, ignored] { try Data("before".utf8).write(to: url) }

    var manager = SloppyTUIUndoManager()
    let baseline = manager.makeBaseline(rootURL: root)
    for url in [source, ignored] { try Data("after".utf8).write(to: url) }
    #expect(manager.recordChanges(rootURL: root, baseline: baseline) == .recorded(paths: ["nested/source.txt"]))
    _ = try manager.undo(rootURL: root)
    #expect(try String(contentsOf: source, encoding: .utf8) == "before")
}

@Test
func tuiUndoSnapshotSkipsUninitializedSubmoduleRoot() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try undoGit(root, ["init", "-q"])
    try undoGit(root, ["update-index", "--add", "--cacheinfo", "160000," + String(repeating: "1", count: 40) + ",nested"])
    try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
    var manager = SloppyTUIUndoManager()
    let baseline = manager.makeBaseline(rootURL: root)
    #expect(manager.recordChanges(rootURL: root, baseline: baseline) == .noChanges)
}

@Test
func tuiUndoSnapshotDoesNotFollowSymbolicLinksOutsideWorkspace() throws {
    let root = try makeUndoRedoRoot()
    let external = try makeUndoRedoRoot()
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: external)
    }
    let file = external.appendingPathComponent("source.txt")
    try Data("before".utf8).write(to: file)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked-file"), withDestinationURL: file)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked-directory"), withDestinationURL: external)
    var manager = SloppyTUIUndoManager()
    let baseline = manager.makeBaseline(rootURL: root)
    try Data("after".utf8).write(to: file)
    #expect(manager.recordChanges(rootURL: root, baseline: baseline) == .noChanges)
}

private func undoGit(_ root: URL, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", root.path] + arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

private func makeUndoRedoRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-tui-undo-redo-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test
func tuiUndoTurnsRevertsFromEarliestMatchingTurnOnly() throws {
    let root = try makeUndoRedoRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("note.txt")
    try Data("zero".utf8).write(to: fileURL)

    var manager = SloppyTUIUndoManager()
    for (index, text) in ["one", "two", "three"].enumerated() {
        let baseline = manager.makeBaseline(rootURL: root)
        try Data(text.utf8).write(to: fileURL)
        _ = manager.recordChanges(rootURL: root, baseline: baseline, turnKey: "turn-\(index + 1)")
    }

    let result = try manager.undoTurns(withKeys: ["turn-2", "turn-3"], rootURL: root)

    #expect(result.paths == ["note.txt"])
    #expect(try String(contentsOf: fileURL, encoding: .utf8) == "one")
    #expect(manager.canUndo)
    #expect(throws: SloppyTUIUndoManager.Error.nothingToUndo) {
        try manager.undoTurns(withKeys: ["turn-9"], rootURL: root)
    }
}

@Test
func liveSessionDiffDoesNotRecordUndoOrLeakAcrossSessions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("File.swift")
    try "old\n".write(to: file, atomically: true, encoding: .utf8)
    var managers = SloppyTUISessionUndoManagers()
    let baseline = managers.makeBaseline(sessionID: "one", rootURL: root)
    try "new\n".write(to: file, atomically: true, encoding: .utf8)
    let first = try managers.sessionDiff(sessionID: "one", rootURL: root, pendingBaseline: baseline)
    #expect(first.diff.contains("+new"))
    #expect(!managers.canUndo(sessionID: "one"))
    #expect(try managers.sessionDiff(sessionID: "two", rootURL: root, pendingBaseline: baseline).hasChanges == false)
    _ = managers.recordChanges(baseline)
    #expect(try managers.sessionDiff(sessionID: "one", rootURL: root) == first)
    #expect(managers.canUndo(sessionID: "one"))
}
