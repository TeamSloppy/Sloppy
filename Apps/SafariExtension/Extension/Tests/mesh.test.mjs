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
