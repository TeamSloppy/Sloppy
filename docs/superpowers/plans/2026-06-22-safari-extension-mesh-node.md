# SafariExtension Mesh Node Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Safari Web Extension a JavaScript-only Sloppy mesh node that can accept bundled relay invites and chat with agents through a selected mesh node.

**Architecture:** Add focused WebExtension modules for mesh identity, invite acceptance, and one-shot `core.http` RPC over relay WebSocket. Keep existing direct Core HTTP behavior, and route existing panel/background Core API calls through mesh only when `settings.mesh.enabled` is true and a target node is configured.

**Tech Stack:** Safari WebExtension Manifest V3, JavaScript ES modules, `chrome.storage.local`, WebCrypto Ed25519, WebSocket, Node built-in test runner.

## Global Constraints

- Package manager: SwiftPM plus WebExtension `npm test` under `Apps/SafariExtension/Extension`.
- Do not make the extension run local shell, git, or agent-worker jobs.
- Do not proxy through the local Core as the primary implementation.
- Do not implement streaming mesh chat in the first increment; mesh `core.http` currently returns complete HTTP responses.
- Do not add text heuristics for agent behavior or completion detection.
- Private key material is stored in `chrome.storage.local` for the first increment and must not be exposed to page content scripts.
- Existing direct Core HTTP behavior remains available when mesh is disabled.
- Use 2-space indentation, semicolons, and double quotes in WebExtension JavaScript.

---

## File Structure

- Create `Apps/SafariExtension/Extension/Resources/mesh.js`: pure mesh helpers plus WebCrypto identity, invite parsing/acceptance, WebSocket RPC, and Response-like mesh Core fetch adapter.
- Create `Apps/SafariExtension/Extension/Tests/mesh.test.mjs`: unit tests for mesh helpers and transport behavior.
- Modify `Apps/SafariExtension/Extension/Resources/panel.js`: sanitize/preserve mesh settings and route existing Core API helpers through injected mesh-aware fetch.
- Modify `Apps/SafariExtension/Extension/Resources/background.js`: expose mesh join/status/save messages, use mesh-aware API calls, and keep private key operations in the background worker.
- Modify `Apps/SafariExtension/Extension/Resources/contentScript.js`: add Mesh settings controls to the existing settings dialog.
- Modify `Apps/SafariExtension/Extension/Resources/panel.css`: style Mesh settings controls using the existing settings dialog style.
- Modify `Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs`: tests for mesh settings sanitization and mesh transport selection.
- Modify `Apps/SafariExtension/Extension/Tests/contentSelection.test.mjs`: tests for Mesh settings controls only if existing DOM tests cover the settings dialog.

---

### Task 1: Mesh Invite and Identity Helpers

**Files:**
- Create: `Apps/SafariExtension/Extension/Resources/mesh.js`
- Test: `Apps/SafariExtension/Extension/Tests/mesh.test.mjs`

**Interfaces:**
- Produces: `parseMeshInviteBundle(token: string): object`
- Produces: `resolveRelayWebSocketURL(relayURL: string): string`
- Produces: `makeNodeId(name: string, randomToken?: string): string`
- Produces: `base64URLToBytes(value: string): Uint8Array`
- Produces: `bytesToBase64URL(bytes: Uint8Array): string`
- Produces: `buildMeshInviteAcceptPayload(token: string, identity: object, bundle?: object): object`
- Produces: `normalizeMeshSettings(mesh?: object): object`

- [ ] **Step 1: Write the failing mesh helper tests**

Add `Apps/SafariExtension/Extension/Tests/mesh.test.mjs`:

