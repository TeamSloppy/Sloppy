import assert from "node:assert/strict";
import { test } from "node:test";
import { build } from "esbuild";

// Bundle the real API and auth store together so they share the session state.
const bundle = await build({
  stdin: {
    contents: 'export * from "./src/shared/api/coreApi"; export * from "./src/shared/api/dashboardAuth";',
    resolveDir: new URL("..", import.meta.url).pathname,
    loader: "ts"
  },
  bundle: true,
  write: false,
  format: "esm",
  platform: "browser",
  define: { "import.meta.env": "{}" }
});

const storage = new Map();
globalThis.window = {
  localStorage: {
    getItem: (key) => storage.get(key) ?? null,
    setItem: (key, value) => storage.set(key, value),
    removeItem: (key) => storage.delete(key)
  },
  location: { search: "" },
  __SLOPPY_CONFIG__: { apiBase: "http://sloppy.test" },
  dispatchEvent: () => {}
};
const auth = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString("base64")}`);
const api = auth.createCoreApi();

function mockServer({ mode = "login_password", savedConfig, saveStatus = 200, challengeStatus = 200 }) {
  const requests = [];
  globalThis.fetch = async (url, options) => {
    const path = new URL(url).pathname;
    requests.push({ path, authorization: options.headers.get("authorization") });
    if (path === "/v1/auth/challenge") {
      return Response.json({ mode }, { status: challengeStatus });
    }
    assert.equal(path, "/v1/config");
    assert.equal(options.method, "PUT");
    return Response.json(saveStatus === 200 ? savedConfig : { error: "config_write_failed" }, { status: saveStatus });
  };
  return requests;
}

for (const persist of [true, false]) {
  for (const dashboardAuth of [
    { enabled: true, token: "legacy-dashboard-token" },
    { enabled: false, token: "" }
  ]) {
    test(`config saves preserve identity session (remember=${persist}, legacy enabled=${dashboardAuth.enabled})`, async () => {
      storage.clear();
      auth.setDashboardAuthToken("identity-session-token", { persist });
      const config = { ui: { dashboardAuth }, models: [] };
      const requests = mockServer({ savedConfig: config });

      // The second save reproduces the request that used to fail with HTTP 401.
      await api.updateRuntimeConfig(config);
      await api.updateRuntimeConfig(config);

      assert.equal(auth.getDashboardAuthToken(), "identity-session-token");
      assert.equal(auth.isDashboardAuthTokenPersisted(), persist);
      assert.ok(requests.every((request) => request.authorization === "Bearer identity-session-token"));
      assert.equal(requests.filter((request) => request.path === "/v1/config").length, 2);
    });
  }

  test(`legacy token rotation uses saved config and retains remember=${persist}`, async () => {
    storage.clear();
    auth.setDashboardAuthToken("old-token", { persist });
    const config = { ui: { dashboardAuth: { enabled: true, token: "requested-token" } } };
    const savedConfig = { ui: { dashboardAuth: { enabled: true, token: "saved-token" } } };
    const requests = mockServer({ mode: "token", savedConfig });

    assert.deepEqual(await api.updateRuntimeConfig(config), savedConfig);
    assert.equal(auth.getDashboardAuthToken(), "saved-token");
    assert.equal(auth.isDashboardAuthTokenPersisted(), persist);
    assert.ok(requests.every((request) => request.authorization === "Bearer old-token"));
  });
}

test("disabling legacy auth clears the legacy token", async () => {
  auth.setDashboardAuthToken("old-token", { persist: true });
  const config = { ui: { dashboardAuth: { enabled: false, token: "" } } };
  mockServer({ mode: "token", savedConfig: config });
  await api.updateRuntimeConfig(config);
  assert.equal(auth.getDashboardAuthToken(), "");
  assert.equal(auth.isDashboardAuthTokenPersisted(), false);
});

test("failed save keeps the current credentials", async () => {
  auth.setDashboardAuthToken("old-token", { persist: true });
  mockServer({ mode: "token", saveStatus: 500 });
  await assert.rejects(api.updateRuntimeConfig({}), /HTTP 500/);
  assert.equal(auth.getDashboardAuthToken(), "old-token");
  assert.equal(auth.isDashboardAuthTokenPersisted(), true);
});

for (const challenge of [{ challengeStatus: 503 }, { mode: "unknown" }]) {
  test(`unavailable or unknown auth mode prevents an unsafe save: ${JSON.stringify(challenge)}`, async () => {
    auth.setDashboardAuthToken("identity-session-token", { persist: true });
    const requests = mockServer(challenge);
    await assert.rejects(api.updateRuntimeConfig({}), /authentication mode/);
    assert.equal(requests.length, 1);
    assert.equal(auth.getDashboardAuthToken(), "identity-session-token");
  });
}

for (const persist of [true, false]) {
  test(`connecting a client in token mode preserves the session (remember=${persist})`, async () => {
    auth.setDashboardAuthToken("operator-token", { persist });
    const paths = [];
    globalThis.fetch = async (url, options) => {
      paths.push(new URL(url).pathname);
      assert.equal(options.headers.get("authorization"), "Bearer operator-token");
      assert.equal(new URL(url).pathname, "/v1/auth/challenge", "token mode must never request identity pairing");
      return Response.json({ mode: "token" });
    };

    assert.deepEqual(await auth.prepareClientConnection(), { mode: "token" });
    assert.deepEqual(paths, ["/v1/auth/challenge"]);
    assert.equal(auth.getDashboardAuthToken(), "operator-token");
    assert.equal(auth.isDashboardAuthTokenPersisted(), persist);
  });
}

test("connecting an identity client creates short-lived pairing with the current session", async () => {
  auth.setDashboardAuthToken("identity-session-token", { persist: true });
  const pairing = { token: "slp_pair_test", user: { id: "user-1", name: "Test", login: "test" } };
  const paths = [];
  globalThis.fetch = async (url, options) => {
    const path = new URL(url).pathname;
    paths.push(path);
    assert.equal(options.headers.get("authorization"), "Bearer identity-session-token");
    if (path === "/v1/auth/challenge") return Response.json({ mode: "login_password" });
    assert.equal(path, "/v1/auth/device-pairing");
    assert.equal(options.method, "POST");
    assert.deepEqual(JSON.parse(options.body), { clientName: "Sloppy Client", ttlSeconds: 120 });
    return Response.json(pairing, { status: 201 });
  };

  assert.deepEqual(await auth.prepareClientConnection(), { mode: "login_password", pairing });
  assert.deepEqual(paths, ["/v1/auth/challenge", "/v1/auth/device-pairing"]);
  assert.equal(auth.getDashboardAuthToken(), "identity-session-token");
});

for (const response of [{ mode: "unknown", status: 200 }, { mode: "token", status: 503 }]) {
  test(`client connection does not guess auth mode: ${JSON.stringify(response)}`, async () => {
    auth.setDashboardAuthToken("operator-token", { persist: true });
    globalThis.fetch = async (url) => {
      assert.equal(new URL(url).pathname, "/v1/auth/challenge");
      return Response.json({ mode: response.mode }, { status: response.status });
    };
    await assert.rejects(auth.prepareClientConnection());
    assert.equal(auth.getDashboardAuthToken(), "operator-token");
  });
}

test("leaving the connection page during mode discovery does not create pairing", async () => {
  const controller = new AbortController();
  globalThis.fetch = async (url) => {
    assert.equal(new URL(url).pathname, "/v1/auth/challenge");
    controller.abort();
    return Response.json({ mode: "login_password" });
  };
  await assert.rejects(auth.prepareClientConnection(controller.signal), { name: "AbortError" });
});

test("an expired identity session still invalidates dashboard auth", async () => {
  auth.setDashboardAuthToken("expired-session", { persist: true });
  globalThis.fetch = async (url) => new URL(url).pathname === "/v1/auth/challenge"
    ? Response.json({ mode: "login_password" })
    : Response.json({ error: "unauthorized" }, { status: 401 });
  await assert.rejects(auth.prepareClientConnection(), /HTTP 401/);
  assert.equal(auth.getDashboardAuthToken(), "");
  assert.equal(auth.isDashboardAuthTokenPersisted(), false);
});
