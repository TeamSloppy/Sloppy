import Foundation
import Testing
@testable import sloppy
import Protocols

@Test
func sqliteWorkflowPersistenceRoundTripsRunStepsAndPendingActions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let dbPath = root.appendingPathComponent("sloppy.sqlite").path
    let schemaPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/sloppy/Storage/schema.sql")
    let schema = try String(contentsOf: schemaPath, encoding: .utf8)
    let store = SQLiteStore(path: dbPath, schemaSQL: schema)
    let startedAt = Date(timeIntervalSince1970: 1_778_100_000)
    let finishedAt = Date(timeIntervalSince1970: 1_778_100_120)
    let run = WorkflowRun(
        id: "run-1",
        workflowId: "workflow-1",
        workflowVersion: 3,
        projectId: "project-1",
        taskId: "task-1",
        status: .waitingForHuman,
        currentNodeIds: ["approval"],
        startedBy: "human:admin",
        startedAt: startedAt
    )
    let step = WorkflowRunStep(
        id: "step-1",
        runId: "run-1",
        nodeId: "approval",
        status: .waiting,
        input: ["taskId": .string("task-1")],
        output: ["status": .string("waiting")],
        startedAt: startedAt,
        finishedAt: nil
    )
    let action = WorkflowPendingAction(
        id: "action-1",
        projectId: "project-1",
        workflowRunId: "run-1",
        nodeId: "approval",
        taskId: "task-1",
        assignee: "human:admin",
        prompt: "Approve?",
        decisions: [.approved, .rejected],
        createdAt: startedAt
    )

    await store.saveWorkflowRun(run)
    await store.saveWorkflowRunStep(step)
    await store.saveWorkflowPendingAction(action)

    #expect(await store.listWorkflowRuns(projectId: "project-1") == [run])
    #expect(await store.getWorkflowRun(id: "run-1") == run)
    #expect(await store.listWorkflowRunSteps(runId: "run-1") == [step])
    #expect(await store.listWorkflowPendingActions(projectId: "project-1", includeResolved: false) == [action])
    #expect(await store.listWorkflowPendingActions(runId: "run-1") == [action])

    let resolved = await store.resolveWorkflowPendingAction(actionId: "action-1", resolvedAt: finishedAt)
    #expect(resolved?.resolvedAt == finishedAt)
    #expect(await store.listWorkflowPendingActions(projectId: "project-1", includeResolved: false) == [])
    #expect(await store.listWorkflowPendingActions(projectId: "project-1", includeResolved: true).first?.resolvedAt == finishedAt)
}