```js
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  buildMeshInviteAcceptPayload,
  makeNodeId,
  normalizeMeshSettings,
  parseMeshInviteBundle,
  resolveRelayWebSocketURL
} from "../Resources/mesh.js";

function bundleToken(payload) {
  const json = JSON.stringify(payload);
  const encoded = Buffer.from(json, "utf8")
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
  return `slp_mesh_${encoded}`;
}

test("parseMeshInviteBundle decodes Swift-compatible bundled invite tokens", () => {
  const token = bundleToken({
    v: 1,
    inviteToken: "slp_invite_remote",
    relayURL: "https://mesh.example.com",
    networkId: "personal",
    networkName: "VPS-Node",
    nodeId: "node_bound",
    publicKey: "ed25519:bound"
  });

  assert.deepEqual(parseMeshInviteBundle(token), {
    version: 1,
    inviteToken: "slp_invite_remote",
    relayURL: "https://mesh.example.com",
    networkId: "personal",
    networkName: "VPS-Node",
    nodeId: "node_bound",
    publicKey: "ed25519:bound",
    token
  });
});

test("parseMeshInviteBundle rejects invalid tokens and unsupported versions", () => {
  assert.throws(() => parseMeshInviteBundle("slp_invite_plain"), /Mesh invite bundle token is invalid/);
  assert.throws(() => parseMeshInviteBundle("slp_mesh_not-base64"), /payload is invalid/);
  assert.throws(() => parseMeshInviteBundle(bundleToken({ v: 2, inviteToken: "x", relayURL: "https://mesh.example.com" })), /version 2 is not supported/);
  assert.throws(() => parseMeshInviteBundle(bundleToken({ v: 1, inviteToken: "", relayURL: "" })), /payload is invalid/);
});

test("resolveRelayWebSocketURL matches Swift relay URL rules", () => {
  assert.equal(resolveRelayWebSocketURL("https://sloppy.example.com"), "wss://sloppy.example.com/v1/node/mesh/ws");
  assert.equal(resolveRelayWebSocketURL("http://127.0.0.1:8787/"), "ws://127.0.0.1:8787/v1/node/mesh/ws");
  assert.equal(resolveRelayWebSocketURL("ws://relay.local/custom"), "ws://relay.local/custom");
  assert.equal(resolveRelayWebSocketURL("wss://relay.local/custom"), "wss://relay.local/custom");
  assert.throws(() => resolveRelayWebSocketURL("ftp://relay.local"), /Unsupported relay URL scheme/);
});

test("makeNodeId creates Swift-style node IDs", () => {
  assert.equal(makeNodeId("Safari Extension", "abc123"), "node_safari-extension_abc123");
  assert.equal(makeNodeId("   ", "abc123"), "node_node_abc123");
});

test("buildMeshInviteAcceptPayload uses the original bundled token and identity", () => {
  const token = bundleToken({ v: 1, inviteToken: "slp_invite_remote", relayURL: "https://mesh.example.com" });
  const bundle = parseMeshInviteBundle(token);
  const identity = {
    nodeId: "node_safari_123",
    name: "Safari Extension",
    publicKey: "ed25519:public",
    roles: ["client"],
    capabilities: ["browser_context", "core_http"]
  };

  assert.deepEqual(buildMeshInviteAcceptPayload(token, identity, bundle), {
    token,
    endpoint: "https://mesh.example.com",
    nodeId: "node_safari_123",
    name: "Safari Extension",
    publicKey: "ed25519:public",
    roles: ["client"],
    capabilities: ["browser_context", "core_http"]
  });
});

test("normalizeMeshSettings preserves configured mesh state and defaults disabled", () => {
  assert.deepEqual(normalizeMeshSettings(), { enabled: false });
  assert.deepEqual(normalizeMeshSettings({
    enabled: true,
    relayURL: " https://mesh.example.com/ ",
    targetNodeId: " node_home ",
    networkId: " personal ",
    networkName: " VPS-Node ",
    identity: { nodeId: "node_safari", publicKey: "ed25519:public", privateKey: "ed25519:private" }
  }), {
    enabled: true,
    relayURL: "https://mesh.example.com",
    targetNodeId: "node_home",
    networkId: "personal",
    networkName: "VPS-Node",
    identity: { nodeId: "node_safari", publicKey: "ed25519:public", privateKey: "ed25519:private" }
  });
});
```

