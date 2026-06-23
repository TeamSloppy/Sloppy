import "./i18n.js";
import {
  chooseAgentID,
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
import { acceptMeshInvite } from "./mesh.js";

const defaultSettings = {
  coreURLString: "http://127.0.0.1:25101",
  authToken: "",
  defaultAgentID: "sloppy",
  selectedModel: "",
  floatingButtonEnabled: true,
  selectionBubbleEnabled: true,
  voiceLanguage: "auto"
};

const summarizePageContextMenuId = "sloppy.summaryPage";

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
  return sanitized;
}

async function listAgents(settings) {
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

async function listSessions(settings, agentId) {
  const headers = {};
  if (settings.authToken) {
    headers.authorization = `Bearer ${settings.authToken}`;
  }
  const encodedAgentId = encodeURIComponent(String(agentId || settings.defaultAgentID || "sloppy"));
  const response = await coreFetch(settings, `/v1/agents/${encodedAgentId}/sessions?limit=50`, { headers });
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
  const encodedAgentId = encodeURIComponent(String(agentId || settings.defaultAgentID || "sloppy"));
  const encodedSessionId = encodeURIComponent(String(sessionId || ""));
  const response = await coreFetch(settings, `/v1/agents/${encodedAgentId}/sessions/${encodedSessionId}`, { headers });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `session_failed_${response.status}`);
  }
  return body;
}

async function listSlashCommands(settings, agentId) {
  const headers = {};
  if (settings.authToken) {
    headers.authorization = `Bearer ${settings.authToken}`;
  }
  const encodedAgentId = encodeURIComponent(String(agentId || settings.defaultAgentID || "sloppy"));
  const response = await coreFetch(settings, `/v1/agents/${encodedAgentId}/chat-slash-commands`, { headers });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `commands_failed_${response.status}`);
  }
  return Array.isArray(body.commands) ? body.commands : [];
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

async function runBrowserTool(action) {
  if (action?.name === "browser.open_tab") {
    return { tab: await openTab(action.input?.url) };
  }
  if (action?.name === "browser.capture_visible_tab") {
    return { attachment: await captureVisibleTab() };
  }
  throw new Error(`Unsupported browser tool: ${action?.name || "unknown"}`);
}

if (typeof chrome !== "undefined") {
  chrome.runtime.onInstalled?.addListener(() => registerContextMenus());
  chrome.contextMenus?.onClicked?.addListener((info, tab) => {
    void handleContextMenuClick(info, tab);
  });
  registerContextMenus();

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
          if (selectedAgentId !== settings.defaultAgentID) {
            await saveSettings({ ...settings, defaultAgentID: selectedAgentId });
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
          delete nextSettings.sessionId;
        }
        const saved = await saveSettings(nextSettings);
        const session = sessionId ? await getSession(saved, message.agentId || saved.defaultAgentID, sessionId) : null;
        sendResponse({ settings: publicSettings(saved), session });
      })().catch((error) => {
        sendResponse({ error: error.message || "Unable to select session." });
      });
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
        const effectiveSettings = selectedModel && selectedModel !== "default"
          ? { ...settings, selectedModel }
          : { ...settings, selectedModel: "" };
        const selection = fallbackSelectionText(message.selection);
        const options = {
          tabs: message.tabs || [],
          pageSnapshot: message.pageSnapshot || null,
          attachments: message.attachments || []
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
