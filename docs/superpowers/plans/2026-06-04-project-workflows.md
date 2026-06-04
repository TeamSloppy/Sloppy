# Project Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first project-scoped visual workflows MVP: persisted workflow definitions, manual runs, deterministic execution for simple nodes, Dashboard pending human actions, a minimal project Workflows tab, and a follow-up path for a built-in workflow skill that lets agents intentionally create visual workflow plans.

**Architecture:** Add shared workflow DTOs in `Protocols`, a file-backed definition store under `workspace/workflows/<projectId>/`, SQLite-backed run/action history, CoreService workflow APIs, a `ProjectWorkflowsAPIRouter`, and Dashboard project UI. The MVP runner executes a deterministic single-path graph and pauses for Dashboard human actions.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftNIO router conventions, SQLite via existing `CSQLite3` store, React 19 + Vite Dashboard, TypeScript/JS API client.

---

## Scope

This plan implements the MVP vertical slice:

- project workflow definition CRUD
- validation helpers
- manual workflow runs
- `trigger`, `project_task`, `condition`, `human_approval`, `update_task`, and `end` nodes
- Dashboard pending human actions
- minimal project Workflows tab

This plan intentionally defers general automatic workflow creation, tool checks, automatic triggers, templates, parallel branches, and external-channel approvals. Agent-created workflows are allowed only through the built-in workflow skill described below, so regular agent turns do not silently invent workflow state.

## Built-in Workflow Skill Direction

The agent-planned workflow behavior belongs behind an explicit built-in skill, tentatively named `workflow`. When that skill is active, the agent may create a project workflow as part of doing the user's work. Outside that skill, agents should use the normal task/session flow and must not create workflow definitions or runs as a side effect.

The skill's job is to make workflow planning intentional:

- inspect the current project/task context
- propose a structured workflow graph before execution when the work benefits from visual planning
- create lanes, nodes, and edges through typed workflow APIs/tools
- bind `agent_step` nodes to real agent sessions or subagent tasks through typed runtime metadata
- update node/run state from runtime events, not model-output phrase matching
- finish by offering a Dashboard link to inspect the workflow visualization

The expected user-facing flow is:

1. User invokes or selects the built-in workflow skill for a task.
2. The agent creates a draft workflow proposal with lanes, nodes, edges, and short rationale.
3. Dashboard can render the draft graph and allow a human to run, reject, or defer it.
4. The first MVP run advances through deterministic nodes and human actions; the workflow skill phase adds typed `agent_step` links to real agent sessions or subagent tasks.
5. When the workflow is created or completed, the agent reports a link such as `/projects/<projectId>/workflows/<workflowId>` or `/projects/<projectId>/workflow-runs/<runId>`.

This is intentionally similar to Claude Code Workflows in spirit: the workflow is the visible plan for doing the work. Sloppy's difference is that the plan is first-class project state with a live graph visualization.

## File Structure

- Modify `Sources/Protocols/APIModels.swift`: workflow DTOs, enums, request/response models.
- Create `Sources/sloppy/Stores/WorkflowDefinitionFileStore.swift`: file-backed definitions by project.
- Modify `Sources/sloppy/Stores/PersistenceStore.swift`: workflow run/action persistence protocol methods and persisted records.
- Modify `Sources/sloppy/Storage/schema.sql`: workflow run, step, and action tables.
- Modify `Sources/sloppy/CorePersistenceFactory.swift`: migration/bootstrap alignment for workflow tables if schema bootstrapping is explicit there.
- Modify `Sources/sloppy/SQLiteStore.swift`: SQLite implementation of workflow persistence.
- Create `Sources/sloppy/CoreService+Workflows.swift`: workflow CRUD, validation, manual run, action resolution.
- Create `Sources/sloppy/Workflows/WorkflowRunner.swift`: deterministic graph walker for MVP nodes.
- Create `Sources/sloppy/Gateway/Routers/ProjectWorkflowsAPIRouter.swift`: HTTP routes.
- Modify `Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift`: register router.
- Create `Tests/sloppyTests/WorkflowDefinitionFileStoreTests.swift`: file store tests.
- Create `Tests/sloppyTests/WorkflowRunnerTests.swift`: runner behavior tests.
- Create `Tests/sloppyTests/ProjectWorkflowsAPIRouterTests.swift`: API tests.
- Modify `Dashboard/src/shared/api/coreApi.ts`: workflow client methods.
- Modify `Dashboard/src/api.ts`: legacy re-exports if this file mirrors `coreApi`.
- Modify `Dashboard/src/app/routing/dashboardRouteAdapter.ts`: add `workflows` project tab.
- Modify `Dashboard/src/views/Projects/utils.js`: add `workflows` tab metadata.
- Modify `Dashboard/src/views/ProjectsView.jsx`: render Workflows tab.
- Create `Dashboard/src/views/Projects/ProjectWorkflowsTab.tsx`: MVP UI.
- Create `Sources/sloppy/Tools/AgentTools/WorkflowTool.swift`: built-in workflow-skill tool for proposing, linking, and starting workflows.
- Create built-in skill metadata/instructions for `workflow`: explicit activation rules and tool usage guidance.
- Modify agent prompt/skill catalog wiring as needed so the built-in workflow skill is discoverable but not always active.
- Modify or create a Dashboard stylesheet under `Dashboard/src/styles/` following existing project styles.

---

### Task 1: Add Shared Workflow API Models

**Files:**
- Modify: `Sources/Protocols/APIModels.swift`
- Test: `Tests/ProtocolsTests/APIModelsTests.swift` or create `Tests/ProtocolsTests/WorkflowAPIModelsTests.swift`

