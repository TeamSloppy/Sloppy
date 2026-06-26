import "./i18n.js";
import {
  chooseAgentID,
  buildBrowserContextPayload,
  coreFetch,
  fallbackSelectionText,
  fetchProviderModels,
  fetchVoiceConfig,
  normalizeAgentSessions,
  postBrowserContext,
  postBrowserContextStreaming,
  publicMeshSettings,
  publicSettings,
  sanitizeSettings,
  synthesizeVoiceSpeech,
  transcribeVoiceAudio
} from "./panel.js";
import {
  acceptMeshInvite,
  meshQueueBrowserContextMessage,
  meshListAgentDirectory,
  normalizeMeshAgentDirectory,
  parseMeshAgentAddress
} from "./mesh.js";

const defaultSettings = {
  coreURLString: "http://127.0.0.1:25101",
  authToken: "",
  defaultAgentID: "sloppy",
  selectedModel: "",
  floatingButtonEnabled: true,
  selectionBubbleEnabled: true,
  startPageEnabled: true,
  startPageTheme: "dark",
  startPageBackgroundImage: "",
  startPageShortcuts: [],
  startPageItems: [],
  voiceLanguage: "auto"
};

const summarizePageContextMenuId = "sloppy.summaryPage";
const safariBridgeCapabilities = [
  "tabs",
  "open_tab",
  "capture_visible_tab",
  "click",
  "type",
  "scroll",
  "evaluate",
  "print",
  "dom_snapshot"
];
const safariBridgeState = {
  bridgeId: ""
};

function t(key, params = {}) {
  return globalThis.SloppyI18n?.t(key, params) || key;
}

async function loadSettings() {
  const stored = await chrome.storage.local.get(defaultSettings);
  return sanitizeSettings({ ...defaultSettings, ...stored });
}

function createContextMenus() {
  chrome.contextMenus?.create?.({
    id: summarizePageContextMenuId,
    title: t("summarizePageContextMenu"),
    contexts: ["page"],
    icons: {
      16: "text.aligncenter.svg",
      32: "text.aligncenter.svg"
    }
  });
}

function registerContextMenus() {
  if (!chrome.contextMenus) {
    return;
  }
  if (typeof chrome.contextMenus.removeAll === "function") {
    const result = chrome.contextMenus.removeAll(() => createContextMenus());
    result?.then?.(createContextMenus).catch?.(() => createContextMenus());
    return;
  }
  createContextMenus();
}

async function handleContextMenuClick(info, tab) {
  if (info?.menuItemId !== summarizePageContextMenuId || !tab?.id) {
    return;
  }
  await chrome.tabs.sendMessage(tab.id, { type: "sloppy.page.summarize" });
}

function mergeMeshSettings(currentMesh, incomingMesh) {
  if (!incomingMesh || typeof incomingMesh !== "object") {
    return incomingMesh === undefined ? currentMesh : incomingMesh;
  }

  const merged = {
    ...(currentMesh && typeof currentMesh === "object" ? currentMesh : {}),
    ...incomingMesh
  };
  const currentIdentity = currentMesh?.identity;
  const incomingIdentity = incomingMesh.identity;
  if (currentIdentity || incomingIdentity) {
    merged.identity = {
      ...(currentIdentity && typeof currentIdentity === "object" ? currentIdentity : {}),
      ...(incomingIdentity && typeof incomingIdentity === "object" ? incomingIdentity : {})
    };
    if (!Object.prototype.hasOwnProperty.call(incomingIdentity || {}, "privateKey") && currentIdentity?.privateKey) {
      merged.identity.privateKey = currentIdentity.privateKey;
    }
  }
  return merged;
}

async function saveSettings(settings) {
  const current = await loadSettings();
  const sanitized = sanitizeSettings({
    ...defaultSettings,
    ...current,
    ...settings,
    mesh: mergeMeshSettings(current.mesh, settings?.mesh)
  });
  await chrome.storage.local.set(sanitized);
  if (!sanitized.selectedModel) {
    await chrome.storage.local.remove?.("selectedModel");
  }
  if (!sanitized.sessionId) {
    await chrome.storage.local.remove?.("sessionId");
  }
  return sanitized;
}

