# Trigger-Driven Initiatives Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add event-driven triggers to Sloppy so external signals such as webhooks and GitHub Actions failures can create, resume, or enrich autonomous initiatives.

**Architecture:** Reuse the existing automation/workflow storage and routing patterns to introduce `TriggerDefinition`, `TriggerEventRecord`, and `InitiativeTemplate` as project-scoped trigger infrastructure. Normalize incoming events into durable trigger records, resolve them through dedupe and dispatch policy, and then create/resume/append into the initiative runtime already established by ADR 0002 and ADR 0003.

**Tech Stack:** Swift 6.2, SwiftPM, SQLite via `CSQLite3`, Sloppy CoreService and Gateway routers, React 19 + Vite dashboard, Swift Testing.

## Global Constraints

- Preserve the current initiative runtime as the only execution engine; triggers may create, resume, or append to initiatives, but must not bypass initiative policy by launching arbitrary work directly.
- Reuse existing project-scoped storage patterns where possible, especially the shape used by `AutomationDefinitionFileStore` and project automation routers.
- Keep event sources typed and normalized; do not infer trigger meaning from free-form text or provider-specific string heuristics beyond explicit payload fields.
- Add dedupe and max-concurrency guardrails in the first MVP so noisy webhooks do not create duplicate or runaway initiatives.
- Keep the first provider integration narrow: generic webhook ingestion plus one GitHub Actions failure adapter/template (`ci_failure`).

---

### Task 1: Add Trigger And Template Data Models

**Files:**
- Modify: `Sources/Protocols/APIModels.swift`
- Modify: `Sources/sloppy/Stores/PersistenceStore.swift`
- Modify: `Sources/sloppy/CorePersistenceFactory.swift`
- Modify: `Sources/sloppy/SQLiteStore.swift`
- Modify: `Sources/sloppy/Storage/schema.sql`
- Test: `Tests/sloppyTests/TriggerPersistenceTests.swift`

**Interfaces:**
- Consumes: existing initiative models, project-scoped persistence patterns, automation/workflow storage conventions.
- Produces:
  - `TriggerSource`
  - `TriggerDispatchMode`
  - `TriggerEventStatus`
  - `TriggerDispatchResult`
  - `TriggerDefinitionRecord`
  - `TriggerEventRecord`
  - `InitiativeTemplateRecord`
  - `PersistenceStore` methods for trigger definitions, trigger events, and initiative templates

- [ ] **Step 1: Write the failing persistence test for trigger definitions and trigger events**

```swift
import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Test
func savesAndLoadsTriggerDefinitionsAndEvents() async throws {
    let store = InMemoryPersistenceStore()
    let definition = TriggerDefinitionRecord(
        id: "ci-failure",
        projectID: "project-ci",
        source: .githubActions,
        eventType: "workflow_run.failed",
        enabled: true,
        dispatchMode: .resumeOrCreate,
        initiativeTemplateId: "ci_failure",
        filters: ["workflow": "CI"],
        dedupeWindowSeconds: 600,
        maxConcurrentInitiatives: 1,
        metadata: [:],
        createdAt: Date(),
        updatedAt: Date()
    )
    await store.saveTriggerDefinition(definition)

    let event = TriggerEventRecord(
        id: "event-1",
        triggerId: "ci-failure",
        projectID: "project-ci",
        source: .githubActions,
        eventType: "workflow_run.failed",
        externalRef: "TeamSloppy/Sloppy:CI:run-123",
        dedupeKey: "github_actions:TeamSloppy/Sloppy:CI:run-123:failed",
        status: .received,
        payload: ["workflow": .string("CI")],
        linkedInitiativeId: nil,
        dispatchResult: nil,
        receivedAt: Date(),
        processedAt: nil
    )
    await store.saveTriggerEvent(event)

    let definitions = await store.listTriggerDefinitions(projectID: "project-ci")
    let events = await store.listTriggerEvents(projectID: "project-ci")

    #expect(definitions.map(\.id) == ["ci-failure"])
    #expect(events.map(\.dedupeKey) == ["github_actions:TeamSloppy/Sloppy:CI:run-123:failed"])
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter TriggerPersistenceTests`
Expected: FAIL with missing trigger models or persistence APIs.