- [ ] **Step 1: Write Codable round-trip tests**

Create `Tests/ProtocolsTests/WorkflowAPIModelsTests.swift` with:

```swift
import Foundation
import Testing
@testable import Protocols

@Test
func workflowDefinitionRoundTrips() throws {
    let now = Date(timeIntervalSince1970: 1_778_000_000)
    let definition = WorkflowDefinition(
        id: "wf_bug_fix",
        projectId: "proj",
        name: "Bug Fix",
        version: 1,
        lanes: [
            WorkflowLane(id: "system", title: "System", kind: .system),
            WorkflowLane(id: "owner", title: "Owner", kind: .human, actorId: "human:admin")
        ],
        nodes: [
            WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system", config: ["mode": .string("manual")], positionX: 100, positionY: 80),
            WorkflowNode(id: "approval", type: .humanApproval, title: "Approve", laneId: "owner", config: ["prompt": .string("Approve task?")], positionX: 360, positionY: 80)
        ],
        edges: [
            WorkflowEdge(id: "edge_start_approval", sourceNodeId: "start", targetNodeId: "approval", conditionKey: nil)
        ],
        enabled: true,
        createdAt: now,
        updatedAt: now
    )

    let data = try JSONEncoder().encode(definition)
    let decoded = try JSONDecoder().decode(WorkflowDefinition.self, from: data)

    #expect(decoded == definition)
}

@Test
func workflowRunRequestRoundTrips() throws {
    let request = WorkflowRunCreateRequest(taskId: "task-1", startedBy: "human:admin", input: ["source": .string("manual")])
    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(WorkflowRunCreateRequest.self, from: data)

    #expect(decoded == request)
}
```

- [ ] **Step 2: Run model tests and verify failure**

Run:

```bash
swift test --filter WorkflowAPIModelsTests
```

Expected: compile failure because workflow types do not exist.

- [ ] **Step 3: Add workflow DTOs**

Append the workflow models near project/task API models in `Sources/Protocols/APIModels.swift`:

```swift
public enum WorkflowNodeType: String, Codable, Sendable, CaseIterable {
    case trigger
    case projectTask = "project_task"
    case agentStep = "agent_step"
    case humanApproval = "human_approval"
    case humanInput = "human_input"
    case toolCheck = "tool_check"
    case condition
    case updateTask = "update_task"
    case notify
    case end
}

public enum WorkflowLaneKind: String, Codable, Sendable, CaseIterable {
    case system
    case human
    case agent
    case team
}

public enum WorkflowRunStatus: String, Codable, Sendable, CaseIterable {
    case queued
    case running
    case waitingForHuman = "waiting_for_human"
    case waitingForAgent = "waiting_for_agent"
    case blocked
    case failed
    case completed
    case cancelled
}

public enum WorkflowStepStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case running
    case waiting
    case succeeded
    case failed
    case skipped
}

public enum WorkflowHumanDecision: String, Codable, Sendable, CaseIterable {
    case approved
    case rejected
    case changesRequested = "changes_requested"
}

public struct WorkflowLane: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var kind: WorkflowLaneKind
    public var actorId: String?
    public var teamId: String?

    public init(id: String, title: String, kind: WorkflowLaneKind, actorId: String? = nil, teamId: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.actorId = actorId
        self.teamId = teamId
    }
}

public struct WorkflowNode: Codable, Sendable, Equatable {
    public var id: String
    public var type: WorkflowNodeType
    public var title: String
    public var laneId: String
    public var config: [String: JSONValue]
    public var positionX: Double
    public var positionY: Double

    public init(id: String, type: WorkflowNodeType, title: String, laneId: String, config: [String: JSONValue] = [:], positionX: Double = 0, positionY: Double = 0) {
        self.id = id
        self.type = type
        self.title = title
        self.laneId = laneId
        self.config = config
        self.positionX = positionX
        self.positionY = positionY
    }
}

public struct WorkflowEdge: Codable, Sendable, Equatable {
    public var id: String
    public var sourceNodeId: String
    public var targetNodeId: String
    public var conditionKey: String?

    public init(id: String, sourceNodeId: String, targetNodeId: String, conditionKey: String? = nil) {
        self.id = id
        self.sourceNodeId = sourceNodeId
        self.targetNodeId = targetNodeId
        self.conditionKey = conditionKey
    }
}

public struct WorkflowDefinition: Codable, Sendable, Equatable {
    public var id: String
    public var projectId: String
    public var name: String
    public var version: Int
    public var lanes: [WorkflowLane]
    public var nodes: [WorkflowNode]
    public var edges: [WorkflowEdge]
    public var enabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, projectId: String, name: String, version: Int = 1, lanes: [WorkflowLane] = [], nodes: [WorkflowNode] = [], edges: [WorkflowEdge] = [], enabled: Bool = true, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.version = version
        self.lanes = lanes
        self.nodes = nodes
        self.edges = edges
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WorkflowDefinitionUpsertRequest: Codable, Sendable, Equatable {
    public var name: String
    public var lanes: [WorkflowLane]
    public var nodes: [WorkflowNode]
    public var edges: [WorkflowEdge]
    public var enabled: Bool

    public init(name: String, lanes: [WorkflowLane], nodes: [WorkflowNode], edges: [WorkflowEdge], enabled: Bool = true) {
        self.name = name
        self.lanes = lanes
        self.nodes = nodes
        self.edges = edges
        self.enabled = enabled
    }
}

public struct WorkflowRunCreateRequest: Codable, Sendable, Equatable {
    public var taskId: String?
    public var startedBy: String
    public var input: [String: JSONValue]

    public init(taskId: String? = nil, startedBy: String, input: [String: JSONValue] = [:]) {
        self.taskId = taskId
        self.startedBy = startedBy
        self.input = input
    }
}

public struct WorkflowRun: Codable, Sendable, Equatable {
    public var id: String
    public var workflowId: String
    public var workflowVersion: Int
    public var projectId: String
    public var taskId: String?
    public var status: WorkflowRunStatus
    public var currentNodeIds: [String]
    public var startedBy: String
    public var startedAt: Date
    public var finishedAt: Date?
}

public struct WorkflowRunStep: Codable, Sendable, Equatable {
    public var id: String
    public var runId: String
    public var nodeId: String
    public var status: WorkflowStepStatus
    public var input: [String: JSONValue]
    public var output: [String: JSONValue]
    public var error: String?
    public var startedAt: Date
    public var finishedAt: Date?
}

public struct WorkflowPendingAction: Codable, Sendable, Equatable {
    public var id: String
    public var projectId: String
    public var workflowRunId: String
    public var nodeId: String
    public var taskId: String?
    public var assignee: String
    public var prompt: String
    public var decisions: [WorkflowHumanDecision]
    public var createdAt: Date
    public var resolvedAt: Date?
}

public struct WorkflowActionResolveRequest: Codable, Sendable, Equatable {
    public var decision: WorkflowHumanDecision
    public var comment: String?
    public var resolvedBy: String

    public init(decision: WorkflowHumanDecision, comment: String? = nil, resolvedBy: String) {
        self.decision = decision
        self.comment = comment
        self.resolvedBy = resolvedBy
    }
}

public struct WorkflowRunDetail: Codable, Sendable, Equatable {
    public var run: WorkflowRun
    public var steps: [WorkflowRunStep]
    public var pendingActions: [WorkflowPendingAction]
}

public struct WorkflowValidationIssue: Codable, Sendable, Equatable {
    public var severity: String
    public var message: String
    public var nodeId: String?
}
```

