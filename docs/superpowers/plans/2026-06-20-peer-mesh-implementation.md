# Peer Mesh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the first SloppyNode Mesh slice from coordinator-owned state mutation toward signed peer events with deterministic projection, while preserving current mesh APIs and task dispatch behavior.

**Architecture:** Add signed mesh events in `SloppyNodeCore`, persist them beside the existing `MeshState`, derive projection through a `NodeMeshProjection`, and route task lifecycle changes through event ingestion. Existing Core API and CLI commands remain compatibility surfaces backed by the projection, while new event endpoints and WebSocket frames enable peer sync.

**Tech Stack:** Swift 6.2, SwiftPM, Swift Testing, `SloppyNodeCore`, `sloppy` Core API/router, existing Ed25519 helpers in `NodeIdentityGenerator`, existing `JSONValue` and `JSONValueCoder`.

## Global Constraints

- Preserve current `SloppyNodeCore` public models unless a task explicitly extends them with backward-compatible fields.
- Do not make relay nodes authority; every state-changing mesh event must be signed and verified.
- Do not infer routing, task state, intent, or completion from free-form text.
- Keep existing `/v1/node/mesh/nodes`, `/shared-projects`, `/tasks`, and `/audit-log` behavior stable.
- Use Swift Testing macros with deterministic arrange/act/assert tests.
- Run the narrow test command after each task, then run `swift test --filter SloppyNodeCoreTests` and `swift build -c release --product SloppyNode` after the final task.

---

## File Structure

- Create `Sources/NodeCore/NodeMeshEvent.swift`: signed event models, event type enum, signing payload canonicalization, verify helpers, reject reasons.
- Create `Sources/NodeCore/NodeMeshProjection.swift`: deterministic projection from `[SignedMeshEvent]` to `MeshState`.
- Modify `Sources/NodeCore/NodeMesh.swift`: extend `MeshState` with event log fields; add event-backed store methods while preserving current method names.
- Modify `Sources/NodeCore/NodeMeshClient.swift`: understand `event.publish`, `event.batch`, `event.ack`, and `event.reject` envelopes in the local response path.
- Modify `Sources/sloppy/Gateway/NodeMeshRelay.swift`: ingest signed events, route accepted event envelopes, retain mailbox events for offline peers.
- Modify `Sources/sloppy/CoreService+NodeMesh.swift`: expose event list/ingest/projection/sync methods.
- Modify `Sources/sloppy/Gateway/Routers/NodeMeshAPIRouter.swift`: add event and projection endpoints.
- Modify `Sources/SloppyNodeCLI/NodeCommand.swift`: add a narrow event inspection/publish smoke path for operators.
- Add tests in `Tests/SloppyNodeCoreTests/NodeMeshEventTests.swift`, `Tests/SloppyNodeCoreTests/NodeMeshProjectionTests.swift`, and extend existing mesh store/client tests.
- Extend `Tests/sloppyTests/CoreRouterTests.swift` or `CoreHTTPServerTests.swift` for event API and relay behavior.
- Update `docs/guides/mesh.md` after behavior is implemented.

---

### Task 1: Signed Mesh Event Model

**Files:**
- Create: `Sources/NodeCore/NodeMeshEvent.swift`
- Test: `Tests/SloppyNodeCoreTests/NodeMeshEventTests.swift`

**Interfaces:**
- Consumes: `NodeIdentity`, `NodeIdentityGenerator.sign(challenge:privateKey:)`, `NodeIdentityGenerator.verify(signature:challenge:publicKey:)`, `JSONValue`, `JSONValueCoder`.
- Produces:
  - `public enum MeshEventType: String, Codable, Sendable, CaseIterable`
  - `public struct MeshEvent: Codable, Sendable, Equatable`
  - `public struct SignedMeshEvent: Codable, Sendable, Equatable`
  - `public enum MeshEventVerificationError: LocalizedError, Equatable, Sendable`
  - `public enum MeshEventSigner`

- [ ] **Step 1: Write failing signed event tests**

Add `Tests/SloppyNodeCoreTests/NodeMeshEventTests.swift`:

```swift
import Foundation
import Protocols
@testable import SloppyNodeCore
import Testing

@Suite("NodeMeshEvent")
struct NodeMeshEventTests {
    @Test("signed mesh event verifies with actor public key")
    func signedMeshEventVerifiesWithActorPublicKey() throws {
        let identity = NodeIdentityGenerator.makeIdentity(
            name: "Home",
            roles: ["worker"],
            capabilities: ["git"]
        )
        let event = MeshEvent(
            type: .taskCreated,
            actorNodeId: identity.nodeId,
            targetNodeId: nil,
            projectId: "sp_sloppy",
            logicalTime: 1,
            payload: .object([
                "taskId": .string("mesh_task_1"),
                "title": .string("Run tests"),
            ])
        )

        let signed = try MeshEventSigner.sign(event, identity: identity)

        #expect(signed.event.actorNodeId == identity.nodeId)
        #expect(try MeshEventSigner.verify(signed, publicKey: identity.publicKey) == true)
    }

    @Test("tampered signed mesh event fails verification")
    func tamperedSignedMeshEventFailsVerification() throws {
        let identity = NodeIdentityGenerator.makeIdentity(
            name: "Home",
            roles: ["worker"],
            capabilities: ["git"]
        )
        let event = MeshEvent(
            type: .taskCreated,
            actorNodeId: identity.nodeId,
            projectId: "sp_sloppy",
            logicalTime: 1,
            payload: .object(["title": .string("Run tests")])
        )
        var signed = try MeshEventSigner.sign(event, identity: identity)
        signed.event.payload = .object(["title": .string("Different")])

        #expect(try MeshEventSigner.verify(signed, publicKey: identity.publicKey) == false)
    }

    @Test("event signing payload is stable")
    func eventSigningPayloadIsStable() throws {
        let event = MeshEvent(
            id: "evt_1",
            type: .projectCreated,
            actorNodeId: "node_home",
            targetNodeId: nil,
            projectId: "sp_sloppy",
            logicalTime: 42,
            wallTime: Date(timeIntervalSince1970: 1_800_000_000),
            causalParents: ["evt_0"],
            payload: .object(["name": .string("Sloppy")])
        )

        let data = try MeshEventSigner.signingData(for: event)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains(#""id":"evt_1""#))
        #expect(text.contains(#""type":"project.created""#))
        #expect(text.contains(#""logicalTime":42"#))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter NodeMeshEventTests
```

