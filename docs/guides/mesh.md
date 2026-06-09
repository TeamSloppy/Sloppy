---
layout: doc
title: SloppyNode Mesh
---

# SloppyNode Mesh

SloppyNode Mesh connects several `SloppyNode` instances through a Sloppy relay so they can discover each other, share project metadata, route node RPC calls, and dispatch project tasks to remote workers.

Use Mesh when one Sloppy installation should coordinate work across multiple machines: for example, a laptop that owns the project board and a workstation that can run heavier local builds, tests, or agent work.

## What Mesh Provides

| Capability | Purpose |
| --- | --- |
| Node registry | Tracks known nodes, roles, capabilities, and online/offline status. |
| Relay WebSocket | Routes authenticated mesh envelopes between connected nodes at `/v1/node/mesh/ws`. |
| Shared projects | Maps one Git repository to per-node local checkout paths and permissions. |
| Task dispatch | Records a mesh task and sends a `task.dispatch` envelope to the assigned node. |
| Node RPC | Sends typed requests such as `node.status`, `node.capabilities`, or `project.status` to another node. |
| Audit log | Records routing, authorization, task, invite, and project membership events. |

Mesh is not a replacement for Git, CI, or the main Sloppy project board. It is the transport and coordination layer that lets nodes participate in the same project safely.

## Concepts

### Coordinator

The coordinator is a `sloppy run` server with Mesh relay enabled. It owns the Core API, the WebSocket relay, and the mesh state file configured by `core.nodeMesh.statePath`.

Start a coordinator with a public relay URL:

```bash
sloppy run --relay-public-url https://sloppy.example.com
```

For a relay-only process without the bundled dashboard:

```bash
sloppy run --relay-only --relay-public-url https://sloppy.example.com
```

`http` and `https` relay URLs are resolved by nodes to `/v1/node/mesh/ws` with `ws` or `wss`. If you pass a `ws://` or `wss://` URL directly, the path is used as-is.

Coordinator-side `sloppy-node` mesh commands must use the same mesh state file as the Sloppy server. The server default is `node/mesh.json` relative to the Sloppy config directory. If you manage mesh metadata from the standalone CLI, set a helper variable first:

```bash
MESH_STATE=/path/to/sloppy-config-dir/node/mesh.json
```

### Node

A node is a `SloppyNode` process with a local identity in `~/.sloppy/node.json`. The identity includes:

- `nodeId`
- human-readable name
- public/private key pair
- roles, such as `worker`
- capabilities, such as `run_agent` or `git`
- optional relay URL

Nodes authenticate to the relay by signing an `auth.challenge` nonce with their private key. The relay accepts the connection only when the node is already registered in mesh state and the signature matches the registered public key.

### Shared Project

A shared project describes a Git repository that multiple mesh nodes can work on. Each member node stores its own local checkout path and permission set.

Shared project policies default to:

| Policy | Default | Meaning |
| --- | --- | --- |
| `branchPerTask` | `true` | Workers should use a task-specific branch. |
| `directPushToMain` | `false` | Workers must not push directly to the default branch. |
| `requireCleanWorktree` | `true` | Work should start from a clean checkout. |
| `requireTestsBeforeReady` | `true` | Workers should run tests before marking work ready for review. |

## Quick Start

### 1. Create a Mesh Network

On the coordinator machine:

```bash
sloppy-node network-create \
  --mesh-path "$MESH_STATE" \
  --id personal \
  --name "Personal Mesh"
```

This initializes or updates coordinator mesh metadata.

### 2. Create an Invite

Still on the coordinator:

```bash
sloppy-node invite-create \
  --mesh-path "$MESH_STATE" \
  --network personal \
  --name build-mac \
  --roles worker \
  --capabilities run_agent,git
```

The command prints a one-time invite token, the granted roles and capabilities, and its expiration time.

### 3. Join from a Worker Node

On the worker machine:

```bash
sloppy-node join \
  --relay https://sloppy.example.com \
  --invite <invite-token> \
  --name build-mac
```

This creates or updates `~/.sloppy/node.json`, consumes the invite in local mesh state, and stores the relay URL in node config.

If a local node config already exists and you intentionally want to replace it:

```bash
sloppy-node join \
  --relay https://sloppy.example.com \
  --invite <invite-token> \
  --name build-mac \
  --force
```

### 4. Start the Worker

```bash
sloppy-node start
```

Or override the configured relay:

```bash
sloppy-node start --relay https://sloppy.example.com
```