- [ ] **Step 2: Run the mesh helper tests and verify they fail**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test -- Tests/mesh.test.mjs
```

Expected: FAIL because `../Resources/mesh.js` does not exist or the exported functions are missing.

- [ ] **Step 3: Implement the minimal mesh helpers**

Create `Apps/SafariExtension/Extension/Resources/mesh.js`:

```js
export function bytesToBase64URL(bytes) {
  const binary = Array.from(bytes, (byte) => String.fromCharCode(byte)).join("");
  const base64 = typeof btoa === "function"
    ? btoa(binary)
    : Buffer.from(bytes).toString("base64");
  return base64.replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

export function base64URLToBytes(value) {
  let normalized = String(value || "").replaceAll("-", "+").replaceAll("_", "/");
  const remainder = normalized.length % 4;
  if (remainder > 0) {
    normalized += "=".repeat(4 - remainder);
  }
  const binary = typeof atob === "function"
    ? atob(normalized)
    : Buffer.from(normalized, "base64").toString("binary");
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function parseMeshInviteBundle(token) {
  const text = String(token || "").trim();
  const prefix = "slp_mesh_";
  if (!text.startsWith(prefix)) {
    throw new Error("Mesh invite bundle token is invalid.");
  }

  let payload;
  try {
    const bytes = base64URLToBytes(text.slice(prefix.length));
    payload = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new Error("Mesh invite bundle payload is invalid.");
  }

  const version = Number(payload?.v);
  if (version !== 1) {
    throw new Error(`Mesh invite bundle version ${version} is not supported.`);
  }
  if (!payload.inviteToken || !payload.relayURL) {
    throw new Error("Mesh invite bundle payload is invalid.");
  }

  return {
    version,
    inviteToken: String(payload.inviteToken),
    relayURL: String(payload.relayURL),
    networkId: payload.networkId ? String(payload.networkId) : undefined,
    networkName: payload.networkName ? String(payload.networkName) : undefined,
    nodeId: payload.nodeId ? String(payload.nodeId) : undefined,
    publicKey: payload.publicKey ? String(payload.publicKey) : undefined,
    token: text
  };
}

export function resolveRelayWebSocketURL(relayURL) {
  let url;
  try {
    url = new URL(String(relayURL || "").trim());
  } catch {
    throw new Error(`Invalid relay URL: ${relayURL}`);
  }
  if (url.protocol === "http:") {
    url.protocol = "ws:";
    url.pathname = "/v1/node/mesh/ws";
  } else if (url.protocol === "https:") {
    url.protocol = "wss:";
    url.pathname = "/v1/node/mesh/ws";
  } else if (url.protocol !== "ws:" && url.protocol !== "wss:") {
    throw new Error(`Unsupported relay URL scheme: ${url.protocol.replace(":", "")}`);
  }
  return url.toString();
}

export function makeNodeId(name, randomToken = randomBase64URL(6)) {
  const slug = String(name || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `node_${slug || "node"}_${randomToken}`;
}

export function normalizeMeshSettings(mesh = {}) {
  if (!mesh || typeof mesh !== "object") {
    return { enabled: false };
  }
  const normalized = { enabled: Boolean(mesh.enabled) };
  const relayURL = trimTrailingSlashes(mesh.relayURL);
  const targetNodeId = String(mesh.targetNodeId || "").trim();
  const networkId = String(mesh.networkId || "").trim();
  const networkName = String(mesh.networkName || "").trim();
  if (relayURL) normalized.relayURL = relayURL;
  if (targetNodeId) normalized.targetNodeId = targetNodeId;
  if (networkId) normalized.networkId = networkId;
  if (networkName) normalized.networkName = networkName;
  if (mesh.identity && typeof mesh.identity === "object") {
    normalized.identity = mesh.identity;
  }
  if (mesh.joinedAt) {
    normalized.joinedAt = String(mesh.joinedAt);
  }
  if (mesh.acceptedNode && typeof mesh.acceptedNode === "object") {
    normalized.acceptedNode = mesh.acceptedNode;
  }
  return normalized;
}

export function buildMeshInviteAcceptPayload(token, identity, bundle = parseMeshInviteBundle(token)) {
  if (bundle.publicKey && bundle.publicKey !== identity.publicKey) {
    throw new Error("This invite is bound to another node identity.");
  }
  return {
    token: String(token || "").trim(),
    endpoint: bundle.relayURL,
    nodeId: identity.nodeId,
    name: identity.name,
    publicKey: identity.publicKey,
    roles: identity.roles || ["client"],
    capabilities: identity.capabilities || ["browser_context", "core_http"]
  };
}

function trimTrailingSlashes(value) {
  return String(value || "").trim().replace(/\/+$/, "");
}

function randomBase64URL(byteCount) {
  const bytes = new Uint8Array(byteCount);
  if (globalThis.crypto?.getRandomValues) {
    globalThis.crypto.getRandomValues(bytes);
  } else {
    for (let index = 0; index < bytes.length; index += 1) {
      bytes[index] = Math.floor(Math.random() * 256);
    }
  }
  return bytesToBase64URL(bytes);
}
```

- [ ] **Step 4: Run the mesh helper tests and verify they pass**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test -- Tests/mesh.test.mjs
```

Expected: PASS for all tests in `mesh.test.mjs`.

- [ ] **Step 5: Commit Task 1**

```bash
git add Apps/SafariExtension/Extension/Resources/mesh.js Apps/SafariExtension/Extension/Tests/mesh.test.mjs
git commit -m "Add Safari extension mesh invite helpers"
```

---

### Task 2: Mesh Identity, Invite Acceptance, and Core HTTP RPC Transport

**Files:**
- Modify: `Apps/SafariExtension/Extension/Resources/mesh.js`
- Modify: `Apps/SafariExtension/Extension/Tests/mesh.test.mjs`

**Interfaces:**
- Consumes: `parseMeshInviteBundle`, `resolveRelayWebSocketURL`, `buildMeshInviteAcceptPayload`, `bytesToBase64URL`, `base64URLToBytes`
- Produces: `createMeshIdentity(options?: object): Promise<object>`
- Produces: `signMeshChallenge(identity: object, nonce: string): Promise<string>`
- Produces: `buildAuthResponseEnvelope(identity: object, challengeEnvelope: object): Promise<object | null>`
- Produces: `buildNodeHelloEnvelope(identity: object): object`
- Produces: `buildCoreHTTPRPCEnvelope(identity: object, targetNodeId: string, request: object): object`
- Produces: `decodeCoreHTTPRPCResponse(envelope: object): Response`
- Produces: `acceptMeshInvite(options: object): Promise<object>`
- Produces: `meshCoreFetch(settings: object, path: string, options?: object, deps?: object): Promise<Response>`

- [ ] **Step 1: Add failing tests for identity, auth, accept, and RPC**

Append to `Apps/SafariExtension/Extension/Tests/mesh.test.mjs`:

```js
import {
  acceptMeshInvite,
  buildAuthResponseEnvelope,
  buildCoreHTTPRPCEnvelope,
  buildNodeHelloEnvelope,
  createMeshIdentity,
  decodeCoreHTTPRPCResponse,
  meshCoreFetch
} from "../Resources/mesh.js";

test("createMeshIdentity creates Swift-compatible Ed25519 identity fields", async () => {
  const identity = await createMeshIdentity({
    name: "Safari Extension",
    randomToken: "abc123",
    cryptoImpl: fakeCrypto()
  });

  assert.equal(identity.nodeId, "node_safari-extension_abc123");
  assert.equal(identity.name, "Safari Extension");
  assert.equal(identity.publicKey, "ed25519:cHVibGljLWtleQ");
  assert.equal(identity.privateKey, "ed25519:cHJpdmF0ZS1rZXk");
  assert.deepEqual(identity.roles, ["client"]);
  assert.deepEqual(identity.capabilities, ["browser_context", "core_http"]);
});

test("buildAuthResponseEnvelope signs auth challenge nonce", async () => {
  const identity = await createMeshIdentity({ cryptoImpl: fakeCrypto(), randomToken: "abc123" });
  const response = await buildAuthResponseEnvelope(identity, {
    id: "challenge-1",
    type: "auth.challenge",
    from: "relay",
    payload: {
      nonce: "nonce_auth",
      nodeId: identity.nodeId,
      publicKey: identity.publicKey
    }
  }, { cryptoImpl: fakeCrypto("signature") });

  assert.equal(response.type, "auth.response");
  assert.equal(response.from, identity.nodeId);
  assert.equal(response.to, "relay");
  assert.deepEqual(response.payload, {
    nonce: "nonce_auth",
    nodeId: identity.nodeId,
    publicKey: identity.publicKey,
    signature: "ed25519:c2lnbmF0dXJl"
  });
});

test("buildNodeHelloEnvelope announces the extension node", async () => {
  const identity = await createMeshIdentity({ cryptoImpl: fakeCrypto(), randomToken: "abc123" });
  assert.deepEqual(stripVolatileEnvelopeFields(buildNodeHelloEnvelope(identity)), {
    type: "node.hello",
    from: "node_safari-extension_abc123",
    payload: {
      name: "Safari Extension",
      publicKey: "ed25519:cHVibGljLWtleQ",
      roles: ["client"],
      capabilities: ["browser_context", "core_http"]
    }
  });
});

test("acceptMeshInvite reuses existing identity and persists accepted mesh settings", async () => {
  const token = bundleToken({ v: 1, inviteToken: "slp_invite_remote", relayURL: "https://mesh.example.com", networkId: "personal" });
  const existingIdentity = await createMeshIdentity({ cryptoImpl: fakeCrypto(), randomToken: "abc123" });
  const saved = [];
  const fetchImpl = async (url, options) => {
    assert.equal(url, "https://mesh.example.com/v1/node/mesh/invites/accept");
    assert.equal(JSON.parse(options.body).nodeId, existingIdentity.nodeId);
    return Response.json({ id: existingIdentity.nodeId, name: "Safari Extension" }, { status: 201 });
  };

  const result = await acceptMeshInvite({
    token,
    currentMesh: { identity: existingIdentity },
    fetchImpl,
    saveMesh: async (mesh) => saved.push(mesh)
  });

  assert.equal(result.mesh.identity.nodeId, existingIdentity.nodeId);
  assert.equal(result.mesh.enabled, true);
  assert.equal(result.mesh.relayURL, "https://mesh.example.com");
  assert.equal(result.mesh.networkId, "personal");
  assert.equal(saved[0].identity.nodeId, existingIdentity.nodeId);
});

test("buildCoreHTTPRPCEnvelope wraps Core requests for mesh core.http", async () => {
  const identity = await createMeshIdentity({ cryptoImpl: fakeCrypto(), randomToken: "abc123" });
  const envelope = buildCoreHTTPRPCEnvelope(identity, "node_home", {
    method: "POST",
    path: "/v1/agents/sloppy/sessions",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ title: "Safari" })
  });

  assert.equal(envelope.type, "rpc.request");
  assert.equal(envelope.from, identity.nodeId);
  assert.equal(envelope.to, "node_home");
  assert.equal(envelope.payload.method, "core.http");
  assert.equal(envelope.payload.params.method, "POST");
  assert.equal(envelope.payload.params.path, "/v1/agents/sloppy/sessions");
  assert.equal(Buffer.from(envelope.payload.params.bodyBase64, "base64").toString("utf8"), "{\"title\":\"Safari\"}");
});

test("decodeCoreHTTPRPCResponse returns a Response-like object", async () => {
  const response = decodeCoreHTTPRPCResponse({
    type: "rpc.response",
    payload: {
      requestId: "rpc-1",
      method: "core.http",
      ok: true,
      result: {
        status: 200,
        contentType: "application/json",
        bodyBase64: Buffer.from(JSON.stringify({ ok: true }), "utf8").toString("base64")
      }
    }
  });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/json");
  assert.deepEqual(await response.json(), { ok: true });
});

test("meshCoreFetch performs relay auth and returns core.http response", async () => {
  const identity = await createMeshIdentity({ cryptoImpl: fakeCrypto(), randomToken: "abc123" });
  const sent = [];
  const socketFactory = () => fakeSocket([
    { type: "auth.challenge", from: "relay", payload: { nonce: "nonce_auth", nodeId: identity.nodeId, publicKey: identity.publicKey } },
    { type: "rpc.response", from: "node_home", payload: { requestId: "rpc-fixed", method: "core.http", ok: true, result: { status: 200, contentType: "application/json", bodyBase64: Buffer.from("{\"agents\":[]}", "utf8").toString("base64") } } }
  ], sent);

  const response = await meshCoreFetch({
    mesh: {
      enabled: true,
      relayURL: "https://mesh.example.com",
      targetNodeId: "node_home",
      identity
    }
  }, "/v1/agents", { method: "GET" }, {
    cryptoImpl: fakeCrypto("signature"),
    makeRequestId: () => "rpc-fixed",
    socketFactory
  });

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { agents: [] });
  assert.equal(sent.some((envelope) => envelope.type === "auth.response"), true);
  assert.equal(sent.some((envelope) => envelope.type === "node.hello"), true);
  assert.equal(sent.some((envelope) => envelope.type === "rpc.request"), true);
});

function fakeCrypto(signature = "signature") {
  return {
    subtle: {
      async generateKey() {
        return { publicKey: "public", privateKey: "private" };
      },
      async exportKey(format, key) {
        assert.equal(format, "raw");
        return new TextEncoder().encode(`${key}-key`);
      },
      async importKey(_format, data) {
        return new TextDecoder().decode(data);
      },
      async sign() {
        return new TextEncoder().encode(signature);
      }
    },
    getRandomValues(bytes) {
      bytes.fill(7);
      return bytes;
    }
  };
}

function fakeSocket(inboundEnvelopes, sent) {
  const listeners = {};
  const socket = {
    addEventListener(type, listener) {
      listeners[type] = listener;
    },
    send(text) {
      sent.push(JSON.parse(text));
    },
    close() {},
    open() {
      listeners.open?.({});
      for (const envelope of inboundEnvelopes) {
        listeners.message?.({ data: JSON.stringify(envelope) });
      }
    }
  };
  queueMicrotask(() => socket.open());
  return socket;
}

function stripVolatileEnvelopeFields(envelope) {
  const { id, timestamp, ...stable } = envelope;
  assert.ok(id);
  assert.ok(timestamp);
  return stable;
}
```

- [ ] **Step 2: Run the mesh transport tests and verify they fail**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test -- Tests/mesh.test.mjs
```

Expected: FAIL because Task 2 exports are not implemented.

- [ ] **Step 3: Implement identity, accept, and RPC transport**

Extend `Apps/SafariExtension/Extension/Resources/mesh.js` with these exports:

```js
const defaultRoles = ["client"];
const defaultCapabilities = ["browser_context", "core_http"];

export async function createMeshIdentity(options = {}) {
  const cryptoImpl = options.cryptoImpl || globalThis.crypto;
  if (!cryptoImpl?.subtle?.generateKey) {
    throw new Error("WebCrypto Ed25519 is unavailable.");
  }
  let keyPair;
  try {
    keyPair = await cryptoImpl.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  } catch {
    throw new Error("WebCrypto Ed25519 is unavailable.");
  }
  const publicBytes = new Uint8Array(await cryptoImpl.subtle.exportKey("raw", keyPair.publicKey));
  const privateBytes = new Uint8Array(await cryptoImpl.subtle.exportKey("raw", keyPair.privateKey));
  const name = String(options.name || "Safari Extension").trim() || "Safari Extension";
  return {
    nodeId: makeNodeId(name, options.randomToken),
    name,
    publicKey: `ed25519:${bytesToBase64URL(publicBytes)}`,
    privateKey: `ed25519:${bytesToBase64URL(privateBytes)}`,
    roles: defaultRoles,
    capabilities: defaultCapabilities,
    createdAt: new Date().toISOString()
  };
}

export async function signMeshChallenge(identity, nonce, deps = {}) {
  const cryptoImpl = deps.cryptoImpl || globalThis.crypto;
  if (!cryptoImpl?.subtle?.importKey || !cryptoImpl?.subtle?.sign) {
    throw new Error("WebCrypto Ed25519 is unavailable.");
  }
  const privateKeyBytes = decodeKeyMaterial(identity.privateKey);
  const key = await cryptoImpl.subtle.importKey("raw", privateKeyBytes, { name: "Ed25519" }, false, ["sign"]);
  const signature = await cryptoImpl.subtle.sign({ name: "Ed25519" }, key, new TextEncoder().encode(nonce));
  return `ed25519:${bytesToBase64URL(new Uint8Array(signature))}`;
}

export async function buildAuthResponseEnvelope(identity, challengeEnvelope, deps = {}) {
  if (challengeEnvelope?.type !== "auth.challenge") {
    return null;
  }
  const challenge = challengeEnvelope.payload || {};
  if (challenge.nodeId && challenge.nodeId !== identity.nodeId) {
    return null;
  }
  const signature = await signMeshChallenge(identity, challenge.nonce, deps);
  return makeEnvelope({
    type: "auth.response",
    from: identity.nodeId,
    to: challengeEnvelope.from,
    scope: challengeEnvelope.scope,
    payload: {
      nonce: challenge.nonce,
      nodeId: identity.nodeId,
      publicKey: identity.publicKey,
      signature
    }
  });
}

export function buildNodeHelloEnvelope(identity) {
  return makeEnvelope({
    type: "node.hello",
    from: identity.nodeId,
    payload: {
      name: identity.name,
      publicKey: identity.publicKey,
      roles: identity.roles || defaultRoles,
      capabilities: identity.capabilities || defaultCapabilities
    }
  });
}

export function buildCoreHTTPRPCEnvelope(identity, targetNodeId, request, options = {}) {
  const body = request.body == null ? null : String(request.body);
  return makeEnvelope({
    id: options.requestId,
    type: "rpc.request",
    from: identity.nodeId,
    to: targetNodeId,
    payload: {
      method: "core.http",
      params: {
        method: String(request.method || "GET").toUpperCase(),
        path: request.path,
        headers: request.headers || {},
        ...(body == null ? {} : { bodyBase64: base64FromString(body) })
      }
    }
  });
}

export function decodeCoreHTTPRPCResponse(envelope) {
  const payload = envelope?.payload || {};
  if (payload.ok === false) {
    const message = payload.error?.message || payload.error?.code || "Remote Core request failed.";
    throw new Error(message);
  }
  const result = payload.result || {};
  const body = result.bodyBase64 ? stringFromBase64(result.bodyBase64) : "";
  return new Response(body, {
    status: Number(result.status || 500),
    headers: { "content-type": result.contentType || "application/octet-stream" }
  });
}

export async function acceptMeshInvite(options) {
  const token = String(options.token || "").trim();
  const bundle = parseMeshInviteBundle(token);
  const identity = options.currentMesh?.identity || await createMeshIdentity({
    name: options.name || "Safari Extension",
    cryptoImpl: options.cryptoImpl
  });
  const payload = buildMeshInviteAcceptPayload(token, identity, bundle);
  const url = new URL(bundle.relayURL);
  url.pathname = "/v1/node/mesh/invites/accept";
  url.search = "";
  const response = await (options.fetchImpl || fetch)(url.toString(), {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.message || body.error || `Mesh invite accept failed with HTTP ${response.status}.`);
  }
  const mesh = normalizeMeshSettings({
    ...options.currentMesh,
    enabled: true,
    relayURL: bundle.relayURL,
    networkId: bundle.networkId,
    networkName: bundle.networkName,
    identity,
    acceptedNode: body,
    joinedAt: new Date().toISOString()
  });
  await options.saveMesh?.(mesh);
  return { mesh, node: body };
}

export async function meshCoreFetch(settings, path, options = {}, deps = {}) {
  const mesh = normalizeMeshSettings(settings.mesh);
  if (!mesh.enabled || !mesh.relayURL || !mesh.targetNodeId || !mesh.identity) {
    throw new Error("Mesh target node is not configured.");
  }
  const requestId = deps.makeRequestId?.() || cryptoRandomId();
  const request = buildCoreHTTPRPCEnvelope(mesh.identity, mesh.targetNodeId, {
    method: options.method || "GET",
    path,
    headers: options.headers || {},
    body: options.body
  }, { requestId });
  const socketFactory = deps.socketFactory || ((url) => new WebSocket(url));
  const socket = socketFactory(resolveRelayWebSocketURL(mesh.relayURL));
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      socket.close?.();
      reject(new Error(`Mesh RPC request timed out: ${requestId}`));
    }, deps.timeoutMs || 30000);
    const fail = (error) => {
      clearTimeout(timeout);
      socket.close?.();
      reject(error instanceof Error ? error : new Error(String(error)));
    };
    const sendEnvelope = (envelope) => socket.send(JSON.stringify(envelope));
    socket.addEventListener("error", () => fail(new Error("Relay WebSocket failed.")));
    socket.addEventListener("message", (event) => {
      void (async () => {
        const envelope = JSON.parse(String(event.data));
        if (envelope.type === "auth.challenge") {
          const auth = await buildAuthResponseEnvelope(mesh.identity, envelope, deps);
          if (!auth) {
            fail(new Error("Relay auth challenge does not match this node."));
            return;
          }
          sendEnvelope(auth);
          sendEnvelope(buildNodeHelloEnvelope(mesh.identity));
          sendEnvelope(request);
          return;
        }
        if (envelope.type === "rpc.response" && envelope.payload?.requestId === requestId) {
          clearTimeout(timeout);
          socket.close?.();
          resolve(decodeCoreHTTPRPCResponse(envelope));
        }
      })().catch(fail);
    });
  });
}