Expected: FAIL because `MeshEvent`, `SignedMeshEvent`, and `MeshEventSigner` do not exist.

- [ ] **Step 3: Add event model and signing helpers**

Create `Sources/NodeCore/NodeMeshEvent.swift`:

```swift
import Foundation
import Protocols

public enum MeshEventType: String, Codable, Sendable, CaseIterable {
    case nodeAnnounced = "node.announced"
    case nodeStatusChanged = "node.status.changed"
    case nodeAliasUpdated = "node.alias.updated"
    case projectCreated = "project.created"
    case projectUpdated = "project.updated"
    case projectMemberAdded = "project.member.added"
    case projectMemberRemoved = "project.member.removed"
    case taskCreated = "task.created"
    case taskAssigned = "task.assigned"
    case taskStatusUpdated = "task.status.updated"
    case messageSent = "message.sent"
    case aclGranted = "acl.granted"
    case aclRevoked = "acl.revoked"
}

public struct MeshEvent: Codable, Sendable, Equatable {
    public var id: String
    public var type: MeshEventType
    public var actorNodeId: String
    public var targetNodeId: String?
    public var projectId: String?
    public var logicalTime: UInt64
    public var wallTime: Date
    public var causalParents: [String]
    public var payload: JSONValue

    public init(
        id: String = "mesh_evt_" + UUID().uuidString,
        type: MeshEventType,
        actorNodeId: String,
        targetNodeId: String? = nil,
        projectId: String? = nil,
        logicalTime: UInt64,
        wallTime: Date = Date(),
        causalParents: [String] = [],
        payload: JSONValue = .object([:])
    ) {
        self.id = id
        self.type = type
        self.actorNodeId = actorNodeId
        self.targetNodeId = targetNodeId
        self.projectId = projectId
        self.logicalTime = logicalTime
        self.wallTime = wallTime
        self.causalParents = causalParents
        self.payload = payload
    }
}

public struct SignedMeshEvent: Codable, Sendable, Equatable {
    public var event: MeshEvent
    public var actorPublicKey: String
    public var signature: String

    public init(event: MeshEvent, actorPublicKey: String, signature: String) {
        self.event = event
        self.actorPublicKey = actorPublicKey
        self.signature = signature
    }
}

public enum MeshEventVerificationError: LocalizedError, Equatable, Sendable {
    case actorMismatch
    case invalidSignature
    case signingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .actorMismatch:
            "Mesh event actor does not match the expected identity."
        case .invalidSignature:
            "Mesh event signature is invalid."
        case .signingFailed(let message):
            "Mesh event signing failed: \(message)"
        }
    }
}

public enum MeshEventSigner {
    public static func sign(_ event: MeshEvent, identity: NodeIdentity) throws -> SignedMeshEvent {
        guard event.actorNodeId == identity.nodeId else {
            throw MeshEventVerificationError.actorMismatch
        }
        do {
            let signature = try NodeIdentityGenerator.sign(
                challenge: signingData(for: event),
                privateKey: identity.privateKey
            )
            return SignedMeshEvent(
                event: event,
                actorPublicKey: identity.publicKey,
                signature: signature
            )
        } catch {
            throw MeshEventVerificationError.signingFailed(error.localizedDescription)
        }
    }

    public static func verify(_ signed: SignedMeshEvent, publicKey: String) throws -> Bool {
        guard signed.actorPublicKey == publicKey else {
            return false
        }
        return NodeIdentityGenerator.verify(
            signature: signed.signature,
            challenge: signingData(for: signed.event),
            publicKey: publicKey
        )
    }

    public static func signingData(for event: MeshEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(event)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter NodeMeshEventTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NodeCore/NodeMeshEvent.swift Tests/SloppyNodeCoreTests/NodeMeshEventTests.swift
git commit -m "feat: add signed mesh events"
```

---

### Task 2: Event Log Persistence and Idempotent Ingestion

**Files:**
- Modify: `Sources/NodeCore/NodeMesh.swift`
- Test: `Tests/SloppyNodeCoreTests/NodeMeshStoreTests.swift`

**Interfaces:**
- Consumes: `SignedMeshEvent`, `MeshEventSigner.verify(_:publicKey:)`.
- Produces:
  - `MeshState.events: [SignedMeshEvent]`
  - `MeshState.eventCursors: [String: String]`
  - `NodeMeshStore.appendEvent(_:expectedActorPublicKey:) throws -> SignedMeshEvent`
  - `NodeMeshStore.listEvents(after:limit:) throws -> [SignedMeshEvent]`

- [ ] **Step 1: Write failing store event tests**

Append to `NodeMeshStoreTests`:

```swift
@Test("mesh store appends signed events idempotently")
func meshStoreAppendsSignedEventsIdempotently() throws {
    let store = NodeMeshStore(stateURL: temporaryStateURL())
    let identity = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
    let event = MeshEvent(
        id: "evt_task_create",
        type: .taskCreated,
        actorNodeId: identity.nodeId,
        projectId: "sp_sloppy",
        logicalTime: 1,
        payload: .object(["title": .string("Run build")])
    )
    let signed = try MeshEventSigner.sign(event, identity: identity)

    _ = try store.appendEvent(signed, expectedActorPublicKey: identity.publicKey)
    _ = try store.appendEvent(signed, expectedActorPublicKey: identity.publicKey)

    let state = try store.load()
    #expect(state.events.map(\.event.id) == ["evt_task_create"])
    #expect(state.auditLog.last?.action == "event.append")
}

@Test("mesh store rejects signed event with wrong public key")
func meshStoreRejectsSignedEventWithWrongPublicKey() throws {
    let store = NodeMeshStore(stateURL: temporaryStateURL())
    let identity = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
    let other = NodeIdentityGenerator.makeIdentity(name: "Other", roles: ["client"], capabilities: ["git"])
    let signed = try MeshEventSigner.sign(
        MeshEvent(type: .taskCreated, actorNodeId: identity.nodeId, logicalTime: 1),
        identity: identity
    )

    #expect(throws: MeshEventVerificationError.invalidSignature) {
        _ = try store.appendEvent(signed, expectedActorPublicKey: other.publicKey)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter NodeMeshStoreTests/meshStoreAppendsSignedEventsIdempotently
```

