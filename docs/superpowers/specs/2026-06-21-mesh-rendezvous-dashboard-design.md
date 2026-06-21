# Mesh Rendezvous Dashboard Design

## Goal

Make the mesh setup match the intended topology:

- Local Sloppy instances keep their own local Core API and dashboard.
- A VPS can act as the public transport coordinator, relay, and mailbox.
- Local nodes join that VPS relay without switching their dashboard API base to the VPS.
- Any authorized node can address any other node through the relay.

The coordinator is a transport role, not a mesh authority. Mesh authority comes from node identities, signed events, project ACLs, and event verification.

## Current Problem

The dashboard currently exposes an `Accept Invite` flow against the currently selected Core API:

```text
POST /v1/node/mesh/invites/accept
```

That is correct for accepting an invite inside the coordinator's own mesh state, but it is wrong for local onboarding. If a local dashboard posts a VPS invite to the local Core API, the local mesh state does not contain that invite and returns:

```text
Invite token was not found in this coordinator state.
This bundled token points to relay <vps-url>.
```

The user intent is different: the local machine should join the remote relay while the dashboard continues to talk to local Core.

## Concepts

### Core API Base

The dashboard's Core API base controls the local Sloppy instance. It must remain local for home, work, and mobile clients unless the user explicitly wants to administer the VPS itself.

Examples:

```text
Home dashboard -> Home Core API
Work dashboard -> Work Core API
VPS dashboard -> VPS Core API
```

### Mesh Relay URL

The mesh relay URL is a per-node connection target. It can point at the VPS:

```text
http://81.26.176.106:25102
```

It must not replace the dashboard Core API base.

### Transport Coordinator

The VPS coordinator:

- accepts node WebSocket connections;
- verifies relay authentication;
- stores pending envelopes;
- forwards events between connected nodes;
- exposes coordinator diagnostics and invite management;
- may expose a projection for convenience.

It does not become the only actor allowed to mutate mesh state.

### Peer Authority

State-changing mesh events are authorized by:

- the event signature;
- the actor node identity;
- project membership and permissions;
- deterministic projection rules.

This keeps A, B, C, and future mobile nodes equal at the protocol layer even when B is the only public transport node.

## Target Topology

```text
A = home/local
B = VPS/public relay
C = work/local
M = mobile client

A ---> B <--- C
M ---> B

C -> B -> A
A -> B -> C
M -> B -> A/C/B
```

B is the rendezvous point. A, C, and M remain local clients with their own dashboard/Core surfaces.

## Dashboard UX

### VPS Dashboard

The VPS dashboard should focus on coordinator operations:

- mesh network identity;
- public relay URL;
- create and revoke invites;
- connected and known nodes;
- pending envelopes;
- audit log;
- relay health.

Copy should call this "Coordinator" or "Relay", not "the mesh master".

### Local Dashboard

The local dashboard should focus on local node membership:

- local node identity;
- connected relay URL;
- connection status;
- known peers from the relay/projection;
- inbound and outbound pending events;
- local shared project checkout mappings;
- actions: `Join Remote Mesh`, `Reconnect`, `Leave Mesh`.

The local dashboard must not require switching API base to the VPS for joining.

## Invite Flows

### Coordinator: Create Invite

On the VPS:

1. User opens `Nodes` or `Mesh Coordinator`.
2. User creates an invite.
3. The invite includes or points to:
   - relay URL;
   - network id;
   - roles;
   - capabilities;
   - optional expected node id/public key for pre-authorized invites.
4. Dashboard displays the bundled `slp_mesh_...` token.

### Local: Join Remote Mesh

On home/work/mobile:

1. User opens local dashboard.
2. User clicks `Join Remote Mesh`.
3. User pastes `slp_mesh_...`.
4. Local Core parses the token and extracts relay URL.
5. Local Core creates or reuses the local node identity.
6. Local Core calls the coordinator's invite acceptance endpoint, not its own local acceptance endpoint.
7. Local Core stores:
   - relay URL;
   - node identity;
   - network id;
   - coordinator metadata.
8. Local node connects to the relay and sends `node.hello`.

Result: dashboard remains local, mesh transport points to VPS.

## API Shape

Add a local endpoint for joining a remote mesh:

```text
POST /v1/node/mesh/remote-joins
{
  "token": "slp_mesh_...",
  "name": "work-mac",
  "force": false
}
```

Behavior:

1. Parse token as `MeshInviteBundle`.
2. Resolve `bundle.relayURL`.
3. Ensure local node identity exists, or create it.
4. Send an accept/join request to the coordinator from the local Core service.
5. Save local node config with the relay URL.
6. Return local node record plus remote coordinator summary.

Keep the existing coordinator endpoint:

```text
POST /v1/node/mesh/invites/accept
```

But label it as a coordinator/admin operation, not the normal local join path.

## Error Handling

If a user pastes a remote invite into the coordinator accept modal on the wrong dashboard, the UI should not just show an error. It should detect the embedded relay URL and offer:

```text
This invite belongs to http://81.26.176.106:25102.

Use this local node to join that remote mesh?
[Join Remote Mesh] [Cancel]
```

If the local node cannot reach the coordinator, show:

```text
Could not reach relay coordinator at <url>.
Check URL, firewall, and that sloppy run --relay-public-url is running there.
```

If the invite is pre-authorized for a different public key, show:

```text
This invite is bound to another node identity.
Create a new invite for this machine or use --force to replace local identity.
```

## Security Rules

- The local node private key never leaves the local machine.
- The coordinator stores only public keys and invite metadata.
- Relay delivery does not imply authority; event signatures and ACLs still decide validity.
- Joining a remote mesh should not overwrite local identity unless `force` is explicit.
- The dashboard must clearly distinguish local Core API from remote relay URL.

## Testing

Add backend tests for:

- joining a remote bundled invite without changing local Core API state incorrectly;
- rejecting an invite bound to a different public key;
- preserving local node identity unless `force` is set;
- storing relay URL after successful remote join;
- surfacing coordinator unreachable errors.

Add dashboard/API tests for:

- local `Join Remote Mesh` sends to the new local endpoint;
- wrong-coordinator invite error offers the remote join path;
- dashboard API base remains unchanged after joining;
- relay URL is displayed separately from API base.

## Non-Goals

- Do not make the VPS the only authority for mesh state.
- Do not require local dashboards to switch API base to the VPS.
- Do not solve full multi-relay federation in this pass.
- Do not require the mobile client to be fully implemented in this pass; it should use the same join model later.
