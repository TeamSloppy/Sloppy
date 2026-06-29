import assert from "node:assert/strict";
import { test } from "node:test";
import {
  buildVoicePrompt,
  buildBrowserContextPayload,
  chooseAgentID,
  coreFetch,
  collectBrowserToolActions,
  decodeSSEBlock,
  describeCoreError,
  fallbackSelectionText,
  fetchVoiceConfig,
  localSpeechAvailable,
  normalizeCoreURL,
  normalizeAgentSessions,
  normalizeSidebarState,
  publicMeshSettings,
  normalizeVoiceConfig,
  sidebarStateAfterCollapseToggle,
  postBrowserContext,
  postBrowserContextStreaming,
  renderMarkdown,
  sanitizeSettings,
  sanitizeStartPageBackgroundImage,
  sanitizeStartPageShortcuts,
  sanitizeStartPageTheme,
  transcribeVoiceAudio
} from "../Resources/panel.js";

async function loadBackgroundRuntime(storedSettings = {}, fetchImpl = async () => Response.json({}), options = {}) {
  const originalChrome = globalThis.chrome;
  const originalFetch = globalThis.fetch;
  const originalNavigator = globalThis.navigator;
  const storageState = structuredClone(storedSettings);
  let messageListener = null;
  let contextMenuClickListener = null;
  const contextMenus = [];
  const tabMessages = [];
  const scriptCalls = [];
  const tabs = options.tabs || [];

  if (options.language) {
    Object.defineProperty(globalThis, "navigator", {
      configurable: true,
      value: { language: options.language, languages: [options.language] }
    });
  }
  globalThis.fetch = fetchImpl;
  globalThis.chrome = {
    action: {
      onClicked: {
        addListener() {}
      }
    },
    runtime: {
      onInstalled: {
        addListener() {}
      },
      onMessage: {
        addListener(listener) {
          messageListener = listener;
        }
      }
    },
    contextMenus: {
      create(item) {
        contextMenus.push(structuredClone(item));
      },
      removeAll(callback) {
        contextMenus.length = 0;
        callback?.();
      },
      onClicked: {
        addListener(listener) {
          contextMenuClickListener = listener;
        }
      }
    },
    storage: {
      local: {
        async get(defaults = {}) {
          return { ...structuredClone(defaults), ...structuredClone(storageState) };
        },
        async set(nextValues = {}) {
          Object.assign(storageState, structuredClone(nextValues));
        },
        async remove(keys) {
          for (const key of Array.isArray(keys) ? keys : [keys]) {
            delete storageState[key];
          }
        }
      }
    },
    tabs: {
      async query(query = {}) {
        if (query.active) {
          return tabs.filter((tab) => tab.active);
        }
        return tabs;
      },
      async create({ url }) {
        return { id: 1, url, title: null };
      },
      async captureVisibleTab() {
        return "data:image/png;base64,abcd";
      },
      async sendMessage(tabId, message) {
        tabMessages.push({ tabId, message });
      }
    },
    scripting: {
      async executeScript(call) {
        scriptCalls.push(call);
        return [{ result: options.scriptResult || { ok: true } }];
      }
    }
  };

  await import(new URL(`../Resources/background.js?test=${Date.now()}-${Math.random()}`, import.meta.url));

  return {
    storageState,
    contextMenus,
    tabMessages,
    scriptCalls,
    async clickContextMenu(info = {}, tab = {}) {
      await contextMenuClickListener?.(info, tab);
    },
    async sendMessage(message, sender = {}) {
      return await new Promise((resolve, reject) => {
        try {
          const handled = messageListener?.(message, sender, resolve);
          if (!handled) {
            reject(new Error(`Message was not handled: ${message?.type || "unknown"}`));
          }
        } catch (error) {
          reject(error);
        }
      });
    },
    cleanup() {
      if (typeof originalChrome === "undefined") {
        delete globalThis.chrome;
      } else {
        globalThis.chrome = originalChrome;
      }
      if (options.language) {
        if (typeof originalNavigator === "undefined") {
          delete globalThis.navigator;
        } else {
          Object.defineProperty(globalThis, "navigator", {
            configurable: true,
            value: originalNavigator
          });
        }
      }
      globalThis.fetch = originalFetch;
    }
  };
}

function assertPublicMeshIdentity(mesh, expected = {}) {
  assert.equal(mesh.identity.privateKey, undefined);
  assert.deepEqual(mesh.identity, expected);
}

test("normalizeCoreURL adds http scheme and removes trailing slashes", () => {
  assert.equal(normalizeCoreURL("192.168.1.50:25101/"), "http://192.168.1.50:25101");
});

test("normalizeSidebarState clamps width and coerces collapsed flag", () => {
  assert.deepEqual(normalizeSidebarState({ width: 90, collapsed: "yes" }), {
    width: 128,
    collapsed: true
  });
  assert.deepEqual(normalizeSidebarState({ width: 520, collapsed: false }), {
    width: 360,
    collapsed: false
  });
});

test("sidebarStateAfterCollapseToggle preserves width while toggling collapsed state", () => {
  assert.deepEqual(sidebarStateAfterCollapseToggle({ width: 244, collapsed: false }), {
    width: 244,
    collapsed: true
  });
  assert.deepEqual(sidebarStateAfterCollapseToggle({ width: 244, collapsed: true }), {
    width: 244,
    collapsed: false
  });
});

test("buildBrowserContextPayload creates typed Safari context payload", () => {
  const payload = buildBrowserContextPayload(
    { defaultAgentID: "sloppy" },
    { url: "https://example.com/a", title: "Article" },
    "Selected text",
    "Explain this",
    {
      tabs: [{ id: 7, url: "https://example.com/other", title: "Other" }],
      pageSnapshot: { elements: [{ selector: "#buy", text: "Buy" }] },
      attachments: [{ id: "att-1", name: "note.md", mimeType: "text/markdown", sizeBytes: 8, contentBase64: "IyBOb3Rl" }]
    }
  );

  assert.deepEqual(payload, {
    source: "safari_extension",
    page: {
      url: "https://example.com/a",
      title: "Article"
    },
    selection: {
      text: "Selected text"
    },
    browser: {
      tabs: [{ id: 7, url: "https://example.com/other", title: "Other" }]
    },
    attachments: [{ name: "note.md", mimeType: "text/markdown", sizeBytes: 8, contentBase64: "IyBOb3Rl" }],
    prompt: "Explain this",
    target: {
      agentId: "sloppy",
      sessionId: null
    },
    userId: "safari_extension"
  });
});

test("buildBrowserContextPayload allows chat without selected text", () => {
  const payload = buildBrowserContextPayload(
    { defaultAgentID: "sloppy", sessionId: "session-1" },
    { url: "https://example.com/a", title: "Article" },
    "   ",
    "What is this page about?"
  );

  assert.equal(fallbackSelectionText("   "), "No selected text.");
  assert.equal(payload.selection.text, "No selected text.");
  assert.equal(payload.target.sessionId, "session-1");
});

