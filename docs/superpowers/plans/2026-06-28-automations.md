# Automations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build project-scoped automations that start existing workflows from manual, cron, webhook, and GitHub PR/review triggers, with optional task creation/attachment before workflow start.

**Architecture:** Add a new `AutomationDefinition` product layer on top of the existing workflow engine. Persist definitions as project files, persist automation run history in SQLite, normalize trigger payloads into typed workflow inputs, and reuse `WorkflowRunner` for actual execution. Keep the MVP constrained to one automation bound to one project and one repository, with GitHub scope limited to `pull_request` and `pull_request_review`.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftNIO router conventions, SQLite via existing `CSQLite3` store, React 19 + Vite Dashboard, TypeScript/JS API client.

## Global Constraints

- One automation binds to exactly one project and one repository.
- Supported MVP triggers are `manual`, `cron`, `webhook`, `github_pull_request`, and `github_pull_request_review`.
- GitHub MVP supports only `pull_request` and `pull_request_review` events.
- Slack triggers are explicitly out of scope.
- Task creation is optional per automation via typed `taskMode`.
- Automation execution must reuse the existing workflow engine rather than creating a second runner.
- Control flow and trigger routing must use typed fields, never natural-language matching.

---

## File Structure

- Modify `Sources/Protocols/APIModels.swift`: add automation DTOs, trigger enums, task mode, requests, and run records.
- Create `Sources/sloppy/Stores/AutomationDefinitionFileStore.swift`: file-backed automation definition CRUD under `workspace/automations/<projectId>/`.
- Modify `Sources/sloppy/Stores/PersistenceStore.swift`: add automation run persistence methods.
- Modify `Sources/sloppy/SQLiteStore.swift`: add SQLite-backed automation run storage and migrations.
- Modify `Sources/sloppy/CorePersistenceFactory.swift`: add in-memory fallback storage for automation runs.
- Create `Sources/sloppy/CoreService+Automations.swift`: automation CRUD, manual start, task pre-processing, trigger execution, run queries.
- Create `Sources/sloppy/Automation/AutomationTriggerMatcher.swift`: typed trigger matching helpers for cron/webhook/GitHub events.
- Create `Sources/sloppy/Automation/AutomationTaskResolver.swift`: task create/attach policy helpers.
- Create `Sources/sloppy/Gateway/Routers/ProjectAutomationsAPIRouter.swift`: project CRUD and manual run routes.
- Create `Sources/sloppy/Gateway/Routers/AutomationIngressAPIRouter.swift`: webhook and GitHub ingress endpoints.
- Modify `Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift`: register automation routers.
- Modify `Sources/sloppy/Runners/CronRunner.swift`: fire automation cron definitions in addition to existing cron tasks.
- Modify `Dashboard/src/shared/api/coreApi.ts`: add automation API methods.
- Modify `Dashboard/src/api.ts`: re-export new automation client surface if needed for legacy imports.
- Modify `Dashboard/src/app/routing/dashboardRouteAdapter.ts`: add project automation routes.
- Modify `Dashboard/src/views/Projects/utils.js`: add `automations` tab metadata.
- Modify `Dashboard/src/views/ProjectsView.jsx`: render the new Automations tab.
- Create `Dashboard/src/views/Projects/ProjectAutomationsTab.tsx`: project-level automation editor and run list.
- Modify `Dashboard/src/styles/projects.css`: add automation styles.
- Create `Tests/ProtocolsTests/AutomationAPIModelsTests.swift`: DTO round-trip tests.
- Create `Tests/sloppyTests/AutomationDefinitionFileStoreTests.swift`: file store tests.
- Create `Tests/sloppyTests/AutomationServiceTests.swift`: service and task mode tests.
- Create `Tests/sloppyTests/AutomationIngressAPIRouterTests.swift`: webhook and GitHub ingress tests.
- Create `Tests/sloppyTests/ProjectAutomationsAPIRouterTests.swift`: CRUD/manual run router tests.

### Task 1: Add Shared Automation API Models

**Files:**
- Modify: `Sources/Protocols/APIModels.swift`
- Create: `Tests/ProtocolsTests/AutomationAPIModelsTests.swift`