async function listAgents(settings) {
  if (settings.mesh?.enabled) {
    try {
      return await meshListAgentDirectory(settings);
    } catch {
      return listSelectedMeshNodeAgents(settings);
    }
  }
  const headers = {};
  if (settings.authToken) {
    headers.authorization = `Bearer ${settings.authToken}`;
  }
  const response = await coreFetch(settings, "/v1/agents", { headers });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `agents_failed_${response.status}`);
  }
  const records = Array.isArray(body.agents) ? body.agents : Array.isArray(body) ? body : [];
  return records
    .map((agent) => ({
      id: String(agent.id || agent.name || "").trim(),
      title: String(agent.title || agent.displayName || agent.name || agent.id || "").trim()
    }))
    .filter((agent) => agent.id);
}

async function listSelectedMeshNodeAgents(settings) {
  const headers = {};
  if (settings.authToken) {
    headers.authorization = `Bearer ${settings.authToken}`;
  }
  const effectiveSettings = settingsForAgent(settings, settings.defaultAgentID);
  const response = await coreFetch(effectiveSettings, "/v1/agents", { headers });
  const body = await response.json().catch(() => ({}));
  const records = response.ok
    ? (Array.isArray(body.agents) ? body.agents : Array.isArray(body) ? body : [])
    : [];
  const agents = records
    .map((agent) => ({
      id: String(agent.id || agent.name || "").trim(),
      title: String(agent.title || agent.displayName || agent.name || agent.id || "").trim()
    }))
    .filter((agent) => agent.id);
  const targetNodeId = effectiveSettings.mesh?.targetNodeId || settings.mesh.targetNodeId;
  const onlineDirectory = normalizeMeshAgentDirectory([{
    nodeId: targetNodeId,
    nodeName: settings.mesh.targetNodeName || targetNodeId,
    nodeStatus: "online",
    agents
  }]);
  return mergeAgentDirectory(onlineDirectory, settings.mesh.agentDirectory);
}

async function listSessions(settings, agentId) {
  const headers = {};
  if (settings.authToken) {
    headers.authorization = `Bearer ${settings.authToken}`;
  }
  const effectiveSettings = settingsForAgent(settings, agentId || settings.defaultAgentID);
  const encodedAgentId = encodeURIComponent(agentIdForCore(agentId || settings.defaultAgentID || "sloppy"));
  const response = await coreFetch(effectiveSettings, `/v1/agents/${encodedAgentId}/sessions?limit=50`, { headers });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `sessions_failed_${response.status}`);
  }
  const records = Array.isArray(body.sessions) ? body.sessions : Array.isArray(body) ? body : [];
  return normalizeAgentSessions(records);
}

async function getSession(settings, agentId, sessionId) {
  const headers = {};
  if (settings.authToken) {
    headers.authorization = `Bearer ${settings.authToken}`;
  }
  const effectiveSettings = settingsForAgent(settings, agentId || settings.defaultAgentID);
  const encodedAgentId = encodeURIComponent(agentIdForCore(agentId || settings.defaultAgentID || "sloppy"));
  const encodedSessionId = encodeURIComponent(String(sessionId || ""));
  const response = await coreFetch(effectiveSettings, `/v1/agents/${encodedAgentId}/sessions/${encodedSessionId}`, { headers });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `session_failed_${response.status}`);
  }
  return body;
}

async function listArtifacts(settings) {
  const response = await coreFetch(settings, "/v1/artifacts", {
    headers: bridgeHeaders(settings)
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `artifacts_failed_${response.status}`);
  }
  return Array.isArray(body.artifacts) ? body.artifacts : [];
}

async function getArtifactWidget(settings, artifactId) {
  const response = await coreFetch(settings, `/v1/artifacts/${encodeURIComponent(String(artifactId || "").trim())}/widget`, {
    headers: bridgeHeaders(settings)
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `artifact_widget_failed_${response.status}`);
  }
  return body;
}

async function generateArtifactWidget(settings, prompt, size) {
  const response = await coreFetch(settings, "/v1/artifacts/widgets/generate", {
    method: "POST",
    headers: bridgeHeaders(settings),
    body: JSON.stringify({
      prompt: String(prompt || ""),
      size: String(size || "small")
    })
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `artifact_generate_failed_${response.status}`);
  }
  return body;
}

