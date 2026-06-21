# Mesh Remote Join Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local `Join Remote Mesh` flow so home/work/mobile dashboards can join a VPS relay without switching the dashboard Core API base away from the local Sloppy instance.

**Architecture:** Split coordinator invite acceptance from local remote-join onboarding. Coordinator endpoints keep owning invite state; local Core parses a bundled invite, creates or reuses local node identity, calls the coordinator accept endpoint with that identity, stores the relay URL in local node config, and returns local join status to the dashboard.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, SloppyNodeCore, Sloppy Core HTTP router, React 19 + TypeScript/JS dashboard, Vite.

## Global Constraints

- Do not make the VPS the only authority for mesh state.
- Do not require local dashboards to switch API base to the VPS.
- Keep local node private keys on the local machine.
- Coordinator stores public keys and invite metadata only.
- Joining a remote mesh must not overwrite local identity unless `force` is explicit.
- Clearly distinguish dashboard Core API base from mesh relay URL.
- Preserve existing coordinator invite endpoints for compatibility.

---

## File Structure

- `Sources/NodeCore/NodeMesh.swift`
  - Extend invite request/accept models and bundled invite parsing so generic bundled invites can omit pre-bound public keys.
  - Add local remote join request/result/error models.
- `Sources/NodeCore/NodeMeshRemoteJoiner.swift`
  - New focused join orchestration unit. It owns local identity load/create/update and calls an injected coordinator accept transport.
- `Sources/sloppy/CoreService.swift`
  - Inject `NodeConfigStore` into `CoreService` for test-safe local node config writes.
- `Sources/sloppy/CoreService+NodeMesh.swift`
  - Add `joinRemoteMesh(_:)`.
  - Extend coordinator `acceptMeshInvite(_:)` to accept identity-bearing requests.
- `Sources/sloppy/Gateway/Routers/NodeMeshAPIRouter.swift`
  - Add `POST /v1/node/mesh/remote-joins`.
  - Update invite accept description/copy to coordinator semantics.
- `Tests/SloppyNodeCoreTests/NodeMeshStoreTests.swift`
  - Add generic invite bundle and identity-bearing accept tests.
- `Tests/SloppyNodeCoreTests/NodeMeshRemoteJoinerTests.swift`
  - New unit tests for local join orchestration.
- `Tests/sloppyTests/CoreRouterTests.swift`
  - Add router-level tests for coordinator accept and local remote join.
- `Dashboard/src/shared/api/coreApi.ts`
  - Add `joinRemoteMesh(payload)`.
- `Dashboard/src/views/NodesView.tsx`
  - Add `Join Remote Mesh` modal and wrong-coordinator recovery path.
- `Dashboard/src/styles/nodes.css`
  - Add `nodes-join-relay` and `nodes-checkbox-row` styles used by the new modal.

---

### Task 1: Generic Invite Bundle and Identity-Bearing Coordinator Accept

**Files:**
- Modify: `Sources/NodeCore/NodeMesh.swift`
- Test: `Tests/SloppyNodeCoreTests/NodeMeshStoreTests.swift`

**Interfaces:**
- Produces:
  - `MeshInviteAcceptRequest.nodeId: String?`
  - `MeshInviteAcceptRequest.name: String?`
  - `MeshInviteAcceptRequest.publicKey: String?`
  - `MeshInviteAcceptRequest.roles: [String]?`
  - `MeshInviteAcceptRequest.capabilities: [String]?`
  - `MeshInviteBundle.publicKey: String?`
  - `MeshInvite.bundleToken` generated when `relayURL != nil`, even when `publicKey == nil`
- Consumes:
  - Existing `NodeMeshStore.consumeInvite(token:identity:endpoint:)`
  - Existing `NodeMeshStore.acceptInvite(token:endpoint:)`

- [ ] **Step 1: Add failing generic invite bundle test**

Add this test near existing invite tests in `Tests/SloppyNodeCoreTests/NodeMeshStoreTests.swift`:

```swift
@Test("generic bundled invite does not require a pre-bound public key")
func genericBundledInviteDoesNotRequirePreBoundPublicKey() throws {
    let store = NodeMeshStore(stateURL: temporaryStateURL())
    let invite = try store.createInvite(
        networkId: "personal",
        name: "Work Mac",
        roles: ["worker"],
        capabilities: ["run_agent", "git"],
        ttlSeconds: 60,
        relayURL: "https://mesh.example.com"
    )

    let bundleToken = try #require(invite.bundleToken)
    let bundle = try MeshInviteBundle.parse(bundleToken)

    #expect(bundle.inviteToken == invite.token)
    #expect(bundle.relayURL == "https://mesh.example.com")
    #expect(bundle.nodeId == nil)
    #expect(bundle.publicKey == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter genericBundledInviteDoesNotRequirePreBoundPublicKey`