**Interfaces:**
- Consumes: existing `JSONValue`, `WorkflowRunDetail`, and project/task API model conventions from `Sources/Protocols/APIModels.swift`
- Produces:
  - `public enum AutomationTriggerKind: String, Codable, Sendable, CaseIterable`
  - `public enum AutomationTaskMode: String, Codable, Sendable, CaseIterable`
  - `public enum AutomationRunStatus: String, Codable, Sendable, CaseIterable`
  - `public struct AutomationDefinition: Codable, Sendable, Equatable`
  - `public struct AutomationDefinitionUpsertRequest: Codable, Sendable, Equatable`
  - `public struct AutomationRun: Codable, Sendable, Equatable`
  - `public struct AutomationRunDetail: Codable, Sendable, Equatable`
  - `public struct AutomationManualRunRequest: Codable, Sendable, Equatable`
  - `public struct AutomationTriggerPayload: Codable, Sendable, Equatable`
  - `public struct GitHubAutomationEventRequest: Codable, Sendable, Equatable`

- [ ] **Step 1: Write the failing DTO round-trip tests**

```swift
import Foundation
import Testing
@testable import Protocols

@Test
func automationDefinitionRoundTrips() throws {
    let now = Date(timeIntervalSince1970: 1_782_000_000)
    let definition = AutomationDefinition(
        id: "auto_pr_review",
        projectId: "proj",
        name: "PR Review Automation",
        description: "Run review workflow on PR open",
        enabled: true,
        workflowId: "wf_review",
        repositoryFullName: "TeamSloppy/Sloppy",
        trigger: .init(
            type: .githubPullRequest,
            config: [
                "actions": .array([.string("opened"), .string("synchronize")]),
                "branchPatterns": .array([.string("main")])
            ]
        ),
        taskMode: .createOrAttach,
        model: nil,
        permissionsScope: .projectVisible,
        createdAt: now,
        updatedAt: now
    )

    let data = try JSONEncoder().encode(definition)
    let decoded = try JSONDecoder().decode(AutomationDefinition.self, from: data)

    #expect(decoded == definition)
}

@Test
func githubAutomationEventRequestRoundTrips() throws {
    let request = GitHubAutomationEventRequest(
        deliveryId: "delivery-1",
        event: "pull_request",
        action: "opened",
        repositoryFullName: "TeamSloppy/Sloppy",
        payload: [
            "pullRequestNumber": .number(42),
            "title": .string("Fix flaky tests")
        ]
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(GitHubAutomationEventRequest.self, from: data)

    #expect(decoded == request)
}
```

- [ ] **Step 2: Run the focused protocol tests and verify they fail**

Run: `swift test --filter AutomationAPIModelsTests`

Expected: FAIL with compile errors referencing missing automation types.

- [ ] **Step 3: Add the automation enums and structs to `APIModels.swift`**

```swift
public enum AutomationTriggerKind: String, Codable, Sendable, CaseIterable {
    case manual
    case cron
    case webhook
    case githubPullRequest = "github_pull_request"
    case githubPullRequestReview = "github_pull_request_review"
}

public enum AutomationTaskMode: String, Codable, Sendable, CaseIterable {
    case none
    case createTask = "create_task"
    case attachToExistingIfMatch = "attach_to_existing_if_match"
    case createOrAttach = "create_or_attach"
}

public enum AutomationRunStatus: String, Codable, Sendable, CaseIterable {
    case queued
    case running
    case waitingForWorkflow = "waiting_for_workflow"
    case completed
    case failed
    case cancelled
    case ignored
}

public enum AutomationPermissionsScope: String, Codable, Sendable, CaseIterable {
    case `private`
    case projectVisible = "project_visible"
    case projectManaged = "project_managed"
}

public struct AutomationTrigger: Codable, Sendable, Equatable {
    public var type: AutomationTriggerKind
    public var config: [String: JSONValue]
}
```
```swift
public struct AutomationDefinition: Codable, Sendable, Equatable {
    public var id: String
    public var projectId: String
    public var name: String
    public var description: String?
    public var enabled: Bool
    public var workflowId: String
    public var repositoryFullName: String
    public var trigger: AutomationTrigger
    public var taskMode: AutomationTaskMode
    public var model: String?
    public var permissionsScope: AutomationPermissionsScope
    public var createdAt: Date
    public var updatedAt: Date
}
```

