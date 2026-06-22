import assert from "node:assert/strict";
import { test } from "node:test";
import {
  acceptMeshInvite,
  buildAuthResponseEnvelope,
  buildCoreHTTPRPCEnvelope,
  buildMeshInviteAcceptPayload,
  buildNodeHelloEnvelope,
  createMeshIdentity,
  decodeCoreHTTPRPCResponse,
  makeNodeId,
  meshCoreFetch,
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
  assert.throws(() => parseMeshInviteBundle(bundleToken({ v: "1", inviteToken: "x", relayURL: "https://mesh.example.com" })), /payload is invalid/);
});

test("parseMeshInviteBundle rejects malformed invite payload field types", () => {
  assert.throws(() => parseMeshInviteBundle(bundleToken({ v: 1, inviteToken: 5, relayURL: "https://mesh.example.com" })), /payload is invalid/);
  assert.throws(() => parseMeshInviteBundle(bundleToken({ v: 1, inviteToken: "x", relayURL: 4 })), /payload is invalid/);
  assert.throws(() => parseMeshInviteBundle(bundleToken({ v: 1, inviteToken: "x", relayURL: "https://mesh.example.com", networkId: 7 })), /payload is invalid/);
  assert.throws(() => parseMeshInviteBundle(bundleToken({ v: 1, inviteToken: "x", relayURL: "https://mesh.example.com", publicKey: null })), /payload is invalid/);
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
  assert.equal(makeNodeId("Секретный портал", "abc123"), "node_секретный-портал_abc123");
  assert.equal(makeNodeId("Café Node", "abc123"), "node_café-node_abc123");
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

test("acceptMeshInvite rejects invalid relay URLs", async () => {
  const token = bundleToken({ v: 1, inviteToken: "slp_invite_remote", relayURL: "not-a-url" });
  const identity = await createMeshIdentity({ cryptoImpl: fakeCrypto(), randomToken: "abc123" });

  await assert.rejects(
    () => acceptMeshInvite({
      token,
      currentMesh: { identity },
      fetchImpl: () => {
        assert.fail("fetch should not be called for invalid relay URL");
      }
    }),
    /Invalid relay URL|relay URL is invalid/
  );
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

test("buildAuthResponseEnvelope rejects malformed auth challenge payloads", async () => {
  const identity = await createMeshIdentity({ cryptoImpl: fakeCrypto(), randomToken: "abc123" });

  await assert.rejects(
    () => buildAuthResponseEnvelope(identity, { type: "auth.challenge", from: "relay", payload: "bad" }, { cryptoImpl: fakeCrypto("signature") }),
    /Auth challenge payload is invalid/
  );
  await assert.rejects(
    () => buildAuthResponseEnvelope(identity, { type: "auth.challenge", from: "relay", payload: { nodeId: identity.nodeId } }, { cryptoImpl: fakeCrypto("signature") }),
    /nonce is missing or invalid/
  );
});

test("buildAuthResponseEnvelope returns null when challenge targets another node", async () => {
  const identity = await createMeshIdentity({ cryptoImpl: fakeCrypto(), randomToken: "abc123" });
  const response = await buildAuthResponseEnvelope(identity, {
    type: "auth.challenge",
    from: "relay",
    payload: { nonce: "nonce_auth", nodeId: "node_other", publicKey: identity.publicKey }
  }, { cryptoImpl: fakeCrypto("signature") });
  assert.equal(response, null);
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

test("decodeCoreHTTPRPCResponse rejects invalid protocol responses", async () => {
  assert.throws(() => {
    decodeCoreHTTPRPCResponse({ type: "rpc.response", payload: { ok: true } });
  }, /result is required/);
  assert.throws(() => {
    decodeCoreHTTPRPCResponse({
      type: "rpc.response",
      payload: {
        ok: true,
        result: { status: "200", contentType: "text/plain", bodyBase64: "e30=" }
      }
    });
  }, /status must be a number/);
  assert.throws(() => {
    decodeCoreHTTPRPCResponse({
      type: "rpc.response",
      payload: {
        ok: true,
        result: { status: 200, contentType: 10, bodyBase64: "e30=" }
      }
    });
  }, /contentType must be a string/);
  assert.throws(() => {
    decodeCoreHTTPRPCResponse({
      type: "rpc.response",
      payload: {
        ok: true,
        result: { status: 200, contentType: "text/plain" }
      }
    });
  }, /bodyBase64 must be a string/);
  assert.throws(() => {
    decodeCoreHTTPRPCResponse({
      type: "rpc.response",
      payload: {
        ok: true,
        result: { status: 200, contentType: "text/plain", bodyBase64: 13 }
      }
    });
  }, /bodyBase64 must be a string/);
  assert.throws(() => {
    decodeCoreHTTPRPCResponse({
      type: "rpc.response",
      payload: {
        ok: true,
        result: { status: 200, contentType: "text/plain", bodyBase64: "not%base64" }
      }
    });
  }, /bodyBase64 is not valid base64/);
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