- [ ] **Step 3: Add trigger and template models to `APIModels.swift`**

```swift
public enum TriggerSource: String, Codable, Sendable, Equatable, CaseIterable {
    case webhook
    case github
    case githubActions = "github_actions"
    case cron
    case runtimeSignal = "runtime_signal"
}

public enum TriggerDispatchMode: String, Codable, Sendable, Equatable, CaseIterable {
    case create
    case resume
    case resumeOrCreate = "resume_or_create"
    case appendOnly = "append_only"
}

public enum TriggerEventStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case received
    case deduped
    case processed
    case ignored
    case rejected
    case failed
}
```

- [ ] **Step 4: Extend persistence and schema for trigger definitions, trigger events, and templates**

```sql
CREATE TABLE IF NOT EXISTS project_trigger_definitions (...);
CREATE TABLE IF NOT EXISTS project_trigger_events (...);
CREATE TABLE IF NOT EXISTS initiative_templates (...);
```

- [ ] **Step 5: Run the focused test and a narrow build**

Run: `swift test --filter TriggerPersistenceTests`
Expected: PASS

Run: `swift build --target sloppyTests`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit the trigger persistence foundation**

```bash
git add Sources/Protocols/APIModels.swift Sources/sloppy/Stores/PersistenceStore.swift Sources/sloppy/CorePersistenceFactory.swift Sources/sloppy/SQLiteStore.swift Sources/sloppy/Storage/schema.sql Tests/sloppyTests/TriggerPersistenceTests.swift
git commit -m "feat: add trigger persistence models"
```

### Task 2: Add Trigger Definition Store And Core Service

**Files:**
- Create: `Sources/sloppy/Stores/TriggerDefinitionFileStore.swift`
- Create: `Sources/sloppy/CoreService+Triggers.swift`
- Modify: `Sources/sloppy/CoreService.swift`
- Test: `Tests/sloppyTests/TriggerDefinitionFileStoreTests.swift`
- Test: `Tests/sloppyTests/TriggerDispatchPolicyTests.swift`

**Interfaces:**
- Consumes: Task 1 models, existing automation definition store patterns, initiative create/resume APIs.
- Produces:
  - `TriggerDefinitionFileStore`
  - `CoreService` trigger CRUD methods
  - dispatch helpers:
    - `normalizeTriggerEvent(...)`
    - `dispatchTriggerEvent(...)`
    - `findResumableInitiative(...)`
    - `dedupeTriggerEvent(...)`

- [ ] **Step 1: Write the failing test for resume-or-create dispatch**

```swift
@Test
func triggerDispatchResumesExistingInitiativeWithinScope() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    // create project, template, definition, existing initiative
    let result = try await service.dispatchTriggerEvent(
        projectID: "project-ci",
        triggerID: "ci-failure",
        payload: .init(
            source: .githubActions,
            eventType: "workflow_run.failed",
            externalRef: "TeamSloppy/Sloppy:CI:main",
            dedupeKey: "github_actions:TeamSloppy/Sloppy:CI:run-123:failed",
            payload: ["workflow": .string("CI"), "branch": .string("main")]
        )
    )
    #expect(result.result == .resumed)
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter TriggerDispatchPolicyTests`
Expected: FAIL with missing trigger dispatch service methods.

- [ ] **Step 3: Implement a project-scoped trigger definition store following automation-store patterns**

```swift
final class TriggerDefinitionFileStore {
    func list(projectID: String) throws -> [TriggerDefinitionRecord]
    func get(projectID: String, triggerID: String) throws -> TriggerDefinitionRecord
    func create(projectID: String, request: TriggerDefinitionUpsertRequest) throws -> TriggerDefinitionRecord
    func update(projectID: String, triggerID: String, request: TriggerDefinitionUpsertRequest) throws -> TriggerDefinitionRecord
    func delete(projectID: String, triggerID: String) throws
}
```

- [ ] **Step 4: Implement trigger dispatch policy in `CoreService+Triggers.swift`**

```swift
func dispatchTriggerEvent(projectID: String, triggerID: String, payload: TriggerEventCreateRequest) async throws -> TriggerDispatchResponse
```