Expected: FAIL because `bundleToken` is `nil` or `MeshInviteBundle.parse` rejects missing `publicKey`.

- [ ] **Step 3: Add failing identity-bearing accept test**

Add this test near the generic bundle test:

```swift
@Test("generic invite accepts caller supplied identity")
func genericInviteAcceptsCallerSuppliedIdentity() throws {
    let store = NodeMeshStore(stateURL: temporaryStateURL())
    let identity = NodeIdentityGenerator.makeIdentity(name: "Work Mac", roles: ["worker"], capabilities: ["run_agent", "git"])
    let invite = try store.createInvite(
        networkId: "personal",
        name: "Work Mac",
        roles: ["worker"],
        capabilities: ["run_agent", "git"],
        ttlSeconds: 60,
        relayURL: "https://mesh.example.com"
    )
    let token = try #require(invite.bundleToken)

    let node = try store.consumeInvite(token: token, identity: identity, endpoint: "https://mesh.example.com")

    #expect(node.id == identity.nodeId)
    #expect(node.name == "Work Mac")
    #expect(node.publicKey == identity.publicKey)
    #expect(node.endpoint == "https://mesh.example.com")
    let state = try store.load()
    #expect(state.invites.first?.consumedByNodeId == identity.nodeId)
    #expect(state.nodes.map(\.id) == [identity.nodeId])
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `swift test --filter genericInviteAcceptsCallerSuppliedIdentity`

Expected: FAIL because bundled generic tokens are not yet accepted.

- [ ] **Step 5: Update `MeshInviteBundle.publicKey`**

In `Sources/NodeCore/NodeMesh.swift`, change the bundle model:

```swift
public struct MeshInviteBundle: Codable, Sendable, Equatable {
    public static let prefix = "slp_mesh_"

    public var version: Int
    public var inviteToken: String
    public var relayURL: String
    public var nodeId: String?
    public var publicKey: String?

    public init(
        version: Int = 1,
        inviteToken: String,
        relayURL: String,
        nodeId: String? = nil,
        publicKey: String? = nil
    ) {
        self.version = version
        self.inviteToken = inviteToken
        self.relayURL = relayURL
        self.nodeId = nodeId
        self.publicKey = publicKey
    }
```

Then update parse validation:

```swift
guard !bundle.inviteToken.isEmpty, !bundle.relayURL.isEmpty else {
    throw MeshInviteBundleError.invalidPayload
}
```

- [ ] **Step 6: Update `MeshInvite.bundleToken`**

In `MeshInvite.bundleToken`, replace the current `relayURL/publicKey` guard with:

```swift
public var bundleToken: String? {
    guard let relayURL else { return nil }
    return try? MeshInviteBundle(
        inviteToken: token,
        relayURL: relayURL,
        nodeId: nodeId,
        publicKey: publicKey
    ).tokenString()
}
```

- [ ] **Step 7: Extend `MeshInviteAcceptRequest`**

In `Sources/NodeCore/NodeMesh.swift`, extend the request:

```swift
public struct MeshInviteAcceptRequest: Codable, Sendable, Equatable {
    public var token: String
    public var endpoint: String?
    public var allowRemote: Bool
    public var nodeId: String?
    public var name: String?
    public var publicKey: String?
    public var roles: [String]?
    public var capabilities: [String]?

    public init(
        token: String,
        endpoint: String? = nil,
        allowRemote: Bool = true,
        nodeId: String? = nil,
        name: String? = nil,
        publicKey: String? = nil,
        roles: [String]? = nil,
        capabilities: [String]? = nil
    ) {
        self.token = token
        self.endpoint = endpoint
        self.allowRemote = allowRemote
        self.nodeId = nodeId
        self.name = name
        self.publicKey = publicKey
        self.roles = roles
        self.capabilities = capabilities
    }

