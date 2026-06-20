# Peer Mesh Design

Date: 2026-06-20
Status: Draft
Owner: Codex + user

## Goal

Evolve SloppyNode Mesh from a coordinator-centric relay model into a peer mesh where every Sloppy instance can control, observe, message, and assign work to other authorized instances without any product-level "main" node.

The target deployment has:

- a home instance that is usually online, connected to Telegram, and trusted for broad local control
- a work instance that may be offline but should become a full control surface while online
- a mobile client that acts as a lightweight control and messaging peer
- a VPS instance with a public IP that behaves as relay/mailbox infrastructure, not as system authority

## Non-Goals

- Replacing Git, CI, or per-machine local checkout ownership.
- Requiring every peer to maintain direct network reachability to every other peer.
- Building a general-purpose distributed database before mesh workflows work.
- Making relay nodes trusted to decide authorization policy.
- Treating UI display text as routing or permission control flow.

## Product Requirements

- Every Sloppy instance has a stable mesh identity with a public key, roles, capabilities, and user-visible aliases.
- Any authorized peer can create tasks, assign tasks to another peer, update task state, and inspect progress.
- Dashboard, TUI, Apple client, and channel integrations can switch between mesh peers and an "all mesh" view.
- Messages can target peers explicitly, such as `@home`, `@work`, or `@mesh`, while runtime routing uses typed node identities.
- Shared projects remain first-class: each project has a repo URL, member nodes, per-node local checkout paths, policies, and permissions.
- Offline peers can later catch up from durable signed events.
- VPS and home can store and forward events for availability, but neither is the canonical source of truth.
- Telegram-connected home should be able to route user commands into mesh without making home the sole coordinator.

## Design Principle

Authority belongs to signed identities and ACL events, not to a coordinator process.

Relay/mailbox peers are infrastructure. They may store envelopes, retry delivery, expose HTTP/WebSocket surfaces, and cache projections, but they do not decide that an unsigned or unauthorized action is valid. A peer accepts state only after verifying event signatures and applying deterministic authorization rules.

## High-Level Architecture

### Peer Identity

Each instance has a local `NodeIdentity` stored in `~/.sloppy/node.json` or the existing platform-specific secure equivalent.

Required identity fields:

- stable `nodeId`
- display name
- aliases, such as `home`, `work`, or `mobile`
- public/private key pair
- roles
- capabilities
- preferred relay URLs

Aliases are user-facing conveniences. Runtime routing resolves aliases to `nodeId` before sending any event or envelope.

### Signed Mesh Events

Mesh state is represented by an append-only event log. Current state is a projection of verified events.

Initial event families:

- `node.announced`
- `node.status.changed`
- `node.alias.updated`
- `project.created`
- `project.updated`
- `project.member.added`
- `project.member.removed`
- `task.created`
- `task.assigned`
- `task.status.updated`
- `message.sent`
- `acl.granted`
- `acl.revoked`

Each event includes:

- event id
- event type
- actor node id
- target node id or project id when relevant
- Lamport timestamp or hybrid logical timestamp
- wall-clock timestamp for display
- causal parents when relevant
- payload
- actor signature

Peers reject events with invalid signatures, unsupported schema versions, missing causal requirements, or insufficient actor permissions.

### Event Log and Projection

Every peer keeps a local event log and a deterministic projection.

Projection surfaces include:

- node registry and online/offline/degraded status
- shared projects and memberships
- task board and task lifecycle
- messages and per-peer inboxes
- audit log
- pending outbound envelopes

The existing `NodeMeshStore` can evolve from "single JSON state file" into a store that persists signed events plus cached projection. The cached projection is rebuildable and must not be treated as authority.

### Relay and Mailbox Peers

VPS and home can both act as relay/mailbox peers.

Relay responsibilities:

- accept authenticated WebSocket connections
- verify basic event envelope shape and signatures
- route envelopes to connected peers
- retain pending envelopes for offline peers
- gossip or sync event logs with other relay-capable peers
- expose projections over Core API for UI clients

Relay non-responsibilities:

- minting global truth
- silently rewriting events
- granting implicit permissions
- becoming required for local peer-to-peer communication when another path is available

### Authorization Model

Authorization is event-based and project-scoped by default.

Permissions remain close to the current mesh values:

- `project.read`
- `project.write`
- `task.create`
- `task.assign`
- `task.update`
- `node.rpc`
- `node.shell`
- `node.agent.spawn`
- `node.files.read`
- `node.files.write`
- `node.relay`

ACL changes are signed events. Revocation is eventually consistent: a peer may accept older events that were valid before a revocation timestamp, but rejects new events after the revocation becomes known and causally ordered.

The first implementation should avoid broad default permissions. Home can have broad capabilities, but that should be explicit in ACL events rather than hard-coded by node name.

## User Experience

### Mesh Selector

Dashboard, TUI, and Apple client gain a mesh selector with:

- `Local`
- named peers, such as `Home`, `Work`, `Mobile`, and `VPS`
- `All Mesh`

The selected peer controls the default routing target for commands, status views, logs, and task details. `All Mesh` shows aggregated projections and makes target selection explicit for mutating actions.

### Peer Mentions

Messages and command surfaces can include peer mentions:

```text
@home run release build
@work show project status
@mesh who is online?
```

Mention parsing is UI/input resolution only. The runtime receives structured target fields such as:

- `targetNodeId`
- `targetScope`
- `projectId`
- `messageIntent`

The system must not infer routing or completion behavior from localized free-form phrases.

### Task Flow

A work peer can create and assign a task to home:

1. Work emits `task.created`.
2. Work emits `task.assigned` with target `home`.
3. VPS/home relay routes the assignment to home if online, or stores it for later delivery.
4. Home emits `task.status.updated` values such as `claimed`, `started`, `progress`, `ready_for_review`, or `failed`.
5. Work and mobile catch up by syncing events and rebuilding projection.

## Shared Projects

Shared projects become replicated mesh objects.

Project fields:

- stable project id
- display name
- repo URL
- default branch
- event scope
- policies
- members

Member fields:

- node id
- role
- local repo path for that node
- actor id when needed
- permissions

Project policies keep the current defaults unless changed by a signed event:

- `branchPerTask = true`
- `directPushToMain = false`
- `requireCleanWorktree = true`
- `requireTestsBeforeReady = true`

Workers still execute against their own local checkouts. Mesh coordinates who should do what; Git remains the artifact transport for code.

## Data Flow

### Online Delivery

1. Peer signs a mesh event.
2. Peer appends it to local event log.
3. Peer sends it to configured relay/mailbox peers.
4. Relay verifies envelope integrity and routes to connected targets.
5. Receiving peer verifies signature, authorization, and causal requirements.
6. Receiving peer appends the event and updates projection.

### Offline Catch-Up

1. Offline peer reconnects to VPS, home, or another relay-capable peer.
2. Peers exchange event log cursors.
3. Missing events are transferred in bounded batches.
4. Receiver verifies and applies each event.
5. Projection rebuilds or incrementally updates.

### Conflict Handling

The first version should avoid complex multi-writer conflicts by using clear merge rules:

- task status is append-only history; projection shows the latest authorized status by logical timestamp
- project membership removals override later events from the removed member unless those later events causally precede revocation
- alias conflicts are allowed internally but UI must show disambiguation
- duplicate events are ignored by event id

## Migration From Current Mesh

Current implementation pieces to preserve:

- `MeshEnvelope`
- relay WebSocket endpoint at `/v1/node/mesh/ws`
- `NodeIdentity`
- `NodeMeshClient`
- `NodeMeshRelay`
- shared project model
- task status model
- Core API mesh routes
- dashboard node/project/task views

Pieces to evolve:

- `NodeMeshStore` should persist signed events and derive the current state projection.
- task dispatch should be derived from `task.assigned` events.
- relay delivery should store signed events/envelopes as mailbox data, not coordinator-owned truth.
- Core API should expose both projection and sync/event ingestion surfaces.
- dashboard/TUI/client should target peers by resolved `nodeId`.

Compatibility bridge:

- Existing `mesh.json` can be imported into an initial event log by emitting bootstrap events signed by the local identity that owns the migration.
- Existing coordinator deployments can keep working in compatibility mode until peer event sync is enabled.

## API Surface

Initial Core API additions:

- `GET /v1/node/mesh/events?cursor=...`
- `POST /v1/node/mesh/events`
- `GET /v1/node/mesh/projection`
- `GET /v1/node/mesh/peers`
- `POST /v1/node/mesh/sync`

Existing endpoints for nodes, shared projects, tasks, and audit log can continue to serve projection views.

WebSocket additions:

- `event.publish`
- `event.batch`
- `event.cursor`
- `event.ack`
- `event.reject`

Reject frames should include structured reason codes, such as:

- `invalid_signature`
- `unknown_actor`
- `permission_denied`
- `schema_unsupported`
- `causal_parent_missing`

## Security Requirements

- Every state-changing event must be signed by the actor identity.
- Relay peers must not be able to forge actor events.
- Private keys never leave the local node or secure platform storage.
- ACL projection must be deterministic and test-covered.
- Event ingestion must be idempotent.
- Revocation must be represented as an event and visible in audit history.
- Dangerous operations such as shell, agent spawning, and file writes require explicit permissions.

## Reliability Requirements

- Peers can operate while disconnected and sync later.
- Relay/mailbox peers retain pending events for offline peers.
- Event sync is resumable by cursor.
- Duplicate delivery is harmless.
- Projection can be rebuilt from event log.
- UI clearly distinguishes stale/offline status from live status.

## Testing Strategy

Unit tests:

- signed event encoding and verification
- event id idempotency
- ACL grant and revoke projection
- task lifecycle projection
- shared project membership projection
- alias resolution and disambiguation
- invalid event rejection

Integration tests:

- work peer creates a task while home is online
- work peer creates a task while home is offline; home receives it after reconnect
- mobile reads projection through relay
- VPS relay routes events without becoming actor authority
- revoked peer cannot create new project-scoped tasks

Compatibility tests:

- existing mesh state imports into bootstrap events
- existing node list/project/task HTTP projection endpoints remain stable

## First Implementation Slice

The first slice should be narrow and testable:

1. Add signed mesh event types and verification.
2. Add event log persistence beside the current projection.
3. Implement projection for nodes, shared projects, ACL, and tasks.
4. Route `task.created`, `task.assigned`, and `task.status.updated` through event ingestion.
5. Keep existing coordinator routes as projection-backed compatibility APIs.
6. Add a basic peer selector/target model before deeper UI polish.

This slice is enough to let work assign a task to home through VPS/home relay while preserving the product rule that no peer is the authority.

## Open Decisions

- Exact key storage strategy for Apple client and server deployments.
- Whether event sync cursors are per-peer vector clocks or compact per-log offsets in the first slice.
- Whether VPS should persist encrypted mailbox payloads in the first version.
- How much of peer mention UX belongs in TUI first versus dashboard/client first.