- [ ] **Step 4: Run the focused protocol tests and verify they pass**

Run: `swift test --filter AutomationAPIModelsTests`

Expected: PASS with `2 tests passed`.

- [ ] **Step 5: Commit the model layer**

```bash
git add Sources/Protocols/APIModels.swift Tests/ProtocolsTests/AutomationAPIModelsTests.swift
git commit -m "feat: add automation API models"
```

### Task 2: Add File-Backed Definitions and SQLite Run Persistence

**Files:**
- Create: `Sources/sloppy/Stores/AutomationDefinitionFileStore.swift`
- Modify: `Sources/sloppy/Stores/PersistenceStore.swift`
- Modify: `Sources/sloppy/SQLiteStore.swift`
- Modify: `Sources/sloppy/CorePersistenceFactory.swift`
- Create: `Tests/sloppyTests/AutomationDefinitionFileStoreTests.swift`

**Interfaces:**
- Consumes: `AutomationDefinition`, `AutomationDefinitionUpsertRequest`, and file store patterns from `WorkflowDefinitionFileStore`
- Produces:
  - `final class AutomationDefinitionFileStore`
  - `func listAutomationRuns(projectId: String) async -> [AutomationRun]`
  - `func getAutomationRun(id: String) async -> AutomationRun?`
  - `func saveAutomationRun(_ run: AutomationRun) async`
  - `func listAutomationRuns(automationId: String) async -> [AutomationRun]`

- [ ] **Step 1: Write the failing file store test**

```swift
import Foundation
import Testing
@testable import sloppy
import Protocols

@Test
func automationDefinitionStoreCreatesListsUpdatesAndDeletesDefinitions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = AutomationDefinitionFileStore(workspaceRootURL: root)

    let created = try store.create(
        projectID: "proj",
        request: AutomationDefinitionUpsertRequest(
            name: "PR Review",
            description: "Review PRs",
            enabled: true,
            workflowId: "wf_review",
            repositoryFullName: "TeamSloppy/Sloppy",
            trigger: .init(type: .githubPullRequest, config: ["actions": .array([.string("opened")])]),
            taskMode: .createOrAttach,
            model: nil,
            permissionsScope: .projectVisible
        )
    )

    #expect(created.projectId == "proj")
    #expect(try store.list(projectID: "proj").count == 1)

    let updated = try store.update(
        projectID: "proj",
        automationID: created.id,
        request: AutomationDefinitionUpsertRequest(
            name: "PR Review Updated",
            description: "Review PRs again",
            enabled: false,
            workflowId: "wf_review",
            repositoryFullName: "TeamSloppy/Sloppy",
            trigger: .init(type: .githubPullRequest, config: ["actions": .array([.string("synchronize")])]),
            taskMode: .none,
            model: "openai:gpt-5",
            permissionsScope: .projectVisible
        )
    )

    #expect(updated.version == created.version + 1)

    try store.delete(projectID: "proj", automationID: created.id)
    #expect(try store.list(projectID: "proj").isEmpty)
}
```

- [ ] **Step 2: Run the focused store test and verify it fails**

Run: `swift test --filter AutomationDefinitionFileStoreTests`

Expected: FAIL with compile errors because `AutomationDefinitionFileStore` and persistence methods do not exist.

- [ ] **Step 3: Implement `AutomationDefinitionFileStore` using the workflow store pattern**

```swift
final class AutomationDefinitionFileStore {
    enum StoreError: Error, Equatable {
        case invalidPayload
        case notFound
        case storageFailure
    }

    func create(projectID: String, request: AutomationDefinitionUpsertRequest) throws -> AutomationDefinition
    func update(projectID: String, automationID: String, request: AutomationDefinitionUpsertRequest) throws -> AutomationDefinition
    func list(projectID: String) throws -> [AutomationDefinition]
    func get(projectID: String, automationID: String) throws -> AutomationDefinition
    func delete(projectID: String, automationID: String) throws
}
```
```swift
private func ensureProjectDirectory(projectID: String) throws -> URL {
    let projectID = try normalizedPathComponent(projectID)
    let directory = workspaceRootURL
        .appendingPathComponent("automations")
        .appendingPathComponent(projectID)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
```

- [ ] **Step 4: Add automation run persistence protocol and SQLite storage**

