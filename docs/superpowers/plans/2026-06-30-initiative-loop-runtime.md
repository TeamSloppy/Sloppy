# Initiative Loop Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first-class initiative loop runtime to Sloppy so long-lived technical objectives can persist state, delegate work, store project-local operational artifacts under `.meta`, and resume after review or user decisions.

**Architecture:** Introduce `Initiative` and `DecisionPacket` as typed project records backed by SQLite plus project-local `.meta` files, then thread initiative-aware orchestration through project services, task routing, and dashboard views. Keep the database as the query/index plane while `.meta` holds durable project-local artifacts and resume state.

**Tech Stack:** Swift 6.2, SwiftPM, SQLite via `CSQLite3`, Sloppy CoreService and Gateway routers, React 19 + Vite dashboard, Swift Testing.

## Global Constraints

- Preserve the existing project/task architecture: initiative is a new top-level object, but normal project tasks remain the executable child work items.
- Keep actor graph usage policy-driven: `single-agent` is default, `delegation` / `swarm` / `council` are escalation modes rather than always-on behavior.
- Store durable initiative artifacts inside `<project-root>/.meta/` while keeping SQLite metadata indexes and dashboard queries intact.
- Do not introduce language heuristics for runtime control flow; all transitions must use typed phase, mode, decision, review, or runtime event fields.
- Follow repository conventions: Swift Testing for tests, minimal focused files, and 2-space + semicolon style in dashboard code.

---

### Task 1: Add Initiative And Decision Packet Data Models

**Files:**
- Modify: `Sources/Protocols/APIModels.swift`
- Modify: `Sources/sloppy/Stores/PersistenceStore.swift`
- Modify: `Sources/sloppy/CorePersistenceFactory.swift`
- Modify: `Sources/sloppy/SQLiteStore.swift`
- Modify: `Sources/sloppy/Storage/schema.sql`
- Test: `Tests/sloppyTests/InitiativePersistenceTests.swift`

**Interfaces:**
- Consumes: existing `ProjectRecord`, `ProjectTaskRecord`, `ArtifactRecord`, `TaskClarificationRecord`, and persistence store conventions.
- Produces:
  - `InitiativePhase`
  - `InitiativeExecutionMode`
  - `InitiativeRecord`
  - `DecisionPacketRecord`
  - `PersistenceStore` methods:
    - `listInitiatives(projectID: String) async -> [InitiativeRecord]`
    - `getInitiative(projectID: String, initiativeID: String) async -> InitiativeRecord?`
    - `saveInitiative(_ record: InitiativeRecord) async`
    - `deleteInitiative(projectID: String, initiativeID: String) async -> Bool`
    - `listDecisionPackets(projectID: String, initiativeID: String) async -> [DecisionPacketRecord]`
    - `saveDecisionPacket(_ record: DecisionPacketRecord) async`

- [ ] **Step 1: Write the failing persistence test for initiative round-trip**

```swift
import Foundation
import Testing
@testable import Protocols
@testable import sloppy

struct InitiativePersistenceTests {
    @Test func savesAndLoadsInitiativeRecords() async throws {
        let store = InMemoryPersistenceStore()
        let record = InitiativeRecord(
            id: "init-ci",
            projectID: "project-ci",
            title: "Optimize CI pipeline",
            goal: "Reduce CI duration without reducing confidence",
            phase: .framing,
            executionMode: .singleAgent,
            successMetrics: ["duration_p95_minutes <= 12"],
            constraints: ["keep release builds green"],
            resumePoint: "collect baseline timings",
            blocker: nil,
            metadata: ["origin": "user"],
            createdAt: Date(),
            updatedAt: Date()
        )

        await store.saveInitiative(record)
        let loaded = await store.getInitiative(projectID: "project-ci", initiativeID: "init-ci")

        #expect(loaded?.phase == .framing)
        #expect(loaded?.executionMode == .singleAgent)
        #expect(loaded?.resumePoint == "collect baseline timings")
    }
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter InitiativePersistenceTests`
Expected: FAIL with missing `InitiativeRecord`, `InitiativePhase`, or missing persistence APIs.

