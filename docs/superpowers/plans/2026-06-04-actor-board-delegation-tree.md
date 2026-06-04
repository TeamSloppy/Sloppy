# Actor Board Delegation Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Delegation Tree mode to Actor Board so users can build and validate multi-agent swarm trees backed by the existing swarm runtime.

**Architecture:** The backend adds shared preview DTOs, a pure preview builder that mirrors `SwarmCoordinator` semantics, and a `POST /v1/actors/delegation-tree/preview` endpoint. The Dashboard adds a Map/Delegation Tree mode switch, defaults tree-mode links to `task + hierarchical + one_way`, and renders root preview validation in the existing Actors inspector.

**Tech Stack:** Swift 6.2, Swift Testing, existing CoreRouter/APIRouter patterns, React 19/TypeScript Vite Dashboard, existing ActorsView CSS and API client.

---

### Task 1: Backend Preview Models And Service

**Files:**
- Modify: `Sources/Protocols/APIModels.swift`
- Modify: `Sources/sloppy/CoreService+ActorBoard.swift`
- Test: `Tests/sloppyTests/ActorDelegationTreePreviewTests.swift`

- [ ] **Step 1: Write failing backend tests**

Create `Tests/sloppyTests/ActorDelegationTreePreviewTests.swift` with tests that build an `ActorBoardSnapshot` in memory and call the new preview builder through `CoreService.previewActorDelegationTree(board:rootActorId:)`.

Required cases:

```swift
@Test
func delegationTreePreviewReturnsBranchingLevels()

@Test
func delegationTreePreviewBlocksRootWithoutChildren()

@Test
func delegationTreePreviewBlocksReachableCycle()

@Test
func delegationTreePreviewBlocksNonAgentExecutionTarget()

@Test
func delegationTreePreviewWarnsAboutIgnoredTwoWayTaskLink()
```

- [ ] **Step 2: Run tests and confirm compile failure**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-mod-cache SWIFT_MODULE_CACHE_PATH=/tmp/clang-mod-cache swift test --filter ActorDelegationTreePreviewTests -Xswiftc -module-cache-path -Xswiftc /tmp/clang-mod-cache
```

Expected: FAIL because preview DTOs and `previewActorDelegationTree` do not exist.

- [ ] **Step 3: Add shared DTOs**

In `Sources/Protocols/APIModels.swift`, immediately after `ActorRouteResponse`, add:

```swift
public enum ActorDelegationTreeStatus: String, Codable, Sendable, Equatable {
    case valid
    case invalid
}

public enum ActorDelegationTreeIssueSeverity: String, Codable, Sendable, Equatable {
    case error
    case warning
}

public struct ActorDelegationTreeIssue: Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    public var severity: ActorDelegationTreeIssueSeverity
    public var actorId: String?
    public var linkId: String?

    public init(
        code: String,
        message: String,
        severity: ActorDelegationTreeIssueSeverity,
        actorId: String? = nil,
        linkId: String? = nil
    ) {
        self.code = code
        self.message = message
        self.severity = severity
        self.actorId = actorId
        self.linkId = linkId
    }
}

public struct ActorDelegationTreeLevelActor: Codable, Sendable, Equatable {
    public var actorId: String
    public var displayName: String
    public var linkedAgentId: String

    public init(actorId: String, displayName: String, linkedAgentId: String) {
        self.actorId = actorId
        self.displayName = displayName
        self.linkedAgentId = linkedAgentId
    }
}

public struct ActorDelegationTreePreviewRequest: Codable, Sendable {
    public var rootActorId: String

    public init(rootActorId: String) {
        self.rootActorId = rootActorId
    }
}

public struct ActorDelegationTreePreviewResponse: Codable, Sendable, Equatable {
    public var status: ActorDelegationTreeStatus
    public var rootActorId: String
    public var levels: [[ActorDelegationTreeLevelActor]]
    public var errors: [ActorDelegationTreeIssue]
    public var warnings: [ActorDelegationTreeIssue]
    public var previewedAt: Date

    public init(
        status: ActorDelegationTreeStatus,
        rootActorId: String,
        levels: [[ActorDelegationTreeLevelActor]],
        errors: [ActorDelegationTreeIssue],
        warnings: [ActorDelegationTreeIssue],
        previewedAt: Date = Date()
    ) {
        self.status = status
        self.rootActorId = rootActorId
        self.levels = levels
        self.errors = errors
        self.warnings = warnings
        self.previewedAt = previewedAt
    }
}
```

- [ ] **Step 4: Implement preview builder**

In `Sources/sloppy/CoreService+ActorBoard.swift`, add `public func previewActorDelegationTree(request:)` and internal `func previewActorDelegationTree(board:rootActorId:)`.

Rules:

- normalize root with `normalizedActorEntityID`;
- return invalid preview for missing/unknown/non-agent root;
- inspect reachable `task + hierarchical + one_way` links;
- require all reachable execution nodes to be agent nodes with non-empty `linkedAgentId`;
- return levels of `ActorDelegationTreeLevelActor`;
- detect cycles using `SwarmCoordinator.buildHierarchy`;
- include warnings for ignored two-way hierarchical task links and disconnected execution roots.

- [ ] **Step 5: Run backend tests**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-mod-cache SWIFT_MODULE_CACHE_PATH=/tmp/clang-mod-cache swift test --filter ActorDelegationTreePreviewTests -Xswiftc -module-cache-path -Xswiftc /tmp/clang-mod-cache
```