```swift
public protocol PersistenceStore: Actor {
    func listAutomationRuns(projectId: String) async -> [AutomationRun]
    func listAutomationRuns(automationId: String) async -> [AutomationRun]
    func getAutomationRun(id: String) async -> AutomationRun?
    func saveAutomationRun(_ run: AutomationRun) async
}
```
```swift
CREATE TABLE IF NOT EXISTS automation_runs (
    id TEXT PRIMARY KEY,
    automation_id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    workflow_id TEXT NOT NULL,
    workflow_run_id TEXT,
    repository_full_name TEXT NOT NULL,
    trigger_type TEXT NOT NULL,
    trigger_event_id TEXT,
    status TEXT NOT NULL,
    task_id TEXT,
    summary TEXT,
    started_at TEXT NOT NULL,
    finished_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_automation_runs_project ON automation_runs(project_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_automation_runs_automation ON automation_runs(automation_id, started_at DESC);
```

- [ ] **Step 5: Run focused tests and a narrow package build**

Run: `swift test --filter AutomationDefinitionFileStoreTests`

Expected: PASS with `1 test passed`.

Run: `swift build --target sloppyTests`

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit persistence and file storage**

```bash
git add Sources/sloppy/Stores/AutomationDefinitionFileStore.swift Sources/sloppy/Stores/PersistenceStore.swift Sources/sloppy/SQLiteStore.swift Sources/sloppy/CorePersistenceFactory.swift Tests/sloppyTests/AutomationDefinitionFileStoreTests.swift
git commit -m "feat: add automation definition and run storage"
```

### Task 3: Add CoreService Automation CRUD, Manual Start, and Task Policy

**Files:**
- Create: `Sources/sloppy/CoreService+Automations.swift`
- Create: `Sources/sloppy/Automation/AutomationTaskResolver.swift`
- Create: `Tests/sloppyTests/AutomationServiceTests.swift`

**Interfaces:**
- Consumes:
  - `AutomationDefinitionFileStore`
  - `PersistenceStore.saveAutomationRun(_:)`
  - existing `startWorkflowRun(projectID:workflowID:request:)`
  - existing project task creation/update APIs
- Produces:
  - `public func listAutomationDefinitions(projectID: String) async throws -> [AutomationDefinition]`
  - `public func createAutomationDefinition(projectID: String, request: AutomationDefinitionUpsertRequest) async throws -> AutomationDefinition`
  - `public func updateAutomationDefinition(projectID: String, automationID: String, request: AutomationDefinitionUpsertRequest) async throws -> AutomationDefinition`
  - `public func startAutomationRun(projectID: String, automationID: String, request: AutomationManualRunRequest) async throws -> AutomationRunDetail`
  - `public func triggerAutomation(projectID: String, automationID: String, payload: AutomationTriggerPayload) async throws -> AutomationRunDetail`

- [ ] **Step 1: Write the failing service test for manual run and task mode**

```swift
import Foundation
import Testing
@testable import sloppy
import Protocols

@Test
func automationManualRunCreatesTaskBeforeWorkflowWhenConfigured() async throws {
    let fixture = try await makeAutomationFixture()

    let automation = try await fixture.service.createAutomationDefinition(
        projectID: fixture.projectID,
        request: AutomationDefinitionUpsertRequest(
            name: "PR Review",
            description: nil,
            enabled: true,
            workflowId: fixture.workflowID,
            repositoryFullName: "TeamSloppy/Sloppy",
            trigger: .init(type: .manual, config: [:]),
            taskMode: .createTask,
            model: nil,
            permissionsScope: .projectVisible
        )
    )

    let detail = try await fixture.service.startAutomationRun(
        projectID: fixture.projectID,
        automationID: automation.id,
        request: AutomationManualRunRequest(
            actorId: "human:admin",
            input: ["title": .string("Review PR #42")]
        )
    )

    #expect(detail.run.workflowRunId != nil)
    #expect(detail.run.taskId != nil)
    #expect(detail.workflowRun?.run.workflowId == fixture.workflowID)
}
```

- [ ] **Step 2: Run the focused service test and verify it fails**

Run: `swift test --filter AutomationServiceTests`

Expected: FAIL with compile errors because `CoreService+Automations` APIs and run detail wrappers do not exist.