async function listSlashCommands(settings, agentId) {
  const headers = {};
  if (settings.authToken) {
    headers.authorization = `Bearer ${settings.authToken}`;
  }
  const effectiveSettings = settingsForAgent(settings, agentId || settings.defaultAgentID);
  const encodedAgentId = encodeURIComponent(agentIdForCore(agentId || settings.defaultAgentID || "sloppy"));
  const response = await coreFetch(effectiveSettings, `/v1/agents/${encodedAgentId}/chat-slash-commands`, { headers });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `commands_failed_${response.status}`);
  }
  return Array.isArray(body.commands) ? body.commands : [];
}

function settingsForAgent(settings, agentId) {
  const address = parseMeshAgentAddress(agentId);
  if (!address || !settings.mesh?.enabled) {
    return settings;
  }
  return {
    ...settings,
    defaultAgentID: address.agentId,
    mesh: {
      ...settings.mesh,
      targetNodeId: address.nodeId
    }
  };
}

function agentIdForCore(agentId) {
  return parseMeshAgentAddress(agentId)?.agentId || String(agentId || "sloppy");
}

function mergeAgentDirectory(primary, cached) {
  const merged = [];
  const seen = new Set();
  for (const agent of [
    ...normalizeMeshAgentDirectory(primary),
    ...normalizeMeshAgentDirectory(cached)
  ]) {
    if (seen.has(agent.id)) {
      continue;
    }
    seen.add(agent.id);
    merged.push(agent);
  }
  return merged;
}

function selectedOfflineMeshAgent(settings) {
  const address = parseMeshAgentAddress(settings.defaultAgentID);
  if (!address || !settings.mesh?.enabled) {
    return null;
  }
  const agent = normalizeMeshAgentDirectory(settings.mesh.agentDirectory)
    .find((candidate) => candidate.id === settings.defaultAgentID);
  return agent?.nodeStatus === "offline" ? { ...agent, ...address } : null;
}

async function listTabs() {
  const tabs = await chrome.tabs.query({});
  return tabs.map((tab) => ({
    id: tab.id || null,
    url: tab.url || "",
    title: tab.title || null,
    active: Boolean(tab.active),
    currentWindow: Boolean(tab.currentWindow)
  }));
}

async function openTab(url) {
  const tab = await chrome.tabs.create({ url });
  return {
    id: tab.id || null,
    url: tab.url || url,
    title: tab.title || null
  };
}

async function captureVisibleTab() {
  const image = await chrome.tabs.captureVisibleTab(undefined, { format: "png" });
  return {
    name: `safari-tab-${Date.now()}.png`,
    kind: "image",
    mimeType: "image/png",
    dataURL: image
  };
}

function bridgeHeaders(settings) {
  const headers = { "content-type": "application/json" };
  if (settings.authToken) {
    headers.authorization = `Bearer ${settings.authToken}`;
  }
  return headers;
}

async function registerSafariBridge(settings = null) {
  const effectiveSettings = settings || await loadSettings();
  const tabs = await listTabs();
  const response = await coreFetch(effectiveSettings, "/v1/safari-bridge/register", {
    method: "POST",
    headers: bridgeHeaders(effectiveSettings),
    body: JSON.stringify({
      bridgeId: safariBridgeState.bridgeId || null,
      tabs,
      capabilities: safariBridgeCapabilities
    })
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `safari_bridge_register_failed_${response.status}`);
  }
  safariBridgeState.bridgeId = String(body.bridgeId || safariBridgeState.bridgeId || "").trim();
  return body;
}

async function pollSafariBridgeCommands(settings = null) {
  const effectiveSettings = settings || await loadSettings();
  if (!safariBridgeState.bridgeId) {
    await registerSafariBridge(effectiveSettings);
  }
  if (!safariBridgeState.bridgeId) {
    return { commands: 0 };
  }
  const response = await coreFetch(
    effectiveSettings,
    `/v1/safari-bridge/commands?bridgeId=${encodeURIComponent(safariBridgeState.bridgeId)}&limit=5`,
    { headers: bridgeHeaders(effectiveSettings) }
  );
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `safari_bridge_poll_failed_${response.status}`);
  }
  const commands = Array.isArray(body.commands) ? body.commands : [];
  for (const command of commands) {
    await completeSafariBridgeCommand(effectiveSettings, command);
  }
  return { commands: commands.length };
}