- [ ] **Step 5: Run focused store and dispatch tests**

Run: `swift test --filter TriggerDefinitionFileStoreTests`
Expected: PASS

Run: `swift test --filter TriggerDispatchPolicyTests`
Expected: PASS

- [ ] **Step 6: Commit the trigger service layer**

```bash
git add Sources/sloppy/Stores/TriggerDefinitionFileStore.swift Sources/sloppy/CoreService+Triggers.swift Sources/sloppy/CoreService.swift Tests/sloppyTests/TriggerDefinitionFileStoreTests.swift Tests/sloppyTests/TriggerDispatchPolicyTests.swift
git commit -m "feat: add trigger dispatch service"
```

### Task 3: Add Trigger APIs And Generic Webhook Ingestion

**Files:**
- Create: `Sources/sloppy/Gateway/Routers/TriggersAPIRouter.swift`
- Modify: `Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift`
- Modify: `Sources/Protocols/APIModels.swift`
- Test: `Tests/sloppyTests/TriggersAPITests.swift`

**Interfaces:**
- Consumes: Task 2 trigger service methods and models.
- Produces routes:
  - `GET /v1/projects/:projectId/triggers`
  - `POST /v1/projects/:projectId/triggers`
  - `PATCH /v1/projects/:projectId/triggers/:triggerId`
  - `DELETE /v1/projects/:projectId/triggers/:triggerId`
  - `GET /v1/projects/:projectId/trigger-events`
  - `GET /v1/projects/:projectId/trigger-events/:eventId`
  - `POST /v1/projects/:projectId/triggers/:triggerId/fire`

- [ ] **Step 1: Write the failing API test for firing a trigger**

```swift
@Test
func firingTriggerCreatesOrResumesInitiative() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    // create project and trigger definition
    let response = await router.handle(
        method: "POST",
        path: "/v1/projects/project-ci/triggers/ci-failure/fire",
        body: try JSONEncoder().encode([
            "source": "github_actions",
            "eventType": "workflow_run.failed",
            "externalRef": "TeamSloppy/Sloppy:CI:run-123",
            "payload": ["workflow": "CI", "branch": "main"]
        ])
    )
    #expect(response.status == 200)
}
```

- [ ] **Step 2: Run the focused API test to verify it fails**

Run: `swift test --filter TriggersAPITests`
Expected: FAIL with missing routes.

- [ ] **Step 3: Add trigger API request/response types to `APIModels.swift`**

```swift
public struct TriggerDefinitionUpsertRequest: Codable, Sendable, Equatable { ... }
public struct TriggerEventCreateRequest: Codable, Sendable, Equatable { ... }
public struct TriggerDispatchResponse: Codable, Sendable, Equatable { ... }
```

- [ ] **Step 4: Implement `TriggersAPIRouter` and register it**

```swift
struct TriggersAPIRouter: APIRouter {
    func configure(on router: CoreRouterRegistrar) { ... }
}
```

- [ ] **Step 5: Run focused API tests and release build**

Run: `swift test --filter TriggersAPITests`
Expected: PASS

Run: `swift build -c release --product sloppy`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit the trigger API layer**

```bash
git add Sources/sloppy/Gateway/Routers/TriggersAPIRouter.swift Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift Sources/Protocols/APIModels.swift Tests/sloppyTests/TriggersAPITests.swift
git commit -m "feat: add trigger apis"
```

### Task 4: Add GitHub Actions CI Failure Template

**Files:**
- Create: `Sources/sloppy/Triggers/GitHubActionsTriggerNormalizer.swift`
- Modify: `Sources/sloppy/CoreService+Triggers.swift`
- Modify: `Sources/sloppy/CoreService+Initiatives.swift`
- Test: `Tests/sloppyTests/GitHubActionsTriggerTests.swift`

**Interfaces:**
- Consumes: Task 2 dispatch service, Task 3 generic fire endpoint.
- Produces:
  - `ci_failure` initiative template bootstrap
  - GitHub Actions payload normalizer
  - resume scope key: `<repo>:<workflow>:<branch>`
  - dedupe key: `github_actions:<repo>:<workflow>:<run_id>:failed`

- [ ] **Step 1: Write the failing test for CI failure trigger**

