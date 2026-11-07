import Foundation
import Testing
import SloppyClientCore
@testable import SloppyFeatureProjects

@Suite("Project workflows")
struct ProjectWorkflowTests {
    @Test @MainActor func opensTheLinkedDefinitionAndKeepsItAcrossRefresh() async throws {
        let (model, session) = try makeModel(initialWorkflowID: "other")
        defer { session.invalidateAndCancel() }
        await model.load(projectId: "project")
        #expect(model.selectedWorkflow?.id == "other")
        #expect(model.selectedRunID == nil)
        await model.load(projectId: "project")
        #expect(model.selectedWorkflow?.id == "other")
    }

    @Test @MainActor func missingLinkedWorkflowDoesNotShowAnotherGraph() async throws {
        let (model, session) = try makeModel(initialWorkflowID: "missing")
        defer { session.invalidateAndCancel() }
        await model.load(projectId: "project")
        #expect(model.selectedWorkflow == nil)
        #expect(model.errorMessage != nil)
    }

    @Test @MainActor func loadsProjectGraphRunsAndRecordedStepData() async throws {
        let (model, session) = try makeModel()
        defer { session.invalidateAndCancel() }
        await model.load(projectId: "project")
        #expect(model.errorMessage == nil)
        #expect(model.workflows.map(\.id) == ["flow", "other"])
        #expect(model.runs.map(\.id) == ["slow", "fast", "historical"])
        #expect(model.selectedWorkflowID == "flow")
        #expect(model.selectedRunID == "slow")
        let workflow = try #require(model.selectedWorkflow)
        #expect(workflow.nodes.count == 4)
        #expect(workflow.nodes[1].config["prompt"] == .string("Implement the task"))
        #expect(workflow.edges[1].label == "result.approved = true")

        model.selectRun("fast")
        await model.loadSelectedRun(projectId: "project")
        let detail = try #require(model.detail)
        #expect(detail.run.taskId == "TASK-2")
        #expect(detail.steps.first?.input["nested"] == .object(["items": .array([.number(2), .null])]))
        #expect(detail.steps.first?.output["answer"] == .string("Ready"))
        #expect(detail.steps.first?.error == "Tool unavailable")
        #expect(detail.pendingActions.first?.prompt == "Review the result")
        #expect(model.canOverlayRun)

        model.selectRun("historical")
        await model.loadSelectedRun(projectId: "project")
        #expect(!model.canOverlayRun)
        #expect(model.detail?.run.status == "future_paused")
    }

    @Test @MainActor func keepsSelectionAndDefinitionOnlyAcrossRefresh() async throws {
        let (model, session) = try makeModel()
        defer { session.invalidateAndCancel() }
        await model.load(projectId: "project")
        model.selectRun("fast")
        await model.load(projectId: "project")
        #expect(model.selectedRunID == "fast")
        model.selectRun(nil)
        await model.load(projectId: "project")
        #expect(model.selectedRunID == nil)
        #expect(model.detail == nil)
        model.selectWorkflow("other")
        #expect(model.workflowRuns.isEmpty)
        #expect(model.selectedRunID == nil)
        model.selectRun("fast")
        #expect(model.selectedRunID == nil)
        model.selectWorkflow("flow")
        #expect(model.selectedRunID == "slow")
    }

    @Test @MainActor func lateDetailCannotReplaceNewSelectionOrDefinitionOnly() async throws {
        let (model, session) = try makeModel()
        defer { session.invalidateAndCancel() }
        await model.load(projectId: "project")
        let slow = Task { await model.loadSelectedRun(projectId: "project") }
        for _ in 0..<100 where !model.isLoadingDetail { await Task.yield() }
        model.selectRun("fast")
        await model.loadSelectedRun(projectId: "project")
        await slow.value
        #expect(model.detail?.run.id == "fast")
        #expect(!model.isLoadingDetail)

        model.selectRun("slow")
        let pending = Task { await model.loadSelectedRun(projectId: "project") }
        for _ in 0..<100 where !model.isLoadingDetail { await Task.yield() }
        model.selectRun(nil)
        await pending.value
        #expect(model.detail == nil)
        #expect(!model.isLoadingDetail)
    }