test("buildBrowserContextPayload carries selected model override", () => {
  const payload = buildBrowserContextPayload(
    { defaultAgentID: "sloppy", selectedModel: "openai/gpt-5.4" },
    { url: "https://example.com/a", title: "Article" },
    "",
    "Explain this"
  );

  assert.equal(payload.target.model, "openai/gpt-5.4");
});

test("buildBrowserContextPayload carries widget editor session metadata", () => {
  const payload = buildBrowserContextPayload(
    { defaultAgentID: "sloppy" },
    { url: "https://example.com/start", title: "Start" },
    "",
    "/widget make a clock",
    {
      widgetSession: {
        mode: "widget_editor",
        isolated: true,
        sessionId: null,
        sourceItemId: "widget-card-1",
        widget: {
          kind: "widget",
          title: "Clock",
          size: "2x1",
          colSpan: 2,
          rowSpan: 1,
          artifactId: "artifact-clock",
          sourceItemId: "widget-card-1"
        }
      }
    }
  );

  assert.equal(payload.mode, "widget_editor");
  assert.deepEqual(payload.widgetSession, {
    mode: "widget_editor",
    isolated: true,
    sessionId: null,
    sourceItemId: "widget-card-1",
    widget: {
      kind: "widget",
      title: "Clock",
      size: "2x1",
      colSpan: 2,
      rowSpan: 1,
      artifactId: "artifact-clock",
      sourceItemId: "widget-card-1"
    }
  });
});

test("sanitizeSettings keeps a user-configured LAN Core URL for extension storage", () => {
  const settings = sanitizeSettings({
    coreURLString: "  192.168.1.50:25101/  ",
    authToken: "  token-1  ",
    defaultAgentID: "  web-agent  ",
    floatingButtonEnabled: true,
    selectionBubbleEnabled: false
  });

  assert.deepEqual(settings, {
    coreURLString: "http://192.168.1.50:25101",
    authToken: "token-1",
    defaultAgentID: "web-agent",
    floatingButtonEnabled: true,
    selectionBubbleEnabled: false,
    startPageEnabled: true,
    startPageTheme: "dark",
    startPageBackgroundImage: "",
    startPageShortcuts: [],
    startPageItems: [],
    voiceLanguage: "auto",
    mesh: { enabled: false }
  });
});

test("sanitizeSettings keeps selection bubble enabled by default", () => {
  assert.equal(sanitizeSettings({}).floatingButtonEnabled, true);
  assert.equal(sanitizeSettings({ floatingButtonEnabled: false }).floatingButtonEnabled, false);
  assert.equal(sanitizeSettings({}).selectionBubbleEnabled, true);
  assert.equal(sanitizeSettings({ selectionBubbleEnabled: false }).selectionBubbleEnabled, false);
});

test("sanitizeSettings defaults start page customization", () => {
  const settings = sanitizeSettings({});

  assert.equal(settings.startPageEnabled, true);
  assert.equal(settings.startPageTheme, "dark");
  assert.equal(settings.startPageBackgroundImage, "");
  assert.deepEqual(settings.startPageShortcuts, []);
  assert.deepEqual(settings.startPageItems, []);
});

test("sanitizeStartPageTheme accepts only light and dark", () => {
  assert.equal(sanitizeStartPageTheme("light"), "light");
  assert.equal(sanitizeStartPageTheme("dark"), "dark");
  assert.equal(sanitizeStartPageTheme("system"), "dark");
});

test("sanitizeStartPageShortcuts keeps only http and https urls", () => {
  assert.deepEqual(sanitizeStartPageShortcuts([
    { title: "GitHub", url: "https://github.com" },
    { title: "", url: "http://localhost:25101" },
    { title: "Bad", url: "javascript:alert(1)" },
    { title: "File", url: "file:///tmp/a" }
  ]), [
    { title: "GitHub", url: "https://github.com/" },
    { title: "localhost:25101", url: "http://localhost:25101/" }
  ]);
});

test("sanitizeSettings keeps mixed start page items and falls back to legacy shortcuts", () => {
  assert.deepEqual(
    sanitizeSettings({
      startPageShortcuts: [{ title: "GitHub", url: "https://github.com" }],
      startPageItems: [
        { kind: "shortcut", title: "Docs", url: "https://docs.example/path" },
        { kind: "widget", artifactId: "widget-1", title: "Clock", size: "small", width: 999, height: 42 }
      ]
    }).startPageItems,
    [
      { kind: "shortcut", title: "Docs", url: "https://docs.example/path" },
      { kind: "widget", artifactId: "widget-1", title: "Clock", size: "small", width: 160, height: 120 }
    ]
  );

  assert.deepEqual(
    sanitizeSettings({
      startPageShortcuts: [{ title: "GitHub", url: "https://github.com" }]
    }).startPageItems,
    [{ kind: "shortcut", title: "GitHub", url: "https://github.com/" }]
  );
});

test("sanitizeSettings canonicalizes widget dimensions by size", () => {
  assert.deepEqual(
    sanitizeSettings({
      startPageItems: [
        { kind: "widget", artifactId: "widget-1", title: "Clock", size: "medium", width: 999, height: 1, html: "<html></html>" },
        { kind: "widget", artifactId: "widget-2", title: "Stats", size: "large", width: 12, height: 900 }
      ]
    }).startPageItems,
    [
      { kind: "widget", artifactId: "widget-1", title: "Clock", size: "medium", width: 320, height: 180 },
      { kind: "widget", artifactId: "widget-2", title: "Stats", size: "large", width: 320, height: 320 }
    ]
  );
});

test("sanitizeStartPageBackgroundImage keeps small image data urls only", () => {
  assert.equal(sanitizeStartPageBackgroundImage("data:image/png;base64,abcd"), "data:image/png;base64,abcd");
  assert.equal(sanitizeStartPageBackgroundImage("data:text/html;base64,abcd"), "");
  assert.equal(sanitizeStartPageBackgroundImage("https://example.com/image.png"), "");
});

test("sanitizeSettings preserves selected model override", () => {
  assert.equal(sanitizeSettings({ selectedModel: " openai/gpt-5.4 " }).selectedModel, "openai/gpt-5.4");
  assert.equal("selectedModel" in sanitizeSettings({ selectedModel: "default" }), false);
  assert.equal("selectedModel" in sanitizeSettings({ selectedModel: "   " }), false);
});

test("sanitizeSettings preserves supported voice language override", () => {
  assert.equal(sanitizeSettings({ voiceLanguage: " ru-RU " }).voiceLanguage, "ru-RU");
  assert.equal(sanitizeSettings({ voiceLanguage: "zz-ZZ" }).voiceLanguage, "auto");
});

test("sanitizeSettings preserves a selected voice input device", () => {
  assert.equal(sanitizeSettings({ voiceInputDeviceId: " microphone-2 " }).voiceInputDeviceId, "microphone-2");
  assert.equal("voiceInputDeviceId" in sanitizeSettings({ voiceInputDeviceId: "   " }), false);
});

