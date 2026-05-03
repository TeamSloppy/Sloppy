import Foundation
import Testing
import Protocols
@testable import sloppy

@Test
func projectChangeWatcherEmitsCreatedModifiedDeletedAndIgnoresExcludedDirs() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-change-watch-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let watcher = ProjectChangeWatcherService(
        configuration: ProjectChangeWatcherConfiguration(
            pollIntervalNanoseconds: 10_000_000,
            debounceNanoseconds: 10_000_000
        )
    )
    let firstURL = root.appendingPathComponent("first.txt")
    try "one".write(to: firstURL, atomically: true, encoding: .utf8)
    let modifiedURL = root.appendingPathComponent("modified.txt")
    try "before".write(to: modifiedURL, atomically: true, encoding: .utf8)
    let initial = watcher.snapshot(rootURL: root)

    try "after".write(to: modifiedURL, atomically: true, encoding: .utf8)
    let secondURL = root.appendingPathComponent("second.txt")
    try "new".write(to: secondURL, atomically: true, encoding: .utf8)
    try FileManager.default.removeItem(at: firstURL)

    let gitURL = root.appendingPathComponent(".git", isDirectory: true)
    try FileManager.default.createDirectory(at: gitURL, withIntermediateDirectories: true)
    try "ignored".write(to: gitURL.appendingPathComponent("index"), atomically: true, encoding: .utf8)
    let dotEnvURL = root.appendingPathComponent(".env")
    try "visible metadata".write(to: dotEnvURL, atomically: true, encoding: .utf8)

    let current = watcher.snapshot(rootURL: root)
    let batch = try #require(watcher.changes(projectID: "demo", rootURL: root, previous: initial, current: current))

    #expect(batch.projectId == "demo")
    #expect(batch.changes.contains { $0.path == "first.txt" && $0.kind == .deleted })
    #expect(batch.changes.contains { $0.path == "modified.txt" && $0.kind == .modified })
    #expect(batch.changes.contains { $0.path == "second.txt" && $0.kind == .created })
    #expect(batch.changes.contains { $0.path == ".env" && $0.kind == .created })
    #expect(!batch.changes.contains { $0.path.hasPrefix(".git/") })
}

@Test
func cwdProjectResolverReusesRepoPathAndHashesIdConflict() async throws {
    let repoRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("same-name-\(UUID().uuidString)", isDirectory: true)
    let otherRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("outer-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent(repoRoot.lastPathComponent, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: repoRoot)
        try? FileManager.default.removeItem(at: otherRoot.deletingLastPathComponent())
    }
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)

    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let first = try await service.resolveOrCreateProjectForCurrentDirectory(repoRoot.path)
    let reused = try await service.resolveOrCreateProjectForCurrentDirectory(repoRoot.path)
    let second = try await service.resolveOrCreateProjectForCurrentDirectory(otherRoot.path)

    #expect(reused.id == first.id)
    #expect(first.repoPath == repoRoot.standardizedFileURL.path)
    #expect(second.id.hasPrefix(first.id + "-"))
    #expect(second.repoPath == otherRoot.standardizedFileURL.path)
}