- [ ] **Step 3: Implement task policy resolution in a focused helper**

```swift
struct AutomationTaskResolution: Sendable, Equatable {
    var taskId: String?
    var created: Bool
}

struct AutomationTaskResolver {
    func resolve(
        mode: AutomationTaskMode,
        projectID: String,
        repositoryFullName: String,
        payload: AutomationTriggerPayload,
        service: CoreService
    ) async throws -> AutomationTaskResolution
}
```
```swift
private func githubMatchKey(repository: String, payload: AutomationTriggerPayload) -> String? {
    guard let number = payload.data["pullRequest"]?.asObject?["number"]?.asInt else {
        return nil
    }
    return "\(repository)#\(number)"
}
```

- [ ] **Step 4: Implement automation CRUD and workflow bridge in `CoreService+Automations.swift`**

```swift
public struct AutomationRunDetail: Codable, Sendable, Equatable {
    public var run: AutomationRun
    public var workflowRun: WorkflowRunDetail?
}
```
```swift
public func triggerAutomation(
    projectID: String,
    automationID: String,
    payload: AutomationTriggerPayload
) async throws -> AutomationRunDetail {
    let automation = try await getAutomationDefinition(projectID: projectID, automationID: automationID)
    let taskResolution = try await taskResolver.resolve(
        mode: automation.taskMode,
        projectID: projectID,
        repositoryFullName: automation.repositoryFullName,
        payload: payload,
        service: self
    )
    let workflowDetail = try await startWorkflowRun(
        projectID: projectID,
        workflowID: automation.workflowId,
        request: WorkflowRunCreateRequest(
            taskId: taskResolution.taskId,
            startedBy: payload.startedBy,
            input: payload.workflowInput
        )
    )
    let run = AutomationRun(
        id: "autorun_\(UUID().uuidString.lowercased())",
        automationId: automation.id,
        projectId: projectID,
        workflowId: automation.workflowId,
        workflowRunId: workflowDetail.run.id,
        repositoryFullName: automation.repositoryFullName,
        triggerType: automation.trigger.type,
        triggerEventId: payload.triggerEventId,
        status: .completed,
        taskId: taskResolution.taskId,
        summary: nil,
        startedAt: Date(),
        finishedAt: Date()
    )
    await store.saveAutomationRun(run)
    return AutomationRunDetail(run: run, workflowRun: workflowDetail)
}
```

- [ ] **Step 5: Run focused service tests and the existing workflow tests**

Run: `swift test --filter AutomationServiceTests`

Expected: PASS.

Run: `swift test --filter WorkflowRunnerTests`

Expected: PASS, confirming the automation bridge did not regress workflow execution.

- [ ] **Step 6: Commit the service layer**

```bash
git add Sources/sloppy/CoreService+Automations.swift Sources/sloppy/Automation/AutomationTaskResolver.swift Tests/sloppyTests/AutomationServiceTests.swift
git commit -m "feat: add automation service and task policy"
```

### Task 4: Add Cron, Webhook, and GitHub Trigger Ingestion

**Files:**
- Create: `Sources/sloppy/Automation/AutomationTriggerMatcher.swift`
- Create: `Sources/sloppy/Gateway/Routers/AutomationIngressAPIRouter.swift`
- Modify: `Sources/sloppy/Runners/CronRunner.swift`
- Modify: `Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift`
- Create: `Tests/sloppyTests/AutomationIngressAPIRouterTests.swift`

**Interfaces:**
- Consumes:
  - `CoreService.triggerAutomation(projectID:automationID:payload:)`
  - `AutomationDefinition.trigger`
  - existing GitHub auth and project/repository metadata where available
- Produces:
  - `struct AutomationTriggerMatcher`
  - `func matchingAutomations(forGitHubEvent request: GitHubAutomationEventRequest, definitions: [AutomationDefinition]) -> [AutomationDefinition]`
  - `func matchingAutomations(forCron date: Date, definitions: [AutomationDefinition]) -> [AutomationDefinition]`

- [ ] **Step 1: Write the failing router test for GitHub PR event ingestion**