function makeEnvelope(fields) {
  return {
    id: fields.id || cryptoRandomId(),
    type: fields.type,
    from: fields.from,
    ...(fields.to ? { to: fields.to } : {}),
    ...(fields.scope ? { scope: fields.scope } : {}),
    timestamp: new Date().toISOString(),
    payload: fields.payload || {}
  };
}

function decodeKeyMaterial(value) {
  const [, encoded] = String(value || "").split("ed25519:");
  if (!encoded) {
    throw new Error("Invalid node identity key material.");
  }
  return base64URLToBytes(encoded);
}

function base64FromString(value) {
  const bytes = new TextEncoder().encode(String(value));
  return typeof Buffer !== "undefined"
    ? Buffer.from(bytes).toString("base64")
    : btoa(Array.from(bytes, (byte) => String.fromCharCode(byte)).join(""));
}

function stringFromBase64(value) {
  if (typeof Buffer !== "undefined") {
    return Buffer.from(String(value), "base64").toString("utf8");
  }
  return new TextDecoder().decode(Uint8Array.from(atob(String(value)), (character) => character.charCodeAt(0)));
}

function cryptoRandomId() {
  if (globalThis.crypto?.randomUUID) {
    return globalThis.crypto.randomUUID();
  }
  return `mesh_rpc_${randomBase64URL(12)}`;
}
```

- [ ] **Step 4: Run the mesh transport tests and verify they pass**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test -- Tests/mesh.test.mjs
```