- [ ] **Step 3: Add typed initiative and decision packet models in `APIModels.swift`**

```swift
public enum InitiativePhase: String, Codable, Sendable, Equatable {
    case intake
    case framing
    case researching
    case planning
    case executing
    case verifying
    case reviewing
    case needsUserDecision = "needs_user_decision"
    case blocked
    case done
    case abandoned
}

public enum InitiativeExecutionMode: String, Codable, Sendable, Equatable {
    case singleAgent = "single_agent"
    case delegation
    case swarm
    case councilReview = "council_review"
}

public struct InitiativeRecord: Codable, Sendable, Equatable {
    public var id: String
    public var projectID: String
    public var title: String
    public var goal: String
    public var phase: InitiativePhase
    public var executionMode: InitiativeExecutionMode
    public var successMetrics: [String]
    public var constraints: [String]
    public var resumePoint: String?
    public var blocker: String?
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date
}

public struct DecisionPacketRecord: Codable, Sendable, Equatable {
    public var id: String
    public var projectID: String
    public var initiativeID: String
    public var summary: String
    public var rationale: String
    public var tradeoffs: [String]
    public var requestedAction: String
    public var resumePoint: String?
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date
}
```

- [ ] **Step 4: Extend persistence interfaces and storage schema with initiative tables**

```swift
func listInitiatives(projectID: String) async -> [InitiativeRecord]
func getInitiative(projectID: String, initiativeID: String) async -> InitiativeRecord?
func saveInitiative(_ record: InitiativeRecord) async
func deleteInitiative(projectID: String, initiativeID: String) async -> Bool
func listDecisionPackets(projectID: String, initiativeID: String) async -> [DecisionPacketRecord]
func saveDecisionPacket(_ record: DecisionPacketRecord) async
```

```sql
CREATE TABLE IF NOT EXISTS project_initiatives (
    id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    title TEXT NOT NULL,
    goal TEXT NOT NULL,
    phase TEXT NOT NULL,
    execution_mode TEXT NOT NULL,
    success_metrics_json TEXT NOT NULL,
    constraints_json TEXT NOT NULL,
    resume_point TEXT,
    blocker TEXT,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    PRIMARY KEY (project_id, id)
);

CREATE TABLE IF NOT EXISTS initiative_decision_packets (
    id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    initiative_id TEXT NOT NULL,
    summary TEXT NOT NULL,
    rationale TEXT NOT NULL,
    tradeoffs_json TEXT NOT NULL,
    requested_action TEXT NOT NULL,
    resume_point TEXT,
    status TEXT NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    PRIMARY KEY (project_id, id)
);
```

- [ ] **Step 5: Run the focused persistence test and a narrow build**

Run: `swift test --filter InitiativePersistenceTests`
Expected: PASS

Run: `swift build --target sloppyTests`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit the data-model foundation**

```bash
git add Sources/Protocols/APIModels.swift Sources/sloppy/Stores/PersistenceStore.swift Sources/sloppy/CorePersistenceFactory.swift Sources/sloppy/SQLiteStore.swift Sources/sloppy/Storage/schema.sql Tests/sloppyTests/InitiativePersistenceTests.swift
git commit -m "feat: add initiative persistence models"
```

### Task 2: Add Project-Local `.meta` Initiative Storage

**Files:**
- Create: `Sources/sloppy/Projects/ProjectMetaStore.swift`
- Modify: `Sources/sloppy/CoreService+Projects.swift`
- Modify: `Sources/sloppy/Projects/ProjectContextLoader.swift`
- Modify: `Sources/sloppy/Artifacts/WidgetArtifactService.swift`
- Test: `Tests/sloppyTests/ProjectMetaStoreTests.swift`