async function completeSafariBridgeCommand(settings, command) {
  const commandId = String(command?.id || "").trim();
  if (!commandId) {
    return;
  }
  let result;
  try {
    const data = await runSafariBridgeCommand(command);
    result = { commandId, ok: true, data };
  } catch (error) {
    result = {
      commandId,
      ok: false,
      error: error.message || "Safari bridge command failed."
    };
  }
  await coreFetch(settings, `/v1/safari-bridge/commands/${encodeURIComponent(commandId)}/result`, {
    method: "POST",
    headers: bridgeHeaders(settings),
    body: JSON.stringify(result)
  });
}

async function activeTabId(input = {}) {
  const explicit = Number(input.tabId);
  if (Number.isFinite(explicit) && explicit > 0) {
    return explicit;
  }
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  const tabId = tabs[0]?.id;
  if (!tabId) {
    throw new Error("No active Safari tab is available.");
  }
  return tabId;
}

async function executeInTab(input, func, args = []) {
  if (!chrome.scripting?.executeScript) {
    throw new Error("Safari scripting API is unavailable.");
  }
  const tabId = await activeTabId(input);
  const results = await chrome.scripting.executeScript({
    target: { tabId },
    func,
    args
  });
  return results?.[0]?.result ?? {};
}

async function runSafariBridgeCommand(command) {
  const input = command?.input || {};
  switch (command?.name) {
  case "safari.tabs":
    return { tabs: await listTabs() };
  case "safari.open_tab":
    return { tab: await openTab(input.url) };
  case "safari.capture_visible_tab":
    return { attachment: await captureVisibleTab() };
  case "safari.click":
    return executeInTab(input, (selector) => {
      const element = document.querySelector(selector);
      if (!element) {
        throw new Error(`Element not found: ${selector}`);
      }
      element.scrollIntoView?.({ block: "center", inline: "center" });
      element.click();
      return { clicked: selector, url: location.href, title: document.title };
    }, [input.selector]);
  case "safari.type":
    return executeInTab(input, (selector, text) => {
      const element = document.querySelector(selector);
      if (!element) {
        throw new Error(`Element not found: ${selector}`);
      }
      element.focus?.();
      if ("value" in element) {
        element.value = text || "";
        element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text || "" }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
      } else {
        element.textContent = text || "";
        element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text || "" }));
      }
      return { typed: selector, length: String(text || "").length, url: location.href, title: document.title };
    }, [input.selector, input.text || ""]);
  case "safari.scroll":
    return executeInTab(input, (x, y, behavior) => {
      window.scrollBy({ left: Number(x || 0), top: Number(y || 0), behavior: behavior === "smooth" ? "smooth" : "auto" });
      return { scrolled: { x: Number(x || 0), y: Number(y || 0) }, url: location.href, title: document.title };
    }, [input.x || 0, input.y || input.deltaY || 0, input.behavior || "auto"]);
  case "safari.evaluate":
    return executeInTab(input, (script) => {
      const value = globalThis.eval(script);
      return { value };
    }, [input.script || ""]);
  case "safari.print":
    return executeInTab(input, () => {
      window.print();
      return { printed: true, url: location.href, title: document.title };
    });
  case "safari.dom_snapshot":
    return executeInTab(input, () => {
      const elements = Array.from(document.querySelectorAll("a, button, input, textarea, select, [role='button'], [contenteditable='true']"))
        .slice(0, 80)
        .map((element, index) => ({
          index,
          tag: element.tagName?.toLowerCase() || null,
          text: String(element.innerText || element.value || element.getAttribute?.("aria-label") || element.title || "").trim().slice(0, 180),
          role: element.getAttribute?.("role") || null,
          type: element.getAttribute?.("type") || null
        }));
      return {
        title: document.title || null,
        url: location.href,
        text: String(document.body?.innerText || "").replace(/\s+/g, " ").trim().slice(0, 24000),
        elements
      };
    });
  default:
    throw new Error(`Unsupported Safari bridge command: ${command?.name || "unknown"}`);
  }
}