- [ ] **Step 4: Run model tests**

Run:

```bash
swift test --filter WorkflowAPIModelsTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Protocols/APIModels.swift Tests/ProtocolsTests/WorkflowAPIModelsTests.swift
git commit -m "feat: add workflow API models"
```

---

### Task 2: Add File-Backed Workflow Definition Store

**Files:**
- Create: `Sources/sloppy/Stores/WorkflowDefinitionFileStore.swift`
- Test: `Tests/sloppyTests/WorkflowDefinitionFileStoreTests.swift`

- [ ] **Step 1: Write store tests**

Create `Tests/sloppyTests/WorkflowDefinitionFileStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import sloppy
import Protocols

@Test
func workflowDefinitionStoreCreatesListsUpdatesAndDeletesDefinitions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = WorkflowDefinitionFileStore(workspaceRootURL: root)
    let request = WorkflowDefinitionUpsertRequest(
        name: "Bug Fix",
        lanes: [WorkflowLane(id: "system", title: "System", kind: .system)],
        nodes: [WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system")],
        edges: [],
        enabled: true
    )

    let created = try store.create(projectID: "proj", request: request)
    #expect(created.projectId == "proj")
    #expect(created.version == 1)
    #expect(try store.list(projectID: "proj").map(\.id) == [created.id])

    let updated = try store.update(projectID: "proj", workflowID: created.id, request: WorkflowDefinitionUpsertRequest(
        name: "Bug Fix Updated",
        lanes: request.lanes,
        nodes: request.nodes,
        edges: request.edges,
        enabled: false
    ))
    #expect(updated.version == 2)
    #expect(updated.enabled == false)

    try store.delete(projectID: "proj", workflowID: created.id)
    #expect(try store.list(projectID: "proj").isEmpty)
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
swift test --filter WorkflowDefinitionFileStoreTests
```

Expected: compile failure because `WorkflowDefinitionFileStore` does not exist.

- [ ] **Step 3: Implement store**

Create `Sources/sloppy/Stores/WorkflowDefinitionFileStore.swift` with:

```swift
import Foundation
import Protocols

final class WorkflowDefinitionFileStore {
    enum StoreError: Error {
        case invalidPayload
        case notFound
        case storageFailure
    }

    private let fileManager: FileManager
    private var workspaceRootURL: URL

    init(workspaceRootURL: URL, fileManager: FileManager = .default) {
        self.workspaceRootURL = workspaceRootURL
        self.fileManager = fileManager
    }

    func updateWorkspaceRootURL(_ url: URL) {
        workspaceRootURL = url
    }

    func list(projectID: String) throws -> [WorkflowDefinition] {
        let directory = try ensureProjectDirectory(projectID: projectID)
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map(readDefinition(at:))
    }

    func get(projectID: String, workflowID: String) throws -> WorkflowDefinition {
        let url = try definitionURL(projectID: projectID, workflowID: workflowID)
        guard fileManager.fileExists(atPath: url.path) else { throw StoreError.notFound }
        return try readDefinition(at: url)
    }

    func create(projectID: String, request: WorkflowDefinitionUpsertRequest) throws -> WorkflowDefinition {
        let now = Date()
        let workflowID = "wf_\(UUID().uuidString.lowercased())"
        let definition = WorkflowDefinition(
            id: workflowID,
            projectId: normalizedProjectID(projectID),
            name: sanitizedName(request.name),
            version: 1,
            lanes: request.lanes,
            nodes: request.nodes,
            edges: request.edges,
            enabled: request.enabled,
            createdAt: now,
            updatedAt: now
        )
        try validate(definition)
        try write(definition)
        return definition
    }

    func update(projectID: String, workflowID: String, request: WorkflowDefinitionUpsertRequest) throws -> WorkflowDefinition {
        let existing = try get(projectID: projectID, workflowID: workflowID)
        let next = WorkflowDefinition(
            id: existing.id,
            projectId: existing.projectId,
            name: sanitizedName(request.name),
            version: existing.version + 1,
            lanes: request.lanes,
            nodes: request.nodes,
            edges: request.edges,
            enabled: request.enabled,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        try validate(next)
        try write(next)
        return next
    }

    func delete(projectID: String, workflowID: String) throws {
        let url = try definitionURL(projectID: projectID, workflowID: workflowID)
        guard fileManager.fileExists(atPath: url.path) else { throw StoreError.notFound }
        try fileManager.removeItem(at: url)
    }

    func validate(_ definition: WorkflowDefinition) throws {
        guard !definition.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !definition.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !definition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw StoreError.invalidPayload
        }
        let laneIDs = Set(definition.lanes.map(\.id))
        let nodeIDs = Set(definition.nodes.map(\.id))
        guard laneIDs.count == definition.lanes.count, nodeIDs.count == definition.nodes.count else {
            throw StoreError.invalidPayload
        }
        for node in definition.nodes where !laneIDs.contains(node.laneId) {
            throw StoreError.invalidPayload
        }
        for edge in definition.edges where !nodeIDs.contains(edge.sourceNodeId) || !nodeIDs.contains(edge.targetNodeId) {
            throw StoreError.invalidPayload
        }
    }

    private func readDefinition(at url: URL) throws -> WorkflowDefinition {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.sloppyWorkflow.decode(WorkflowDefinition.self, from: data)
    }

    private func write(_ definition: WorkflowDefinition) throws {
        let url = try definitionURL(projectID: definition.projectId, workflowID: definition.id)
        let data = try JSONEncoder.sloppyWorkflow.encode(definition)
        try data.write(to: url, options: .atomic)
    }

    private func definitionURL(projectID: String, workflowID: String) throws -> URL {
        let directory = try ensureProjectDirectory(projectID: projectID)
        let id = workflowID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !id.contains("/") else { throw StoreError.invalidPayload }
        return directory.appendingPathComponent(id).appendingPathExtension("json")
    }

    private func ensureProjectDirectory(projectID: String) throws -> URL {
        let projectID = normalizedProjectID(projectID)
        guard !projectID.isEmpty, !projectID.contains("/") else { throw StoreError.invalidPayload }
        let directory = workspaceRootURL.appendingPathComponent("workflows").appendingPathComponent(projectID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func normalizedProjectID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension JSONEncoder {
    static var sloppyWorkflow: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var sloppyWorkflow: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 4: Run store tests**

Run:

```bash
swift test --filter WorkflowDefinitionFileStoreTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/sloppy/Stores/WorkflowDefinitionFileStore.swift Tests/sloppyTests/WorkflowDefinitionFileStoreTests.swift
git commit -m "feat: add workflow definition store"
```

---

### Task 3: Add Workflow Run Persistence

**Files:**
- Modify: `Sources/sloppy/Stores/PersistenceStore.swift`
- Modify: `Sources/sloppy/Storage/schema.sql`
- Modify: `Sources/sloppy/CorePersistenceFactory.swift`
- Modify: `Sources/sloppy/SQLiteStore.swift`
- Test: `Tests/sloppyTests/WorkflowPersistenceTests.swift`

- [ ] **Step 1: Write persistence tests**

Create `Tests/sloppyTests/WorkflowPersistenceTests.swift` with tests that create a test persistence store, insert a run, insert a step, insert a pending action, list them by project/run, resolve the action, and verify `resolvedAt` is non-nil.

Use the existing SQLite test factory pattern in nearby persistence tests such as `TaskActivitiesTests` or `ToolApprovalTests`.

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
swift test --filter WorkflowPersistenceTests
```

Expected: compile failure because persistence methods do not exist.

- [ ] **Step 3: Add persisted records and protocol methods**

In `Sources/sloppy/Stores/PersistenceStore.swift`, add record structs for `PersistedWorkflowRun`, `PersistedWorkflowRunStep`, and `PersistedWorkflowPendingAction` mirroring the API DTOs. Add protocol methods:

```swift
func saveWorkflowRun(_ run: WorkflowRun) async
func listWorkflowRuns(projectId: String) async -> [WorkflowRun]
func getWorkflowRun(id: String) async -> WorkflowRun?
func saveWorkflowRunStep(_ step: WorkflowRunStep) async
func listWorkflowRunSteps(runId: String) async -> [WorkflowRunStep]
func saveWorkflowPendingAction(_ action: WorkflowPendingAction) async
func listWorkflowPendingActions(projectId: String, includeResolved: Bool) async -> [WorkflowPendingAction]
func listWorkflowPendingActions(runId: String) async -> [WorkflowPendingAction]
func resolveWorkflowPendingAction(actionId: String, resolvedAt: Date) async -> WorkflowPendingAction?
```

- [ ] **Step 4: Add schema tables**

Append to `Sources/sloppy/Storage/schema.sql`:

```sql
CREATE TABLE IF NOT EXISTS workflow_runs (
    id TEXT PRIMARY KEY,
    workflow_id TEXT NOT NULL,
    workflow_version INTEGER NOT NULL,
    project_id TEXT NOT NULL,
    task_id TEXT,
    status TEXT NOT NULL,
    current_node_ids_json TEXT NOT NULL,
    started_by TEXT NOT NULL,
    started_at TEXT NOT NULL,
    finished_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_workflow_runs_project ON workflow_runs(project_id, started_at DESC);

CREATE TABLE IF NOT EXISTS workflow_run_steps (
    id TEXT PRIMARY KEY,
    run_id TEXT NOT NULL,
    node_id TEXT NOT NULL,
    status TEXT NOT NULL,
    input_json TEXT NOT NULL,
    output_json TEXT NOT NULL,
    error TEXT,
    started_at TEXT NOT NULL,
    finished_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_workflow_run_steps_run ON workflow_run_steps(run_id, started_at ASC);

CREATE TABLE IF NOT EXISTS workflow_pending_actions (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    workflow_run_id TEXT NOT NULL,
    node_id TEXT NOT NULL,
    task_id TEXT,
    assignee TEXT NOT NULL,
    prompt TEXT NOT NULL,
    decisions_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    resolved_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_workflow_pending_actions_project ON workflow_pending_actions(project_id, resolved_at, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_pending_actions_run ON workflow_pending_actions(workflow_run_id);
```

- [ ] **Step 5: Implement SQLite methods**

In `Sources/sloppy/SQLiteStore.swift`, add methods using the existing prepare/bind/step helpers. Store `currentNodeIds`, `input`, `output`, and `decisions` as JSON strings using `JSONEncoder`/`JSONDecoder`.

- [ ] **Step 6: Run persistence tests**

Run:

```bash
swift test --filter WorkflowPersistenceTests
```

Expected: tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/sloppy/Stores/PersistenceStore.swift Sources/sloppy/Storage/schema.sql Sources/sloppy/CorePersistenceFactory.swift Sources/sloppy/SQLiteStore.swift Tests/sloppyTests/WorkflowPersistenceTests.swift
git commit -m "feat: persist workflow runs"
```

---

### Task 4: Add CoreService Workflow CRUD and Runner

**Files:**
- Create: `Sources/sloppy/Workflows/WorkflowRunner.swift`
- Create: `Sources/sloppy/CoreService+Workflows.swift`
- Modify: `Sources/sloppy/CoreService.swift`
- Test: `Tests/sloppyTests/WorkflowRunnerTests.swift`

- [ ] **Step 1: Write runner tests**

Create tests for:

- start -> update task -> end completes a run
- start -> human approval pauses with pending action
- resolving approved action resumes and completes
- condition follows matching `conditionKey`

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter WorkflowRunnerTests
```

Expected: compile failure because runner/service APIs do not exist.

- [ ] **Step 3: Add `WorkflowRunner`**

Create `Sources/sloppy/Workflows/WorkflowRunner.swift`. Keep it small and deterministic:

```swift
import Foundation
import Protocols

struct WorkflowRunner {
    struct Context: Sendable {
        var projectId: String
        var taskId: String?
        var startedBy: String
        var input: [String: JSONValue]
    }

    enum Result: Sendable, Equatable {
        case completed(WorkflowRun)
        case waitingForHuman(WorkflowRun, WorkflowPendingAction)
        case failed(WorkflowRun, String)
    }

    func validate(definition: WorkflowDefinition) -> [WorkflowValidationIssue] {
        var issues: [WorkflowValidationIssue] = []
        let starts = definition.nodes.filter { $0.type == .trigger }
        if starts.count != 1 {
            issues.append(WorkflowValidationIssue(severity: "error", message: "Workflow must have exactly one trigger node.", nodeId: nil))
        }
        let nodeIDs = Set(definition.nodes.map(\.id))
        for edge in definition.edges where !nodeIDs.contains(edge.sourceNodeId) || !nodeIDs.contains(edge.targetNodeId) {
            issues.append(WorkflowValidationIssue(severity: "error", message: "Workflow contains an edge with missing source or target node.", nodeId: edge.sourceNodeId))
        }
        return issues
    }
}
```

Then extend it with execution helpers in the same file or private extensions. The runner should call injected closures for task updates and persistence so tests can use fakes.

- [ ] **Step 4: Wire store into CoreService**

Modify `Sources/sloppy/CoreService.swift` to add a `workflowDefinitionStore` property initialized with the workspace root, matching `ActorBoardFileStore` patterns. If CoreService has workspace root update logic, update the workflow store there too.

- [ ] **Step 5: Add service methods**

Create `Sources/sloppy/CoreService+Workflows.swift` with:

```swift
extension CoreService {
    public func listWorkflowDefinitions(projectID: String) async throws -> [WorkflowDefinition]
    public func getWorkflowDefinition(projectID: String, workflowID: String) async throws -> WorkflowDefinition
    public func createWorkflowDefinition(projectID: String, request: WorkflowDefinitionUpsertRequest) async throws -> WorkflowDefinition
    public func updateWorkflowDefinition(projectID: String, workflowID: String, request: WorkflowDefinitionUpsertRequest) async throws -> WorkflowDefinition
    public func deleteWorkflowDefinition(projectID: String, workflowID: String) async throws
    public func validateWorkflowDefinition(_ definition: WorkflowDefinition) -> [WorkflowValidationIssue]
    public func startWorkflowRun(projectID: String, workflowID: String, request: WorkflowRunCreateRequest) async throws -> WorkflowRunDetail
    public func listWorkflowRuns(projectID: String) async -> [WorkflowRun]
    public func getWorkflowRunDetail(projectID: String, runID: String) async throws -> WorkflowRunDetail
    public func listWorkflowPendingActions(projectID: String) async -> [WorkflowPendingAction]
    public func resolveWorkflowPendingAction(projectID: String, actionID: String, request: WorkflowActionResolveRequest) async throws -> WorkflowRunDetail
}
```

Define `WorkflowError` in this extension with invalid payload, workflow not found, run not found, action not found, validation failed, project not found.

- [ ] **Step 6: Run runner tests**

Run:

```bash
swift test --filter WorkflowRunnerTests
```