    enum CodingKeys: String, CodingKey {
        case token
        case endpoint
        case allowRemote
        case nodeId
        case name
        case publicKey
        case roles
        case capabilities
    }
```

Update `init(from:)` to decode all new optional fields.

- [ ] **Step 8: Run invite tests**

Run:

```bash
swift test --filter genericBundledInviteDoesNotRequirePreBoundPublicKey
swift test --filter genericInviteAcceptsCallerSuppliedIdentity
swift test --filter NodeMeshStoreTests/invite
```

Expected: all selected tests pass.

- [ ] **Step 9: Commit**

```bash
git add Sources/NodeCore/NodeMesh.swift Tests/SloppyNodeCoreTests/NodeMeshStoreTests.swift
git commit -m "Support generic mesh invite bundles"
```

---

### Task 2: Local Remote Join Orchestration

**Files:**
- Create: `Sources/NodeCore/NodeMeshRemoteJoiner.swift`
- Modify: `Sources/sloppy/CoreService.swift`
- Modify: `Sources/sloppy/CoreService+NodeMesh.swift`
- Test: `Tests/SloppyNodeCoreTests/NodeMeshRemoteJoinerTests.swift`

**Interfaces:**
- Consumes:
  - `MeshInviteBundle.parse(_:)`
  - `NodeConfigStore.load()`
  - `NodeConfigStore.initialize(name:roles:capabilities:relayURL:force:)`
  - `NodeConfigStore.save(_:)`
  - Extended `MeshInviteAcceptRequest`
- Produces:
  - `MeshRemoteJoinRequest`
  - `MeshRemoteJoinResult`
  - `NodeMeshRemoteJoiner.join(_:) async throws -> MeshRemoteJoinResult`
  - `CoreService.joinRemoteMesh(_:) async throws -> MeshRemoteJoinResult`

- [ ] **Step 1: Write failing remote joiner tests**

Create `Tests/SloppyNodeCoreTests/NodeMeshRemoteJoinerTests.swift`:

```swift
import Foundation
import Testing
@testable import SloppyNodeCore

@Suite("NodeMeshRemoteJoiner")
struct NodeMeshRemoteJoinerTests {
    @Test("remote join creates local identity and accepts invite at coordinator")
    func remoteJoinCreatesLocalIdentityAndAcceptsInviteAtCoordinator() async throws {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-node-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("node.json")
        let token = try MeshInviteBundle(
            inviteToken: "slp_invite_remote",
            relayURL: "https://mesh.example.com"
        ).tokenString()
        var acceptedURL: URL?
        var acceptedRequest: MeshInviteAcceptRequest?
        let joiner = NodeMeshRemoteJoiner(
            configStore: NodeConfigStore(configURL: configURL),
            acceptInvite: { url, request in
                acceptedURL = url
                acceptedRequest = request
                return MeshNodeRecord(
                    id: request.nodeId ?? "missing",
                    name: request.name ?? "missing",
                    publicKey: request.publicKey ?? "missing",
                    roles: request.roles ?? [],
                    endpoint: request.endpoint,
                    status: .offline,
                    capabilities: request.capabilities ?? []
                )
            }
        )

        let result = try await joiner.join(MeshRemoteJoinRequest(token: token, name: "Work Mac"))

        #expect(result.relayURL == "https://mesh.example.com")
        #expect(acceptedURL?.absoluteString == "https://mesh.example.com/v1/node/mesh/invites/accept")
        #expect(acceptedRequest?.token == token)
        #expect(acceptedRequest?.nodeId == result.node.id)
        #expect(acceptedRequest?.publicKey == result.node.publicKey)
        #expect(try NodeConfigStore(configURL: configURL).load().relayURL == "https://mesh.example.com")
    }