Expected: PASS for `mesh.test.mjs`.

- [ ] **Step 5: Commit Task 2**

```bash
git add Apps/SafariExtension/Extension/Resources/mesh.js Apps/SafariExtension/Extension/Tests/mesh.test.mjs
git commit -m "Add Safari extension mesh RPC transport"
```

---

### Task 3: Route Panel Core API Calls Through Mesh Mode

**Files:**
- Modify: `Apps/SafariExtension/Extension/Resources/panel.js`
- Modify: `Apps/SafariExtension/Extension/Resources/background.js`
- Modify: `Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs`

**Interfaces:**
- Consumes: `normalizeMeshSettings(mesh)`, `meshCoreFetch(settings, path, options, deps)`
- Produces: `coreFetch(settings: object, path: string, options?: object, fetchImpl?: Function): Promise<Response>`
- Produces: `sanitizeSettings(settings?: object): object` preserving `mesh`
- Produces: background message `sloppy.mesh.join`
- Produces: background message `sloppy.mesh.status`

- [ ] **Step 1: Add failing panel/background transport tests**

Update imports in `Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs` to include `coreFetch`, then append:

```js
test("sanitizeSettings preserves normalized mesh settings", () => {
  const settings = sanitizeSettings({
    coreURLString: "http://127.0.0.1:25101",
    defaultAgentID: "sloppy",
    mesh: {
      enabled: true,
      relayURL: " https://mesh.example.com/ ",
      targetNodeId: " node_home ",
      identity: { nodeId: "node_safari", publicKey: "ed25519:public", privateKey: "ed25519:private" }
    }
  });

  assert.deepEqual(settings.mesh, {
    enabled: true,
    relayURL: "https://mesh.example.com",
    targetNodeId: "node_home",
    identity: { nodeId: "node_safari", publicKey: "ed25519:public", privateKey: "ed25519:private" }
  });
});

test("coreFetch uses direct Core URL when mesh is disabled", async () => {
  const requests = [];
  const response = await coreFetch(
    { coreURLString: "http://127.0.0.1:25101", mesh: { enabled: false } },
    "/v1/agents",
    {},
    async (url, options) => {
      requests.push({ url, options });
      return Response.json({ agents: [] });
    }
  );

  assert.equal(requests[0].url, "http://127.0.0.1:25101/v1/agents");
  assert.deepEqual(await response.json(), { agents: [] });
});

test("coreFetch uses mesh fetch when mesh is enabled", async () => {
  const meshCalls = [];
  const response = await coreFetch(
    {
      coreURLString: "http://127.0.0.1:25101",
      mesh: {
        enabled: true,
        relayURL: "https://mesh.example.com",
        targetNodeId: "node_home",
        identity: { nodeId: "node_safari", publicKey: "ed25519:public", privateKey: "ed25519:private" }
      }
    },
    "/v1/agents",
    { method: "GET" },
    async () => {
      throw new Error("direct fetch should not run");
    },
    async (settings, path, options) => {
      meshCalls.push({ settings, path, options });
      return Response.json({ agents: [{ id: "remote" }] });
    }
  );

  assert.equal(meshCalls[0].path, "/v1/agents");
  assert.deepEqual(await response.json(), { agents: [{ id: "remote" }] });
});
```