Expected: FAIL because `MeshState.events` and `appendEvent` do not exist.

- [ ] **Step 3: Extend `MeshState` and `NodeMeshStore`**

Modify `MeshState` in `Sources/NodeCore/NodeMesh.swift`:

```swift
public struct MeshState: Codable, Sendable, Equatable {
    public var networkId: String
    public var networkName: String
    public var nodes: [MeshNodeRecord]
    public var invites: [MeshInvite]
    public var sharedProjects: [SharedProjectRecord]
    public var tasks: [MeshTaskRecord]
    public var envelopes: [MeshEnvelope]
    public var auditLog: [MeshAuditLogEntry]
    public var events: [SignedMeshEvent]
    public var eventCursors: [String: String]

    public init(
        networkId: String = "personal",
        networkName: String = "Personal Mesh",
        nodes: [MeshNodeRecord] = [],
        invites: [MeshInvite] = [],
        sharedProjects: [SharedProjectRecord] = [],
        tasks: [MeshTaskRecord] = [],
        envelopes: [MeshEnvelope] = [],
        auditLog: [MeshAuditLogEntry] = [],
        events: [SignedMeshEvent] = [],
        eventCursors: [String: String] = [:]
    ) {
        self.networkId = networkId
        self.networkName = networkName
        self.nodes = nodes
        self.invites = invites
        self.sharedProjects = sharedProjects
        self.tasks = tasks
        self.envelopes = envelopes
        self.auditLog = auditLog
        self.events = events
        self.eventCursors = eventCursors
    }
}
```

Add store methods near `listTasks`:

```swift
@discardableResult
public func appendEvent(
    _ signed: SignedMeshEvent,
    expectedActorPublicKey: String
) throws -> SignedMeshEvent {
    var state = try load()
    guard try MeshEventSigner.verify(signed, publicKey: expectedActorPublicKey) else {
        state.auditLog.append(MeshAuditLogEntry(
            actor: signed.event.actorNodeId,
            action: "event.append",
            project: signed.event.projectId,
            allowed: false,
            message: "invalid_signature"
        ))
        try save(state)
        throw MeshEventVerificationError.invalidSignature
    }
    if state.events.contains(where: { $0.event.id == signed.event.id }) {
        return signed
    }
    state.events.append(signed)
    state.auditLog.append(MeshAuditLogEntry(
        actor: signed.event.actorNodeId,
        target: signed.event.targetNodeId,
        action: "event.append",
        project: signed.event.projectId,
        allowed: true,
        message: signed.event.type.rawValue
    ))
    try save(state)
    return signed
}

public func listEvents(after cursor: String? = nil, limit: Int = 100) throws -> [SignedMeshEvent] {
    let events = try load().events
    let startIndex: Int
    if let cursor, let index = events.firstIndex(where: { $0.event.id == cursor }) {
        startIndex = events.index(after: index)
    } else {
        startIndex = events.startIndex
    }
    guard startIndex < events.endIndex else {
        return []
    }
    return Array(events[startIndex...].prefix(max(1, limit)))
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter NodeMeshStoreTests/meshStore
```

Expected: PASS for the two new tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NodeCore/NodeMesh.swift Tests/SloppyNodeCoreTests/NodeMeshStoreTests.swift
git commit -m "feat: persist mesh event log"
```

---

### Task 3: Deterministic Projection for Nodes, Projects, ACL, and Tasks

**Files:**
- Create: `Sources/NodeCore/NodeMeshProjection.swift`
- Modify: `Sources/NodeCore/NodeMesh.swift`
- Test: `Tests/SloppyNodeCoreTests/NodeMeshProjectionTests.swift`

**Interfaces:**
- Consumes: `[SignedMeshEvent]`, current `MeshState`, `MeshPermission`, `SharedProjectRecord`, `MeshTaskRecord`.
- Produces:
  - `public enum NodeMeshProjection`
  - `public static func project(events:base:) throws -> MeshState`
  - `NodeMeshStore.projectedState() throws -> MeshState`

- [ ] **Step 1: Write failing projection tests**

Create `Tests/SloppyNodeCoreTests/NodeMeshProjectionTests.swift`:

```swift
import Foundation
import Protocols
@testable import SloppyNodeCore
import Testing

@Suite("NodeMeshProjection")
struct NodeMeshProjectionTests {
    @Test("projection builds task lifecycle from signed events")
    func projectionBuildsTaskLifecycleFromSignedEvents() throws {
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        let projectId = "sp_sloppy"
        let events = try [
            signed(.projectCreated, actor: work, projectId: projectId, logicalTime: 1, payload: [
                "id": .string(projectId),
                "name": .string("Sloppy"),
                "repoUrl": .string("git@example.com:sloppy.git"),
                "defaultBranch": .string("main"),
            ]),
            signed(.projectMemberAdded, actor: work, target: work.nodeId, projectId: projectId, logicalTime: 2, payload: [
                "nodeId": .string(work.nodeId),
                "localRepoPath": .string("/work/sloppy"),
                "role": .string("controller"),
                "permissions": .array([
                    .string(MeshPermission.projectRead.rawValue),
                    .string(MeshPermission.taskCreate.rawValue),
                    .string(MeshPermission.taskAssign.rawValue),
                ]),
            ]),
            signed(.projectMemberAdded, actor: work, target: home.nodeId, projectId: projectId, logicalTime: 3, payload: [
                "nodeId": .string(home.nodeId),
                "localRepoPath": .string("/home/sloppy"),
                "role": .string("worker"),
                "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
            ]),
            signed(.taskCreated, actor: work, projectId: projectId, logicalTime: 4, payload: [
                "taskId": .string("mesh_task_1"),
                "title": .string("Run build"),
            ]),
            signed(.taskAssigned, actor: work, target: home.nodeId, projectId: projectId, logicalTime: 5, payload: [
                "taskId": .string("mesh_task_1"),
                "assignedNodeId": .string(home.nodeId),
            ]),
            signed(.taskStatusUpdated, actor: home, projectId: projectId, logicalTime: 6, payload: [
                "taskId": .string("mesh_task_1"),
                "status": .string(MeshTaskStatus.readyForReview.rawValue),
                "branch": .string("agent/home/mesh-task-1-run-build"),
                "summary": .string("Build passed."),
            ]),
        ]

        let state = try NodeMeshProjection.project(events: events, base: MeshState())

        let task = try #require(state.tasks.first)
        #expect(task.id == "mesh_task_1")
        #expect(task.assignedNodeId == home.nodeId)
        #expect(task.status == .readyForReview)
        #expect(task.branch == "agent/home/mesh-task-1-run-build")
        #expect(state.sharedProjects.first?.members.count == 2)
    }