    @Test("remote join preserves existing identity unless force is true")
    func remoteJoinPreservesExistingIdentityUnlessForceIsTrue() async throws {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-node-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("node.json")
        let store = NodeConfigStore(configURL: configURL)
        let existing = try store.initialize(name: "Existing", roles: ["worker"], capabilities: ["git"])
        let token = try MeshInviteBundle(
            inviteToken: "slp_invite_remote",
            relayURL: "https://mesh.example.com"
        ).tokenString()
        let joiner = NodeMeshRemoteJoiner(
            configStore: store,
            acceptInvite: { _, request in
                MeshNodeRecord(
                    id: request.nodeId ?? "missing",
                    name: request.name ?? "missing",
                    publicKey: request.publicKey ?? "missing",
                    roles: request.roles ?? [],
                    endpoint: request.endpoint,
                    status: .offline,
                    capabilities: request.capabilities ?? []
                )
            }
        )

        let result = try await joiner.join(MeshRemoteJoinRequest(token: token, name: "New Name"))

        #expect(result.node.id == existing.identity.nodeId)
        #expect(result.node.name == existing.identity.name)
        #expect(try store.load().identity.nodeId == existing.identity.nodeId)
        #expect(try store.load().relayURL == "https://mesh.example.com")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NodeMeshRemoteJoinerTests`

Expected: FAIL because `NodeMeshRemoteJoiner`, `MeshRemoteJoinRequest`, and `MeshRemoteJoinResult` do not exist.

- [ ] **Step 3: Add remote join models**

In `Sources/NodeCore/NodeMesh.swift`, add near invite models:

```swift
public struct MeshRemoteJoinRequest: Codable, Sendable, Equatable {
    public var token: String
    public var name: String?
    public var force: Bool

    public init(token: String, name: String? = nil, force: Bool = false) {
        self.token = token
        self.name = name
        self.force = force
    }
}

public struct MeshRemoteJoinResult: Codable, Sendable, Equatable {
    public var node: MeshNodeRecord
    public var relayURL: String
    public var coordinatorAcceptURL: String
    public var networkId: String?

    public init(node: MeshNodeRecord, relayURL: String, coordinatorAcceptURL: String, networkId: String? = nil) {
        self.node = node
        self.relayURL = relayURL
        self.coordinatorAcceptURL = coordinatorAcceptURL
        self.networkId = networkId
    }
}

public enum MeshRemoteJoinError: LocalizedError, Equatable {
    case invalidInvite(String)
    case identityMismatch(expectedPublicKey: String, actualPublicKey: String)
    case coordinatorUnreachable(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidInvite(message):
            "Remote mesh invite is invalid: \(message)"
        case .identityMismatch:
            "This invite is bound to another node identity. Create a new invite for this machine or use force to replace local identity."
        case let .coordinatorUnreachable(url):
            "Could not reach relay coordinator at \(url)."
        }
    }
}
```

- [ ] **Step 4: Implement `NodeMeshRemoteJoiner`**

Create `Sources/NodeCore/NodeMeshRemoteJoiner.swift`:

```swift
import Foundation

public struct NodeMeshRemoteJoiner: Sendable {
    public typealias AcceptInvite = @Sendable (URL, MeshInviteAcceptRequest) async throws -> MeshNodeRecord

    public var configStore: NodeConfigStore
    public var acceptInvite: AcceptInvite

    public init(
        configStore: NodeConfigStore = NodeConfigStore(),
        acceptInvite: @escaping AcceptInvite
    ) {
        self.configStore = configStore
        self.acceptInvite = acceptInvite
    }

    public func join(_ request: MeshRemoteJoinRequest) async throws -> MeshRemoteJoinResult {
        let bundle: MeshInviteBundle
        do {
            bundle = try MeshInviteBundle.parse(request.token)
        } catch {
            throw MeshRemoteJoinError.invalidInvite(String(describing: error))
        }

        let config = try localConfig(for: request, bundle: bundle)
        if let expectedPublicKey = bundle.publicKey,
           expectedPublicKey != config.identity.publicKey {
            throw MeshRemoteJoinError.identityMismatch(
                expectedPublicKey: expectedPublicKey,
                actualPublicKey: config.identity.publicKey
            )
        }

        let acceptURL = try coordinatorAcceptURL(from: bundle.relayURL)
        let acceptRequest = MeshInviteAcceptRequest(
            token: request.token,
            endpoint: bundle.relayURL,
            nodeId: config.identity.nodeId,
            name: config.identity.name,
            publicKey: config.identity.publicKey,
            roles: config.identity.roles,
            capabilities: config.identity.capabilities
        )
        let node = try await acceptInvite(acceptURL, acceptRequest)
        try configStore.save(NodeConfig(identity: config.identity, relayURL: bundle.relayURL))
        return MeshRemoteJoinResult(
            node: node,
            relayURL: bundle.relayURL,
            coordinatorAcceptURL: acceptURL.absoluteString
        )
    }

    private func localConfig(for request: MeshRemoteJoinRequest, bundle: MeshInviteBundle) throws -> NodeConfig {
        if !request.force, let existing = try? configStore.load() {
            return NodeConfig(identity: existing.identity, relayURL: bundle.relayURL)
        }
        return try configStore.initialize(
            name: request.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? request.name! : "Sloppy Node",
            roles: ["worker"],
            capabilities: ["run_agent", "git"],
            relayURL: bundle.relayURL,
            force: request.force
        )
    }

    private func coordinatorAcceptURL(from relayURL: String) throws -> URL {
        guard var components = URLComponents(string: relayURL),
              components.scheme?.isEmpty == false,
              components.host?.isEmpty == false
        else {
            throw MeshRemoteJoinError.invalidInvite("relay URL is invalid")
        }
        components.path = "/v1/node/mesh/invites/accept"
        components.query = nil
        guard let url = components.url else {
            throw MeshRemoteJoinError.invalidInvite("relay URL is invalid")
        }
        return url
    }
}
```

- [ ] **Step 5: Run joiner tests**

Run: `swift test --filter NodeMeshRemoteJoinerTests`

Expected: PASS.

- [ ] **Step 6: Inject `NodeConfigStore` into `CoreService`**

In `Sources/sloppy/CoreService.swift`, add a property next to `nodeMeshStore`:

```swift
nonisolated let nodeConfigStore: NodeConfigStore
```

Add a parameter to both public and internal initializers:

```swift
nodeConfigStore: NodeConfigStore = NodeConfigStore()
```

Pass it from the public initializer into the internal initializer, and assign:

```swift
self.nodeConfigStore = nodeConfigStore
```

- [ ] **Step 7: Add CoreService remote join method and HTTP accept transport**

In `Sources/sloppy/CoreService+NodeMesh.swift`, keep `import Foundation` and add Linux networking import at the top:

```swift
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
```

Then add:

```swift
public func joinRemoteMesh(_ request: MeshRemoteJoinRequest) async throws -> MeshRemoteJoinResult {
    let joiner = NodeMeshRemoteJoiner(
        configStore: nodeConfigStore,
        acceptInvite: { url, acceptRequest in
            try await Self.postMeshInviteAccept(to: url, request: acceptRequest)
        }
    )
    return try await joiner.join(request)
}

private static func postMeshInviteAccept(to url: URL, request: MeshInviteAcceptRequest) async throws -> MeshNodeRecord {
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    urlRequest.httpBody = try encoder.encode(request)
    let (data, response) = try await URLSession.shared.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw MeshRemoteJoinError.coordinatorUnreachable(url.absoluteString)
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(MeshNodeRecord.self, from: data)
}
```

Keep this transport in `CoreService+NodeMesh.swift`; do not put URLSession logic into `NodeMeshRemoteJoiner`.

- [ ] **Step 8: Run core build**

Run: `swift build --target SloppyNodeCoreTests`

Expected: build succeeds.

- [ ] **Step 9: Commit**

```bash
git add Sources/NodeCore/NodeMesh.swift Sources/NodeCore/NodeMeshRemoteJoiner.swift Sources/sloppy/CoreService.swift Sources/sloppy/CoreService+NodeMesh.swift Tests/SloppyNodeCoreTests/NodeMeshRemoteJoinerTests.swift
git commit -m "Add local remote mesh joiner"
```

---

### Task 3: Core API Remote Join Endpoint

**Files:**
- Modify: `Sources/sloppy/Gateway/Routers/NodeMeshAPIRouter.swift`
- Modify: `Sources/sloppy/CoreService+NodeMesh.swift`
- Test: `Tests/sloppyTests/CoreRouterTests.swift`

**Interfaces:**
- Consumes:
  - `CoreService.joinRemoteMesh(_:) async throws -> MeshRemoteJoinResult`
  - `MeshRemoteJoinRequest`
  - Extended `MeshInviteAcceptRequest`
- Produces:
  - `POST /v1/node/mesh/remote-joins`

- [ ] **Step 1: Add coordinator accept test for generic identity request**

In `Tests/sloppyTests/CoreRouterTests.swift`, add:

```swift
@Test
func meshAPIAcceptGenericInviteWithSuppliedIdentity() async throws {
    let service = CoreService(config: .test)
    let router = CoreRouter(service: service)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let inviteBody = try encoder.encode(MeshInviteCreateRequest(
        networkId: "personal",
        name: "Work Mac",
        roles: ["worker"],
        capabilities: ["run_agent", "git"],
        ttlSeconds: 600,
        relayURL: "https://mesh.example.com"
    ))
    let inviteResponse = await router.handle(method: "POST", path: "/v1/node/mesh/invites", body: inviteBody)
    #expect(inviteResponse.status == 201)
    let invite = try decoder.decode(MeshInvite.self, from: inviteResponse.body)
    let token = try #require(invite.bundleToken)

    let acceptBody = try encoder.encode(MeshInviteAcceptRequest(
        token: token,
        endpoint: "https://mesh.example.com",
        nodeId: "node_work",
        name: "Work Mac",
        publicKey: "ed25519:work_public",
        roles: ["worker"],
        capabilities: ["run_agent", "git"]
    ))
    let acceptResponse = await router.handle(method: "POST", path: "/v1/node/mesh/invites/accept", body: acceptBody)

    #expect(acceptResponse.status == 201)
    let node = try decoder.decode(MeshNodeRecord.self, from: acceptResponse.body)
    #expect(node.id == "node_work")
    #expect(node.publicKey == "ed25519:work_public")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter meshAPIAcceptGenericInviteWithSuppliedIdentity`

Expected: FAIL because `acceptMeshInvite(_:)` does not yet route supplied identity fields to `consumeInvite`.

- [ ] **Step 3: Update coordinator accept service**

In `Sources/sloppy/CoreService+NodeMesh.swift`, update `acceptMeshInvite(_:)`:

```swift
public func acceptMeshInvite(_ request: MeshInviteAcceptRequest) throws -> MeshNodeRecord {
    do {
        if let nodeId = request.nodeId,
           let publicKey = request.publicKey {
            let identity = NodeIdentity(
                nodeId: nodeId,
                name: request.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? request.name! : nodeId,
                publicKey: publicKey,
                privateKey: "",
                roles: request.roles ?? ["worker"],
                capabilities: request.capabilities ?? ["run_agent", "git"]
            )
            return try nodeMeshStore.consumeInvite(token: request.token, identity: identity, endpoint: request.endpoint)
        }
        return try nodeMeshStore.acceptInvite(token: request.token, endpoint: request.endpoint)
    } catch NodeMeshStoreError.inviteMissing {
        if let bundle = try? MeshInviteBundle.parse(request.token) {
            throw NodeMeshStoreError.inviteWrongCoordinator(bundle.relayURL)
        }
        throw NodeMeshStoreError.inviteMissing
    }
}
```

The empty `privateKey` is acceptable here because coordinator state stores only the public node record. Do not persist remote private keys.

- [ ] **Step 4: Add route test for invalid remote join body**

In `Tests/sloppyTests/CoreRouterTests.swift`, add:

```swift
@Test
func meshAPIRemoteJoinRejectsInvalidBodyWithExpectedShape() async throws {
    let service = CoreService(config: .test)
    let router = CoreRouter(service: service)

    let response = await router.handle(method: "POST", path: "/v1/node/mesh/remote-joins", body: Data("{}".utf8))

    #expect(response.status == 400)
    let object = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    #expect(object["error"] as? String == "invalid_body")
    #expect((object["message"] as? String)?.contains(#""token":"slp_mesh_...""#) == true)
}
```

- [ ] **Step 5: Add remote join route**

In `Sources/sloppy/Gateway/Routers/NodeMeshAPIRouter.swift`, after `/v1/node/mesh/invites/accept`, add:

```swift
router.post("/v1/node/mesh/remote-joins", metadata: RouteMetadata(summary: "Join remote mesh", description: "Uses this local node identity to join the relay embedded in a bundled mesh invite", tags: ["Node Mesh"])) { request in
    guard let body = request.body,
          let payload = CoreRouter.decode(body, as: MeshRemoteJoinRequest.self),
          !payload.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return CoreRouter.json(status: HTTPStatus.badRequest, payload: [
            "error": ErrorCode.invalidBody,
            "message": #"Expected JSON body like {"token":"slp_mesh_...","name":"work-mac","force":false}."#,
        ])
    }

    do {
        return CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.joinRemoteMesh(payload))
    } catch {
        return meshErrorResponse(error)
    }
}
```

- [ ] **Step 6: Extend mesh error response for remote join errors**

In `meshErrorResponse(_:)`, add handling:

```swift
if let remoteJoinError = error as? MeshRemoteJoinError {
    return CoreRouter.json(status: HTTPStatus.badRequest, payload: [
        "error": "mesh_invalid_request",
        "message": remoteJoinError.localizedDescription,
    ])
}
```

- [ ] **Step 7: Run router tests**

Run:

```bash
swift test --filter meshAPIAcceptGenericInviteWithSuppliedIdentity
swift test --filter meshAPIRemoteJoinRejectsInvalidBodyWithExpectedShape
swift test --filter CoreRouterTests/meshAPI
```

Expected: all selected tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/sloppy/Gateway/Routers/NodeMeshAPIRouter.swift Sources/sloppy/CoreService+NodeMesh.swift Tests/sloppyTests/CoreRouterTests.swift
git commit -m "Expose remote mesh join endpoint"
```

---

### Task 4: Dashboard API Client and Join Remote Mesh UX

**Files:**
- Modify: `Dashboard/src/shared/api/coreApi.ts`
- Modify: `Dashboard/src/views/NodesView.tsx`
- Modify: `Dashboard/src/styles/nodes.css`

**Interfaces:**
- Consumes:
  - `POST /v1/node/mesh/remote-joins`
  - Existing `acceptMeshInvite(payload)`
- Produces:
  - `coreApi.joinRemoteMesh(payload)`
  - `NodesView` modal state `"join"`
  - Wrong-coordinator error recovery path that keeps dashboard API base unchanged.

- [ ] **Step 1: Add dashboard API method**

In `Dashboard/src/shared/api/coreApi.ts`, add near `acceptMeshInvite`:

```ts
joinRemoteMesh: async (payload) => {
  const response = await requestJson<AnyRecord, AnyRecord>({
    path: "/v1/node/mesh/remote-joins",
    method: "POST",
    body: payload
  });
  if (!response.ok) {
    throw new Error(formatHttpError(response.status, response.data));
  }
  return response.data;
},
```

Also add this method to the exported `CoreApi` type if it is declared explicitly in the file.

- [ ] **Step 2: Run dashboard typecheck to verify expected errors**

Run: `cd Dashboard && npm run typecheck`

Expected: FAIL until `CoreApi` type and `NodesView` usage are updated, or PASS if `CoreApi` is inferred from the object.

- [ ] **Step 3: Add join modal state**

In `Dashboard/src/views/NodesView.tsx`, change:

```ts
type MeshModal = "network" | "invite" | "accept" | "node" | null;
```

to:

```ts
type MeshModal = "network" | "invite" | "accept" | "join" | "node" | null;
```

Add state next to `acceptInviteToken`:

```ts
const [joinInviteToken, setJoinInviteToken] = useState("");
const [joinNodeName, setJoinNodeName] = useState("");
const [joinForce, setJoinForce] = useState(false);
const [detectedRemoteRelayURL, setDetectedRemoteRelayURL] = useState("");
```

- [ ] **Step 4: Add bundled relay parser helper**

Add helper functions near `meshInviteToken`:

```ts
function parseMeshInviteBundle(token: string) {
  const prefix = "slp_mesh_";
  if (!token.startsWith(prefix)) {
    return null;
  }
  try {
    const encoded = token.slice(prefix.length).replace(/-/g, "+").replace(/_/g, "/");
    const padded = encoded.padEnd(encoded.length + ((4 - encoded.length % 4) % 4), "=");
    const json = atob(padded);
    const value = JSON.parse(json) as AnyRecord;
    return value;
  } catch {
    return null;
  }
}

function relayURLFromInviteToken(token: string) {
  return text(parseMeshInviteBundle(token)?.relayURL);
}
```

- [ ] **Step 5: Add local join action**

Add this function near `acceptInvite()`:

```ts
async function joinRemoteMesh() {
  const token = joinInviteToken.trim();
  if (!token) {
    setError("Invite token is required.");
    return;
  }
  await runAction("join", async () => {
    const result = await coreApi.joinRemoteMesh({
      token,
      name: joinNodeName.trim() || null,
      force: joinForce
    });
    if (!result) {
      setError("Remote mesh could not be joined.");
      return false;
    }
    setJoinInviteToken("");
    setJoinNodeName("");
    setJoinForce(false);
    setDetectedRemoteRelayURL(text(result.relayURL));
    return true;
  });
}
```

- [ ] **Step 6: Improve wrong-coordinator accept handling**

Update `acceptInvite()` catch behavior by not relying only on `runAction`. Replace its body with explicit handling:

```ts
async function acceptInvite() {
  const token = acceptInviteToken.trim();
  if (!token) {
    setError("Invite token is required.");
    return;
  }
  setBusyAction("accept");
  setError("");
  try {
    const node = await coreApi.acceptMeshInvite({ token });
    setAcceptInviteToken("");
    setSelectedNodeId(text(node.id));
    setActiveModal(null);
    await refresh();
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invite could not be accepted.";
    const relayURL = relayURLFromInviteToken(token);
    if (relayURL && message.includes("not found in this coordinator state")) {
      setDetectedRemoteRelayURL(relayURL);
      setJoinInviteToken(token);
      setActiveModal("join");
      setError("");
    } else {
      setError(message);
    }
  } finally {
    setBusyAction("");
  }
}
```

- [ ] **Step 7: Add Join Remote Mesh modal**

In the modal render block, add before `activeModal === "node"`:

```tsx
if (activeModal === "join") {
  const relayURL = relayURLFromInviteToken(joinInviteToken) || detectedRemoteRelayURL;
  return (
    <MeshModalFrame title="Join Remote Mesh" description="Connect this local Sloppy node to the relay embedded in a mesh invite." icon="hub" onClose={() => setActiveModal(null)}>
      <div className="nodes-modal-body">
        <Field label="Invite token" hint="Paste the bundled slp_mesh token from the coordinator. The dashboard API base stays local.">
          <textarea value={joinInviteToken} onChange={(event) => setJoinInviteToken(event.target.value)} rows={6} />
        </Field>
        {relayURL ? (
          <div className="nodes-join-relay">
            <span>Remote relay</span>
            <code>{relayURL}</code>
          </div>
        ) : null}
        <Field label="Local node name" hint="Used only if this machine does not already have a node identity.">
          <input type="text" value={joinNodeName} onChange={(event) => setJoinNodeName(event.target.value)} />
        </Field>
        <label className="nodes-checkbox-row">
          <input type="checkbox" checked={joinForce} onChange={(event) => setJoinForce(event.target.checked)} />
          <span>Replace existing local node identity</span>
        </label>
      </div>
      <div className="nodes-modal-actions">
        <button type="button" onClick={() => setActiveModal(null)}>Cancel</button>
        <button type="button" className="nodes-primary-button" disabled={!joinInviteToken.trim() || !!busyAction} onClick={() => void joinRemoteMesh()}>
          {busyAction === "join" ? "Joining" : "Join mesh"}
        </button>
      </div>
    </MeshModalFrame>
  );
}
```

- [ ] **Step 8: Add page action**

In the top action cluster where `Accept Invite` exists, change copy:

```tsx
<button type="button" className="nodes-secondary-button" onClick={() => setActiveModal("join")}>
  <span className="material-symbols-rounded" aria-hidden="true">hub</span>
  Join Remote Mesh
</button>
```

Keep the existing accept action but relabel it as coordinator-scoped:

```tsx
<button type="button" className="nodes-secondary-button" onClick={() => setActiveModal("accept")}>
  Accept Invite Here
</button>
```

- [ ] **Step 9: Add minimal CSS**

In `Dashboard/src/styles/nodes.css`, add:

```css
.nodes-join-relay {
  display: grid;
  gap: 4px;
  padding: 10px 12px;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: var(--background);
}

.nodes-join-relay span {
  color: var(--muted);
  font-size: 12px;
}

.nodes-join-relay code {
  overflow-wrap: anywhere;
}

.nodes-checkbox-row {
  display: flex;
  gap: 8px;
  align-items: center;
  color: var(--text);
}
```

- [ ] **Step 10: Run dashboard checks**

Run:

```bash
cd Dashboard && npm run typecheck
cd Dashboard && npm run build
```

Expected: both pass.

- [ ] **Step 11: Commit**

```bash
git add Dashboard/src/shared/api/coreApi.ts Dashboard/src/views/NodesView.tsx Dashboard/src/styles/nodes.css
git commit -m "Add dashboard remote mesh join flow"
```

---

### Task 5: End-to-End Verification and Docs Touch-Up

**Files:**
- Modify: `docs/guides/mesh.md`
- Test: relevant Swift and dashboard commands

**Interfaces:**
- Consumes all previous task outputs.
- Produces updated operator guidance that no longer tells users to switch local dashboard API base to the VPS for local joining.

- [ ] **Step 1: Update mesh guide local join section**

In `docs/guides/mesh.md`, add a short dashboard section after the CLI quick start:

```markdown
### Dashboard Join Model

The dashboard Core API base and mesh relay URL are separate settings.
Keep the dashboard pointed at the local Sloppy Core when joining a remote mesh.
Use **Join Remote Mesh** and paste the bundled `slp_mesh_...` invite.
The local Core parses the relay URL from the invite, registers the local node with that coordinator, and stores the relay URL in local node config.

Use the VPS dashboard for coordinator tasks such as creating invites and inspecting relay health.
Use the local dashboard for local node membership, local projects, and local task execution state.
```

- [ ] **Step 2: Run focused Swift tests**

Run:

```bash
swift test --filter NodeMeshRemoteJoinerTests
swift test --filter NodeMeshStoreTests/invite
swift test --filter CoreRouterTests/meshAPI
```

Expected: all pass.

- [ ] **Step 3: Run broader mesh tests**

Run:

```bash
swift test --filter SloppyNodeCoreTests
swift test --filter nodeMeshRelay
```

Expected: all pass.

- [ ] **Step 4: Run builds**

Run:

```bash
swift build -c release --product SloppyNode
swift build -c release --product sloppy
cd Dashboard && npm run typecheck
cd Dashboard && npm run build
```

Expected: all pass. Existing unrelated Swift warnings are acceptable only if they match pre-existing warnings.

- [ ] **Step 5: Final diff check**

Run:

```bash
git diff --check HEAD
git status --short
```

Expected: no whitespace errors; only intended files changed before the final docs commit.

- [ ] **Step 6: Commit**

```bash
git add docs/guides/mesh.md
git commit -m "Document dashboard remote mesh join"
```

---

## Review Gates

After each task:

1. Run that task's focused tests.
2. Commit the task.
3. Request code review for that task's commit range.
4. Fix Critical and Important findings before moving on.

## Future Work

- Mobile client joins should use the same `MeshRemoteJoinRequest` and relay URL separation.
- Multi-relay federation is intentionally out of scope.
- A separate UX refactor can split `NodesView.tsx` into feature components after this remote-join slice ships.