test("background settings enable the floating button by default", async () => {
  const runtime = await loadBackgroundRuntime();

  try {
    const response = await runtime.sendMessage({ type: "sloppy.settings.get" });
    assert.equal(response.floatingButtonEnabled, true);
  } finally {
    runtime.cleanup();
  }
});

test("background clears selected session when agent selection is normalized to another agent", async () => {
  const runtime = await loadBackgroundRuntime(
    { defaultAgentID: "missing-agent", sessionId: "session-from-missing-agent" },
    async (url) => {
      if (url.endsWith("/v1/agents")) {
        return Response.json({ agents: [{ id: "front_dev", displayName: "Frontend" }] });
      }
      return Response.json({});
    }
  );

  try {
    const response = await runtime.sendMessage({ type: "sloppy.agents.list" });

    assert.equal(response.selectedAgentId, "front_dev");
    assert.equal(runtime.storageState.defaultAgentID, "front_dev");
    assert.equal("sessionId" in runtime.storageState, false);
  } finally {
    runtime.cleanup();
  }
});

test("background registers Safari context menu summary action", async () => {
  const runtime = await loadBackgroundRuntime();

  assert.deepEqual(runtime.contextMenus, [{
    id: "sloppy.summaryPage",
    title: "Summary Page",
    contexts: ["page"],
    icons: {
      16: "text.aligncenter.svg",
      32: "text.aligncenter.svg"
    }
  }]);

  await runtime.clickContextMenu({ menuItemId: "sloppy.summaryPage" }, { id: 17 });
  assert.deepEqual(runtime.tabMessages, [{
    tabId: 17,
    message: { type: "sloppy.page.summarize" }
  }]);

  runtime.cleanup();
});

test("background sloppy.artifacts.list proxies Core artifacts", async () => {
  const runtime = await loadBackgroundRuntime(
    {},
    async (url) => {
      assert.equal(url, "http://127.0.0.1:25101/v1/artifacts");
      return Response.json({
        artifacts: [{ id: "artifact-1", title: "Clock", kind: "widget" }]
      });
    }
  );

  try {
    const response = await runtime.sendMessage({ type: "sloppy.artifacts.list" });
    assert.deepEqual(response, [{ id: "artifact-1", title: "Clock", kind: "widget" }]);
  } finally {
    runtime.cleanup();
  }
});

test("background sloppy.artifacts.widget fetches widget payload", async () => {
  const runtime = await loadBackgroundRuntime(
    {},
    async (url) => {
      assert.equal(url, "http://127.0.0.1:25101/v1/artifacts/widget-1/widget");
      return Response.json({
        artifactId: "widget-1",
        html: "<html><body>Clock</body></html>"
      });
    }
  );

  try {
    const response = await runtime.sendMessage({ type: "sloppy.artifacts.widget", artifactId: "widget-1" });
    assert.deepEqual(response, {
      artifactId: "widget-1",
      html: "<html><body>Clock</body></html>"
    });
  } finally {
    runtime.cleanup();
  }
});

test("background sloppy.artifacts.delete removes artifact through Core", async () => {
  const runtime = await loadBackgroundRuntime(
    {},
    async (url, options) => {
      assert.equal(url, "http://127.0.0.1:25101/v1/artifacts/widget-1");
      assert.equal(options.method, "DELETE");
      return Response.json({ deleted: true });
    }
  );

  try {
    const response = await runtime.sendMessage({ type: "sloppy.artifacts.delete", artifactId: "widget-1" });
    assert.deepEqual(response, { deleted: true });
  } finally {
    runtime.cleanup();
  }
});

test("background sloppy.artifacts.widget.generate posts prompt and size", async () => {
  const runtime = await loadBackgroundRuntime(
    {},
    async (url, options) => {
      assert.equal(url, "http://127.0.0.1:25101/v1/artifacts/widgets/generate");
      assert.equal(options.method, "POST");
      assert.deepEqual(JSON.parse(options.body), {
        prompt: "Build a clock widget",
        size: "medium"
      });
      return Response.json({
        artifact: { id: "widget-1", title: "Clock", kind: "widget" }
      });
    }
  );

  try {
    const response = await runtime.sendMessage({
      type: "sloppy.artifacts.widget.generate",
      prompt: "Build a clock widget",
      size: "medium"
    });
    assert.deepEqual(response, {
      artifact: { id: "widget-1", title: "Clock", kind: "widget" }
    });
  } finally {
    runtime.cleanup();
  }
});

test("background localizes Safari context menu summary action", async () => {
  const runtime = await loadBackgroundRuntime({}, async () => Response.json({}), { language: "zh-CN" });

  assert.deepEqual(runtime.contextMenus, [{
    id: "sloppy.summaryPage",
    title: "总结页面",
    contexts: ["page"],
    icons: {
      16: "text.aligncenter.svg",
      32: "text.aligncenter.svg"
    }
  }]);

  runtime.cleanup();
});

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

test("publicMeshSettings removes private keys from public mesh payloads", () => {
  const mesh = publicMeshSettings({
    enabled: true,
    relayURL: " https://mesh.example.com/ ",
    targetNodeId: " node_home ",
    networkId: "mesh-1",
    identity: {
      nodeId: "node_safari",
      name: "Safari Extension",
      publicKey: "ed25519:public",
      privateKey: "ed25519:private",
      roles: ["client"],
      capabilities: ["browser_context"],
      createdAt: "2026-06-22T10:00:00Z"
    }
  });

  assert.deepEqual(mesh, {
    enabled: true,
    relayURL: "https://mesh.example.com",
    targetNodeId: "node_home",
    networkId: "mesh-1",
    identity: {
      nodeId: "node_safari",
      name: "Safari Extension",
      publicKey: "ed25519:public",
      roles: ["client"],
      capabilities: ["browser_context"],
      createdAt: "2026-06-22T10:00:00Z"
    }
  });
  assert.equal("privateKey" in mesh.identity, false);
});

test("background sloppy.settings.get scrubs mesh private key from public settings responses", async () => {
  const runtime = await loadBackgroundRuntime({
    mesh: {
      enabled: true,
      relayURL: "https://mesh.example.com",
      targetNodeId: "node_home",
      identity: {
        nodeId: "node_safari",
        publicKey: "ed25519:public",
        privateKey: "ed25519:private"
      }
    }
  });

  try {
    const response = await runtime.sendMessage({ type: "sloppy.settings.get" });
    assert.equal(response.mesh.enabled, true);
    assertPublicMeshIdentity(response.mesh, {
      nodeId: "node_safari",
      publicKey: "ed25519:public"
    });
    assert.equal(runtime.storageState.mesh.identity.privateKey, "ed25519:private");
  } finally {
    runtime.cleanup();
  }
});