    private func signed(
        _ type: MeshEventType,
        actor: NodeIdentity,
        target: String? = nil,
        projectId: String?,
        logicalTime: UInt64,
        payload: [String: JSONValue]
    ) throws -> SignedMeshEvent {
        try MeshEventSigner.sign(
            MeshEvent(
                type: type,
                actorNodeId: actor.nodeId,
                targetNodeId: target,
                projectId: projectId,
                logicalTime: logicalTime,
                payload: .object(payload)
            ),
            identity: actor
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter NodeMeshProjectionTests
```

Expected: FAIL because `NodeMeshProjection` does not exist.

- [ ] **Step 3: Implement projection**

Create `Sources/NodeCore/NodeMeshProjection.swift`:

```swift
import Foundation
import Protocols

public enum NodeMeshProjection {
    public static func project(events: [SignedMeshEvent], base: MeshState = MeshState()) throws -> MeshState {
        var state = base
        state.sharedProjects.removeAll()
        state.tasks.removeAll()
        for signed in events.sorted(by: eventSort) {
            apply(signed.event, to: &state)
        }
        return state
    }

    private static func eventSort(_ lhs: SignedMeshEvent, _ rhs: SignedMeshEvent) -> Bool {
        if lhs.event.logicalTime == rhs.event.logicalTime {
            return lhs.event.id < rhs.event.id
        }
        return lhs.event.logicalTime < rhs.event.logicalTime
    }

    private static func apply(_ event: MeshEvent, to state: inout MeshState) {
        switch event.type {
        case .projectCreated:
            applyProjectCreated(event, to: &state)
        case .projectUpdated:
            applyProjectUpdated(event, to: &state)
        case .projectMemberAdded:
            applyProjectMemberAdded(event, to: &state)
        case .projectMemberRemoved:
            applyProjectMemberRemoved(event, to: &state)
        case .taskCreated:
            applyTaskCreated(event, to: &state)
        case .taskAssigned:
            applyTaskAssigned(event, to: &state)
        case .taskStatusUpdated:
            applyTaskStatusUpdated(event, to: &state)
        default:
            break
        }
    }

    private static func applyProjectCreated(_ event: MeshEvent, to state: inout MeshState) {
        guard let payload = event.payload.asObject,
              let id = payload["id"]?.asString ?? event.projectId,
              let name = payload["name"]?.asString,
              let repoUrl = payload["repoUrl"]?.asString
        else { return }
        let project = SharedProjectRecord(
            id: id,
            name: name,
            repoUrl: repoUrl,
            defaultBranch: payload["defaultBranch"]?.asString ?? "main",
            createdAt: event.wallTime,
            updatedAt: event.wallTime
        )
        upsert(project, in: &state.sharedProjects)
    }

    private static func applyProjectUpdated(_ event: MeshEvent, to state: inout MeshState) {
        guard let projectId = event.projectId,
              let index = state.sharedProjects.firstIndex(where: { $0.id == projectId }),
              let payload = event.payload.asObject
        else { return }
        if let name = payload["name"]?.asString { state.sharedProjects[index].name = name }
        if let repoUrl = payload["repoUrl"]?.asString { state.sharedProjects[index].repoUrl = repoUrl }
        if let defaultBranch = payload["defaultBranch"]?.asString { state.sharedProjects[index].defaultBranch = defaultBranch }
        state.sharedProjects[index].updatedAt = event.wallTime
    }

    private static func applyProjectMemberAdded(_ event: MeshEvent, to state: inout MeshState) {
        guard let projectId = event.projectId,
              let index = state.sharedProjects.firstIndex(where: { $0.id == projectId }),
              let payload = event.payload.asObject,
              let nodeId = payload["nodeId"]?.asString,
              let localRepoPath = payload["localRepoPath"]?.asString
        else { return }
        let member = SharedProjectMember(
            nodeId: nodeId,
            actorId: payload["actorId"]?.asString,
            localRepoPath: localRepoPath,
            role: payload["role"]?.asString ?? "worker",
            permissions: stringArray(payload["permissions"])
        )
        if let memberIndex = state.sharedProjects[index].members.firstIndex(where: { $0.nodeId == nodeId }) {
            state.sharedProjects[index].members[memberIndex] = member
        } else {
            state.sharedProjects[index].members.append(member)
        }
        state.sharedProjects[index].updatedAt = event.wallTime
    }

    private static func applyProjectMemberRemoved(_ event: MeshEvent, to state: inout MeshState) {
        guard let projectId = event.projectId,
              let index = state.sharedProjects.firstIndex(where: { $0.id == projectId }),
              let nodeId = event.targetNodeId ?? event.payload.asObject?["nodeId"]?.asString
        else { return }
        state.sharedProjects[index].members.removeAll { $0.nodeId == nodeId }
        state.sharedProjects[index].updatedAt = event.wallTime
    }

    private static func applyTaskCreated(_ event: MeshEvent, to state: inout MeshState) {
        guard let payload = event.payload.asObject,
              let projectId = event.projectId,
              let taskId = payload["taskId"]?.asString,
              let title = payload["title"]?.asString
        else { return }
        let task = MeshTaskRecord(
            id: taskId,
            projectId: projectId,
            title: title,
            assignedNodeId: payload["assignedNodeId"]?.asString ?? "",
            status: .queued,
            createdAt: event.wallTime,
            updatedAt: event.wallTime
        )
        upsert(task, in: &state.tasks)
    }

    private static func applyTaskAssigned(_ event: MeshEvent, to state: inout MeshState) {
        guard let payload = event.payload.asObject,
              let taskId = payload["taskId"]?.asString,
              let index = state.tasks.firstIndex(where: { $0.id == taskId })
        else { return }
        state.tasks[index].assignedNodeId = payload["assignedNodeId"]?.asString ?? event.targetNodeId ?? state.tasks[index].assignedNodeId
        state.tasks[index].status = .dispatched
        state.tasks[index].updatedAt = event.wallTime
    }

    private static func applyTaskStatusUpdated(_ event: MeshEvent, to state: inout MeshState) {
        guard let payload = event.payload.asObject,
              let taskId = payload["taskId"]?.asString,
              let index = state.tasks.firstIndex(where: { $0.id == taskId }),
              let rawStatus = payload["status"]?.asString,
              let status = MeshTaskStatus(rawValue: rawStatus)
        else { return }
        state.tasks[index].status = status
        if let branch = payload["branch"]?.asString { state.tasks[index].branch = branch }
        if let commit = payload["commit"]?.asString { state.tasks[index].commit = commit }
        if let summary = payload["summary"]?.asString { state.tasks[index].summary = summary }
        state.tasks[index].updatedAt = event.wallTime
    }

    private static func upsert(_ project: SharedProjectRecord, in projects: inout [SharedProjectRecord]) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
    }

    private static func upsert(_ task: MeshTaskRecord, in tasks: inout [MeshTaskRecord]) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
    }

    private static func stringArray(_ value: JSONValue?) -> [String] {
        guard case let .array(values) = value else {
            return []
        }
        return values.compactMap(\.asString)
    }
}
```

Add to `NodeMeshStore`:

```swift
public func projectedState() throws -> MeshState {
    let state = try load()
    var projected = try NodeMeshProjection.project(events: state.events, base: state)
    projected.events = state.events
    projected.eventCursors = state.eventCursors
    projected.invites = state.invites
    projected.envelopes = state.envelopes
    projected.auditLog = state.auditLog
    return projected
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter NodeMeshProjectionTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NodeCore/NodeMeshProjection.swift Sources/NodeCore/NodeMesh.swift Tests/SloppyNodeCoreTests/NodeMeshProjectionTests.swift
git commit -m "feat: project mesh events into state"
```

---

### Task 4: Event-Backed Compatibility Methods for Projects and Tasks

**Files:**
- Modify: `Sources/NodeCore/NodeMesh.swift`
- Test: `Tests/SloppyNodeCoreTests/NodeMeshStoreTests.swift`

**Interfaces:**
- Consumes: `appendEvent`, `projectedState`, `MeshEventSigner.sign`.
- Produces:
  - overloads that accept `actorIdentity: NodeIdentity`
  - existing `createSharedProject`, `attachMember`, `dispatchTask`, `updateTaskStatus` continue to work in compatibility mode

- [ ] **Step 1: Write failing event-backed task test**

Append to `NodeMeshStoreTests`:

```swift
@Test("dispatch task with actor identity writes signed task events")
func dispatchTaskWithActorIdentityWritesSignedTaskEvents() throws {
    let store = NodeMeshStore(stateURL: temporaryStateURL())
    let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
    let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
    try store.registerNode(work)
    try store.registerNode(home)
    let project = try store.createSharedProject(
        id: "sp_sloppy",
        name: "Sloppy",
        repoUrl: "git@example.com:sloppy.git"
    )
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: work.nodeId,
        localRepoPath: "/work/sloppy",
        role: "controller",
        permissions: [MeshPermission.taskCreate.rawValue, MeshPermission.taskAssign.rawValue]
    )
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: home.nodeId,
        localRepoPath: "/home/sloppy",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )

