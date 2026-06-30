import Foundation
import Testing
@testable import sloppy
@testable import Protocols

@Test
func writesInitiativeArtifactsInsideProjectMeta() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let projectRoot = root.appendingPathComponent("projects/demo", isDirectory: true)
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

    let store = ProjectMetaStore(workspaceRootURL: root)
    try store.ensureProjectMetaLayout(projectID: "demo")

    let url = try store.writeInitiativeArtifact(
        projectID: "demo",
        initiativeID: "init-ci",
        relativePath: "baseline/report.md",
        content: Data("hello".utf8)
    )

    #expect(url.path.contains("/projects/demo/.meta/artifacts/init-ci/"))
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test
func writesDecisionPacketMarkdownInsideProjectMeta() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ProjectMetaStore(workspaceRootURL: root)
    let packet = DecisionPacketRecord(
        id: "packet-1",
        projectID: "demo",
        initiativeID: "init-ci",
        summary: "Need faster runners",
        rationale: "Current queueing dominates CI time.",
        tradeoffs: ["Higher monthly spend"],
        requestedAction: "Approve larger runner pool",
        resumePoint: "rerun benchmark suite",
        status: "open"
    )

    let fileURL = try store.writeDecisionPacketMarkdown(projectID: "demo", packet: packet)
    let markdown = try String(contentsOf: fileURL, encoding: .utf8)

    #expect(fileURL.path.contains("/projects/demo/.meta/decisions/packet-1.md"))
    #expect(markdown.contains("Approve larger runner pool"))
    #expect(markdown.contains("rerun benchmark suite"))
}

@Test
func listsInitiativeArtifactsRelativeToInitiativeDirectory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ProjectMetaStore(workspaceRootURL: root)
    _ = try store.writeInitiativeArtifact(
        projectID: "demo",
        initiativeID: "init-ci",
        relativePath: "baseline/report.md",
        content: Data("hello".utf8)
    )
    _ = try store.writeInitiativeArtifact(
        projectID: "demo",
        initiativeID: "init-ci",
        relativePath: "verification/result.json",
        content: Data("{}".utf8)
    )

    let listed = store.listInitiativeArtifacts(projectID: "demo", initiativeID: "init-ci")
    #expect(listed == ["baseline/report.md", "verification/result.json"])
}

@Test
func savesAndListsInitiativeActivities() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ProjectMetaStore(workspaceRootURL: root)
    let activity = InitiativeActivityRecord(
        id: "activity-1",
        initiativeID: "init-ci",
        kind: "created",
        title: "Initiative created",
        message: "Reduce CI duration"
    )
    try store.saveInitiativeActivities([activity], projectID: "demo", initiativeID: "init-ci")

    let listed = store.listInitiativeActivities(projectID: "demo", initiativeID: "init-ci")
    #expect(listed.count == 1)
    #expect(listed.first?.title == "Initiative created")
}