Expected: PASS.

### Task 2: Backend Route And API Client

**Files:**
- Modify: `Sources/sloppy/Gateway/Routers/ActorsAPIRouter.swift`
- Modify: `Dashboard/src/shared/api/coreApi.ts`
- Modify: `Dashboard/src/api.ts`
- Test: `Tests/sloppyTests/ActorsAPIRouterTests.swift` or new focused router test if no suitable file exists.

- [ ] **Step 1: Add route test**

Add a router test that posts `{"rootActorId":"agent:lead"}` to `/v1/actors/delegation-tree/preview` and expects a JSON response with `status`.

- [ ] **Step 2: Run route test and confirm failure**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-mod-cache SWIFT_MODULE_CACHE_PATH=/tmp/clang-mod-cache swift test --filter ActorsAPIRouterTests -Xswiftc -module-cache-path -Xswiftc /tmp/clang-mod-cache
```

Expected: FAIL because the route is not registered.

- [ ] **Step 3: Implement route**

In `ActorsAPIRouter.configure`, add:

```swift
router.post("/v1/actors/delegation-tree/preview", metadata: RouteMetadata(summary: "Preview actor delegation tree", description: "Validates and previews the saved Actor Board delegation tree for a root actor", tags: ["Actors"])) { request in
    guard let body = request.body,
          let payload = CoreRouter.decode(body, as: ActorDelegationTreePreviewRequest.self)
    else {
        return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidActorPayload])
    }

    do {
        let preview = try await service.previewActorDelegationTree(request: payload)
        return CoreRouter.encodable(status: HTTPStatus.ok, payload: preview)
    } catch let error as CoreService.ActorBoardError {
        return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorRouteFailed)
    } catch {
        return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorRouteFailed])
    }
}
```

- [ ] **Step 4: Add Dashboard API method**

Add `previewActorDelegationTree(payload)` to `CoreApi` in `Dashboard/src/shared/api/coreApi.ts`, implemented with `requestJson` against `/v1/actors/delegation-tree/preview`, and re-export it from `Dashboard/src/api.ts`.

- [ ] **Step 5: Run backend route tests**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-mod-cache SWIFT_MODULE_CACHE_PATH=/tmp/clang-mod-cache swift test --filter ActorsAPIRouterTests -Xswiftc -module-cache-path -Xswiftc /tmp/clang-mod-cache
```

Expected: PASS.

### Task 3: Dashboard Delegation Tree Mode

**Files:**
- Modify: `Dashboard/src/features/actors/ActorsView.tsx`
- Modify: `Dashboard/src/styles/actors.css`

- [ ] **Step 1: Add local UI state**

In `ActorsView`, add state for:

```ts
const [boardMode, setBoardMode] = useState("map");
const [delegationRootId, setDelegationRootId] = useState(null);
const [delegationPreview, setDelegationPreview] = useState(null);
const [isPreviewLoading, setIsPreviewLoading] = useState(false);
```

- [ ] **Step 2: Add preview loader**

Add `loadDelegationPreview(rootId)` that calls `previewActorDelegationTree({ rootActorId: rootId })`, stores the response, and shows `"Delegation tree preview updated"` or `"Delegation tree preview failed"`.

- [ ] **Step 3: Default tree-mode links**

Change `createLink` so when `boardMode === "delegation"` it creates links with:

```js
direction: "one_way",
relationship: "hierarchical",
communicationType: "task"
```

Map mode keeps existing `linkDirection`, `linkRelationship`, and `linkCommunicationType` behavior.

- [ ] **Step 4: Render mode switch and preview panel**

Add a segmented Map/Delegation Tree control near the board toolbar. In the inspector, render selected root, preview levels, errors, and warnings when `boardMode === "delegation"`.

- [ ] **Step 5: Add CSS**

Extend `Dashboard/src/styles/actors.css` with compact styles for:

```css
.actors-mode-switch
.actors-mode-button
.actors-delegation-panel
.actors-delegation-level
.actors-delegation-issue
.actors-delegation-issue.error
.actors-delegation-issue.warning
```

- [ ] **Step 6: Build Dashboard**

Run:

```bash
npm run build
```

from `Dashboard/`.

Expected: PASS.

### Task 4: Final Verification

**Files:**
- No new files.

- [ ] **Step 1: Run narrow backend tests**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-mod-cache SWIFT_MODULE_CACHE_PATH=/tmp/clang-mod-cache swift test --filter ActorDelegationTreePreviewTests -Xswiftc -module-cache-path -Xswiftc /tmp/clang-mod-cache
```

Expected: PASS.

- [ ] **Step 2: Run existing swarm tests**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-mod-cache SWIFT_MODULE_CACHE_PATH=/tmp/clang-mod-cache swift test --filter SwarmCoordinatorTests -Xswiftc -module-cache-path -Xswiftc /tmp/clang-mod-cache
```

Expected: PASS.

- [ ] **Step 3: Build sloppy**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-mod-cache SWIFT_MODULE_CACHE_PATH=/tmp/clang-mod-cache swift build -Xswiftc -module-cache-path -Xswiftc /tmp/clang-mod-cache
```

Expected: PASS.

- [ ] **Step 4: Review git diff**

Run:

```bash
git diff --stat
git diff --check
```

Expected: no whitespace errors and only intended files changed.