    let task = try store.dispatchTask(
        projectIdOrName: project.id,
        title: "Run build",
        assignedNodeId: home.nodeId,
        actorIdentity: work
    )

    let state = try store.load()
    #expect(task.status == .dispatched)
    #expect(state.events.map(\.event.type).contains(.taskCreated))
    #expect(state.events.map(\.event.type).contains(.taskAssigned))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter NodeMeshStoreTests/dispatchTaskWithActorIdentityWritesSignedTaskEvents
```

Expected: FAIL because the `actorIdentity` overload does not exist.

- [ ] **Step 3: Add event-backed overloads**

Add to `NodeMeshStore`:

```swift
@discardableResult
public func dispatchTask(
    projectIdOrName: String,
    title: String,
    assignedNodeId: String,
    actorIdentity: NodeIdentity
) throws -> MeshTaskRecord {
    let state = try projectedState()
    guard let project = state.sharedProjects.first(where: { $0.id == projectIdOrName || $0.name == projectIdOrName }) else {
        throw NodeMeshStoreError.projectMissing(projectIdOrName)
    }
    guard state.nodes.contains(where: { $0.id == assignedNodeId }) else {
        throw NodeMeshStoreError.nodeMissing(assignedNodeId)
    }
    guard let actorMember = project.members.first(where: { $0.nodeId == actorIdentity.nodeId }),
          actorMember.permissions.contains(MeshPermission.taskCreate.rawValue),
          actorMember.permissions.contains(MeshPermission.taskAssign.rawValue)
    else {
        throw NodeMeshStoreError.permissionDenied("task.dispatch")
    }
    let taskId = "mesh_task_" + UUID().uuidString
    let created = MeshEvent(
        type: .taskCreated,
        actorNodeId: actorIdentity.nodeId,
        projectId: project.id,
        logicalTime: nextLogicalTime(from: state),
        payload: .object([
            "taskId": .string(taskId),
            "title": .string(title),
            "assignedNodeId": .string(assignedNodeId),
        ])
    )
    let assigned = MeshEvent(
        type: .taskAssigned,
        actorNodeId: actorIdentity.nodeId,
        targetNodeId: assignedNodeId,
        projectId: project.id,
        logicalTime: nextLogicalTime(from: state) + 1,
        causalParents: [created.id],
        payload: .object([
            "taskId": .string(taskId),
            "assignedNodeId": .string(assignedNodeId),
        ])
    )
    _ = try appendEvent(try MeshEventSigner.sign(created, identity: actorIdentity), expectedActorPublicKey: actorIdentity.publicKey)
    _ = try appendEvent(try MeshEventSigner.sign(assigned, identity: actorIdentity), expectedActorPublicKey: actorIdentity.publicKey)

    let projected = try projectedState()
    guard let task = projected.tasks.first(where: { $0.id == taskId }) else {
        throw NodeMeshStoreError.taskMissing(taskId)
    }
    return task
}

private func nextLogicalTime(from state: MeshState) -> UInt64 {
    (state.events.map(\.event.logicalTime).max() ?? 0) + 1
}
```

Keep the existing `dispatchTask(projectIdOrName:title:assignedNodeId:actor:)` implementation intact for compatibility. Do not rewrite all legacy methods in this task.

- [ ] **Step 4: Add event-backed status update overload**

Add:

```swift
@discardableResult
public func updateTaskStatus(
    taskId: String,
    status: MeshTaskStatus,
    actorIdentity: NodeIdentity,
    branch: String? = nil,
    commit: String? = nil,
    summary: String? = nil
) throws -> MeshTaskRecord {
    let state = try projectedState()
    guard let task = state.tasks.first(where: { $0.id == taskId }) else {
        throw NodeMeshStoreError.taskMissing(taskId)
    }
    guard let project = state.sharedProjects.first(where: { $0.id == task.projectId }),
          let actorMember = project.members.first(where: { $0.nodeId == actorIdentity.nodeId }),
          actorMember.permissions.contains(MeshPermission.taskUpdate.rawValue)
    else {
        throw NodeMeshStoreError.permissionDenied("task.status.update")
    }
    let event = MeshEvent(
        type: .taskStatusUpdated,
        actorNodeId: actorIdentity.nodeId,
        projectId: task.projectId,
        logicalTime: nextLogicalTime(from: state),
        payload: .object([
            "taskId": .string(task.id),
            "status": .string(status.rawValue),
            "branch": branch.map(JSONValue.string) ?? .null,
            "commit": commit.map(JSONValue.string) ?? .null,
            "summary": summary.map(JSONValue.string) ?? .null,
        ])
    )
    _ = try appendEvent(try MeshEventSigner.sign(event, identity: actorIdentity), expectedActorPublicKey: actorIdentity.publicKey)
    let projected = try projectedState()
    guard let updated = projected.tasks.first(where: { $0.id == taskId }) else {
        throw NodeMeshStoreError.taskMissing(taskId)
    }
    return updated
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter NodeMeshStoreTests/dispatchTaskWithActorIdentityWritesSignedTaskEvents
swift test --filter NodeMeshProjectionTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/NodeCore/NodeMesh.swift Tests/SloppyNodeCoreTests/NodeMeshStoreTests.swift
git commit -m "feat: create mesh tasks from signed events"
```

---

### Task 5: Core API Event Endpoints and Projection Views

**Files:**
- Modify: `Sources/sloppy/CoreService+NodeMesh.swift`
- Modify: `Sources/sloppy/Gateway/Routers/NodeMeshAPIRouter.swift`
- Test: `Tests/sloppyTests/CoreRouterTests.swift`

**Interfaces:**
- Consumes: `NodeMeshStore.listEvents`, `appendEvent`, `projectedState`.
- Produces:
  - `CoreService.listMeshEvents(after:limit:)`
  - `CoreService.ingestMeshEvent(_:)`
  - `CoreService.getMeshProjection()`
  - routes `GET /v1/node/mesh/events`, `POST /v1/node/mesh/events`, `GET /v1/node/mesh/projection`

- [ ] **Step 1: Write failing router test**

Add a focused test near existing mesh router tests in `CoreRouterTests.swift`:

```swift
@Test("mesh event endpoints ingest signed events and expose projection")
func meshEventEndpointsIngestSignedEventsAndExposeProjection() async throws {
    let harness = try CoreRouterTestHarness()
    let identity = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
    let event = MeshEvent(
        id: "evt_project_created",
        type: .projectCreated,
        actorNodeId: identity.nodeId,
        projectId: "sp_sloppy",
        logicalTime: 1,
        payload: .object([
            "id": .string("sp_sloppy"),
            "name": .string("Sloppy"),
            "repoUrl": .string("git@example.com:sloppy.git"),
        ])
    )
    let signed = try MeshEventSigner.sign(event, identity: identity)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let body = try encoder.encode(signed)

    let post = await harness.router.handle(method: "POST", path: "/v1/node/mesh/events", body: body)
    #expect(post.status == 202)

    let get = await harness.router.handle(method: "GET", path: "/v1/node/mesh/events", body: nil)
    #expect(get.status == 200)

    let projection = await harness.router.handle(method: "GET", path: "/v1/node/mesh/projection", body: nil)
    #expect(projection.status == 200)
    #expect(String(data: projection.body, encoding: .utf8)?.contains("sp_sloppy") == true)
}
```

Use the local router test harness pattern already present in `CoreRouterTests.swift`; if its type name differs, adapt only the constructor/reference, not the behavior.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter CoreRouterTests/meshEventEndpointsIngestSignedEventsAndExposeProjection
```

Expected: FAIL because routes do not exist.

- [ ] **Step 3: Add service methods**

Add to `CoreService+NodeMesh.swift`:

```swift
public func getMeshProjection() throws -> MeshState {
    try nodeMeshStore.projectedState()
}

public func listMeshEvents(after cursor: String? = nil, limit: Int = 100) throws -> [SignedMeshEvent] {
    try nodeMeshStore.listEvents(after: cursor, limit: limit)
}

public func ingestMeshEvent(_ event: SignedMeshEvent) throws -> SignedMeshEvent {
    try nodeMeshStore.appendEvent(event, expectedActorPublicKey: event.actorPublicKey)
}
```

Change existing projection-like reads to use projected state where safe:

```swift
public func getMeshState() throws -> MeshState {
    try nodeMeshStore.projectedState()
}

public func listMeshSharedProjects() throws -> [SharedProjectRecord] {
    try nodeMeshStore.projectedState().sharedProjects.sorted { $0.name < $1.name }
}

public func listMeshTasks(projectId: String? = nil) throws -> [MeshTaskRecord] {
    let state = try nodeMeshStore.projectedState()
    guard let projectId, !projectId.isEmpty else {
        return state.tasks.sorted { $0.updatedAt > $1.updatedAt }
    }
    let resolvedProjectId = state.sharedProjects.first(where: { $0.id == projectId || $0.name == projectId })?.id ?? projectId
    return state.tasks.filter { $0.projectId == resolvedProjectId }.sorted { $0.updatedAt > $1.updatedAt }
}
```

- [ ] **Step 4: Add routes**

In `NodeMeshAPIRouter.configure`, after `GET /v1/node/mesh`, add:

```swift
router.get("/v1/node/mesh/projection", metadata: RouteMetadata(summary: "Get mesh projection", description: "Returns deterministic SloppyNode mesh projection derived from accepted signed events", tags: ["Node Mesh"])) { _ in
    do {
        return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.getMeshProjection())
    } catch {
        return meshErrorResponse(error)
    }
}

router.get("/v1/node/mesh/events", metadata: RouteMetadata(summary: "List mesh events", description: "Returns accepted signed mesh events after an optional cursor", tags: ["Node Mesh"])) { request in
    do {
        let cursor = request.queryParam("cursor")
        let limit = request.queryParam("limit").flatMap(Int.init) ?? 100
        return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.listMeshEvents(after: cursor, limit: limit))
    } catch {
        return meshErrorResponse(error)
    }
}

router.post("/v1/node/mesh/events", metadata: RouteMetadata(summary: "Ingest mesh event", description: "Accepts one signed mesh event after signature verification", tags: ["Node Mesh"])) { request in
    guard let body = request.body,
          let payload = CoreRouter.decode(body, as: SignedMeshEvent.self) else {
        return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
    }
    do {
        return CoreRouter.encodable(status: HTTPStatus.accepted, payload: try await service.ingestMeshEvent(payload))
    } catch {
        return meshErrorResponse(error)
    }
}
```

Extend `meshErrorResponse`:

```swift
if let verificationError = error as? MeshEventVerificationError {
    return CoreRouter.json(status: HTTPStatus.forbidden, payload: [
        "error": "mesh_event_rejected",
        "message": verificationError.localizedDescription,
    ])
}
```

- [ ] **Step 5: Run test to verify it passes**

Run:

```bash
swift test --filter CoreRouterTests/meshEventEndpointsIngestSignedEventsAndExposeProjection
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/sloppy/CoreService+NodeMesh.swift Sources/sloppy/Gateway/Routers/NodeMeshAPIRouter.swift Tests/sloppyTests/CoreRouterTests.swift
git commit -m "feat: expose mesh event API"
```

---

### Task 6: Relay Event Publish and Offline Mailbox Delivery

**Files:**
- Modify: `Sources/sloppy/Gateway/NodeMeshRelay.swift`
- Modify: `Sources/NodeCore/NodeMeshClient.swift`
- Test: `Tests/sloppyTests/CoreHTTPServerTests.swift`
- Test: `Tests/SloppyNodeCoreTests/NodeMeshClientTests.swift`

**Interfaces:**
- Consumes: `SignedMeshEvent`, `NodeMeshStore.appendEvent`, `MeshMessageType.eventPublish`.
- Produces:
  - relay accepts `event.publish` envelopes whose payload is a signed event
  - relay sends `event.ack`/`event.reject` as `MeshEnvelope` payloads using existing enum values where possible
  - relay delivers event-derived task assignment to online peers and keeps stored events for offline catch-up

- [ ] **Step 1: Write failing client response test**

Append to `NodeMeshClientTests`:

```swift
@Test("client returns ack for accepted event publish")
func clientReturnsAckForAcceptedEventPublish() async throws {
    let identity = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
    let store = NodeMeshStore(stateURL: temporaryStateURL())
    try store.registerNode(identity)
    let client = NodeMeshClient(config: NodeConfig(identity: identity), meshStore: store)
    let signed = try MeshEventSigner.sign(
        MeshEvent(type: .nodeStatusChanged, actorNodeId: identity.nodeId, logicalTime: 1, payload: .object(["status": .string("online")])),
        identity: identity
    )

    let response = try #require(await client.response(to: MeshEnvelope(
        type: .eventPublish,
        from: identity.nodeId,
        payload: try JSONValueCoder.encode(signed)
    )))

    #expect(response.type == .rpcResponse)
    #expect(response.payload.asObject?["ok"] == .bool(true))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter NodeMeshClientTests/clientReturnsAckForAcceptedEventPublish
```

Expected: FAIL because `NodeMeshClient` does not handle `event.publish` as event ingestion.

- [ ] **Step 3: Add client event publish handler**

In `NodeMeshClient.response(to:)`, before RPC method handling, add:

```swift
if envelope.type == .eventPublish {
    return eventPublishResponse(for: envelope)
}
```

Add:

```swift
private func eventPublishResponse(for envelope: MeshEnvelope) -> MeshEnvelope {
    do {
        guard let meshStore else {
            throw NodeMeshStoreError.projectMissing("mesh_store")
        }
        let signed = try JSONValueCoder.decode(SignedMeshEvent.self, from: envelope.payload)
        _ = try meshStore.appendEvent(signed, expectedActorPublicKey: signed.actorPublicKey)
        return MeshEnvelope(
            type: .rpcResponse,
            from: config.identity.nodeId,
            to: envelope.from,
            payload: .object([
                "requestId": .string(envelope.id),
                "ok": .bool(true),
                "eventId": .string(signed.event.id),
            ])
        )
    } catch {
        return MeshEnvelope(
            type: .rpcResponse,
            from: config.identity.nodeId,
            to: envelope.from,
            payload: .object([
                "requestId": .string(envelope.id),
                "ok": .bool(false),
                "error": .object([
                    "code": .string("event_rejected"),
                    "message": .string(error.localizedDescription),
                ]),
            ])
        )
    }
}
```

- [ ] **Step 4: Add relay event route**

In `NodeMeshRelay.route(_:)`, before task status handling:

```swift
if envelope.type == .eventPublish {
    try await routeEventPublish(envelope)
    return
}
```

Add:

```swift
private func routeEventPublish(_ envelope: MeshEnvelope) async throws {
    guard let store else {
        try await sendEventReject(for: envelope, code: "mesh_store_unavailable", message: "Node mesh store is not configured.")
        return
    }
    do {
        let signed = try JSONValueCoder.decode(SignedMeshEvent.self, from: envelope.payload)
        _ = try store.appendEvent(signed, expectedActorPublicKey: signed.actorPublicKey)
        try await sendEventAck(for: envelope, eventId: signed.event.id)
        if let target = signed.event.targetNodeId, let connection = connections[target] {
            try await send(envelope, over: connection.context)
        }
    } catch {
        try await sendEventReject(for: envelope, code: "event_rejected", message: error.localizedDescription)
    }
}

private func sendEventAck(for envelope: MeshEnvelope, eventId: String) async throws {
    guard let source = connections[envelope.from] else { return }
    try await send(MeshEnvelope(
        type: .rpcResponse,
        from: "relay",
        to: envelope.from,
        payload: .object([
            "requestId": .string(envelope.id),
            "ok": .bool(true),
            "eventId": .string(eventId),
        ])
    ), over: source.context)
}

private func sendEventReject(for envelope: MeshEnvelope, code: String, message: String) async throws {
    guard let source = connections[envelope.from] else { return }
    try await send(MeshEnvelope(
        type: .rpcResponse,
        from: "relay",
        to: envelope.from,
        payload: .object([
            "requestId": .string(envelope.id),
            "ok": .bool(false),
            "error": .object([
                "code": .string(code),
                "message": .string(message),
            ]),
        ])
    ), over: source.context)
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter NodeMeshClientTests/clientReturnsAckForAcceptedEventPublish
swift test --filter CoreHTTPServerTests
```

Expected: new client test PASS; existing relay tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/NodeCore/NodeMeshClient.swift Sources/sloppy/Gateway/NodeMeshRelay.swift Tests/SloppyNodeCoreTests/NodeMeshClientTests.swift Tests/sloppyTests/CoreHTTPServerTests.swift
git commit -m "feat: route signed mesh events through relay"
```

---

### Task 7: Operator CLI for Event Inspection and Smoke Publishing

**Files:**
- Modify: `Sources/SloppyNodeCLI/NodeCommand.swift`
- Test: `Tests/sloppyTests/CLITests.swift`

**Interfaces:**
- Consumes: `NodeMeshStore.listEvents`, `NodeConfigStore.load`, `MeshEventSigner.sign`.
- Produces:
  - `sloppy-node event-list --mesh-path "$MESH_STATE" --limit 50`
  - `sloppy-node event-publish-local --mesh-path "$MESH_STATE" --type node.status.changed --payload '{"status":"online"}'`

- [ ] **Step 1: Write failing CLI command list test**

Extend existing `CLITests.swift` subcommand assertion:

```swift
#expect(nodeSubcommands.contains("event-list"))
#expect(nodeSubcommands.contains("event-publish-local"))
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter CLITests
```

Expected: FAIL because the subcommands do not exist.

- [ ] **Step 3: Add commands to `NodeCommand`**

Add `EventList.self` and `EventPublishLocal.self` to `NodeCommand.configuration.subcommands`.

Add after `AuditLog`:

```swift
public struct EventList: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "event-list",
        abstract: "Prints signed mesh events from local mesh state."
    )

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    @Option(name: .long, help: "Optional event cursor id.")
    var cursor: String?

