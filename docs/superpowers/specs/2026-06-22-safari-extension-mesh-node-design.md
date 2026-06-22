# SafariExtension Mesh Node Design

Date: 2026-06-22

## Goal

Make the Safari Web Extension a first-class Sloppy mesh node. A user should be able to paste a bundled relay invite (`slp_mesh_...`) into the extension, have the extension accept that invite with the relay coordinator, and then chat with an agent exposed by another mesh node without requiring a local Sloppy Core HTTP server.

## Non-Goals

- Do not make the extension run local shell, git, or agent-worker jobs.
- Do not proxy through the local Core as the primary implementation.
- Do not implement streaming mesh chat in the first increment; mesh `core.http` currently returns complete HTTP responses.
- Do not add text heuristics for agent behavior or completion detection.

## Current Context

SafariExtension currently stores Core connection settings in `chrome.storage.local` and sends browser context through Core HTTP endpoints such as `/v1/browser/context-message`, `/v1/agents/:id/sessions`, and `/v1/agents/:id/sessions/:id/messages`.

The repository already defines the mesh protocol in Swift:

- `MeshInviteBundle` tokens start with `slp_mesh_` and contain `inviteToken`, `relayURL`, optional network metadata, and optional bound node identity fields.
- Invites are accepted by posting `MeshInviteAcceptRequest` to `${relayURL}/v1/node/mesh/invites/accept`.
- Relay WebSocket URLs resolve from `http(s)://relay` to `ws(s)://relay/v1/node/mesh/ws`.
- Relay authentication uses `auth.challenge` and `auth.response`; the response signs the nonce with the node Ed25519 private key.
- After auth, clients send `node.hello` and can issue `rpc.request` envelopes.
- Remote Core access is exposed as mesh RPC method `core.http`, returning a status, content type, and base64 body.

## Chosen Approach

Implement a JavaScript-only mesh node in the Safari Web Extension.

The extension will generate and persist its own mesh identity, accept relay invites directly, authenticate with the relay over WebSocket, and use `core.http` RPC to call Core API endpoints on a selected target mesh node. Existing direct Core HTTP behavior remains available as a fallback/manual mode.

This keeps mesh ownership inside the extension, avoids a local Core dependency, and matches the user's request that the extension itself become the mesh node.

## User-Facing Behavior

The settings dialog gains a Mesh section with:

- an invite token input for `slp_mesh_...` bundles;
- a Join Mesh action;
- mesh status showing relay/network/node identity after a successful join;
- target mesh node selection or input, used for agent chat requests;
- a toggle or mode indicator distinguishing Direct Core and Mesh transport.

When mesh mode is enabled and configured, the chat panel lists agents, sessions, and sends browser-context prompts by wrapping the same Core API calls in mesh `core.http` RPC requests to the selected target node.

If mesh is not configured, the extension behaves as it does today.

## Storage Model

Extend sanitized extension settings with a `mesh` object:

```json
{
  "enabled": true,
  "relayURL": "https://mesh.example.com",
  "networkId": "personal",
  "networkName": "VPS-Node",
  "targetNodeId": "node_home_mac_abcd",
  "identity": {
    "nodeId": "node_safari_extension_abcd",
    "name": "Safari Extension",
    "publicKey": "ed25519:...",
    "privateKey": "ed25519:...",
    "roles": ["client"],
    "capabilities": ["browser_context", "core_http"]
  },
  "joinedAt": "2026-06-22T00:00:00.000Z"
}
```

Private key material is stored in `chrome.storage.local` for the first increment. The implementation should keep the key contained in the background worker and avoid exposing it to page content scripts.

## Mesh Invite Acceptance

Joining mesh performs these steps:

1. Parse the bundled invite token.
2. Reuse an existing extension identity unless the user explicitly resets it.
3. If no identity exists, generate an Ed25519 keypair with WebCrypto and create a Swift-compatible identity shape.
4. If the invite is bound to a different public key, fail with a clear message.
5. POST to `${relayURL}/v1/node/mesh/invites/accept` with:
   - `token`: the original `slp_mesh_...` token;
   - `endpoint`: the relay URL;
   - `nodeId`, `name`, `publicKey`, `roles`, `capabilities` from the extension identity.
6. Persist relay/network metadata and the accepted node record.

The implementation should use the exact bundle JSON field names used by Swift: `v`, `inviteToken`, `relayURL`, `networkId`, `networkName`, `nodeId`, and `publicKey`.

## Relay RPC Transport

Add a mesh transport module responsible for one-shot Core HTTP RPC calls:

1. Resolve the relay URL to WebSocket URL.
2. Open WebSocket from the background service worker.
3. Wait for `auth.challenge`.
4. Sign the challenge nonce with the extension identity private key and send `auth.response`.
5. Send `node.hello`.
6. Send `rpc.request` to `targetNodeId`:

```json
{
  "method": "core.http",
  "params": {
    "method": "POST",
    "path": "/v1/agents/sloppy/sessions/session-1/messages",
    "headers": { "content-type": "application/json" },
    "bodyBase64": "..."
  }
}
```

7. Wait for the matching `rpc.response` by `requestId`.
8. Decode `result.status`, `result.contentType`, and `result.bodyBase64` into a Response-like object used by the existing panel API helpers.

The first implementation can open a WebSocket per request. It should centralize the transport so a persistent socket can be added later without changing panel call sites.

## Chat Data Flow

In direct mode, existing fetches stay unchanged.

In mesh mode:

- `listAgents` calls remote `GET /v1/agents` through mesh `core.http`.
- `listSessions` calls remote `GET /v1/agents/:agentId/sessions?limit=50`.
- `getSession` calls remote `GET /v1/agents/:agentId/sessions/:sessionId`.
- `listSlashCommands` calls remote `GET /v1/agents/:agentId/chat-slash-commands`.
- `postBrowserContext` first attempts remote `POST /v1/browser/context-message`; if that returns 404, it uses the existing session-message fallback through remote Core HTTP calls.
- `postBrowserContextStreaming` in mesh mode degrades to non-streaming `postBrowserContext` and emits a final completion event for the UI.

## Error Handling

Errors should be explicit and actionable:

- invalid invite token;
- unsupported invite version;
- relay URL missing or invalid;
- WebCrypto Ed25519 unavailable;
- invite public key mismatch;
- relay accept failure with HTTP status/body;
- relay WebSocket auth failure or timeout;
- target node missing or not selected;
- remote Core request failed, including remote HTTP status and path.

Do not infer agent progress or completion from assistant text. Use HTTP/RPC responses and existing structured session events only.

## Testing

Add JavaScript unit tests under `Apps/SafariExtension/Extension/Tests` for:

- parsing valid and invalid `slp_mesh_` invite bundles;
- resolving relay HTTP(S)/WS(S) URLs;
- generating Swift-compatible node IDs and key string prefixes;
- building invite accept payloads;
- preserving existing identity across joins;
- wrapping Core HTTP requests into `core.http` RPC envelopes;
- decoding mesh `core.http` responses;
- selecting mesh transport when `settings.mesh.enabled` is true;
- degrading mesh streaming calls to non-streaming completion.

Run:

```bash
cd Apps/SafariExtension/Extension && npm test
```

For Swift settings changes, run:

```bash
cd Apps/SafariExtension && swift test
```

## Open Implementation Notes

Safari WebCrypto Ed25519 support must be verified in the local test/runtime environment. If unavailable, the implementation should fail clearly rather than silently creating unusable keys. A later native-host fallback can be added if needed.

