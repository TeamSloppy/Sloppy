# Feature Plan: SloppyNode Mesh + Shared Projects

## 1. Summary

Build a secure SloppyNode mesh network where multiple Sloppy nodes can discover each other, maintain persistent connections, route events/RPC messages, and participate in shared projects.

The initial target architecture is **Git + VPS relay + SloppyNodes**:

- Git remains the source of truth for code.
- A VPS SloppyNode acts as relay/bootstrap/coordinator.
- A home Mac SloppyNode can live behind NAT with no public IP.
- A laptop SloppyNode can connect to the VPS and access projects/tasks/nodes across the mesh.
- Shared Projects become a first-class entity spanning multiple nodes, each with its own local repo path, agents, environment, and capabilities.

MVP should be relay-first rather than true direct P2P. Nodes communicate over secure persistent outbound connections, initially WSS/TLS, with future support for direct QUIC/WebRTC/WireGuard-style paths and relay fallback.

---

## 2. Goals

### Product goals

1. Allow a user to connect a laptop, home Mac, and VPS into one Sloppy network.
2. Allow the laptop to see and control work assigned to the home Mac even if the home Mac is behind NAT.
3. Allow any connected node to route access/events to other nodes according to permissions.
4. Support Shared Projects as a separate distributed project entity.
5. Allow remote/autopilot tasks to run on a selected node in that node's own environment.
6. Use Git for code synchronization and branches.
7. Use Sloppy mesh for events, task dispatch, status, node registry, and coordination.

### Technical goals

1. Create a SloppyNode daemon/runtime.
2. Support node identity with cryptographic keypairs.
3. Support secure node registration via one-time invite tokens.
4. Maintain persistent secure node connections to a relay/coordinator.
5. Route messages between nodes.
6. Implement basic RPC and event routing.
7. Implement Shared Project membership with per-node local paths.
8. Dispatch a task to a remote node.
9. Run project-scoped autopilot on the remote node.
10. Push result branches to Git.
11. Report status and audit all remote actions.

---

## 3. Non-goals for MVP

The MVP should explicitly avoid:

1. True direct peer-to-peer hole punching.
2. Multi-relay high availability.
3. Arbitrary remote shell by default.
4. Full end-to-end encrypted payloads for every message.
5. CRDT-based offline project state.
6. File synchronization outside Git.
7. Complex artifact storage.
8. Complex remote desktop/browser control.
9. Multi-tenant enterprise policy engine.
10. Automatic conflict resolution for Git merges.

These can be added in later phases.

---

## 4. Architecture

```text
                   ┌─────────────────────────┐
                   │      VPS SloppyNode      │
                   │ relay/bootstrap/API/DB   │
                   └────────────┬────────────┘
                                │
             ┌──────────────────┼──────────────────┐
             │                  │                  │
             ▼                  ▼                  ▼
    ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
    │ Laptop Node    │  │ Home Mac Node   │  │ Other Node     │
    │ controller     │  │ worker/autopilot│  │ worker/agent   │
    └────────────────┘  └────────────────┘  └────────────────┘
             │                  │
             └────── Git remote ┘
                  GitHub/GitLab/VPS Git
```

Responsibilities:

- **Git remote**: code, branches, commits, pull requests.
- **VPS SloppyNode**: relay, bootstrap, node registry, event routing, shared project coordination.
- **Laptop Node**: client/controller/reviewer.
- **Home Mac Node**: worker/autopilot in local environment.
- **Shared Project**: distributed project metadata, members, permissions, repo URL, local paths, task routing.

---

## 5. Core entities

### 5.1 SloppyNode

```ts
type SloppyNode = {
  id: string
  name: string
  publicKey: string
  roles: NodeRole[]
  endpoint?: string
  status: 'online' | 'offline' | 'degraded'
  lastSeenAt: string
  capabilities: NodeCapability[]
}
```

```ts
type NodeRole =
  | 'client'
  | 'worker'
  | 'autopilot'
  | 'relay'
  | 'bootstrap'
  | 'storage'
  | 'coordinator'
```

```ts
type NodeCapability =
  | 'run_agent'
  | 'run_shell'
  | 'git'
  | 'browser'
  | 'local_files'
  | 'long_running_tasks'
  | 'gpu'
  | 'docker'
  | 'ios_build'
```

---

### 5.2 SloppyNetwork

```ts
type SloppyNetwork = {
  id: string
  name: string
  ownerUserId: string
  nodes: SloppyNode[]
  trustPolicy: TrustPolicy
  relayPolicy: RelayPolicy
}
```

