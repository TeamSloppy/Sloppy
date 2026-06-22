import { postBrowserContext } from "./panel.js";

const defaultSettings = {
  coreURLString: "http://127.0.0.1:25101",
  authToken: "",
  defaultAgentID: "sloppy"
};

async function loadSettings() {
  const stored = await chrome.storage.local.get(defaultSettings);
  return { ...defaultSettings, ...stored };
}

if (typeof chrome !== "undefined") {
  chrome.action.onClicked.addListener(async (tab) => {
    if (!tab.id) {
      return;
    }
    await chrome.tabs.sendMessage(tab.id, { type: "sloppy.panel.open" });
  });

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type !== "sloppy.browserContext.send") {
      return false;
    }
    void (async () => {
      try {
        if (!String(message.selection || "").trim()) {
          sendResponse({ error: "Select text on the page first." });
          return;
        }
        if (!String(message.prompt || "").trim()) {
          sendResponse({ error: "Enter a prompt first." });
          return;
        }
        const settings = await loadSettings();
        const result = await postBrowserContext(settings, message.page, message.selection, message.prompt);
        sendResponse(result);
      } catch (error) {
        sendResponse({ error: error.message || "Sloppy Core unavailable." });
      }
    })();
    return true;
  });
}
