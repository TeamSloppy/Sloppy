import {
  chooseAgentID,
  coreFetch,
  fallbackSelectionText,
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
  floatingButtonEnabled: false,
  selectionBubbleEnabled: true
};

async function loadSettings() {
  const stored = await chrome.storage.local.get(defaultSettings);
  return sanitizeSettings({ ...defaultSettings, ...stored });
}

async function saveSettings(settings) {
  const sanitized = sanitizeSettings({ ...defaultSettings, ...settings });
  await chrome.storage.local.set(sanitized);
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
          sendResponse({ sessions: [], error: error.message || "Sessions unavailable." });
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
        sendResponse({ settings: publicSettings(saved) });
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
        const selection = fallbackSelectionText(message.selection);
        const options = {
          tabs: message.tabs || [],
          pageSnapshot: message.pageSnapshot || null,
          attachments: message.attachments || []
        };
        if (message.type === "sloppy.browserContext.stream") {
          const tabId = _sender.tab?.id;
          const requestId = message.requestId;
          const result = await postBrowserContextStreaming(settings, message.page, selection, message.prompt, {
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
            await saveSettings({ ...settings, sessionId: result.sessionId });
          }
          sendResponse(result);
          return;
        }
        const result = await postBrowserContext(settings, message.page, selection, message.prompt, options);
        if (result?.sessionId) {
          await saveSettings({ ...settings, sessionId: result.sessionId });
        }
        sendResponse(result);
      } catch (error) {
        sendResponse({ error: error.message || "Sloppy Core unavailable." });
      }
    })();
    return true;
  });
}