When connected, the node sends `node.hello`, then periodic `node.heartbeat` envelopes. The relay marks the node offline when the WebSocket disconnects.

### 5. Check the Registry

On the coordinator:

```bash
sloppy-node list --mesh-path "$MESH_STATE"
```

Through the Core API:

```bash
curl http://127.0.0.1:8787/v1/node/mesh/nodes
```

## Shared Projects

Create a shared project:

```bash
sloppy-node shared-project-create \
  --mesh-path "$MESH_STATE" \
  --name Sloppy \
  --repo git@github.com:TeamSloppy/Sloppy.git \
  --default-branch main
```

Attach the coordinator or controller checkout:

```bash
sloppy-node shared-project-attach \
  --mesh-path "$MESH_STATE" \
  --project Sloppy \
  --node <controller-node-id> \
  --path /Users/alice/Developer/Sloppy \
  --role controller \
  --permissions project.read,project.write,task.create,task.assign,task.update,node.rpc
```

Attach a worker checkout:

```bash
sloppy-node shared-project-attach \
  --mesh-path "$MESH_STATE" \
  --project Sloppy \
  --node <worker-node-id> \
  --path /Users/build/Developer/Sloppy \
  --role worker \
  --permissions project.read,task.update,node.rpc
```

List shared projects:

```bash
sloppy-node shared-project-list --mesh-path "$MESH_STATE"
```

Update project metadata or policies:

```bash
sloppy-node shared-project-update \
  --mesh-path "$MESH_STATE" \
  --project Sloppy \
  --require-clean-worktree true \
  --require-tests-before-ready true \
  --direct-push-to-main false
```

Remove a member:

```bash
sloppy-node shared-project-remove-member \
  --mesh-path "$MESH_STATE" \
  --project Sloppy \
  --node <worker-node-id>
```

## Dispatch Tasks

Create a mesh task for a specific node:

```bash
sloppy-node task-create \
  --mesh-path "$MESH_STATE" \
  --project Sloppy \
  --title "Run release build on macOS worker" \
  --assign <worker-node-id>
```

The task starts as a mesh record, then the relay sends a `task.dispatch` envelope to the assigned node. If the node is offline, the relay records the delivery failure and will try pending dispatch envelopes when the node reconnects.

List tasks:

```bash
sloppy-node task-list --mesh-path "$MESH_STATE" --project Sloppy
```

Update task status:

```bash
sloppy-node task-status \
  --mesh-path "$MESH_STATE" \
  --task mesh_task_123 \
  --status ready_for_review \
  --actor <worker-node-id> \
  --branch agent/build-mac/mesh-task-123-run-release-build \
  --commit abc1234 \
  --summary "Release build passed on macOS."
```

Supported task statuses:

- `queued`
- `dispatched`
- `claimed`
- `started`
- `progress`
- `blocked`
- `ready_for_review`
- `failed`

## Node RPC

Mesh RPC requests are regular mesh envelopes with `type: "rpc.request"`. The target node responds with `type: "rpc.response"`.

Built-in RPC methods:

| Method | Result |
| --- | --- |
| `node.ping` | Basic liveness response with server time. |
| `node.status` | Local `SloppyNode` daemon status. |
| `node.capabilities` | Node roles and capabilities. |
| `project.status` | Shared project repo path, branch, dirty state, and recent mesh tasks. |
| `shared_project.list` | Shared projects visible to the caller. |
| `shared_project.get` | One visible shared project by id or name. |

Create an offline RPC envelope in mesh state:

```bash
sloppy-node rpc-request \
  --mesh-path "$MESH_STATE" \
  --from <controller-node-id> \
  --to <worker-node-id> \
  --method node.status
```

Send a live RPC over the configured relay:

```bash
sloppy-node rpc-request \
  --live \
  --to <worker-node-id> \
  --method project.status \
  --params '{"sharedProjectId":"Sloppy"}'
```

For RPC scoped to a shared project, the relay checks project membership and requires the caller to have `node.rpc`.

## HTTP API