**Interfaces:**
- Consumes: `projectDirectoryURL(projectID:)`, existing `.meta` handling in `ProjectContextLoader`, persisted initiative metadata from Task 1.
- Produces:
  - `ProjectMetaStore`
  - `ensureProjectMetaLayout(projectID: String) throws`
  - `initiativeDirectoryURL(projectID: String, initiativeID: String) -> URL`
  - `writeInitiativeArtifact(projectID: String, initiativeID: String, relativePath: String, content: Data) throws -> URL`
  - `writeDecisionPacketMarkdown(projectID: String, packet: DecisionPacketRecord) throws -> URL`

- [ ] **Step 1: Write the failing test for `.meta` layout and artifact write**

```swift
import Foundation
import Testing
@testable import sloppy

struct ProjectMetaStoreTests {
    @Test func writesInitiativeArtifactsInsideProjectMeta() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter ProjectMetaStoreTests`
Expected: FAIL with missing `ProjectMetaStore` or missing `.meta` write helpers.

- [ ] **Step 3: Implement a focused project meta file store**

```swift
struct ProjectMetaStore {
    let workspaceRootURL: URL
    let fileManager: FileManager

    func projectMetaURL(projectID: String) -> URL {
        workspaceRootURL
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectID, isDirectory: true)
            .appendingPathComponent(".meta", isDirectory: true)
    }

    func ensureProjectMetaLayout(projectID: String) throws {
        let base = projectMetaURL(projectID: projectID)
        for name in ["initiatives", "tasks", "artifacts", "decisions", "reviews", "state"] {
            try fileManager.createDirectory(at: base.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
        }
    }
}
```

- [ ] **Step 4: Route initiative artifacts and markdown decision notes through `.meta`**

```swift
func writeInitiativeArtifact(
    projectID: String,
    initiativeID: String,
    relativePath: String,
    content: Data
) throws -> URL {
    try ensureProjectMetaLayout(projectID: projectID)
    let base = projectMetaURL(projectID: projectID)
        .appendingPathComponent("artifacts", isDirectory: true)
        .appendingPathComponent(initiativeID, isDirectory: true)
    let url = base.appendingPathComponent(relativePath)
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.write(to: url, options: .atomic)
    return url
}
```

- [ ] **Step 5: Surface `.meta` files in project context refresh**

```swift
if fileManager.fileExists(atPath: projectMetaURL.appendingPathComponent("MEMORY.md").path) {
    addFile(relativePath: ".meta/MEMORY.md", content: text, to: &memoryDocs)
}
```

- [ ] **Step 6: Run the focused test and project-context regression test**

Run: `swift test --filter ProjectMetaStoreTests`
Expected: PASS

Run: `swift test --filter ProjectContext`
Expected: PASS or existing relevant project-context tests remain green

- [ ] **Step 7: Commit the `.meta` storage layer**

```bash
git add Sources/sloppy/Projects/ProjectMetaStore.swift Sources/sloppy/CoreService+Projects.swift Sources/sloppy/Projects/ProjectContextLoader.swift Sources/sloppy/Artifacts/WidgetArtifactService.swift Tests/sloppyTests/ProjectMetaStoreTests.swift
git commit -m "feat: add project meta initiative storage"
```

### Task 3: Add Initiative Service And Project APIs

**Files:**
- Create: `Sources/sloppy/CoreService+Initiatives.swift`
- Create: `Sources/sloppy/Gateway/Routers/InitiativesAPIRouter.swift`
- Modify: `Sources/sloppy/Gateway/CoreRouterRegistrar.swift`
- Modify: `Sources/sloppy/CoreService+Projects.swift`
- Test: `Tests/sloppyTests/InitiativesAPITests.swift`

**Interfaces:**
- Consumes: Task 1 persistence records, Task 2 `ProjectMetaStore`, existing project and task APIs.
- Produces:
  - `listInitiatives(projectID:)`
  - `createInitiative(projectID:request:)`
  - `updateInitiativePhase(projectID:initiativeID:phase:)`
  - `createDecisionPacket(projectID:initiativeID:request:)`
  - HTTP routes:
    - `GET /v1/projects/:projectId/initiatives`
    - `POST /v1/projects/:projectId/initiatives`
    - `GET /v1/projects/:projectId/initiatives/:initiativeId`
    - `PATCH /v1/projects/:projectId/initiatives/:initiativeId`
    - `GET /v1/projects/:projectId/initiatives/:initiativeId/decision-packets`
    - `POST /v1/projects/:projectId/initiatives/:initiativeId/decision-packets`