test("background sloppy.settings.save scrubs mesh private key from public settings responses", async () => {
  const runtime = await loadBackgroundRuntime();

  try {
    const response = await runtime.sendMessage({
      type: "sloppy.settings.save",
      settings: {
        defaultAgentID: "sloppy",
        mesh: {
          enabled: true,
          relayURL: "https://mesh.example.com",
          targetNodeId: "node_home",
          identity: {
            nodeId: "node_safari",
            publicKey: "ed25519:public",
            privateKey: "ed25519:private"
          }
        }
      }
    });

    assert.equal(response.mesh.enabled, true);
    assertPublicMeshIdentity(response.mesh, {
      nodeId: "node_safari",
      publicKey: "ed25519:public"
    });
    assert.equal(runtime.storageState.mesh.identity.privateKey, "ed25519:private");
  } finally {
    runtime.cleanup();
  }
});

test("background sloppy.settings.save preserves stored mesh private key when public settings omit it", async () => {
  const runtime = await loadBackgroundRuntime({
    defaultAgentID: "sloppy",
    mesh: {
      enabled: true,
      relayURL: "https://mesh.example.com",
      targetNodeId: "node_home",
      identity: {
        nodeId: "node_safari",
        publicKey: "ed25519:public",
        privateKey: "ed25519:private"
      }
    }
  });

  try {
    const response = await runtime.sendMessage({
      type: "sloppy.settings.save",
      settings: {
        defaultAgentID: "sloppy",
        mesh: {
          enabled: true,
          relayURL: "https://mesh.example.com",
          targetNodeId: "node_remote",
          identity: {
            nodeId: "node_safari",
            publicKey: "ed25519:public"
          }
        }
      }
    });

    assert.equal(response.mesh.targetNodeId, "node_remote");
    assertPublicMeshIdentity(response.mesh, {
      nodeId: "node_safari",
      publicKey: "ed25519:public"
    });
    assert.equal(runtime.storageState.mesh.targetNodeId, "node_remote");
    assert.equal(runtime.storageState.mesh.identity.privateKey, "ed25519:private");
  } finally {
    runtime.cleanup();
  }
});