```swift
import Foundation
import Testing
@testable import sloppy
import Protocols

@Test
func githubPullRequestIngressStartsMatchingAutomation() async throws {
    let fixture = try await makeAutomationIngressFixture(trigger: .githubPullRequest)

    let body = try JSONEncoder().encode(
        GitHubAutomationEventRequest(
            deliveryId: "gh-delivery-1",
            event: "pull_request",
            action: "opened",
            repositoryFullName: "TeamSloppy/Sloppy",
            payload: [
                "pullRequest": .object([
                    "number": .number(42),
                    "title": .string("Fix flaky tests"),
                    "baseRef": .string("main")
                ])
            ]
        )
    )

    let response = await fixture.router.handle(
        method: "POST",
        path: "/v1/github/automations/events",
        body: body
    )

    #expect(response.status == 202)
    let runs = await fixture.service.listAutomationRuns(projectID: fixture.projectID)
    #expect(runs.count == 1)
    #expect(runs[0].triggerType == .githubPullRequest)
}
```

- [ ] **Step 2: Run the focused ingress test and verify it fails**

Run: `swift test --filter AutomationIngressAPIRouterTests`

Expected: FAIL with compile errors because the ingress router and matcher do not exist.

- [ ] **Step 3: Implement typed trigger matching**

```swift
struct AutomationTriggerMatcher {
    func matches(_ definition: AutomationDefinition, github request: GitHubAutomationEventRequest) -> Bool {
        guard definition.enabled,
              definition.trigger.type == .githubPullRequest || definition.trigger.type == .githubPullRequestReview,
              definition.repositoryFullName == request.repositoryFullName
        else { return false }

        let config = definition.trigger.config
        let allowedActions = config["actions"]?.asArray?.compactMap(\.asString) ?? []
        if !allowedActions.isEmpty && !allowedActions.contains(request.action) {
            return false
        }
        return true
    }
}
```
```swift
func cronPayload(for automation: AutomationDefinition, date: Date) -> AutomationTriggerPayload {
    AutomationTriggerPayload(
        source: .cron,
        startedBy: "system:cron",
        triggerEventId: ISO8601DateFormatter().string(from: date),
        data: ["triggeredAt": .string(ISO8601DateFormatter().string(from: date))],
        workflowInput: ["source": .string("cron"), "triggeredAt": .string(ISO8601DateFormatter().string(from: date))]
    )
}
```

- [ ] **Step 4: Implement ingress router and wire cron automation firing**

```swift
router.post("/v1/github/automations/events", metadata: RouteMetadata(summary: "Ingest GitHub automation event", description: "Normalizes a GitHub PR or review event and starts matching automations", tags: ["Automations"])) { request in
    guard let body = request.body,
          let payload = CoreRouter.decode(body, as: GitHubAutomationEventRequest.self)
    else {
        return CoreRouter.json(status: .badRequest, payload: ["error": ErrorCode.invalidBody])
    }
    let result = await service.ingestGitHubAutomationEvent(request: payload)
    return CoreRouter.encodable(status: .accepted, payload: result)
}
```
```swift
for automation in await automationProvider.listCronAutomations() {
    if matcher.matchesCron(automation, date: date) {
        _ = try? await service.triggerAutomation(
            projectID: automation.projectId,
            automationID: automation.id,
            payload: cronPayload(for: automation, date: date)
        )
    }
}
```

- [ ] **Step 5: Run focused ingress tests and a narrow sloppy test build**

Run: `swift test --filter AutomationIngressAPIRouterTests`

Expected: PASS.

Run: `swift build --target sloppyTests`

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit trigger ingestion**

```bash
git add Sources/sloppy/Automation/AutomationTriggerMatcher.swift Sources/sloppy/Gateway/Routers/AutomationIngressAPIRouter.swift Sources/sloppy/Gateway/Routers/CoreRouter+HTTPRoutes.swift Sources/sloppy/Runners/CronRunner.swift Tests/sloppyTests/AutomationIngressAPIRouterTests.swift
git commit -m "feat: add automation trigger ingestion"
```

### Task 5: Add Project Automation CRUD and Manual Run HTTP API

**Files:**
- Create: `Sources/sloppy/Gateway/Routers/ProjectAutomationsAPIRouter.swift`
- Create: `Tests/sloppyTests/ProjectAutomationsAPIRouterTests.swift`

**Interfaces:**
- Consumes:
  - `CoreService` automation CRUD methods
  - `AutomationManualRunRequest`
  - `AutomationRunDetail`
