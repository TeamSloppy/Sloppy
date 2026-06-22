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
