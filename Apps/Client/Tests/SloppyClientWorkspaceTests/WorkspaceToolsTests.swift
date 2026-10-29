import Foundation
import Testing
@testable import SloppyClient
import SloppyClientCore

@Suite("Workspace tools", .serialized)
@MainActor
struct WorkspaceToolsTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_WORKSPACE_INTEGRATION"] == "1"))
    func canvasPersistsEditsAndRevisions() async throws {
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "http://127.0.0.1:25102")))
        let workspace = try await api.workspace.createWorkspace(title: "Canvas integration", projectID: "adaengine")
        let model = WorkspaceCanvasModel(service: api.workspace)
        await model.open(workspace)
        #expect(model.document?.revision == 0)
        await model.add(.sticky)
        #expect(model.document?.revision == 1)
        let id = try #require(model.selection)
        model.text = "**Saved by the client**"
        await model.saveSelection()
        #expect(model.error == nil)
        #expect(model.selected?.title == "**Saved by the client**")
        #expect(model.selected?.revision == 2)
        let x = try #require(model.selected?.bounds.x)
        model.zoom = 0.5
        await model.move(id, dx: 20, dy: 10)
        #expect(model.selected?.bounds.x == x + 40)
        let revision = try #require(model.document?.revision)
        // A stale transaction must fail and reload authoritative state rather than overwrite it.
        _ = try await api.workspace.commitCanvas(workspaceID: workspace.id, request: .init(id: UUID().uuidString,
            baseRevision: revision, operations: [.init(kind: .deleteElement, targetId: id)]))
        await model.saveSelection()
        #expect(model.error != nil)
        #expect(model.document?.elements.isEmpty == true)
        #expect(model.document?.revision == revision + 1)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_WORKSPACE_INTEGRATION"] == "1"))
    func automationCreatesRealRunAndRetainsHistory() async throws {
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "http://127.0.0.1:25102")))
        let definition = try await api.workspace.createAutomation(projectID: "adaengine", request: .init(name: "Integration workflow",
            workflowId: "preview", repositoryFullName: "sample/adaengine", trigger: .init(type: .manual)))
        let model = WorkspaceSurfaceModel(api: api)
        await model.runAutomation(definition)
        #expect(model.errors.isEmpty)
        #expect(model.automationRuns.first?.automationId == definition.id)
        #expect(model.automationRuns.first?.status == .completed)
        let history = try await api.workspace.automationRuns(projectID: "adaengine")
        #expect(history.contains { $0.id == model.selectedAutomationRunID })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_TERMINAL_INTEGRATION"] == "1"))
    func localTerminalExecutesAndStopsShell() async throws {
        let session = WorkspaceTerminalSession()
        defer { session.stop() }
        session.start(in: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        #expect(session.error == nil)
        #expect(session.isRunning)
        #if os(Windows)
        session.send("echo SLOPPY_TERMINAL_OK\r")
        #else
        session.send("printf 'SLOPPY_TERMINAL_OK\\n'\r")
        #endif
        var output = ""
        for _ in 0..<100 {
            output = session.terminal.makeRenderSnapshot(scope: .full).lines.map { $0.cells.map(\.text).joined() }.joined(separator: "\n")
            if output.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "SLOPPY_TERMINAL_OK" }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(output.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "SLOPPY_TERMINAL_OK" })
        session.stop()
        #expect(!session.isRunning)
        session.stop()
    }
}