The coordinator exposes mesh management over the Core API:

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/v1/node/mesh/nodes` | List known nodes and status. |
| `GET` | `/v1/node/mesh/shared-projects` | List shared projects and members. |
| `POST` | `/v1/node/mesh/shared-projects` | Create a shared project. |
| `PATCH` | `/v1/node/mesh/shared-projects/:projectId` | Update shared project metadata or policies. |
| `POST` | `/v1/node/mesh/shared-projects/:projectId/members` | Add or update a project member. |
| `GET` | `/v1/node/mesh/tasks?projectId=<id>` | List mesh tasks, optionally filtered by project. |
| `POST` | `/v1/node/mesh/tasks` | Dispatch a mesh task. |
| `PATCH` | `/v1/node/mesh/tasks/:taskId` | Update task lifecycle state and result metadata. |
| `GET` | `/v1/node/mesh/audit-log` | Read authorization, routing, and lifecycle audit entries. |
| `WS` | `/v1/node/mesh/ws` | Authenticated relay socket for connected nodes. |

Example shared project request:

```bash
curl -X POST http://127.0.0.1:8787/v1/node/mesh/shared-projects \
  -H 'content-type: application/json' \
  -d '{
    "name": "Sloppy",
    "repoUrl": "git@github.com:TeamSloppy/Sloppy.git",
    "defaultBranch": "main"
  }'
```

Example task dispatch request:

```bash
curl -X POST http://127.0.0.1:8787/v1/node/mesh/tasks \
  -H 'content-type: application/json' \
  -d '{
    "projectId": "sp_sloppy",
    "title": "Run release build on macOS worker",
    "assignedNodeId": "node_build_mac"
  }'
```

## Permissions

Mesh permissions are stored per shared project member.

| Permission | Use |
| --- | --- |
| `project.read` | Read shared project metadata and visible tasks. |
| `project.write` | Update shared project metadata. |
| `task.create` | Create mesh task records. |
| `task.assign` | Assign tasks to nodes. |
| `task.update` | Update task lifecycle status and result metadata. |
| `node.rpc` | Send project-scoped RPC requests to member nodes. |
| `node.shell` | Reserved for shell-level node actions. |
| `node.agent.spawn` | Allows worker execution paths that spawn an agent. |
| `node.files.read` | Reserved for file-read access through a node. |
| `node.files.write` | Reserved for file-write access through a node. |
| `node.relay` | Reserved for relay-style node behavior. |

Worker defaults are:

```text
project.read,task.update,node.rpc
```

Grant only the permissions required by that node's role. In particular, avoid broad `node.shell` or file permissions unless the node is trusted for that project.

## State Files

`sloppy-node` stores local node identity in:

```text
~/.sloppy/node.json
```

Standalone mesh commands store mesh state in:

```text
~/.sloppy/mesh.json
```

The Sloppy server stores coordinator mesh state through `core.nodeMesh.statePath`, which defaults to:

```text
node/mesh.json
```

Relative server paths are resolved under the Sloppy config directory. Use `--mesh-path` on `sloppy-node` commands when you need to point the standalone CLI at a different mesh state file.

## Audit Log

Print recent local mesh audit entries:

```bash
sloppy-node audit-log --mesh-path "$MESH_STATE" --limit 100
```

Or query the coordinator:

```bash
curl http://127.0.0.1:8787/v1/node/mesh/audit-log
```

Audit entries include time, actor, target, action, project, task, whether the action was allowed, and an optional message. They are useful for debugging invite consumption, node registration, authorization denials, unavailable targets, and task delivery.

## Troubleshooting

### The worker does not connect

Check that the relay URL is reachable from the worker and resolves to the WebSocket endpoint:

```bash
sloppy-node start --relay https://sloppy.example.com
```

Then inspect the coordinator node registry and audit log:

```bash
sloppy-node list --mesh-path "$MESH_STATE"
sloppy-node audit-log --mesh-path "$MESH_STATE" --limit 50
```

### Authentication fails

The relay verifies that the connecting node is registered and that the auth response is signed by the registered public key. Recreate the invite and rejoin if the worker's `~/.sloppy/node.json` was replaced after registration.

### RPC returns `forbidden`

For shared project scoped RPC, both source and target must be project members, and the source member must have `node.rpc`.

Review membership:

```bash
sloppy-node shared-project-list --mesh-path "$MESH_STATE"
```

Then update member permissions with `shared-project-attach`.

### RPC returns `node_unavailable`

The target node is registered but does not currently have an active relay WebSocket. Start or restart the target:

```bash
sloppy-node start
```

### Task dispatch is not delivered

If the assigned node is offline, the relay records the failed delivery and keeps the dispatch envelope in mesh state. Start the assigned node; pending dispatches are sent after `node.hello`.

### Project status has no Git data

`project.status` reads Git state from the member's `localRepoPath`. Confirm the path exists on the target node and points to a Git checkout for the shared repository.