Expected: tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/sloppy/Workflows/WorkflowRunner.swift Sources/sloppy/CoreService.swift Sources/sloppy/CoreService+Workflows.swift Tests/sloppyTests/WorkflowRunnerTests.swift
git commit -m "feat: add workflow runner service"
```

---

### Task 5: Add Workflow HTTP API

**Files:**
- Create: `Sources/sloppy/Gateway/Routers/ProjectWorkflowsAPIRouter.swift`
- Modify: `Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift`
- Test: `Tests/sloppyTests/ProjectWorkflowsAPIRouterTests.swift`

- [ ] **Step 1: Write router tests**

Create tests that:

- create a project
- POST a workflow definition
- GET list and detail
- PUT update increments version
- POST run with `taskId`
- GET run detail
- GET pending actions
- POST resolve action

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter ProjectWorkflowsAPIRouterTests
```

Expected: route 404 or compile failure.

- [ ] **Step 3: Implement router**

Create `Sources/sloppy/Gateway/Routers/ProjectWorkflowsAPIRouter.swift`:

```swift
import Foundation
import Protocols

struct ProjectWorkflowsAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/projects/:projectId/workflows", metadata: RouteMetadata(summary: "List project workflows", description: "Returns workflow definitions for a project", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            do {
                return CoreRouter.encodable(status: .ok, payload: try await service.listWorkflowDefinitions(projectID: projectId))
            } catch {
                return CoreRouter.json(status: .internalServerError, payload: ["error": ErrorCode.projectReadFailed])
            }
        }

        router.post("/v1/projects/:projectId/workflows", metadata: RouteMetadata(summary: "Create project workflow", description: "Creates a workflow definition", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            guard let body = request.body, let payload = CoreRouter.decode(body, as: WorkflowDefinitionUpsertRequest.self) else {
                return CoreRouter.json(status: .badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: .created, payload: try await service.createWorkflowDefinition(projectID: projectId, request: payload))
            } catch {
                return CoreRouter.json(status: .internalServerError, payload: ["error": ErrorCode.projectUpdateFailed])
            }
        }

        router.get("/v1/projects/:projectId/workflows/:workflowId", metadata: RouteMetadata(summary: "Get project workflow", description: "Returns one workflow definition", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let workflowId = request.pathParam("workflowId") ?? ""
            do {
                return CoreRouter.encodable(status: .ok, payload: try await service.getWorkflowDefinition(projectID: projectId, workflowID: workflowId))
            } catch {
                return CoreRouter.json(status: .notFound, payload: ["error": ErrorCode.projectNotFound])
            }
        }

        router.put("/v1/projects/:projectId/workflows/:workflowId", metadata: RouteMetadata(summary: "Update project workflow", description: "Updates one workflow definition", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let workflowId = request.pathParam("workflowId") ?? ""
            guard let body = request.body, let payload = CoreRouter.decode(body, as: WorkflowDefinitionUpsertRequest.self) else {
                return CoreRouter.json(status: .badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: .ok, payload: try await service.updateWorkflowDefinition(projectID: projectId, workflowID: workflowId, request: payload))
            } catch {
                return CoreRouter.json(status: .internalServerError, payload: ["error": ErrorCode.projectUpdateFailed])
            }
        }

        router.delete("/v1/projects/:projectId/workflows/:workflowId", metadata: RouteMetadata(summary: "Delete project workflow", description: "Deletes one workflow definition", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let workflowId = request.pathParam("workflowId") ?? ""
            do {
                try await service.deleteWorkflowDefinition(projectID: projectId, workflowID: workflowId)
                return CoreRouter.noContent()
            } catch {
                return CoreRouter.json(status: .notFound, payload: ["error": ErrorCode.projectNotFound])
            }
        }

        router.post("/v1/projects/:projectId/workflows/:workflowId/runs", metadata: RouteMetadata(summary: "Start workflow run", description: "Starts a manual project workflow run", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let workflowId = request.pathParam("workflowId") ?? ""
            guard let body = request.body, let payload = CoreRouter.decode(body, as: WorkflowRunCreateRequest.self) else {
                return CoreRouter.json(status: .badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: .created, payload: try await service.startWorkflowRun(projectID: projectId, workflowID: workflowId, request: payload))
            } catch {
                return CoreRouter.json(status: .internalServerError, payload: ["error": ErrorCode.projectUpdateFailed])
            }
        }

        router.get("/v1/projects/:projectId/workflow-runs", metadata: RouteMetadata(summary: "List workflow runs", description: "Lists workflow runs for a project", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            return CoreRouter.encodable(status: .ok, payload: await service.listWorkflowRuns(projectID: projectId))
        }

        router.get("/v1/projects/:projectId/workflow-runs/:runId", metadata: RouteMetadata(summary: "Get workflow run", description: "Returns workflow run detail", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let runId = request.pathParam("runId") ?? ""
            do {
                return CoreRouter.encodable(status: .ok, payload: try await service.getWorkflowRunDetail(projectID: projectId, runID: runId))
            } catch {
                return CoreRouter.json(status: .notFound, payload: ["error": ErrorCode.projectNotFound])
            }
        }

        router.get("/v1/projects/:projectId/workflow-actions", metadata: RouteMetadata(summary: "List workflow actions", description: "Lists unresolved Dashboard workflow actions", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            return CoreRouter.encodable(status: .ok, payload: await service.listWorkflowPendingActions(projectID: projectId))
        }

        router.post("/v1/projects/:projectId/workflow-actions/:actionId/resolve", metadata: RouteMetadata(summary: "Resolve workflow action", description: "Resolves one Dashboard workflow action", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let actionId = request.pathParam("actionId") ?? ""
            guard let body = request.body, let payload = CoreRouter.decode(body, as: WorkflowActionResolveRequest.self) else {
                return CoreRouter.json(status: .badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: .ok, payload: try await service.resolveWorkflowPendingAction(projectID: projectId, actionID: actionId, request: payload))
            } catch {
                return CoreRouter.json(status: .notFound, payload: ["error": ErrorCode.projectNotFound])
            }
        }
    }
}
```