async function runBrowserTool(action) {
  if (action?.name === "browser.open_tab") {
    return { tab: await openTab(action.input?.url) };
  }
  if (action?.name === "browser.capture_visible_tab") {
    return { attachment: await captureVisibleTab() };
  }
  if (String(action?.name || "").startsWith("safari.")) {
    return runSafariBridgeCommand({ id: "direct", name: action.name, input: action.input || {} });
  }
  throw new Error(`Unsupported browser tool: ${action?.name || "unknown"}`);
}

function nodeTestRuntime() {
  return typeof process !== "undefined" && Boolean(process.versions?.node);
}

function startSafariBridgeLoop() {
  void registerSafariBridge().catch(() => {});
  if (nodeTestRuntime()) {
    return;
  }
  globalThis.setInterval?.(() => {
    void pollSafariBridgeCommands().catch(() => {});
  }, 1000);
}

if (typeof chrome !== "undefined") {
  chrome.runtime.onInstalled?.addListener(() => registerContextMenus());
  chrome.contextMenus?.onClicked?.addListener((info, tab) => {
    void handleContextMenuClick(info, tab);
  });
  registerContextMenus();
  startSafariBridgeLoop();

  chrome.action.onClicked.addListener(async (tab) => {
    if (!tab.id) {
      return;
    }
    await chrome.tabs.sendMessage(tab.id, { type: "sloppy.panel.open" });
  });

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type === "sloppy.settings.get") {
      void loadSettings().then((settings) => sendResponse(publicSettings(settings))).catch((error) => {
        sendResponse({ error: error.message || "Settings unavailable." });
      });
      return true;
    }
    if (message?.type === "sloppy.settings.save") {
      void saveSettings(message.settings).then((settings) => sendResponse(publicSettings(settings))).catch((error) => {
        sendResponse({ error: error.message || "Settings unavailable." });
      });
      return true;
    }
    if (message?.type === "sloppy.agents.list") {
      void (async () => {
        try {
          const settings = await loadSettings();
          const agents = await listAgents(settings);
          const selectedAgentId = chooseAgentID(settings.defaultAgentID, agents);
          const nextSettings = { ...settings, defaultAgentID: selectedAgentId };
          if (selectedAgentId !== settings.defaultAgentID) {
            nextSettings.sessionId = null;
          }
          if (settings.mesh?.enabled) {
            nextSettings.mesh = {
              ...settings.mesh,
              agentDirectory: agents
            };
          }
          if (selectedAgentId !== settings.defaultAgentID || settings.mesh?.enabled) {
            await saveSettings(nextSettings);
          }
          sendResponse({ agents, selectedAgentId });
        } catch (error) {
          const fallback = await loadSettings().catch(() => defaultSettings);
          sendResponse({
            agents: [{ id: fallback.defaultAgentID || "sloppy", title: fallback.defaultAgentID || "sloppy" }],
            error: error.message || "Agents unavailable."
          });
        }
      })();
      return true;
    }
    if (message?.type === "sloppy.tabs.list") {
      void listTabs().then((tabs) => sendResponse({ tabs })).catch((error) => {
        sendResponse({ tabs: [], error: error.message || "Tabs unavailable." });
      });
      return true;
    }
    if (message?.type === "sloppy.sessions.list") {
      void (async () => {
        try {
          const settings = await loadSettings();
          const sessions = await listSessions(settings, message.agentId || settings.defaultAgentID);
          sendResponse({ sessions, selectedSessionId: settings.sessionId || null });
        } catch (error) {
          sendResponse({ sessions: [], error: error.message || t("sessionsUnavailable") });
        }
      })();
      return true;
    }
    if (message?.type === "sloppy.sessions.select") {
      void (async () => {
        const settings = await loadSettings();
        const sessionId = String(message.sessionId || "").trim();
        const nextSettings = { ...settings };
        if (sessionId) {
          nextSettings.sessionId = sessionId;
        } else {
          nextSettings.sessionId = null;
        }
        const saved = await saveSettings(nextSettings);
        const session = sessionId ? await getSession(saved, message.agentId || saved.defaultAgentID, sessionId) : null;
        sendResponse({ settings: publicSettings(saved), session });
      })().catch((error) => {
        sendResponse({ error: error.message || "Unable to select session." });
      });
      return true;
    }
    if (message?.type === "sloppy.artifacts.list") {
      void loadSettings()
        .then((settings) => listArtifacts(settings))
        .then(sendResponse)
        .catch((error) => sendResponse({ error: error.message || "Artifacts unavailable." }));
      return true;
    }
    if (message?.type === "sloppy.artifacts.widget") {
      void loadSettings()
        .then((settings) => {
          const artifactId = String(message.artifactId || "").trim();
          if (!artifactId) {
            return null;
          }
          return getArtifactWidget(settings, artifactId);
        })
        .then(sendResponse)
        .catch((error) => sendResponse({ error: error.message || "Widget unavailable." }));
      return true;
    }
    if (message?.type === "sloppy.artifacts.widget.generate") {
      void loadSettings()
        .then((settings) => generateArtifactWidget(settings, message.prompt, message.size))
        .then(sendResponse)
        .catch((error) => sendResponse({ error: error.message || "Widget generation failed." }));
      return true;
    }
    if (message?.type === "sloppy.commands.list") {
      void (async () => {
        try {
          const settings = await loadSettings();
          const commands = await listSlashCommands(settings, message.agentId || settings.defaultAgentID);
          sendResponse({ commands });
        } catch (error) {
          sendResponse({ commands: [], error: error.message || "Commands unavailable." });
        }
      })();
      return true;
    }
    if (message?.type === "sloppy.models.list") {
      void (async () => {
        try {
          const settings = await loadSettings();
          const models = await fetchProviderModels(settings);
          sendResponse({ models, selectedModel: settings.selectedModel || "default" });
        } catch (error) {
          const settings = await loadSettings().catch(() => defaultSettings);
          sendResponse({
            models: [{ id: "default", title: t("defaultModel"), subtitle: t("defaultModelSubtitle") }],
            selectedModel: settings.selectedModel || "default",
            error: error.message || "Models unavailable."
          });
        }
      })();
      return true;
    }
    if (message?.type === "sloppy.mesh.status") {
      void loadSettings().then((settings) => {
        sendResponse({ mesh: publicMeshSettings(settings.mesh) });
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
        sendResponse({
          ...result,
          mesh: publicMeshSettings(result.mesh)
        });
      })().catch((error) => {
        sendResponse({ error: error.message || "Unable to join mesh." });
      });
      return true;
    }
    if (message?.type === "sloppy.tabs.open") {
      void openTab(message.url).then((tab) => sendResponse({ tab })).catch((error) => {
        sendResponse({ error: error.message || "Unable to open tab." });
      });
      return true;
    }
    if (message?.type === "sloppy.safariBridge.sync") {
      void registerSafariBridge().then(sendResponse).catch((error) => {
        sendResponse({ error: error.message || "Safari bridge sync failed." });
      });
      return true;
    }
    if (message?.type === "sloppy.safariBridge.poll") {
      void pollSafariBridgeCommands().then(sendResponse).catch((error) => {
        sendResponse({ error: error.message || "Safari bridge poll failed." });
      });
      return true;
    }
    if (message?.type === "sloppy.browserTool.run") {
      void runBrowserTool(message.action).then(sendResponse).catch((error) => {
        sendResponse({ error: error.message || "Browser tool failed." });
      });
      return true;
    }
    if (message?.type === "sloppy.voice.config.get") {
      void (async () => {
        const settings = await loadSettings();
        const config = await fetchVoiceConfig(settings);
        sendResponse({ config });
      })().catch((error) => sendResponse({ error: error.message || "Voice config unavailable." }));
      return true;
    }
    if (message?.type === "sloppy.voice.transcribe") {
      void (async () => {
        const settings = await loadSettings();
        const result = await transcribeVoiceAudio(settings, message.payload || {});
        sendResponse({ result });
      })().catch((error) => sendResponse({ error: error.message || "Voice transcription failed." }));
      return true;
    }
    if (message?.type === "sloppy.voice.speech") {
      void (async () => {
        const settings = await loadSettings();
        const result = await synthesizeVoiceSpeech(settings, message.payload || {});
        sendResponse({ result });
      })().catch((error) => sendResponse({ error: error.message || "Voice speech failed." }));
      return true;
    }
    if (message?.type === "sloppy.bookmarks.list") {
      void (async () => {
        try {
          const browserBookmarks = globalThis.chrome?.bookmarks;
          if (!browserBookmarks?.search || typeof browserBookmarks.search !== "function") {
            sendResponse({ error: "bookmarks_unavailable" });
            return;
          }
          const items = await browserBookmarks.search({});
          sendResponse(Array.isArray(items)
            ? items
              .filter((item) => String(item?.url || "").trim())
              .map((item) => ({
                id: String(item.id || ""),
                title: String(item.title || item.url || "").trim(),
                url: String(item.url || "").trim()
              }))
            : []);
        } catch (error) {
          sendResponse({ error: error?.message || "bookmarks_unavailable" });
        }
      })();
      return true;
    }
    if (message?.type !== "sloppy.browserContext.send") {
      if (message?.type !== "sloppy.browserContext.stream") {
        return false;
      }
    }
    void (async () => {
      try {
        if (!String(message.prompt || "").trim()) {
          sendResponse({ error: "Enter a prompt first." });
          return;
        }
        const settings = await loadSettings();
        const selectedModel = String(message.model || "").trim();
        const offlineMeshAgent = selectedOfflineMeshAgent(settings);
        if (offlineMeshAgent) {
          const queuedSettings = settingsForAgent(settings, settings.defaultAgentID);
          const payload = buildBrowserContextPayload(
            selectedModel && selectedModel !== "default"
              ? { ...queuedSettings, selectedModel }
              : { ...queuedSettings, selectedModel: "" },
            message.page,
            fallbackSelectionText(message.selection),
            message.prompt,
            {
              tabs: message.tabs || [],
              pageSnapshot: message.pageSnapshot || null,
              attachments: message.attachments || [],
              widgetSession: message.widgetSession || null
            }
          );
          const result = await meshQueueBrowserContextMessage(settings, offlineMeshAgent.nodeId, payload);
          sendResponse(result);
          return;
        }
        const routedSettings = settingsForAgent(settings, settings.defaultAgentID);
        const activeSessionId = String(message.sessionId || "").trim();
        const effectiveSettings = selectedModel && selectedModel !== "default"
          ? { ...routedSettings, selectedModel, ...(activeSessionId ? { sessionId: activeSessionId } : {}) }
          : { ...routedSettings, selectedModel: "", ...(activeSessionId ? { sessionId: activeSessionId } : {}) };
        const selection = fallbackSelectionText(message.selection);
        const options = {
          tabs: message.tabs || [],
          pageSnapshot: message.pageSnapshot || null,
          attachments: message.attachments || [],
          widgetSession: message.widgetSession || null
        };
        if (message.type === "sloppy.browserContext.stream") {
          const tabId = _sender.tab?.id;
          const requestId = message.requestId;
          const result = await postBrowserContextStreaming(effectiveSettings, message.page, selection, message.prompt, {
            ...options,
            onEvent: (event) => {
              if (!tabId || !requestId) {
                return;
              }
              void chrome.tabs.sendMessage(tabId, {
                type: "sloppy.browserContext.streamEvent",
                requestId,
                event
              });
            }
          });
          if (result?.sessionId) {
            await saveSettings({ ...effectiveSettings, sessionId: result.sessionId });
          }
          sendResponse(result);
          return;
        }
        const result = await postBrowserContext(effectiveSettings, message.page, selection, message.prompt, options);
        if (result?.sessionId) {
          await saveSettings({ ...effectiveSettings, sessionId: result.sessionId });
        }
        sendResponse(result);
      } catch (error) {
        sendResponse({ error: error.message || "Sloppy Core unavailable." });
      }
    })();
    return true;
  });
}