---

### 5.3 SharedProject

```ts
type SharedProject = {
  id: string
  name: string
  repoUrl: string
  defaultBranch: string
  members: SharedProjectMember[]
  taskStore: TaskStoreConfig
  eventScope: string
  policies: SharedProjectPolicies
}
```

---

### 5.4 SharedProjectMember

```ts
type SharedProjectMember = {
  nodeId: string
  actorId?: string
  localRepoPath: string
  role: 'owner' | 'controller' | 'worker' | 'reviewer'
  permissions: ProjectPermission[]
}
```

Important: `repoUrl` is shared, but `localRepoPath` is per node.

Example:

```yaml
id: sp_my_project
name: My Project
repo:
  url: git@github.com:me/my-project.git
  defaultBranch: main
members:
  - nodeId: node_laptop
    localPath: /Users/me/dev/my-project
    role: controller
  - nodeId: node_home_mac
    localPath: /Users/home/dev/my-project
    role: worker
```

---

## 6. Security model

Security must be designed into the first version.

### 6.1 Transport security

- All external connections use TLS.
- MVP transport: persistent WebSocket over TLS.
- Example endpoint: `wss://sloppy.example.com/node`.

### 6.2 Node identity

Each node has a cryptographic keypair:

```yaml
nodeId: node_home_mac_abc123
publicKey: ed25519:...
privateKey: stored locally only
```

Registration uses an invite token, but long-term auth uses node keys.

### 6.3 Invite flow

1. VPS/coordinator creates a one-time invite token.
2. New node joins with the invite.
3. New node generates a keypair.
4. Coordinator stores the public key.
5. Invite expires/is consumed.
6. Future connections authenticate via signed challenge.

Example CLI:

```bash
sloppy node invite create --network personal --role worker,autopilot
sloppy node join --relay https://sloppy.example.com --invite slp_invite_xxx
```

### 6.4 Challenge authentication

```text
server -> nonce
node -> sign(nonce, privateKey)
server -> verify(publicKey)
```

### 6.5 Authorization and ACL

Authentication answers: who are you?
Authorization answers: what can you do?

Example permissions:

```ts
type Permission =
  | 'project.read'
  | 'project.write'
  | 'task.create'
  | 'task.assign'
  | 'task.update'
  | 'node.rpc'
  | 'node.shell'
  | 'node.agent.spawn'
  | 'node.files.read'
  | 'node.files.write'
  | 'node.relay'
```

Dangerous permissions must be explicit:

- `node.shell`
- `node.files.read`
- `node.files.write`
- `node.agent.spawn`
- access to secrets
- browser/computer control

Remote shell should be disabled by default.

### 6.6 Audit log

Every remote action should be logged:

```json
{
  "time": "2026-...",
  "actor": "node_laptop",
  "target": "node_home_mac",
  "action": "task.dispatch",
  "project": "sp_personal_dev",
  "task": "PROJ-123",
  "allowed": true
}
```

---

## 7. Transport and protocol

### 7.1 MVP transport

Use relay-first persistent WSS:

```text
Home Mac Node -- outbound WSS/TLS --> VPS Node
Laptop Node   -- outbound WSS/TLS --> VPS Node
```

This works without public IP on the home Mac.

### 7.2 Future transport

V2/V3 can add:

- direct QUIC node-to-node;
- WebRTC data channels;
- NAT traversal;
- relay fallback;
- E2E encrypted payloads.

### 7.3 Message types

```ts
type MeshMessage =
  | NodeHello
  | NodeHeartbeat
  | NodeRegistryUpdate
  | EventPublish
  | EventSubscribe
  | RpcRequest
  | RpcResponse
  | StreamOpen
  | StreamChunk
  | StreamClose
  | TaskDispatch
  | TaskStatusUpdate
  | ProjectSyncEvent
```

### 7.4 Envelope

```ts
type MeshEnvelope = {
  id: string
  type: string
  from: string
  to?: string
  scope?: string
  timestamp: string
  payload: unknown
  signature?: string
}
```

### 7.5 RPC example

```json
{
  "type": "rpc.request",
  "id": "req_123",
  "from": "node_laptop",
  "to": "node_home_mac",
  "method": "project.status",
  "params": {
    "sharedProjectId": "sp_personal_dev"
  }
}
```

Response:

```json
{
  "type": "rpc.response",
  "id": "req_123",
  "from": "node_home_mac",
  "to": "node_laptop",
  "ok": true,
  "result": {
    "gitBranch": "agent/home/PROJ-123",
    "dirty": false,
    "runningTasks": []
  }
}
```