- [ ] **Step 4: Register router**

Modify `Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift`:

```swift
ProjectWorkflowsAPIRouter(service: service),
```

Place it after `ProjectsAPIRouter(service: service)`.

- [ ] **Step 5: Run router tests**

Run:

```bash
swift test --filter ProjectWorkflowsAPIRouterTests
```

Expected: tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/sloppy/Gateway/Routers/ProjectWorkflowsAPIRouter.swift Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift Tests/sloppyTests/ProjectWorkflowsAPIRouterTests.swift
git commit -m "feat: expose project workflow API"
```

---

### Task 6: Add Dashboard API Client and Project Routing

**Files:**
- Modify: `Dashboard/src/shared/api/coreApi.ts`
- Modify: `Dashboard/src/api.ts`
- Modify: `Dashboard/src/app/routing/dashboardRouteAdapter.ts`
- Modify: `Dashboard/src/views/Projects/utils.js`

- [ ] **Step 1: Add API client methods**

In `CoreApi`, add:

```ts
fetchProjectWorkflows: (projectId: string) => Promise<AnyRecord[] | null>;
createProjectWorkflow: (projectId: string, payload: AnyRecord) => Promise<AnyRecord | null>;
updateProjectWorkflow: (projectId: string, workflowId: string, payload: AnyRecord) => Promise<AnyRecord | null>;
deleteProjectWorkflow: (projectId: string, workflowId: string) => Promise<boolean>;
startProjectWorkflowRun: (projectId: string, workflowId: string, payload: AnyRecord) => Promise<AnyRecord | null>;
fetchProjectWorkflowRuns: (projectId: string) => Promise<AnyRecord[] | null>;
fetchProjectWorkflowRun: (projectId: string, runId: string) => Promise<AnyRecord | null>;
fetchProjectWorkflowActions: (projectId: string) => Promise<AnyRecord[] | null>;
resolveProjectWorkflowAction: (projectId: string, actionId: string, payload: AnyRecord) => Promise<AnyRecord | null>;
```

Implement these with `requestJson` using the routes from Task 5.

- [ ] **Step 2: Add project tab route**

In `Dashboard/src/app/routing/dashboardRouteAdapter.ts`, add `"workflows"` to `PROJECT_TABS`.

- [ ] **Step 3: Add project tab metadata**

In `Dashboard/src/views/Projects/utils.js`, add the workflows tab to `PROJECT_TABS` with a suitable icon such as `account_tree`.

- [ ] **Step 4: Run Dashboard typecheck/build**

Run:

```bash
cd Dashboard && npm run typecheck && npm run build
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add Dashboard/src/shared/api/coreApi.ts Dashboard/src/api.ts Dashboard/src/app/routing/dashboardRouteAdapter.ts Dashboard/src/views/Projects/utils.js
git commit -m "feat: add workflow dashboard API routes"
```

---

### Task 7: Add Minimal Project Workflows Tab

**Files:**
- Create: `Dashboard/src/views/Projects/ProjectWorkflowsTab.tsx`
- Modify: `Dashboard/src/views/ProjectsView.jsx`
- Modify: `Dashboard/src/styles/projects.css` or the existing project stylesheet used by project tabs

- [ ] **Step 1: Create Workflows tab component**

Create a component that:

- lists workflow definitions
- creates a starter workflow
- starts a run for the selected task when `selectedTask` exists
- lists recent runs
- lists pending actions with approve/reject/request changes buttons
- shows a simple lane-like board using CSS grid, not a full drag canvas yet

- [ ] **Step 2: Wire tab into ProjectsView**

Import `ProjectWorkflowsTab` in `Dashboard/src/views/ProjectsView.jsx` and render it when `activeProjectTab === "workflows"`.

- [ ] **Step 3: Add starter workflow button**

The starter workflow payload should be:

```js
{
  name: "Dashboard Approval",
  enabled: true,
  lanes: [
    { id: "system", title: "System", kind: "system" },
    { id: "owner", title: "Owner", kind: "human", actorId: "human:admin" }
  ],
  nodes: [
    { id: "start", type: "trigger", title: "Manual start", laneId: "system", config: { mode: "manual" }, positionX: 80, positionY: 80 },
    { id: "approval", type: "human_approval", title: "Approve", laneId: "owner", config: { prompt: "Approve this workflow run?" }, positionX: 360, positionY: 80 },
    { id: "done", type: "end", title: "Done", laneId: "system", config: { status: "completed" }, positionX: 640, positionY: 80 }
  ],
  edges: [
    { id: "e_start_approval", sourceNodeId: "start", targetNodeId: "approval" },
    { id: "e_approval_done", sourceNodeId: "approval", targetNodeId: "done", conditionKey: "approved" }
  ]
}
```

- [ ] **Step 4: Add CSS**

Use restrained dashboard styling: dense list/sidebar, unframed lane board, compact buttons, no landing-page treatment.

- [ ] **Step 5: Run Dashboard build**

Run:

```bash
cd Dashboard && npm run typecheck && npm run build
```

Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add Dashboard/src/views/Projects/ProjectWorkflowsTab.tsx Dashboard/src/views/ProjectsView.jsx Dashboard/src/styles/projects.css
git commit -m "feat: add project workflows tab"
```

---