```swift
@Test
func githubActionsFailureCreatesCiFailureInitiative() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let payload: [String: JSONValue] = [
        "repository": .object(["full_name": .string("TeamSloppy/Sloppy")]),
        "workflow_run": .object([
            "id": .number(123),
            "name": .string("CI"),
            "head_branch": .string("main"),
            "conclusion": .string("failure")
        ])
    ]
    let result = try await service.dispatchGitHubActionsTrigger(projectID: "project-ci", triggerID: "ci-failure", payload: payload)
    #expect(result.result == .created)
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter GitHubActionsTriggerTests`
Expected: FAIL with missing GitHub Actions adapter.

- [ ] **Step 3: Implement the GitHub Actions payload adapter and `ci_failure` template mapping**

```swift
struct GitHubActionsTriggerNormalizer {
    func normalize(payload: [String: JSONValue]) throws -> TriggerEventCreateRequest
}
```

- [ ] **Step 4: Ensure resume-or-create uses workflow/branch scope**

```swift
let scopeKey = "\(repo):\(workflow):\(branch)"
```

- [ ] **Step 5: Run focused trigger tests**

Run: `swift test --filter GitHubActionsTriggerTests`
Expected: PASS

- [ ] **Step 6: Commit the GitHub Actions MVP**

```bash
git add Sources/sloppy/Triggers/GitHubActionsTriggerNormalizer.swift Sources/sloppy/CoreService+Triggers.swift Sources/sloppy/CoreService+Initiatives.swift Tests/sloppyTests/GitHubActionsTriggerTests.swift
git commit -m "feat: add github actions initiative trigger"
```

### Task 5: Add Dashboard Trigger History

**Files:**
- Modify: `Dashboard/src/shared/api/coreApi.ts`
- Modify: `Dashboard/src/api.ts`
- Create: `Dashboard/src/views/Projects/ProjectTriggersTab.jsx`
- Modify: `Dashboard/src/views/Projects/utils.js`
- Modify: `Dashboard/src/views/ProjectsView.jsx`

**Interfaces:**
- Consumes: Task 3 routes and Task 4 trigger normalization results.
- Produces:
  - trigger definition list view
  - trigger event history list
  - links from trigger events to linked initiatives

- [ ] **Step 1: Add dashboard API methods for triggers and trigger events**

```ts
fetchProjectTriggers(projectId)
createProjectTrigger(projectId, payload)
updateProjectTrigger(projectId, triggerId, payload)
deleteProjectTrigger(projectId, triggerId)
fetchProjectTriggerEvents(projectId)
```

- [ ] **Step 2: Implement a focused `ProjectTriggersTab`**

```jsx
export function ProjectTriggersTab({ project, onOpenInitiative }) { ... }
```

- [ ] **Step 3: Add the new tab to project navigation**

```js
{ id: "triggers", title: "Triggers" }
```

- [ ] **Step 4: Run dashboard verification**

Run: `cd Dashboard && npm run typecheck`
Expected: PASS

Run: `cd Dashboard && npm run build`
Expected: build completes successfully

- [ ] **Step 5: Commit the Dashboard trigger history view**

```bash
git add Dashboard/src/shared/api/coreApi.ts Dashboard/src/api.ts Dashboard/src/views/Projects/ProjectTriggersTab.jsx Dashboard/src/views/Projects/utils.js Dashboard/src/views/ProjectsView.jsx
git commit -m "feat: add trigger dashboard view"
```

## Self-Review

- Spec coverage:
  - trigger models and normalized events: Task 1
  - trigger CRUD and dispatch: Task 2
  - generic webhook ingestion: Task 3
  - GitHub Actions CI failure MVP: Task 4
  - Dashboard history and observability: Task 5
- Placeholder scan: No `TODO`, `TBD`, or “implement later” steps remain.
- Type consistency:
  - `TriggerDefinitionRecord`, `TriggerEventRecord`, and `InitiativeTemplateRecord` are introduced before service/API usage
  - `TriggerDispatchMode.resumeOrCreate` and `TriggerDispatchResult` names are used consistently across tasks
  - API route names match dashboard method names and service method expectations

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-30-trigger-driven-initiatives.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