- [ ] **Step 1: Write the failing API test for create/list initiative**

```swift
import Foundation
import Testing
@testable import sloppy

struct InitiativesAPITests {
    @Test func createInitiativeEndpointPersistsRecord() async throws {
        let harness = try await CoreRouterTestHarness.make()
        let response = try await harness.requestJSON(
            method: "POST",
            path: "/v1/projects/demo/initiatives",
            body: [
                "title": "Optimize CI pipeline",
                "goal": "Reduce CI duration without reducing confidence",
                "successMetrics": ["duration_p95_minutes <= 12"],
                "constraints": ["keep release builds green"]
            ]
        )

        #expect(response.status == 200)
        #expect(response.json?["initiative"]?["phase"]?.stringValue == "intake")
    }
}
```

- [ ] **Step 2: Run the focused API test to verify it fails**

Run: `swift test --filter InitiativesAPITests`
Expected: FAIL with missing initiative routes or service methods.

- [ ] **Step 3: Implement initiative CRUD and decision packet service methods**

```swift
public func createInitiative(projectID: String, request: CreateInitiativeRequest) async throws -> InitiativeRecord {
    let now = Date()
    let record = InitiativeRecord(
        id: UUID().uuidString.lowercased(),
        projectID: projectID,
        title: request.title,
        goal: request.goal,
        phase: .intake,
        executionMode: .singleAgent,
        successMetrics: request.successMetrics,
        constraints: request.constraints,
        resumePoint: "start framing",
        blocker: nil,
        metadata: request.metadata,
        createdAt: now,
        updatedAt: now
    )
    await store.saveInitiative(record)
    return record
}
```

- [ ] **Step 4: Register initiative API routes under project routers**

```swift
router.get("/v1/projects/:projectId/initiatives", metadata: RouteMetadata(summary: "List initiatives", tags: ["Projects"])) { request in
    let projectID = try request.pathParameter("projectId")
    return try await service.listInitiatives(projectID: projectID)
}
```

- [ ] **Step 5: Persist decision packets as both records and `.meta/decisions/*.md` files**

```swift
let packet = DecisionPacketRecord(
    id: UUID().uuidString.lowercased(),
    projectID: projectID,
    initiativeID: initiativeID,
    summary: request.summary,
    rationale: request.rationale,
    tradeoffs: request.tradeoffs,
    requestedAction: request.requestedAction,
    resumePoint: request.resumePoint,
    status: "open",
    createdAt: now,
    updatedAt: now
)
await store.saveDecisionPacket(packet)
try projectMetaStore.writeDecisionPacketMarkdown(projectID: projectID, packet: packet)
```

- [ ] **Step 6: Run focused API tests and a narrow product build**

Run: `swift test --filter InitiativesAPITests`
Expected: PASS

Run: `swift build -c release --product sloppy`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit the initiative API layer**

```bash
git add Sources/sloppy/CoreService+Initiatives.swift Sources/sloppy/Gateway/Routers/InitiativesAPIRouter.swift Sources/sloppy/Gateway/CoreRouterRegistrar.swift Sources/sloppy/CoreService+Projects.swift Tests/sloppyTests/InitiativesAPITests.swift
git commit -m "feat: add initiative project apis"
```

### Task 4: Add Execution-Mode Policy And Task Linkage

**Files:**
- Modify: `Sources/Protocols/APIModels.swift`
- Modify: `Sources/sloppy/CoreService+Projects.swift`
- Modify: `Sources/sloppy/Agent/AgentSessionOrchestrator.swift`
- Modify: `Sources/sloppy/RecoveryManager.swift`
- Test: `Tests/sloppyTests/InitiativeExecutionPolicyTests.swift`