    @Test @MainActor func emptyErrorsCancellationAndProjectSwitchDoNotShowForeignData() async throws {
        let (model, session) = try makeModel()
        defer { session.invalidateAndCancel() }
        await model.load(projectId: "project")
        await model.load(projectId: "empty")
        #expect(model.workflows.isEmpty)
        #expect(model.runs.isEmpty)
        #expect(model.selectedWorkflowID == nil)
        #expect(model.errorMessage == nil)
        await model.load(projectId: "failure")
        #expect(model.errorMessage?.contains("HTTP 500") == true)
        #expect(!model.isLoading)
        let slow = Task { await model.load(projectId: "slow-project") }
        for _ in 0..<100 where !model.isLoading { await Task.yield() }
        await model.load(projectId: "project")
        await slow.value
        #expect(model.workflows.allSatisfy { $0.projectId == "project" })
        #expect(model.errorMessage == nil)

        let cancelled = Task { await model.load(projectId: "slow-project") }
        for _ in 0..<100 where !model.isLoading { await Task.yield() }
        cancelled.cancel()
        await cancelled.value
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)
    }

    @Test @MainActor func failedRefreshRetainsSnapshotAndDetailMismatchIsRejected() async throws {
        let (model, session) = try makeModel()
        defer { session.invalidateAndCancel() }
        await model.load(projectId: "flaky")
        model.selectRun("fast")
        await model.loadSelectedRun(projectId: "flaky")
        #expect(model.detail != nil)
        let previous = model.workflows
        // The second list request for this URL is intentionally rejected by the fixture.
        await model.load(projectId: "flaky")
        #expect(model.workflows == previous)
        #expect(model.detail != nil)
        #expect(model.errorMessage != nil)

        await model.loadSelectedRun(projectId: "wrong-project")
        #expect(model.detailErrorMessage != nil)
        #expect(model.detail?.run.projectId == "flaky")
    }

    @Test @MainActor func layoutPreservesBranchesJoinsAndTerminatesOnCycles() async throws {
        let (model, session) = try makeModel()
        defer { session.invalidateAndCancel() }
        await model.load(projectId: "project")
        let graph = ProjectWorkflowGraphLayout(workflow: try #require(model.selectedWorkflow))
        let start = try #require(graph.positions["start"])
        let work = try #require(graph.positions["work"])
        let review = try #require(graph.positions["review"])
        let end = try #require(graph.positions["end"])
        #expect(start.x < work.x)
        #expect(work.x == review.x)
        #expect(work.y != review.y)
        #expect(end.x > review.x)
        await model.load(projectId: "cycle")
        let cyclic = ProjectWorkflowGraphLayout(workflow: try #require(model.selectedWorkflow))
        #expect(cyclic.positions.count == 4)
        #expect(Set(cyclic.positions.values.map { "\($0.x),\($0.y)" }).count == 4)
        #expect(cyclic.size.width.isFinite)
    }

    @MainActor
    private func makeModel(initialWorkflowID: String? = nil) throws -> (ProjectWorkflowViewModel, URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkflowFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SloppyAPIClient(baseURL: try #require(URL(string: "https://workflow.test")), session: session,
                                     authSessionStore: AuthSessionStore(persistence: .memory))
        return (ProjectWorkflowViewModel(apiClient: client, initialWorkflowID: initialWorkflowID), session)
    }
}

final class WorkflowFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var flakyRequests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let parts = url.pathComponents
        let project = parts.count > 3 ? parts[3] : "project"
        let isDetail = parts.count > 5
        let runID = isDetail ? url.lastPathComponent : ""
        let delay = runID == "slow" || project == "slow-project" ? 0.18 : 0.01
        var status = project == "failure" ? 500 : 200
        if project == "flaky", url.lastPathComponent == "workflows" {
            Self.lock.lock()
            Self.flakyRequests += 1
            if Self.flakyRequests > 1 { status = 500 }
            Self.lock.unlock()
        }
        let responseStatus = status
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            do {
                let object: Any
                if isDetail {
                    object = ["run": Self.run(runID, project: project == "wrong-project" ? "foreign" : project),
                              "steps": [["id": "step", "runId": runID, "nodeId": "work", "status": "failed",
                                         "input": ["nested": ["items": [2, NSNull()]]], "output": ["answer": "Ready"],
                                         "error": "Tool unavailable", "startedAt": "2026-10-31T10:00:01.123Z"]],
                              "pendingActions": [["id": "action", "nodeId": "review", "assignee": "owner", "prompt": "Review the result"]]]
                } else if project == "empty" {
                    object = []
                } else if url.lastPathComponent == "workflows" {
                    object = [Self.workflow(project: project), Self.workflow(project: project, id: "other"), Self.workflow(project: "foreign")]
                } else {
                    object = [Self.run("historical", project: project), Self.run("fast", project: project),
                              Self.run("slow", project: project), Self.run("foreign", project: "foreign")]
                }
                let data = try JSONSerialization.data(withJSONObject: object)
                guard let response = HTTPURLResponse(url: url, statusCode: responseStatus, httpVersion: nil, headerFields: nil) else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() {}

    static func workflow(project: String, id: String = "flow") -> [String: Any] {
        var edges: [[String: Any]] = [
            ["id": "a", "sourceNodeId": "start", "targetNodeId": "work"],
            ["id": "b", "sourceNodeId": "start", "targetNodeId": "review", "condition": ["path": "result.approved", "equals": true]],
            ["id": "c", "sourceNodeId": "work", "targetNodeId": "end"],
            ["id": "d", "sourceNodeId": "review", "targetNodeId": "end"]
        ]
        if project == "cycle" { edges.append(["id": "loop", "sourceNodeId": "end", "targetNodeId": "start"]) }
        let titles = ["start": "Start", "work": "Implement the task", "review": "Review changes", "end": "Complete"]
        let nodes: [[String: Any]] = ["start", "work", "review", "end"].map { node in
            let type = node == "work" ? "agent_step" : node == "end" ? "end" : "trigger"
            let config: [String: String] = node == "work" ? ["prompt": "Implement the task"] : [:]
            return ["id": node, "title": titles[node] ?? node, "type": type, "laneId": "agent", "config": config]
        }
        return ["id": id, "projectId": project, "name": id == "flow" ? "Build and review" : "Other workflow", "version": 2, "enabled": true,
                "lanes": [["id": "agent", "title": "Developer", "kind": "agent", "actorId": "coder"]],
                "nodes": nodes, "edges": edges]
    }

    static func run(_ id: String, project: String) -> [String: Any] {
        ["id": id, "projectId": project, "workflowId": "flow", "workflowVersion": id == "historical" ? 1 : 2,
         "taskId": id == "fast" ? "TASK-2" : "TASK-1", "status": id == "historical" ? "future_paused" : "running",
         "currentNodeIds": ["work"], "startedAt": id == "slow" ? "2026-10-31T12:00:00Z" : id == "fast" ? "2026-10-31T11:00:00Z" : "2026-10-31T10:00:00Z"]
    }
}