### Task 8: Add Built-in Workflow Skill Integration

**Files:**
- Create: `Sources/sloppy/Tools/AgentTools/WorkflowTool.swift`
- Modify: `Sources/sloppy/Tools/ToolRegistry.swift`
- Modify: built-in skill catalog/store files used by `CoreService` for bundled skills
- Modify: agent prompt/skill wiring only if bundled skill discovery requires it
- Test: `Tests/sloppyTests/WorkflowToolTests.swift`
- Test: skill catalog/prompt tests if bundled skills have existing coverage

- [ ] **Step 1: Write tool and skill activation tests**

Create tests that verify:

- the workflow tool is registered in the default tool registry
- the tool can create a draft workflow definition for a project/task using a structured payload
- the tool rejects invalid graphs with validation issues
- the tool returns stable Dashboard URLs for the workflow definition and run
- regular agent prompt behavior does not instruct agents to create workflows unless the built-in workflow skill is active

The tests must assert typed fields and persisted records. Do not assert behavior by matching model prose.

- [ ] **Step 2: Add built-in `workflow` skill instructions**

Add a bundled skill named `workflow` with guidance similar to:

```markdown
# Workflow

Use this skill when the user explicitly asks for a workflow, visual plan, workflow-mode execution, or a task would benefit from a visible step graph.

When active:
- inspect project/task context first
- create a draft workflow proposal before running substantial work
- model work as lanes, nodes, and edges
- use typed workflow tools/APIs only
- link agent work to `agent_step` nodes through runtime metadata
- update workflow state from runtime events, not model-output text
- after creating or completing a workflow, provide the Dashboard workflow URL

Do not create workflows outside this skill.
```

The skill is built in, so users do not need to install it. It should be discoverable from the normal skill list.

- [ ] **Step 3: Add `WorkflowTool`**

Create `Sources/sloppy/Tools/AgentTools/WorkflowTool.swift` conforming to `CoreTool`.

Recommended tool operations:

- `propose`: create or update a draft `WorkflowDefinition` for a project/task
- `start`: start a workflow run
- `link_agent_step`: bind a workflow node to an agent session or subagent task id
- `status`: return definition/run detail plus Dashboard URLs

The tool input should be structured, for example:

```json
{
  "operation": "propose",
  "projectId": "project-id",
  "taskId": "task-id",
  "name": "Implement feature workflow",
  "rationale": "Visible plan before execution",
  "lanes": [],
  "nodes": [],
  "edges": []
}
```

The tool response should include:

```json
{
  "workflowId": "wf_...",
  "runId": null,
  "definitionUrl": "/projects/project-id/workflows/wf_...",
  "runUrl": null,
  "validationIssues": []
}
```

- [ ] **Step 4: Register the tool**

Add `WorkflowTool()` to `ToolRegistry.makeDefault()` in the project/task tool area. Keep permissions aligned with existing project mutation tools.

- [ ] **Step 5: Support `agent_step` node metadata**

Extend workflow node/run state enough for the tool to persist links from `agent_step` nodes to real execution:

- agent id
- session id or delegated task id
- current status
- started/finished timestamps if already available

Prefer `node.config` or typed run-step output for the MVP unless a stronger model is already needed. Do not infer completion from localized phrases or free-form assistant text.

- [ ] **Step 6: Return Dashboard links**

Add a small URL builder used by the tool and Dashboard tests:

- workflow definition: `/projects/<projectId>/workflows/<workflowId>`
- workflow run: `/projects/<projectId>/workflow-runs/<runId>`

If the existing Dashboard route shape differs, update this step to match the actual router and keep the API response stable.

- [ ] **Step 7: Run focused tests**

Run:

```bash
swift test --filter WorkflowToolTests
swift test --filter WorkflowRunnerTests
swift test --filter ProjectWorkflowsAPIRouterTests
```

Expected: tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/sloppy/Tools/AgentTools/WorkflowTool.swift Sources/sloppy/Tools/ToolRegistry.swift Tests/sloppyTests/WorkflowToolTests.swift <built-in-skill-files>
git commit -m "feat: add built-in workflow skill"
```

---

### Task 9: Verify MVP Vertical Slice

**Files:**
- No new files unless fixing issues found by verification.

- [ ] **Step 1: Run focused backend tests**

Run:

```bash
swift test --filter Workflow
```

Expected: all workflow tests pass.

- [ ] **Step 2: Run project router smoke tests**

Run:

```bash
swift test --filter ProjectWorkflowsAPIRouterTests
```

Expected: pass.

- [ ] **Step 3: Run Dashboard verification**

Run:

```bash
cd Dashboard && npm run typecheck && npm run build
```

Expected: pass.

- [ ] **Step 4: Run CI-adjacent build**

Run:

```bash
swift build --product sloppy
```

Expected: build succeeds.

- [ ] **Step 5: Commit verification fixes**

If verification required fixes:

```bash
git add <fixed-files>
git commit -m "fix: stabilize project workflows mvp"
```

---

## Self-Review

- Spec coverage: the plan covers project-scoped workflow definitions, Dashboard-only human actions, typed statuses, deterministic execution, file-backed definitions, SQLite-backed runs/actions, Core API, and Dashboard MVP.
- Deferred scope is explicit: agent/tool nodes, automatic triggers, templates, parallelism, external-channel approvals.
- Type consistency: model names are consistently `WorkflowDefinition`, `WorkflowRun`, `WorkflowRunStep`, `WorkflowPendingAction`, and request names use `Workflow...Request`.
- Risk: Task 3 depends on existing SQLite helper details, so the implementing worker must follow existing `SQLiteStore.swift` helper style instead of copying arbitrary SQL glue.