- Produces:
  - `GET /v1/projects/:projectId/automations`
  - `POST /v1/projects/:projectId/automations`
  - `GET /v1/projects/:projectId/automations/:automationId`
  - `PUT /v1/projects/:projectId/automations/:automationId`
  - `DELETE /v1/projects/:projectId/automations/:automationId`
  - `POST /v1/projects/:projectId/automations/:automationId/run`
  - `GET /v1/projects/:projectId/automation-runs`
  - `GET /v1/projects/:projectId/automation-runs/:runId`

- [ ] **Step 1: Write the failing router CRUD/manual run test**

```swift
import Foundation
import Testing
@testable import sloppy
import Protocols

@Test
func projectAutomationsRouterCreatesAndRunsManualAutomation() async throws {
    let fixture = try await makeProjectAutomationsRouterFixture()

    let createBody = try JSONEncoder().encode(
        AutomationDefinitionUpsertRequest(
            name: "Manual Review",
            description: nil,
            enabled: true,
            workflowId: fixture.workflowID,
            repositoryFullName: "TeamSloppy/Sloppy",
            trigger: .init(type: .manual, config: [:]),
            taskMode: .none,
            model: nil,
            permissionsScope: .projectVisible
        )
    )

    let created = await fixture.router.handle(
        method: "POST",
        path: "/v1/projects/\(fixture.projectID)/automations",
        body: createBody
    )
    #expect(created.status == 201)
}
```

- [ ] **Step 2: Run the focused router test and verify it fails**

Run: `swift test --filter ProjectAutomationsAPIRouterTests`

Expected: FAIL with compile errors because `ProjectAutomationsAPIRouter` does not exist.

- [ ] **Step 3: Implement the project automation router**

```swift
struct ProjectAutomationsAPIRouter: APIRouter {
    private let service: CoreService

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/projects/:projectId/automations", metadata: RouteMetadata(summary: "List project automations", description: "Returns automation definitions for a project", tags: ["Automations"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            return CoreRouter.encodable(status: .ok, payload: try await service.listAutomationDefinitions(projectID: projectId))
        }
    }
}
```
```swift
router.post("/v1/projects/:projectId/automations/:automationId/run", metadata: RouteMetadata(summary: "Run automation manually", description: "Starts a manual automation run", tags: ["Automations"])) { request in
    let projectId = request.pathParam("projectId") ?? ""
    let automationId = request.pathParam("automationId") ?? ""
    guard let body = request.body,
          let payload = CoreRouter.decode(body, as: AutomationManualRunRequest.self)
    else {
        return CoreRouter.json(status: .badRequest, payload: ["error": ErrorCode.invalidBody])
    }
    return CoreRouter.encodable(status: .created, payload: try await service.startAutomationRun(projectID: projectId, automationID: automationId, request: payload))
}
```

- [ ] **Step 4: Run router tests and existing workflow router tests**

Run: `swift test --filter ProjectAutomationsAPIRouterTests`

Expected: PASS.

Run: `swift test --filter ProjectWorkflowsAPIRouterTests`

Expected: PASS, confirming automation routes did not regress workflow routes.

- [ ] **Step 5: Commit the automation router layer**

```bash
git add Sources/sloppy/Gateway/Routers/ProjectAutomationsAPIRouter.swift Tests/sloppyTests/ProjectAutomationsAPIRouterTests.swift
git commit -m "feat: add project automation routes"
```

### Task 6: Add Dashboard Automations Tab and Run Inspector

**Files:**
- Modify: `Dashboard/src/shared/api/coreApi.ts`
- Modify: `Dashboard/src/api.ts`
- Modify: `Dashboard/src/app/routing/dashboardRouteAdapter.ts`
- Modify: `Dashboard/src/views/Projects/utils.js`
- Modify: `Dashboard/src/views/ProjectsView.jsx`
- Create: `Dashboard/src/views/Projects/ProjectAutomationsTab.tsx`
- Modify: `Dashboard/src/styles/projects.css`

**Interfaces:**
- Consumes:
  - `/v1/projects/:projectId/automations`
  - `/v1/projects/:projectId/automations/:automationId/run`
  - `/v1/projects/:projectId/automation-runs`