    @Option(name: .long, help: "Maximum number of events.")
    var limit: Int = 50

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let events = try NodeMeshStore(stateURL: meshURL(from: meshPath)).listEvents(after: cursor, limit: limit)
        print("EVENT ID\tTYPE\tACTOR\tTARGET\tPROJECT\tLOGICAL TIME")
        for signed in events {
            let event = signed.event
            print("\(event.id)\t\(event.type.rawValue)\t\(event.actorNodeId)\t\(event.targetNodeId ?? "-")\t\(event.projectId ?? "-")\t\(event.logicalTime)")
        }
    }
}

public struct EventPublishLocal: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "event-publish-local",
        abstract: "Signs and appends one local mesh event for smoke testing."
    )

    @Option(name: .long, help: "Event type raw value.")
    var type: String

    @Option(name: .long, help: "JSON payload object.")
    var payload: String = "{}"

    @Option(name: .long, help: "Project id.")
    var project: String?

    @Option(name: .long, help: "Target node id.")
    var target: String?

    @Option(name: .long, help: "Config path. Defaults to ~/.sloppy/node.json.")
    var configPath: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        guard let eventType = MeshEventType(rawValue: type) else {
            throw ValidationError("Unknown mesh event type '\(type)'.")
        }
        let config = try NodeConfigStore(configURL: configURL(from: configPath)).load()
        let store = NodeMeshStore(stateURL: meshURL(from: meshPath))
        let state = try store.load()
        let event = MeshEvent(
            type: eventType,
            actorNodeId: config.identity.nodeId,
            targetNodeId: target,
            projectId: project,
            logicalTime: (state.events.map(\.event.logicalTime).max() ?? 0) + 1,
            payload: try parseJSONValue(payload) ?? .object([:])
        )
        let signed = try MeshEventSigner.sign(event, identity: config.identity)
        _ = try store.appendEvent(signed, expectedActorPublicKey: config.identity.publicKey)
        print("Published mesh event")
        print("  id: \(event.id)")
        print("  type: \(event.type.rawValue)")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter CLITests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyNodeCLI/NodeCommand.swift Tests/sloppyTests/CLITests.swift