**Interfaces:**
- Consumes: initiative records and project tasks from Tasks 1-3, existing actor graph and swarm routing.
- Produces:
  - task-to-initiative linkage (`initiativeId`)
  - initiative phase transitions driven by typed events
  - execution mode escalation rules
  - recovery of initiative runtime state after restart

- [ ] **Step 1: Write the failing test for execution-mode escalation**

```swift
import Testing
@testable import sloppy

struct InitiativeExecutionPolicyTests {
    @Test func escalatesToDelegationWhenVerificationIsRequired() async throws {
        let service = try await CoreServiceTestHarness.make()
        let initiative = try await service.createInitiative(
            projectID: "demo",
            request: .init(
                title: "Optimize CI pipeline",
                goal: "Reduce CI duration without reducing confidence",
                successMetrics: ["duration_p95_minutes <= 12"],
                constraints: ["keep release builds green"],
                metadata: [:]
            )
        )

        let updated = try await service.updateInitiativeExecutionMode(
            projectID: "demo",
            initiativeID: initiative.id,
            signal: .needsIndependentVerification
        )

        #expect(updated.executionMode == .delegation)
    }
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter InitiativeExecutionPolicyTests`
Expected: FAIL with missing initiative execution-policy support.

- [ ] **Step 3: Add initiative linkage and policy-driven mode escalation**

```swift
public enum InitiativeExecutionSignal: String, Codable, Sendable {
    case needsIndependentVerification
    case needsSpecialist
    case parallelizableStreamsDetected
    case tradeoffDecisionRequired
}

func nextExecutionMode(
    current: InitiativeExecutionMode,
    signal: InitiativeExecutionSignal
) -> InitiativeExecutionMode {
    switch signal {
    case .needsIndependentVerification, .needsSpecialist:
        return .delegation
    case .parallelizableStreamsDetected:
        return .swarm
    case .tradeoffDecisionRequired:
        return .councilReview
    }
}
```

- [ ] **Step 4: Link child tasks to initiative ids and typed phase updates**

```swift
public struct ProjectTaskRecord: Codable, Sendable, Equatable {
    public var initiativeID: String?
}
```

```swift
if task.initiativeID == initiative.id, task.status == .done {
    try await advanceInitiativePhase(projectID: projectID, initiativeID: initiative.id, next: .verifying)
}
```

- [ ] **Step 5: Rebuild initiative runtime state during recovery**

```swift
let initiatives = await store.listInitiatives(projectID: projectID)
for initiative in initiatives where initiative.phase != .done && initiative.phase != .abandoned {
    await runtime.restoreInitiative(initiative)
}
```

- [ ] **Step 6: Run focused tests and task-related regressions**

Run: `swift test --filter InitiativeExecutionPolicyTests`
Expected: PASS

Run: `swift test --filter Projects`
Expected: PASS or existing project-task tests remain green

- [ ] **Step 7: Commit the execution-policy integration**

```bash
git add Sources/Protocols/APIModels.swift Sources/sloppy/CoreService+Projects.swift Sources/sloppy/Agent/AgentSessionOrchestrator.swift Sources/sloppy/RecoveryManager.swift Tests/sloppyTests/InitiativeExecutionPolicyTests.swift
git commit -m "feat: add initiative execution policy"
```

### Task 5: Add Dashboard Initiative Management

**Files:**
- Modify: `Dashboard/src/shared/api/coreApi.ts`
- Create: `Dashboard/src/views/Projects/ProjectInitiativesTab.tsx`
- Modify: `Dashboard/src/views/Projects/utils.js`
- Modify: `Dashboard/src/views/ProjectsView.jsx`
- Test: `Dashboard/src/views/Projects/__tests__/ProjectInitiativesTab.test.tsx`

