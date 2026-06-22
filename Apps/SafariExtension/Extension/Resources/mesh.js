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
  const text = String(token || "");
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

  if (typeof payload?.v !== "number" || !Number.isInteger(payload.v)) {
    throw new Error("Mesh invite bundle payload is invalid.");
  }
  if (payload.v !== 1) {
    throw new Error(`Mesh invite bundle version ${payload.v} is not supported.`);
  }
  if (typeof payload.inviteToken !== "string" || !payload.inviteToken.length) {
    throw new Error("Mesh invite bundle payload is invalid.");
  }
  if (typeof payload.relayURL !== "string" || !payload.relayURL.length) {
    throw new Error("Mesh invite bundle payload is invalid.");
  }

  const getOptionalString = (key) => {
    if (!Object.prototype.hasOwnProperty.call(payload, key)) {
      return undefined;
    }
    const value = payload[key];
    if (typeof value !== "string") {
      throw new Error("Mesh invite bundle payload is invalid.");
    }
    return value.length > 0 ? value : undefined;
  };

  const networkId = getOptionalString("networkId");
  const networkName = getOptionalString("networkName");
  const nodeId = getOptionalString("nodeId");
  const publicKey = getOptionalString("publicKey");

  return {
    version: payload.v,
    inviteToken: payload.inviteToken,
    relayURL: payload.relayURL,
    networkId,
    networkName,
    nodeId,
    publicKey,
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
    .replace(/[^\p{L}\p{N}]+/gu, "-")
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
  const challenge = challengeEnvelope.payload;
  if (!isObject(challenge)) {
    throw new Error("Auth challenge payload is invalid.");
  }
  if (typeof challenge.nonce !== "string" || challenge.nonce.length === 0) {
    throw new Error("Auth challenge nonce is missing or invalid.");
  }
  if (Object.prototype.hasOwnProperty.call(challenge, "nodeId")) {
    if (typeof challenge.nodeId !== "string" || challenge.nodeId !== identity.nodeId) {
      return null;
    }
  }
  if (Object.prototype.hasOwnProperty.call(challenge, "publicKey")) {
    if (typeof challenge.publicKey !== "string" || challenge.publicKey.length === 0) {
      throw new Error("Auth challenge publicKey is missing or invalid.");
    }
    if (challenge.publicKey !== identity.publicKey) {
      throw new Error("Auth challenge publicKey does not match node identity.");
    }
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
  if (!isObject(envelope)) {
    throw new Error("Invalid rpc response envelope.");
  }
  const payload = envelope.payload;
  if (!isObject(payload)) {
    throw new Error("Invalid rpc response payload.");
  }
  if (payload.ok !== true) {
    const message = payload.error?.message || payload.error?.code || "Remote Core request failed.";
    throw new Error(message);
  }
  if (payload.method !== "core.http") {
    throw new Error("Invalid rpc response: method must be core.http.");
  }
  const result = payload.result;
  if (!isObject(result)) {
    throw new Error("Invalid rpc response: result is required.");
  }
  if (!Number.isInteger(result.status)) {
    throw new Error("Invalid rpc response: status must be a number.");
  }
  if (typeof result.contentType !== "string") {
    throw new Error("Invalid rpc response: contentType must be a string.");
  }
  if (typeof result.bodyBase64 !== "string") {
    throw new Error("Invalid rpc response: bodyBase64 must be a string.");
  }
  if (!isBase64(valueForBase64Validation(result.bodyBase64))) {
    throw new Error("Invalid rpc response: bodyBase64 is not valid base64.");
  }
  let body;
  try {
    body = stringFromBase64(result.bodyBase64);
  } catch {
    throw new Error("Invalid rpc response: bodyBase64 is not valid base64.");
  }
  return new Response(body, {
    status: result.status,
    headers: { "content-type": result.contentType }
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
  let relayURL;
  try {
    relayURL = new URL(resolveRelayWebSocketURL(bundle.relayURL));
  } catch {
    throw new Error(`Invalid relay URL: ${bundle.relayURL}`);
  }
  if (relayURL.protocol === "ws:") {
    relayURL.protocol = "http:";
  } else if (relayURL.protocol === "wss:") {
    relayURL.protocol = "https:";
  }
  const url = relayURL;
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

function trimTrailingSlashes(value) {
  return String(value || "").trim().replace(/\/+$/, "");
}

function isObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function valueForBase64Validation(value) {
  return String(value).replace(/\s/g, "");
}

function isBase64(value) {
  if (value.length === 0) {
    return true;
  }
  if (!/^[A-Za-z0-9+/=_-]*$/.test(value)) {
    return false;
  }
  return value.length % 4 === 0;
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