### 7.6 Event example

```json
{
  "type": "event.publish",
  "scope": "sharedProject:sp_personal_dev",
  "event": {
    "type": "task.updated",
    "taskId": "PROJ-123",
    "status": "ready_for_review"
  }
}
```

---

## 8. Shared Projects

Shared Project is a first-class distributed entity.

It contains:

- project ID;
- repo URL;
- default branch;
- members;
- per-node local repo path;
- roles;
- permissions;
- policies;
- task routing information;
- event scope.

### 8.1 Shared Project policies

Recommended initial policies:

```yaml
policies:
  branchPerTask: true
  directPushToMain: false
  requireCleanWorktree: true
  requireTestsBeforeReady: true
```

### 8.2 Code sync

Git remains responsible for code sync.

Rules:

1. One task = one branch.
2. Remote worker does not push directly to `main`.
3. Worker must verify clean worktree before starting.
4. Worker pushes result branch.
5. Controller reviews and merges.

Branch naming:

```text
agent/{nodeName}/{taskId}-{slug}
```

Example:

```text
agent/home-mac/PROJ-123-add-sync
```

### 8.3 Result handoff

Remote node reports:

```yaml
result:
  branch: agent/home-mac/PROJ-123-add-sync
  commit: abc123
  tests:
    - command: npm test
      status: passed
    - command: npm run build
      status: passed
  summary: Implemented feature X
```

---

## 9. User flows

### 9.1 Start VPS node

```bash
sloppy node init --name vps-main --role relay,bootstrap,coordinator
sloppy node start --public-url https://sloppy.example.com
```

Or as a service:

```bash
sloppy node install-service
systemctl enable --now sloppynode
```

### 9.2 Create network

```bash
sloppy network create personal
```

### 9.3 Invite home Mac

```bash
sloppy node invite create \
  --network personal \
  --name home-mac \
  --roles worker,autopilot
```

### 9.4 Join home Mac

```bash
sloppy node join \
  --relay https://sloppy.example.com \
  --invite slp_invite_xxx
```

### 9.5 Join laptop

```bash
sloppy node join \
  --relay https://sloppy.example.com \
  --invite slp_invite_yyy
```

### 9.6 List nodes

```bash
sloppy node list
```

Expected output:

```text
NODE ID         NAME         STATUS   ROLES
node_vps        VPS          online   relay,bootstrap
node_home_mac   Home Mac     online   worker,autopilot
node_laptop     MacBook      online   client,controller
```

### 9.7 Create shared project

```bash
sloppy shared-project create \
  --name my-project \
  --repo git@github.com:me/my-project.git \
  --default-branch main
```

### 9.8 Attach nodes to project

```bash
sloppy shared-project attach \
  --project my-project \
  --node node_laptop \
  --path /Users/me/dev/my-project \
  --role controller
```

```bash
sloppy shared-project attach \
  --project my-project \
  --node node_home_mac \
  --path /Users/home/dev/my-project \
  --role worker
```

### 9.9 Dispatch task to home Mac

```bash
sloppy task create \
  --project my-project \
  --title "Implement feature X" \
  --assign node_home_mac
```

Flow:

```text
Laptop creates task
  -> coordinator records task
  -> event task.created
  -> relay sends task.dispatch to home Mac
  -> home Mac claims task
  -> home Mac creates branch
  -> home Mac runs agent
  -> home Mac tests
  -> home Mac commits and pushes branch
  -> home Mac reports ready_for_review
  -> laptop receives push event
```

---

## 10. Implementation phases

### Phase 1: Node identity and daemon

Deliverables:

- `sloppy node init`
- local node config
- keypair generation
- node ID generation
- `sloppy node status`
- daemon start/stop support

Definition of done:

- A node can initialize itself and persist identity locally.
- A node can run as a foreground process.
- Node config survives restart.

---

### Phase 2: VPS relay and persistent connections

Deliverables:

- WSS relay endpoint
- node connection manager
- heartbeat
- online/offline status
- node registry
- `sloppy node list`

Definition of done:

- VPS node accepts secure node connections.
- Laptop and home Mac can connect via outbound WSS.
- VPS can show both nodes online.
- Offline nodes are detected.

---

### Phase 3: Invite flow and authentication

Deliverables:

- invite token creation
- node join command
- signed challenge auth
- public key registration
- invite expiration

Definition of done:

- New node can join using a one-time invite.
- Future connections authenticate by node key, not invite token.
- Unknown nodes are rejected.

---

### Phase 4: Message routing and RPC

Deliverables:

- message envelope
- request/response correlation
- routing by target node ID
- timeout handling
- basic RPC methods:
  - `node.ping`
  - `node.capabilities`
  - `node.status`
  - `project.status`

Definition of done:

- Laptop can call `node.ping` on home Mac through VPS.
- Laptop can request capabilities from home Mac.
- RPC failures/timeouts are reported cleanly.

---

### Phase 5: ACL and audit log

Deliverables:

- basic permission model
- project-scoped authorization checks
- dangerous permission gates
- audit log storage

Definition of done:

- Unauthorized RPC is denied.
- Every remote action is recorded.
- Remote shell is disabled unless explicitly permitted.

---

### Phase 6: Shared Project entity

Deliverables:

- shared project create/update/list
- repo URL and default branch
- node membership
- per-node local path
- member roles
- project event scope

Definition of done:

- A shared project can include laptop and home Mac with different local paths.
- Nodes can query their local configuration for a shared project.
- Project metadata is visible from connected nodes.

---

### Phase 7: Remote task dispatch

Deliverables:

- task assignment to node
- `task.dispatch` message
- remote claim/ack
- status events:
  - `task.claimed`
  - `task.started`
  - `task.progress`
  - `task.blocked`
  - `task.ready_for_review`

Definition of done:

- Laptop can create a task assigned to home Mac.
- Home Mac receives the task without polling.
- Laptop UI/CLI sees task state changes.

---

### Phase 8: Git execution policy

Deliverables:

- clean worktree check
- branch-per-task creation
- agent execution in local project path
- commit and push result branch
- result report with branch/commit/tests

Definition of done:

- Home Mac can receive a task, create a branch, run work, push branch, and report result.
- Dirty worktree blocks execution or requires explicit policy.
- Direct push to `main` is prevented by policy.

---

### Phase 9: UX and dashboard integration

Deliverables:

- node list UI
- node status indicators
- shared project members UI
- task assignment to node
- remote execution status
- branch ready-for-review display

Definition of done:

- User can see all nodes in the network.
- User can see which node is running a task.
- User can review branch/commit from task result.

---

## 11. MVP Definition of Done

The MVP is complete when:

1. A VPS SloppyNode can run as relay/bootstrap/coordinator.
2. A home Mac can join the network without public IP.
3. A laptop can join the same network.
4. `sloppy node list` shows all nodes and statuses.
5. Nodes maintain persistent secure connections.
6. Nodes authenticate using cryptographic identity.
7. A shared project can be created with one `repoUrl`.
8. Each node can have its own `localRepoPath` for the same shared project.
9. A task can be assigned to the home Mac node.
10. The home Mac receives the task through the relay.
11. The home Mac runs the task in its local environment.
12. The home Mac creates a task branch.
13. The home Mac pushes the branch to Git.
14. The laptop receives a `ready_for_review` event.
15. ACL checks protect remote operations.
16. Audit logs record all remote actions.

---

## 12. Future versions

### V2

- Direct node-to-node transport where possible.
- Relay fallback.
- E2E encrypted sensitive RPC payloads.
- Streamed logs.
- Node capability matching for task assignment.
- Artifact upload/download.
- Better dashboard topology view.
- Remote agent handoff.

### V3

- Multiple relay nodes.
- HA coordinator.
- Offline-first shared project state.
- CRDT/event-sourced task state.
- Advanced policy engine.
- Secrets management per node/project.
- WebRTC/QUIC transport.
- NAT hole punching.
- Self-hosted control plane package.

---

## 13. Recommended naming

Recommended feature name:

```text
SloppyNode Mesh
```

Recommended sub-feature names:

```text
Shared Projects
Remote Autopilot
Node Relay
Node Identity
Remote Task Dispatch
```

Avoid calling the MVP pure P2P. Better wording:

```text
SloppyNodes form a secure mesh network. Nodes can communicate directly when possible, or through relay nodes such as a VPS gateway.
```

---

## 14. Final recommendation

Build this in the following order:

1. SloppyNode daemon and identity.
2. VPS relay with persistent WSS connections.
3. Invite-based node join.
4. RPC/event routing.
5. ACL and audit logs.
6. Shared Project entity.
7. Remote task dispatch.
8. Git branch-per-task execution.
9. Dashboard/CLI UX.

This provides a practical MVP quickly while preserving a path toward real P2P, E2E encryption, and advanced distributed project coordination.