test("background sloppy.sessions.select keeps mesh private key in storage but not public responses", async () => {
  const runtime = await loadBackgroundRuntime({
    defaultAgentID: "sloppy",
    sessionId: "session-old",
    mesh: {
      enabled: false,
      identity: {
        nodeId: "node_safari",
        publicKey: "ed25519:public",
        privateKey: "ed25519:private"
      }
    }
  });

  try {
    const response = await runtime.sendMessage({
      type: "sloppy.sessions.select",
      agentId: "sloppy",
      sessionId: ""
    });

    assertPublicMeshIdentity(response.settings.mesh, {
      nodeId: "node_safari",
      publicKey: "ed25519:public"
    });
    assert.equal(runtime.storageState.mesh.identity.privateKey, "ed25519:private");
    assert.equal("sessionId" in runtime.storageState, false);
  } finally {
    runtime.cleanup();
  }
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

test("background agent list includes cached offline mesh agents", async () => {
  const originalWebSocket = globalThis.WebSocket;
  const originalCrypto = globalThis.crypto;
  const identity = {
    nodeId: "node_safari",
    name: "Safari Extension",
    publicKey: "ed25519:public",
    privateKey: "ed25519-pkcs8:private",
    roles: ["client"],
    capabilities: ["browser_context", "core_http"]
  };
  const runtime = await loadBackgroundRuntime({
    defaultAgentID: "mesh:node_home:sloppy",
    mesh: {
      enabled: true,
      relayURL: "https://mesh.example.com",
      targetNodeId: "node_home",
      identity,
      agentDirectory: [
        {
          id: "mesh:node_work:researcher",
          agentId: "researcher",
          nodeId: "node_work",
          nodeName: "Work",
          nodeStatus: "offline",
          title: "Work / Researcher",
          lastSeenAt: "2026-06-22T10:00:00.000Z"
        }
      ]
    }
  }, async () => {
    throw new Error("direct fetch should not run");
  });

  try {
    Object.defineProperty(globalThis, "crypto", {
      configurable: true,
      value: {
        subtle: {
          async importKey() {
            return {};
          },
          async sign() {
            return Buffer.from("signature");
          }
        }
      }
    });
    globalThis.WebSocket = class {
      constructor() {
        this.listeners = {};
        queueMicrotask(() => this.emit("message", {
          data: JSON.stringify({
            type: "auth.challenge",
            from: "relay",
            payload: { nonce: "nonce_auth", nodeId: "node_safari", publicKey: "ed25519:public" }
          })
        }));
      }

      addEventListener(type, listener) {
        this.listeners[type] = listener;
      }

      send(text) {
        const envelope = JSON.parse(text);
        if (envelope.type !== "rpc.request") {
          return;
        }
        queueMicrotask(() => this.emit("message", {
          data: JSON.stringify({
            type: "rpc.response",
            from: "node_home",
            payload: {
              requestId: envelope.id,
              method: "core.http",
              ok: true,
              result: {
                status: 200,
                contentType: "application/json",
                bodyBase64: Buffer.from(JSON.stringify({
                  agents: [{ id: "sloppy", title: "Sloppy" }]
                }), "utf8").toString("base64")
              }
            }
          })
        }));
      }

      close() {}

      emit(type, event) {
        this.listeners[type]?.(event);
      }
    };

    const response = await runtime.sendMessage({ type: "sloppy.agents.list" });

    assert.deepEqual(response.agents.map((agent) => agent.id), [
      "mesh:node_home:sloppy",
      "mesh:node_work:researcher"
    ]);
    assert.equal(response.agents[0].nodeStatus, "online");
    assert.equal(response.agents[1].nodeStatus, "offline");
    assert.equal(response.selectedAgentId, "mesh:node_home:sloppy");
    assert.equal(runtime.storageState.mesh.agentDirectory.length, 2);
  } finally {
    runtime.cleanup();
    globalThis.WebSocket = originalWebSocket;
    Object.defineProperty(globalThis, "crypto", {
      configurable: true,
      value: originalCrypto
    });
  }
});

test("background queues browser context for offline mesh agents", async () => {
  const originalWebSocket = globalThis.WebSocket;
  const originalCrypto = globalThis.crypto;
  const sent = [];
  const identity = {
    nodeId: "node_safari",
    name: "Safari Extension",
    publicKey: "ed25519:public",
    privateKey: "ed25519-pkcs8:private",
    roles: ["client"],
    capabilities: ["browser_context", "core_http"]
  };
  const runtime = await loadBackgroundRuntime({
    defaultAgentID: "mesh:node_work:researcher",
    mesh: {
      enabled: true,
      relayURL: "https://mesh.example.com",
      targetNodeId: "node_home",
      identity,
      agentDirectory: [
        {
          id: "mesh:node_work:researcher",
          agentId: "researcher",
          nodeId: "node_work",
          nodeName: "Work",
          nodeStatus: "offline",
          title: "Work / Researcher"
        }
      ]
    }
  }, async () => {
    throw new Error("direct fetch should not run");
  });

  try {
    Object.defineProperty(globalThis, "crypto", {
      configurable: true,
      value: {
        subtle: {
          async importKey() {
            return {};
          },
          async sign() {
            return Buffer.from("signature");
          }
        }
      }
    });
    globalThis.WebSocket = class {
      constructor() {
        this.listeners = {};
        queueMicrotask(() => this.emit("message", {
          data: JSON.stringify({
            type: "auth.challenge",
            from: "relay",
            payload: { nonce: "nonce_auth", nodeId: "node_safari", publicKey: "ed25519:public" }
          })
        }));
      }

      addEventListener(type, listener) {
        this.listeners[type] = listener;
      }

      send(text) {
        sent.push(JSON.parse(text));
      }

      close() {}

      emit(type, event) {
        this.listeners[type]?.(event);
      }
    };

    const response = await runtime.sendMessage({
      type: "sloppy.browserContext.send",
      page: { url: "https://example.com", title: "Example" },
      selection: "",
      prompt: "read later",
      tabs: []
    });

    const published = sent.find((envelope) => envelope.type === "event.publish");
    assert.equal(response.status, "queued");
    assert.equal(response.queued, true);
    assert.equal(published.to, "node_work");
    assert.equal(published.payload.request.target.agentId, "researcher");
    assert.equal(published.payload.request.prompt, "read later");
  } finally {
    runtime.cleanup();
    globalThis.WebSocket = originalWebSocket;
    Object.defineProperty(globalThis, "crypto", {
      configurable: true,
      value: originalCrypto
    });
  }
});

test("normalizeVoiceConfig falls back to local mode", () => {
  const config = normalizeVoiceConfig({});
  assert.equal(config.enabled, false);
  assert.equal(config.effectiveProvider, "local");
  assert.equal(config.input.mode, "push_to_talk");
  assert.equal(config.local.enabled, true);
});

test("buildVoicePrompt trims transcript and preserves page prompt behavior", () => {
  assert.equal(buildVoicePrompt("  hello agent  "), "hello agent");
  assert.equal(buildVoicePrompt("   "), "");
});

test("localSpeechAvailable checks browser speech APIs without touching assistant text", () => {
  assert.deepEqual(localSpeechAvailable({ SpeechRecognition: function SpeechRecognition() {}, speechSynthesis: {} }), {
    recognition: true,
    synthesis: true
  });
  assert.deepEqual(localSpeechAvailable({ webkitSpeechRecognition: function SpeechRecognition() {} }), {
    recognition: true,
    synthesis: false
  });
});

test("fetchVoiceConfig reads sanitized voice config from Core", async () => {
  const requests = [];
  const fetchImpl = async (url) => {
    requests.push(String(url));
    return Response.json({ enabled: true, effectiveProvider: "openai", openAIConfigured: true });
  };

  const config = await fetchVoiceConfig({ coreURLString: "http://127.0.0.1:25101" }, fetchImpl);

  assert.equal(config.effectiveProvider, "openai");
  assert.equal(requests[0], "http://127.0.0.1:25101/v1/voice/config");
});

test("transcribeVoiceAudio posts audio to Core", async () => {
  const fetchImpl = async (url, options) => {
    assert.equal(String(url), "http://127.0.0.1:25101/v1/voice/transcriptions");
    assert.deepEqual(JSON.parse(options.body), {
      audioBase64: "abcd",
      mimeType: "audio/webm",
      language: "auto",
      prompt: ""
    });
    return Response.json({ text: "hello", provider: "openai", model: "gpt-4o-mini-transcribe" });
  };

  const result = await transcribeVoiceAudio(
    { coreURLString: "http://127.0.0.1:25101" },
    { audioBase64: "abcd", mimeType: "audio/webm", language: "auto", prompt: "" },
    fetchImpl
  );

  assert.equal(result.text, "hello");
});

test("normalizeAgentSessions maps Core sessions into sidebar rows", () => {
  const sessions = normalizeAgentSessions([
    { id: "s1", title: "Safari: example.com", updatedAt: "2026-06-22T10:00:00Z" },
    { sessionId: "s2", name: "Manual chat", createdAt: "2026-06-21T10:00:00Z" },
    { id: "   " }
  ]);

  assert.deepEqual(sessions, [
    { id: "s1", title: "Safari: example.com", subtitle: "2026-06-22T10:00:00Z" },
    { id: "s2", title: "Manual chat", subtitle: "2026-06-21T10:00:00Z" }
  ]);
});

test("renderMarkdown supports common assistant markdown and escapes unsafe html", () => {
  const html = renderMarkdown("**Bold** `code`\n\n- item\n\n<script>alert(1)</script>");

  assert.match(html, /<strong>Bold<\/strong>/);
  assert.match(html, /<code>code<\/code>/);
  assert.match(html, /<ul><li>item<\/li><\/ul>/);
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.equal(html.includes("<script>"), false);
});

test("collectBrowserToolActions normalizes agent browser actions", () => {
  const actions = collectBrowserToolActions({
    openTabs: ["https://example.com/new"],
    actions: [
      { type: "browser.capture_visible_tab" },
      { name: "browser.click_selector", input: { selector: "#buy" } }
    ],
    tool_calls: [
      { tool: "browser.type_text", arguments: { selector: "textarea", text: "hello" } },
      { name: "browser.scroll", arguments: { y: 500 } },
      { name: "browser.dom_snapshot" }
    ]
  });

  assert.deepEqual(actions, [
    { name: "browser.open_tab", input: { url: "https://example.com/new" } },
    { name: "browser.capture_visible_tab", input: {} },
    { name: "browser.click_selector", input: { selector: "#buy" } },
    { name: "browser.type_text", input: { selector: "textarea", text: "hello" } },
    { name: "browser.scroll", input: { y: 500 } },
    { name: "browser.dom_snapshot", input: {} }
  ]);
});

test("background Safari bridge registration sends every accessible tab", async () => {
  const requests = [];
  const runtime = await loadBackgroundRuntime(
    { coreURLString: "http://127.0.0.1:25101" },
    async (url, options = {}) => {
      requests.push({ url: String(url), body: options.body ? JSON.parse(options.body) : null });
      return Response.json({ bridgeId: "safari-test", commandPollIntervalMs: 1000 });
    },
    {
      tabs: [
        { id: 1, url: "https://one.example", title: "One", active: true, currentWindow: true },
        { id: 2, url: "https://two.example", title: "Two", active: false, currentWindow: true }
      ]
    }
  );

  try {
    const response = await runtime.sendMessage({ type: "sloppy.safariBridge.sync" });

    assert.equal(response.bridgeId, "safari-test");
    assert.equal(requests.at(-1).url, "http://127.0.0.1:25101/v1/safari-bridge/register");
    assert.deepEqual(requests.at(-1).body.tabs.map((tab) => tab.url), [
      "https://one.example",
      "https://two.example"
    ]);
  } finally {
    runtime.cleanup();
  }
});

test("background Safari bridge poll executes command and posts result", async () => {
  const requests = [];
  const runtime = await loadBackgroundRuntime(
    { coreURLString: "http://127.0.0.1:25101" },
    async (url, options = {}) => {
      requests.push({ url: String(url), method: options.method || "GET", body: options.body ? JSON.parse(options.body) : null });
      if (String(url).endsWith("/v1/safari-bridge/register")) {
        return Response.json({ bridgeId: "safari-test", commandPollIntervalMs: 1000 });
      }
      if (String(url).includes("/v1/safari-bridge/commands?")) {
        return Response.json({
          commands: [
            { id: "cmd-1", name: "safari.scroll", input: { y: 400 } }
          ]
        });
      }
      return Response.json({ status: "completed" });
    },
    {
      tabs: [{ id: 1, url: "https://one.example", title: "One", active: true, currentWindow: true }],
      scriptResult: { scrolled: { x: 0, y: 400 } }
    }
  );

  try {
    const response = await runtime.sendMessage({ type: "sloppy.safariBridge.poll" });

    assert.equal(response.commands, 1);
    assert.equal(runtime.scriptCalls.length, 1);
    assert.match(requests.at(-1).url, /\/v1\/safari-bridge\/commands\/cmd-1\/result$/);
    assert.equal(requests.at(-1).body.ok, true);
    assert.deepEqual(requests.at(-1).body.data, { scrolled: { x: 0, y: 400 } });
  } finally {
    runtime.cleanup();
  }
});

test("chooseAgentID falls back to first fetched agent when stored agent is unavailable", () => {
  assert.equal(
    chooseAgentID("missing", [
      { id: "alpha", title: "Alpha" },
      { id: "beta", title: "Beta" }
    ]),
    "alpha"
  );
  assert.equal(
    chooseAgentID("beta", [
      { id: "alpha", title: "Alpha" },
      { id: "beta", title: "Beta" }
    ]),
    "beta"
  );
});

test("describeCoreError includes status, endpoint, agent and server details", () => {
  const message = describeCoreError({
    status: 404,
    endpoint: "http://127.0.0.1:25101/v1/browser/context-message",
    agentId: "yadev",
    error: "agent_not_found",
    message: "Agent not found."
  });

  assert.match(message, /Core request failed/);
  assert.match(message, /404/);
  assert.match(message, /agent_not_found/);
  assert.match(message, /yadev/);
  assert.match(message, /\/v1\/browser\/context-message/);
});

test("describeCoreError explains missing browser context endpoint", () => {
  const message = describeCoreError({
    status: 404,
    endpoint: "http://192.168.3.199:25101/v1/browser/context-message",
    agentId: "sloppy",
    error: "not_found"
  });

  assert.match(message, /browser context endpoint/i);
  assert.match(message, /update or restart Sloppy Core/i);
  assert.match(message, /192\.168\.3\.199:25101/);
});

test("background browser context stream uses explicit active session from content script", async () => {
  const requests = [];
  const encoder = new TextEncoder();
  const runtime = await loadBackgroundRuntime(
    { defaultAgentID: "front_dev" },
    async (url, options = {}) => {
      requests.push({ url, method: options.method || "GET", body: options.body ? JSON.parse(options.body) : null });
      if (url.endsWith("/v1/agents/front_dev/sessions")) {
        return new Response(JSON.stringify({ error: "unexpected_session_create" }), { status: 500 });
      }
      if (url.endsWith("/v1/agents/front_dev/sessions/session-existing/stream")) {
        return new Response(new ReadableStream({
          start(controller) {
            controller.enqueue(encoder.encode([
              "event: session_event",
              'data: {"kind":"session_event","cursor":1,"event":{"message":{"role":"assistant","segments":[{"text":"Still same session"}]}}}',
              "",
              ""
            ].join("\n")));
            controller.close();
          }
        }), {
          headers: { "content-type": "text/event-stream" }
        });
      }
      if (url.endsWith("/v1/agents/front_dev/sessions/session-existing/messages")) {
        return Response.json({
          appendedEvents: [
            {
              id: "event-2",
              message: {
                id: "message-2",
                role: "assistant",
                segments: [{ text: "Still same session" }]
              }
            }
          ]
        });
      }
      return new Response(JSON.stringify({ error: "unexpected" }), { status: 500 });
    }
  );

  try {
    const result = await runtime.sendMessage({
      type: "sloppy.browserContext.stream",
      requestId: "request-1",
      sessionId: "session-existing",
      page: { url: "https://example.com", title: "Example" },
      selection: "",
      prompt: "continue",
      tabs: []
    }, { tab: { id: 7 } });

    assert.equal(result.sessionId, "session-existing");
    assert.equal(runtime.storageState.sessionId, "session-existing");
    const agentSessionRequests = requests.filter((request) =>
      request.url.includes("/v1/agents/front_dev/sessions")
    );
    assert.deepEqual(
      agentSessionRequests.map((request) => [request.method, request.url.replace("http://127.0.0.1:25101", "")]),
      [
        ["GET", "/v1/agents/front_dev/sessions/session-existing/stream"],
        ["POST", "/v1/agents/front_dev/sessions/session-existing/messages"]
      ]
    );
  } finally {
    runtime.cleanup();
  }
});

test("postBrowserContext falls back to session message endpoints when browser endpoint is missing", async () => {
  const requests = [];
  const fetchImpl = async (url, options) => {
    requests.push({ url, body: options?.body ? JSON.parse(options.body) : null });
    if (url.endsWith("/v1/browser/context-message")) {
      return new Response(JSON.stringify({ error: "not_found" }), { status: 404 });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions")) {
      return Response.json({ id: "session-1" });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/messages")) {
      return Response.json({
        appendedEvents: [
          {
            id: "event-1",
            message: {
              id: "message-1",
              role: "assistant",
              segments: [{ text: "Fallback answer" }]
            }
          }
        ]
      });
    }
    return new Response(JSON.stringify({ error: "unexpected" }), { status: 500 });
  };

  const result = await postBrowserContext(
    { coreURLString: "http://192.168.3.199:25101", defaultAgentID: "sloppy" },
    { url: "https://github.com/", title: "GitHub" },
    "",
    "Привет",
    {
      pageSnapshot: { title: "GitHub", text: "Repository page content" },
      attachments: [{ name: "paste.png", mimeType: "image/png", sizeBytes: 4, contentBase64: "abcd" }],
      widgetSession: {
        mode: "widget_editor",
        isolated: true,
        widget: {
          title: "Clock",
          size: "2x1",
          sourceItemId: "widget-card-1",
          artifactId: "artifact-clock"
        }
      }
    },
    fetchImpl
  );

  assert.equal(result.sessionId, "session-1");
  assert.equal(result.messageId, "message-1");
  assert.equal(result.status, "completed");
  assert.equal(result.text, "Fallback answer");
  assert.deepEqual(requests[2].body.attachments, [{ name: "paste.png", mimeType: "image/png", sizeBytes: 4, contentBase64: "abcd" }]);
  assert.equal(requests[2].body.mode, "auto");
  assert.match(requests[2].body.content, /No selected text\./);
  assert.doesNotMatch(requests[2].body.content, /Safari page snapshot:/);
  assert.doesNotMatch(requests[2].body.content, /Repository page content/);
  assert.match(requests[2].body.content, /Use `safari\.dom_snapshot` only when live page details are needed/);
  assert.match(requests[2].body.content, /Widget session:/);
  assert.match(requests[2].body.content, /This session is dedicated only to generating and iterating the start-page widget preview\./);
  assert.match(requests[2].body.content, /Create or update the preview only with the `artifacts\.widget\.generate` tool\./);
  assert.match(requests[2].body.content, /Never use `files\.write`, `files\.edit`, or any arbitrary filesystem path for widget output\./);
  assert.match(requests[2].body.content, /Widget title: Clock/);
  assert.match(requests[2].body.content, /Existing artifact id: artifact-clock/);
  assert.match(requests[2].body.content, /Привет/);
});

test("decodeSSEBlock normalizes Core session stream assistant events", () => {
  const event = decodeSSEBlock([
    "id: 7",
    "event: session_event",
    'data: {"kind":"session_event","cursor":7,"event":{"message":{"role":"assistant","segments":[{"text":"Streaming answer"}]}}}'
  ].join("\n"));

  assert.equal(event.type, "assistant_message");
  assert.equal(event.text, "Streaming answer");
  assert.equal(event.sseEvent, "session_event");
});

test("decodeSSEBlock normalizes assistant message content fields", () => {
  const event = decodeSSEBlock([
    "id: 11",
    "event: session_event",
    'data: {"kind":"session_event","cursor":11,"event":{"type":"message","message":{"role":"assistant","content":"Content field answer"}}}'
  ].join("\n"));

  assert.equal(event.type, "assistant_message");
  assert.equal(event.text, "Content field answer");
});

test("decodeSSEBlock normalizes Core session deltas as accumulated text", () => {
  const event = decodeSSEBlock([
    "id: 8",
    "event: session_delta",
    'data: {"kind":"session_delta","cursor":8,"message":"Partial answer"}'
  ].join("\n"));

  assert.equal(event.type, "delta");
  assert.equal(event.text, "Partial answer");
  assert.equal(event.replace, true);
});

test("decodeSSEBlock normalizes Core session delta fields as accumulated text", () => {
  const event = decodeSSEBlock([
    "id: 12",
    "event: session_delta",
    'data: {"kind":"session_delta","cursor":12,"delta":"Delta field answer"}'
  ].join("\n"));

  assert.equal(event.type, "delta");
  assert.equal(event.text, "Delta field answer");
  assert.equal(event.replace, true);
});

test("decodeSSEBlock exposes typed session tool and memory events", () => {
  const toolEvent = decodeSSEBlock([
    "event: session_event",
    'data: {"kind":"session_event","cursor":9,"event":{"type":"tool_call","toolCall":{"tool":"web.read","arguments":{"url":"https://example.com"}}}}'
  ].join("\n"));
  const memoryEvent = decodeSSEBlock([
    "event: session_event",
    'data: {"kind":"session_event","cursor":10,"event":{"type":"memory_checkpoint","memoryCheckpoint":{"status":"done","message":"Saved preference."}}}'
  ].join("\n"));

  assert.equal(toolEvent.type, "tool_call");
  assert.equal(toolEvent.tool.name, "Read web: https://example.com");
  assert.equal(memoryEvent.type, "tool_call");
  assert.equal(memoryEvent.tool.name, "Save memory");
});

test("postBrowserContextStreaming opens a session stream and posts the browser message", async () => {
  const requests = [];
  const encoder = new TextEncoder();
  const fetchImpl = async (url, options = {}) => {
    requests.push({ url, method: options.method || "GET", body: options.body ? JSON.parse(options.body) : null });
    if (url.endsWith("/v1/agents/sloppy/sessions")) {
      return Response.json({ id: "session-1" });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/stream")) {
      return new Response(new ReadableStream({
        start(controller) {
          controller.enqueue(encoder.encode([
            "event: session_event",
            'data: {"kind":"session_event","cursor":1,"event":{"message":{"role":"assistant","segments":[{"text":"Partial answer"}]}}}',
            "",
            ""
          ].join("\n")));
          controller.close();
        }
      }), {
        headers: { "content-type": "text/event-stream" }
      });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/messages")) {
      return Response.json({
        appendedEvents: [
          {
            id: "event-2",
            message: {
              id: "message-2",
              role: "assistant",
              segments: [{ text: "Final answer" }]
            }
          }
        ]
      });
    }
    return new Response(JSON.stringify({ error: "unexpected" }), { status: 500 });
  };
  const events = [];

  const result = await postBrowserContextStreaming(
    { coreURLString: "http://127.0.0.1:25101", defaultAgentID: "sloppy" },
    { url: "https://github.com/gpuweb/gpuweb/issues/425", title: "Issue" },
    "",
    "Summarize this page",
    { onEvent: (event) => events.push(event) },
    fetchImpl
  );

  assert.equal(result.sessionId, "session-1");
  assert.equal(result.messageId, "message-2");
  assert.equal(result.text, "Final answer");
  assert.equal(events.some((event) => event.type === "assistant_message" && event.text === "Partial answer"), true);
  assert.deepEqual(
    requests.map((request) => [request.method, request.url.replace("http://127.0.0.1:25101", "")]),
    [
      ["POST", "/v1/agents/sloppy/sessions"],
      ["GET", "/v1/agents/sloppy/sessions/session-1/stream"],
      ["POST", "/v1/agents/sloppy/sessions/session-1/messages"]
    ]
  );
  assert.equal(requests[2].body.mode, "auto");
});

test("postBrowserContextStreaming reads final assistant content from message content field", async () => {
  const fetchImpl = async (url) => {
    if (url.endsWith("/v1/agents/sloppy/sessions")) {
      return Response.json({ id: "session-1" });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/stream")) {
      return new Response(new ReadableStream({
        start(controller) {
          controller.close();
        }
      }), {
        headers: { "content-type": "text/event-stream" }
      });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/messages")) {
      return Response.json({
        appendedEvents: [
          {
            id: "event-2",
            message: {
              id: "message-2",
              role: "assistant",
              content: "Final content answer"
            }
          }
        ]
      });
    }
    return new Response(JSON.stringify({ error: "unexpected" }), { status: 500 });
  };

  const result = await postBrowserContextStreaming(
    { coreURLString: "http://127.0.0.1:25101", defaultAgentID: "sloppy" },
    { url: "https://example.com", title: "Example" },
    "",
    "Summarize",
    {},
    fetchImpl
  );

  assert.equal(result.messageId, "message-2");
  assert.equal(result.text, "Final content answer");
});

test("postBrowserContextStreaming keeps session stream long enough for late final assistant text", async () => {
  const encoder = new TextEncoder();
  let streamController = null;
  const fetchImpl = async (url) => {
    if (url.endsWith("/v1/agents/sloppy/sessions")) {
      return Response.json({ id: "session-1" });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/stream")) {
      return new Response(new ReadableStream({
        start(controller) {
          streamController = controller;
          controller.enqueue(encoder.encode([
            "event: session_delta",
            'data: {"kind":"session_delta","cursor":1,"message":"Partial"}',
            "",
            ""
          ].join("\n")));
        }
      }), {
        headers: { "content-type": "text/event-stream" }
      });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/messages")) {
      setTimeout(() => {
        streamController.enqueue(encoder.encode([
          "event: session_event",
          'data: {"kind":"session_event","cursor":2,"event":{"type":"message","message":{"role":"assistant","segments":[{"kind":"text","text":"Final answer"}]}}}',
          "",
          ""
        ].join("\n")));
        streamController.close();
      });
      return Response.json({ appendedEvents: [] });
    }
    return new Response(JSON.stringify({ error: "unexpected" }), { status: 500 });
  };
  const events = [];

  const result = await postBrowserContextStreaming(
    { coreURLString: "http://127.0.0.1:25101", defaultAgentID: "sloppy" },
    { url: "https://example.com", title: "Example" },
    "",
    "Summarize",
    { onEvent: (event) => events.push(event) },
    fetchImpl
  );

  assert.equal(result.text, "Final answer");
  assert.equal(events.some((event) => event.type === "assistant_message" && event.text === "Final answer"), true);
});

test("postBrowserContextStreaming waits for terminal run status instead of a short fixed catch-up timeout", async () => {
  const encoder = new TextEncoder();
  let streamController = null;
  const fetchImpl = async (url) => {
    if (url.endsWith("/v1/agents/sloppy/sessions")) {
      return Response.json({ id: "session-1" });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/stream")) {
      return new Response(new ReadableStream({
        start(controller) {
          streamController = controller;
          controller.enqueue(encoder.encode([
            "event: session_event",
            'data: {"kind":"session_event","cursor":1,"event":{"type":"message","message":{"role":"assistant","segments":[{"kind":"thinking","text":"Inspecting"}]}}}',
            "",
            ""
          ].join("\n")));
        }
      }), {
        headers: { "content-type": "text/event-stream" }
      });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/messages")) {
      setTimeout(() => {
        streamController.enqueue(encoder.encode([
          "event: session_event",
          'data: {"kind":"session_event","cursor":2,"event":{"type":"message","message":{"role":"assistant","segments":[{"kind":"text","text":"Final answer after long work"}]}}}',
          "",
          "event: session_event",
          'data: {"kind":"session_event","cursor":3,"event":{"type":"run_status","runStatus":{"stage":"done","label":"Done","details":"Completed."}}}',
          "",
          ""
        ].join("\n")));
        streamController.close();
      }, 1200);
      return Response.json({ appendedEvents: [] });
    }
    return new Response(JSON.stringify({ error: "unexpected" }), { status: 500 });
  };

  const result = await postBrowserContextStreaming(
    { coreURLString: "http://127.0.0.1:25101", defaultAgentID: "sloppy" },
    { url: "https://example.com", title: "Example" },
    "",
    "Summarize",
    {},
    fetchImpl
  );

  assert.equal(result.text, "Final answer after long work");
});

test("postBrowserContextStreaming reloads session detail when message post returns before final assistant text is persisted", async () => {
  const encoder = new TextEncoder();
  let detailReads = 0;
  const fetchImpl = async (url) => {
    if (url.endsWith("/v1/agents/sloppy/sessions")) {
      return Response.json({ id: "session-1" });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/stream")) {
      return new Response(new ReadableStream({
        start(controller) {
          controller.enqueue(encoder.encode([
            "event: session_event",
            'data: {"kind":"session_event","cursor":1,"event":{"type":"tool_call","toolCall":{"tool":"planning.select_route","arguments":{"route":"mode-ask"}}}}',
            "",
            "event: session_event",
            'data: {"kind":"session_event","cursor":2,"event":{"type":"tool_result","toolResult":{"tool":"planning.select_route","ok":true,"data":{"route":"mode-ask"}}}}',
            "",
            ""
          ].join("\n")));
          controller.close();
        }
      }), {
        headers: { "content-type": "text/event-stream" }
      });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/messages")) {
      return Response.json({
        appendedEvents: [
          {
            type: "tool_call",
            toolCall: {
              tool: "planning.select_route",
              arguments: { route: "mode-ask" }
            }
          },
          {
            type: "tool_result",
            toolResult: {
              tool: "planning.select_route",
              ok: true,
              data: { route: "mode-ask" }
            }
          }
        ]
      });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1")) {
      detailReads += 1;
      if (detailReads < 2) {
        return Response.json({
          summary: { id: "session-1", title: "Safari: Example" },
          events: [
            {
              type: "tool_call",
              toolCall: {
                tool: "planning.select_route",
                arguments: { route: "mode-ask" }
              }
            }
          ]
        });
      }
      return Response.json({
        summary: { id: "session-1", title: "Safari: Example" },
        events: [
          {
            id: "event-final",
            message: {
              id: "message-final",
              role: "assistant",
              segments: [{ kind: "text", text: "Recovered final answer" }]
            }
          },
          {
            type: "run_status",
            runStatus: {
              stage: "done",
              label: "Done",
              details: "Response is ready."
            }
          }
        ]
      });
    }
    return new Response(JSON.stringify({ error: "unexpected" }), { status: 500 });
  };

  const result = await postBrowserContextStreaming(
    { coreURLString: "http://127.0.0.1:25101", defaultAgentID: "sloppy" },
    { url: "https://example.com", title: "Example" },
    "",
    "Summarize",
    {},
    fetchImpl
  );

  assert.equal(result.text, "Recovered final answer");
  assert.equal(detailReads >= 2, true);
});

test("postBrowserContextStreaming returns interrupted run status details when final assistant text is missing", async () => {
  const encoder = new TextEncoder();
  const fetchImpl = async (url) => {
    if (url.endsWith("/v1/agents/sloppy/sessions")) {
      return Response.json({ id: "session-1" });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/stream")) {
      return new Response(new ReadableStream({
        start(controller) {
          controller.enqueue(encoder.encode([
            "event: session_event",
            'data: {"kind":"session_event","cursor":1,"event":{"type":"message","message":{"role":"assistant","segments":[{"kind":"thinking","text":"Inspecting privately"}]}}}',
            "",
            ""
          ].join("\n")));
          controller.close();
        }
      }), {
        headers: { "content-type": "text/event-stream" }
      });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/messages")) {
      return Response.json({
        appendedEvents: [
          {
            type: "message",
            message: {
              role: "assistant",
              segments: [{ kind: "thinking", text: "Inspecting privately" }]
            }
          },
          {
            type: "run_status",
            runStatus: {
              stage: "interrupted",
              label: "Error",
              details: "Model provider error: unsupportedModel(\"opencode:openai-yandex-team/gpt-5.4\")"
            }
          }
        ]
      });
    }
    return new Response(JSON.stringify({ error: "unexpected" }), { status: 500 });
  };

  const result = await postBrowserContextStreaming(
    { coreURLString: "http://127.0.0.1:25101", defaultAgentID: "sloppy" },
    { url: "https://example.com", title: "Example" },
    "",
    "Summarize",
    {},
    fetchImpl
  );

  assert.equal(result.text, "Model provider error: unsupportedModel(\"opencode:openai-yandex-team/gpt-5.4\")");
});