- [ ] **Step 2: Run panel tests and verify they fail**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test -- Tests/panelPayload.test.mjs
```

Expected: FAIL because `sanitizeSettings` does not preserve `mesh` and `coreFetch` is not exported.

- [ ] **Step 3: Implement mesh-aware fetch selection in panel.js**

Modify `Apps/SafariExtension/Extension/Resources/panel.js`:

```js
import { meshCoreFetch, normalizeMeshSettings } from "./mesh.js";
```

Update `sanitizeSettings`:

```js
export function sanitizeSettings(settings = {}) {
  const sanitized = {
    coreURLString: normalizeCoreURL(settings.coreURLString),
    authToken: String(settings.authToken || "").trim(),
    defaultAgentID: String(settings.defaultAgentID || "sloppy").trim() || "sloppy",
    floatingButtonEnabled: Boolean(settings.floatingButtonEnabled),
    selectionBubbleEnabled: settings.selectionBubbleEnabled !== false,
    mesh: normalizeMeshSettings(settings.mesh)
  };
  if (settings.sessionId) {
    sanitized.sessionId = settings.sessionId;
  }
  return sanitized;
}
```

Add:

```js
export async function coreFetch(settings, path, options = {}, fetchImpl = fetch, meshFetchImpl = meshCoreFetch) {
  if (settings.mesh?.enabled) {
    return meshFetchImpl(settings, path, options);
  }
  return fetchImpl(`${normalizeCoreURL(settings.coreURLString)}${path}`, options);
}
```

Replace direct `fetchImpl(`${coreURL}...` calls in `postBrowserContext`, `postBrowserContextStreaming`, `ensureBrowserContextSession`, and `postSessionBrowserMessage` with `coreFetch(settings, path, options, fetchImpl)`. Keep the same parse/error behavior by setting `response.url` fallback context paths where needed:

```js
const response = await coreFetch(settings, "/v1/browser/context-message", {
  method: "POST",
  headers: headersForSettings(settings),
  body: JSON.stringify(payload)
}, fetchImpl);
```

In mesh mode, implement `postBrowserContextStreaming` as:

```js
if (settings.mesh?.enabled) {
  const body = await postBrowserContext(settings, page, selection, prompt, options, fetchImpl);
  options.onEvent?.({ type: "complete", body });
  options.onEvent?.({ type: "done", body });
  return body;
}
```

- [ ] **Step 4: Wire background API helpers through coreFetch and mesh join messages**

Modify `Apps/SafariExtension/Extension/Resources/background.js`:

```js
import {
  acceptMeshInvite,
  meshCoreFetch
} from "./mesh.js";
```

In `listAgents`, `listSessions`, `getSession`, and `listSlashCommands`, replace direct `fetch(`${settings.coreURLString}...`)` with:

```js
const response = await coreFetch(settings, "/v1/agents", { headers }, fetch, meshCoreFetch);
```

Add message handlers:

```js
if (message?.type === "sloppy.mesh.status") {
  void loadSettings().then((settings) => {
    sendResponse({ mesh: settings.mesh || { enabled: false } });
  }).catch((error) => {
    sendResponse({ error: error.message || "Mesh settings unavailable." });
  });
  return true;
}

if (message?.type === "sloppy.mesh.join") {
  void (async () => {
    const settings = await loadSettings();
    const result = await acceptMeshInvite({
      token: message.token,
      currentMesh: settings.mesh,
      saveMesh: async (mesh) => {
        await saveSettings({ ...settings, mesh });
      }
    });
    sendResponse(result);
  })().catch((error) => {
    sendResponse({ error: error.message || "Unable to join mesh." });
  });
  return true;
}
```

- [ ] **Step 5: Run panel tests and extension tests**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test -- Tests/panelPayload.test.mjs
cd Apps/SafariExtension/Extension && npm test
```

Expected: PASS.

- [ ] **Step 6: Commit Task 3**

```bash
git add Apps/SafariExtension/Extension/Resources/panel.js Apps/SafariExtension/Extension/Resources/background.js Apps/SafariExtension/Extension/Tests/panelPayload.test.mjs
git commit -m "Route Safari extension API calls through mesh"
```

---

### Task 4: Mesh Settings UI

**Files:**
- Modify: `Apps/SafariExtension/Extension/Resources/contentScript.js`
- Modify: `Apps/SafariExtension/Extension/Resources/panel.css`
- Modify: `Apps/SafariExtension/Extension/Tests/contentSelection.test.mjs`

**Interfaces:**
- Consumes: background messages `sloppy.mesh.join`, `sloppy.mesh.status`, existing `sloppy.settings.save`
- Produces: settings dialog controls with selectors:
  - `[data-sloppy-mesh-enabled]`
  - `[data-sloppy-mesh-invite]`
  - `[data-sloppy-mesh-target-node]`
  - `[data-sloppy-mesh-join]`
  - `[data-sloppy-mesh-status]`

- [ ] **Step 1: Add failing DOM tests for Mesh settings controls**

Append to `Apps/SafariExtension/Extension/Tests/contentSelection.test.mjs` if the file already has panel DOM tests. If it does not, create a focused test using the file's existing import/setup pattern:

```js
test("settings dialog includes mesh invite and target node controls", () => {
  const frame = ensurePanel();
  assert.ok(frame.querySelector("[data-sloppy-mesh-enabled]"));
  assert.ok(frame.querySelector("[data-sloppy-mesh-invite]"));
  assert.ok(frame.querySelector("[data-sloppy-mesh-target-node]"));
  assert.ok(frame.querySelector("[data-sloppy-mesh-join]"));
  assert.ok(frame.querySelector("[data-sloppy-mesh-status]"));
});
```

- [ ] **Step 2: Run content tests and verify they fail**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test -- Tests/contentSelection.test.mjs
```

Expected: FAIL because Mesh controls are missing.

- [ ] **Step 3: Add Mesh controls to the settings dialog**

Modify the settings dialog HTML in `Apps/SafariExtension/Extension/Resources/contentScript.js` by adding this block after the Direct Core fields:

```html
<div class="sloppy-settings-section">
  <strong>Mesh</strong>
  <label class="sloppy-settings-toggle">
    <input data-sloppy-mesh-enabled type="checkbox">
    <span>Use mesh relay</span>
  </label>
  <label>Invite token<textarea data-sloppy-mesh-invite rows="3"></textarea></label>
  <label>Target node<input data-sloppy-mesh-target-node></label>
  <button class="sloppy-settings-save" type="button" data-sloppy-mesh-join>Join mesh</button>
  <p class="sloppy-settings-note" data-sloppy-mesh-status>Mesh is not configured.</p>
</div>
```

Update settings load/render logic:

```js
const mesh = state.settings?.mesh || { enabled: false };
frame.querySelector("[data-sloppy-mesh-enabled]").checked = Boolean(mesh.enabled);
frame.querySelector("[data-sloppy-mesh-target-node]").value = mesh.targetNodeId || "";
frame.querySelector("[data-sloppy-mesh-status]").textContent = mesh.relayURL
  ? `Mesh: ${mesh.networkName || mesh.networkId || mesh.relayURL} as ${mesh.identity?.nodeId || "unknown node"}`
  : "Mesh is not configured.";
```

Update save settings:

```js
mesh: {
  ...(state.settings?.mesh || {}),
  enabled: frame.querySelector("[data-sloppy-mesh-enabled]").checked,
  targetNodeId: frame.querySelector("[data-sloppy-mesh-target-node]").value
}
```

Wire join button:

```js
frame.querySelector("[data-sloppy-mesh-join]").addEventListener("click", async () => {
  const token = frame.querySelector("[data-sloppy-mesh-invite]").value;
  const status = frame.querySelector("[data-sloppy-mesh-status]");
  status.textContent = "Joining mesh...";
  const response = await chrome.runtime.sendMessage({ type: "sloppy.mesh.join", token });
  if (response?.error) {
    status.textContent = response.error;
    return;
  }
  state.settings = { ...(state.settings || {}), mesh: response.mesh };
  status.textContent = `Mesh: ${response.mesh.networkName || response.mesh.networkId || response.mesh.relayURL} as ${response.mesh.identity.nodeId}`;
});
```

- [ ] **Step 4: Style Mesh settings controls**

Append to `Apps/SafariExtension/Extension/Resources/panel.css`:

```css
#sloppy-safari-extension-panel .sloppy-settings-section {
  display: grid;
  gap: 10px;
  padding-top: 12px;
  border-top: 1px solid rgba(255, 255, 255, 0.12);
}

#sloppy-safari-extension-panel .sloppy-settings-note {
  margin: 0;
  color: var(--sloppy-muted);
  font-size: 12px;
  line-height: 1.4;
}

#sloppy-safari-extension-panel [data-sloppy-mesh-invite] {
  min-height: 72px;
  resize: vertical;
}
```

- [ ] **Step 5: Run content tests and all extension tests**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test -- Tests/contentSelection.test.mjs
cd Apps/SafariExtension/Extension && npm test
```

Expected: PASS.

- [ ] **Step 6: Commit Task 4**

```bash
git add Apps/SafariExtension/Extension/Resources/contentScript.js Apps/SafariExtension/Extension/Resources/panel.css Apps/SafariExtension/Extension/Tests/contentSelection.test.mjs
git commit -m "Add Safari extension mesh settings UI"
```

---

### Task 5: Final Verification and Documentation

**Files:**
- Modify: `Apps/SafariExtension/README.md`

**Interfaces:**
- Consumes: all prior task exports and UI behavior.
- Produces: README instructions for accepting a mesh invite and using mesh chat.

- [ ] **Step 1: Add README verification instructions**

Modify `Apps/SafariExtension/README.md` after the Runtime section:

```md
## Mesh Runtime

The extension can join Sloppy mesh directly. Paste a bundled `slp_mesh_...` invite into the Mesh section of the extension settings, click Join mesh, then set the target node id that exposes the agent Core API.

Mesh mode stores the extension node identity in Safari extension storage and sends Core API requests through relay `core.http` RPC. Streaming chat falls back to a complete non-streaming response in the first mesh increment.
```

- [ ] **Step 2: Run all relevant verification**

Run:

```bash
cd Apps/SafariExtension/Extension && npm test
cd Apps/SafariExtension && swift test
```

Expected: both commands PASS. If `swift test` fails because of unrelated local workspace changes, capture the exact failure and do not edit unrelated files.

- [ ] **Step 3: Inspect git diff for scope**

Run:

```bash
git diff -- Apps/SafariExtension docs/superpowers/plans/2026-06-22-safari-extension-mesh-node.md
```

Expected: only SafariExtension mesh implementation, tests, README, and this plan are present.

- [ ] **Step 4: Commit Task 5**

```bash
git add Apps/SafariExtension/README.md docs/superpowers/plans/2026-06-22-safari-extension-mesh-node.md
git commit -m "Document Safari extension mesh mode"
```