**Interfaces:**
- Consumes: initiative and decision packet APIs from Task 3, execution mode and phase data from Task 4.
- Produces:
  - dashboard API helpers:
    - `listProjectInitiatives(projectId)`
    - `createProjectInitiative(projectId, request)`
    - `updateProjectInitiative(projectId, initiativeId, patch)`
    - `listInitiativeDecisionPackets(projectId, initiativeId)`
  - new project tab for initiative state, blockers, decision packets, and linked artifacts

- [ ] **Step 1: Write the failing dashboard test for rendering initiative state**

```tsx
import { render, screen } from "@testing-library/react";
import { ProjectInitiativesTab } from "../ProjectInitiativesTab";

test("renders initiative phase and execution mode", async () => {
  render(
    <ProjectInitiativesTab
      project={{ id: "demo", name: "Demo" }}
      initiatives={[{
        id: "init-ci",
        title: "Optimize CI pipeline",
        phase: "executing",
        executionMode: "delegation",
        resumePoint: "benchmark sharded tests"
      }]}
    />
  );

  expect(screen.getByText("Optimize CI pipeline")).toBeInTheDocument();
  expect(screen.getByText("executing")).toBeInTheDocument();
  expect(screen.getByText("delegation")).toBeInTheDocument();
});
```

- [ ] **Step 2: Run the dashboard test to verify it fails**

Run: `cd Dashboard && npm run typecheck`
Expected: FAIL with missing initiative API/types or missing `ProjectInitiativesTab`.

- [ ] **Step 3: Add API client methods and project tab registration**

```ts
listProjectInitiatives: async (projectId) => {
  const response = await requestJson<AnyRecord>({
    path: `/v1/projects/${encodeURIComponent(projectId)}/initiatives`
  });
  return Array.isArray((response.data as AnyRecord)?.initiatives)
    ? (response.data as AnyRecord).initiatives as AnyRecord[]
    : [];
},
```

- [ ] **Step 4: Implement a focused initiatives tab with phase, mode, blocker, and decision packet panels**

```tsx
export function ProjectInitiativesTab({ project }) {
  const [initiatives, setInitiatives] = useState<AnyRecord[]>([]);
  const [statusText, setStatusText] = useState("Loading initiatives...");

  useEffect(() => {
    let cancelled = false;
    listProjectInitiatives(project.id).then((items) => {
      if (!cancelled) {
        setInitiatives(items);
        setStatusText(`Loaded ${items.length} initiatives`);
      }
    });
    return () => { cancelled = true; };
  }, [project.id]);

  return <section className="project-tab-layout">{/* render cards */}</section>;
}
```

- [ ] **Step 5: Wire the new tab into project navigation and preserve existing task views**

```js
export const PROJECT_TABS = [
  { id: "overview", title: "Overview" },
  { id: "initiatives", title: "Initiatives" },
  { id: "tasks", title: "Tasks" }
];
```

- [ ] **Step 6: Run dashboard verification**

Run: `cd Dashboard && npm run typecheck`
Expected: PASS

Run: `cd Dashboard && npm run build`
Expected: build completes successfully

- [ ] **Step 7: Commit the dashboard initiative surface**

```bash
git add Dashboard/src/shared/api/coreApi.ts Dashboard/src/views/Projects/ProjectInitiativesTab.tsx Dashboard/src/views/Projects/utils.js Dashboard/src/views/ProjectsView.jsx Dashboard/src/views/Projects/__tests__/ProjectInitiativesTab.test.tsx
git commit -m "feat: add initiative dashboard view"
```

## Self-Review

- Spec coverage: The ADR requirements map to the plan as follows:
  - first-class initiative runtime: Tasks 1, 3, and 4
  - actor-graph escalation modes: Task 4
  - decision packets and human gates: Tasks 1 and 3
  - project-local `.meta` artifacts: Task 2
  - dashboard visibility and management: Task 5
- Placeholder scan: No `TODO`, `TBD`, or deferred “implement later” markers remain in task steps.
- Type consistency: `InitiativeRecord`, `DecisionPacketRecord`, `InitiativePhase`, and `InitiativeExecutionMode` are introduced in Task 1 and then reused consistently in Tasks 3-5.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-30-initiative-loop-runtime.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