- Produces:
  - `fetchProjectAutomations(projectId)`
  - `createProjectAutomation(projectId, payload)`
  - `updateProjectAutomation(projectId, automationId, payload)`
  - `deleteProjectAutomation(projectId, automationId)`
  - `runProjectAutomation(projectId, automationId, payload)`
  - `fetchProjectAutomationRuns(projectId)`

- [ ] **Step 1: Add API client tests by first wiring the client surface**

```ts
fetchProjectAutomations: async (projectId) => {
  const response = await requestJson<AnyRecord[]>({
    path: `/v1/projects/${encodeURIComponent(projectId)}/automations`
  });
  if (!response.ok || !Array.isArray(response.data)) return null;
  return response.data;
},
runProjectAutomation: async (projectId, automationId, payload) => {
  const response = await requestJson<AnyRecord, AnyRecord>({
    path: `/v1/projects/${encodeURIComponent(projectId)}/automations/${encodeURIComponent(automationId)}/run`,
    method: "POST",
    body: payload
  });
  if (!response.ok) return null;
  return response.data;
},
```

- [ ] **Step 2: Create the project Automations tab component**

```tsx
export function ProjectAutomationsTab({ project }: { project: AnyRecord }) {
  const [automations, setAutomations] = useState<AnyRecord[]>([]);
  const [runs, setRuns] = useState<AnyRecord[]>([]);
  const [selectedAutomationId, setSelectedAutomationId] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      const [automationList, runList] = await Promise.all([
        fetchProjectAutomations(project.id),
        fetchProjectAutomationRuns(project.id)
      ]);
      if (cancelled) return;
      setAutomations(Array.isArray(automationList) ? automationList : []);
      setRuns(Array.isArray(runList) ? runList : []);
    }
    void load();
    return () => {
      cancelled = true;
    };
  }, [project.id]);

  return <section className="project-automations-shell">...</section>;
}
```

- [ ] **Step 3: Wire routing and tab metadata**

```js
export const PROJECT_TABS = [
  { id: "overview", title: "Overview" },
  { id: "tasks", title: "Tasks" },
  { id: "workflows", title: "Workflows" },
  { id: "automations", title: "Automations" }
];
```

- [ ] **Step 4: Add focused CSS for the new editor and run list**

```css
.project-automations-shell {
  display: grid;
  gap: 16px;
}

.project-automations-grid {
  display: grid;
  grid-template-columns: 280px minmax(0, 1fr) 320px;
  gap: 16px;
}
```

- [ ] **Step 5: Run frontend verification**

Run: `cd Dashboard && npm run typecheck`

Expected: success with no TypeScript errors.

Run: `cd Dashboard && npm run build`

Expected: Vite production build completes successfully.

- [ ] **Step 6: Commit the Dashboard work**

```bash
git add Dashboard/src/shared/api/coreApi.ts Dashboard/src/api.ts Dashboard/src/app/routing/dashboardRouteAdapter.ts Dashboard/src/views/Projects/utils.js Dashboard/src/views/ProjectsView.jsx Dashboard/src/views/Projects/ProjectAutomationsTab.tsx Dashboard/src/styles/projects.css
git commit -m "feat: add dashboard automations tab"
```

## Self-Review

- **Spec coverage:** This plan covers the agreed MVP: project-scoped automation definitions, manual/cron/webhook/GitHub PR+review triggers, one-project/one-repo binding, optional task mode, existing workflow engine reuse, API surface, persistence, and Dashboard UI. Deferred items from the spec remain deferred here: Slack, multi-repo, service accounts, per-automation memory, richer GitHub trigger families.
- **Placeholder scan:** No `TODO`, `TBD`, or “implement later” placeholders remain. Each task names exact files, signatures, tests, and commands.
- **Type consistency:** The plan consistently uses `AutomationDefinition`, `AutomationDefinitionUpsertRequest`, `AutomationRun`, `AutomationRunDetail`, `AutomationTriggerPayload`, `GitHubAutomationEventRequest`, `AutomationTaskMode`, and `ProjectAutomationsAPIRouter` across models, service, routers, and UI.

Plan complete and saved to `docs/superpowers/plans/2026-06-28-automations.md`. Two execution options:

1. Subagent-Driven (recommended) - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. Inline Execution - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