git commit -m "feat: add mesh event CLI commands"
```

---

### Task 8: Docs and Final Verification

**Files:**
- Modify: `docs/guides/mesh.md`

**Interfaces:**
- Consumes: implemented event API and CLI commands.
- Produces: documented peer mesh first slice and compatibility notes.

- [ ] **Step 1: Update guide with peer event section**

Add this section after "What Mesh Provides":

````markdown
## Peer Event Mode

Mesh now accepts signed peer events in addition to the compatibility coordinator-style commands. A relay or mailbox node can store and forward events, but valid mesh state is derived from event signatures and project permissions.

Useful inspection commands:

```bash
sloppy-node event-list --mesh-path "$MESH_STATE"
curl http://127.0.0.1:8787/v1/node/mesh/events
curl http://127.0.0.1:8787/v1/node/mesh/projection
```

Compatibility endpoints such as `/v1/node/mesh/tasks` continue to return projection views.
````

- [ ] **Step 2: Run full relevant verification**

Run:

```bash
swift test --filter NodeMeshEventTests
swift test --filter NodeMeshProjectionTests
swift test --filter NodeMeshStoreTests
swift test --filter NodeMeshClientTests
swift test --filter CoreRouterTests
swift build -c release --product SloppyNode
swift build -c release --product sloppy
```

Expected: all commands pass.

- [ ] **Step 3: Commit docs**

```bash
git add docs/guides/mesh.md
git commit -m "docs: document peer mesh event mode"
```

- [ ] **Step 4: Final status check**

Run:

```bash
git status --short
```

Expected: only unrelated pre-existing worktree changes remain.
