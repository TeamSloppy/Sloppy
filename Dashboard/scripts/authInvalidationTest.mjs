import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";
import { build } from "esbuild";

const bundle = await build({
  stdin: {
    contents: 'export * from "./src/shared/api/coreApi"; export * from "./src/shared/api/dashboardAuth"; export * from "./src/shared/api/httpClient";',
    resolveDir: new URL("..", import.meta.url).pathname,
    loader: "ts"
  },
  bundle: true, write: false, format: "esm", platform: "browser",
  define: { "import.meta.env": "{}" }
});
const storage = new Map();
let invalidations = 0;
globalThis.window = {
  localStorage: {
    getItem: (key) => storage.get(key) ?? null,
    setItem: (key, value) => storage.set(key, value),
    removeItem: (key) => storage.delete(key)
  },
  location: { search: "" },
  __SLOPPY_CONFIG__: { apiBase: "http://sloppy.test" },
  dispatchEvent: () => { invalidations++; }
};
const auth = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`);
const api = auth.createCoreApi();
const denied = () => Response.json({ error: "unauthorized" }, { status: 401 });
beforeEach(() => {
  storage.clear();
  window.__SLOPPY_CONFIG__.apiBase = "http://sloppy.test";
  auth.setDashboardAuthToken("old-token", { persist: true });
  invalidations = 0;
});

for (const kind of ["json", "blob"]) {
  const request = () => kind === "json"
    ? auth.requestJson({ path: "/v1/agents/yadev/memory-imports/job" })
    : auth.requestBlob("/v1/files/attachment");
  for (const nextToken of ["new-token", "old-token"]) {
    test(`${kind}: late 401 cannot clear a newer login, even with the same token (${nextToken})`, async () => {
      let respond;
      globalThis.fetch = () => new Promise((resolve) => { respond = resolve; });
      const pending = request();
      auth.setDashboardAuthToken(nextToken, { persist: true });
      respond(denied());
      await pending;
      assert.equal(auth.getDashboardAuthToken(), nextToken);
      assert.equal(invalidations, 0);
      assert.equal(auth.isDashboardAuthTokenPersisted(), true);
    });
  }
  test(`${kind}: a rejection from the previous server cannot clear this server's session`, async () => {
    let respond;
    globalThis.fetch = () => new Promise((resolve) => { respond = resolve; });
    const pending = request();
    auth.setStoredApiBaseOverride("http://another.test");
    respond(denied());
    await pending;
    assert.equal(auth.getDashboardAuthToken(), "old-token");
    assert.equal(invalidations, 0);
  });
  test(`${kind}: genuine current-session rejection still logs out`, async () => {
    globalThis.fetch = async () => denied();
    await request();
    assert.equal(auth.getDashboardAuthToken(), "");
    assert.equal(invalidations, 1);
  });
}

test("credential validation is a probe and cannot erase the logged-in session", async () => {
  globalThis.fetch = async () => denied();
  assert.equal(await api.validateDashboardAuthToken("mistyped-token"), null);
  assert.equal(auth.getDashboardAuthToken(), "old-token");
  assert.equal(invalidations, 0);
});

test("an unrelated public download's 401 does not log out", async () => {
  globalThis.fetch = async () => denied();
  await auth.requestBlob("/public/download");
  assert.equal(auth.getDashboardAuthToken(), "old-token");
  assert.equal(invalidations, 0);
});

test("requests sent before login cannot undo it", async () => {
  auth.clearDashboardAuthToken();
  let respond;
  globalThis.fetch = () => new Promise((resolve) => { respond = resolve; });
  const pending = auth.requestJson({ path: "/v1/agents/yadev/memory-imports" });
  auth.setDashboardAuthToken("new-login", { persist: true });
  respond(denied());
  await pending;
  assert.equal(auth.getDashboardAuthToken(), "new-login");
  assert.equal(invalidations, 0);
});

test("concurrent import polls invalidate a rejected session only once", async () => {
  const responses = [];
  globalThis.fetch = () => new Promise((resolve) => { responses.push(resolve); });
  const pending = Array.from({ length: 4 }, () => auth.requestJson({ path: "/v1/agents/yadev/memory-imports/job" }));
  for (const respond of responses) respond(denied());
  await Promise.all(pending);
  assert.equal(auth.getDashboardAuthToken(), "");
  assert.equal(invalidations, 1);
});

test("an aborted poll cannot invalidate the session with a queued response", async () => {
  const controller = new AbortController();
  globalThis.fetch = async () => { controller.abort(); return denied(); };
  await auth.requestJson({ path: "/v1/agents/yadev/memory-imports/job", signal: controller.signal });
  assert.equal(auth.getDashboardAuthToken(), "old-token");
  assert.equal(invalidations, 0);
});

for (const status of [403, 429, 500, 503]) {
  test(`import failure HTTP ${status} keeps credentials`, async () => {
    globalThis.fetch = async () => Response.json({ error: "import_failed" }, { status });
    const response = await auth.requestJson({ path: "/v1/agents/yadev/memory-imports/job" });
    assert.equal(response.status, status);
    assert.equal(auth.getDashboardAuthToken(), "old-token");
    assert.equal(invalidations, 0);
  });
}

for (const stale of [true, false]) {
  test(`terminal auth rejection respects the session that opened it (stale=${stale})`, () => {
    let socket;
    globalThis.WebSocket = class {
      constructor() { socket = this; }
      send() {}
      close() {}
    };
    const connection = api.subscribeDashboardTerminal();
    socket.onopen();
    if (stale) auth.setDashboardAuthToken("new-login", { persist: true });
    socket.onmessage({ data: JSON.stringify({ type: "error", code: "unauthorized" }) });
    assert.equal(auth.getDashboardAuthToken(), stale ? "new-login" : "");
    assert.equal(invalidations, stale ? 0 : 1);
    connection.close();
  });
}
