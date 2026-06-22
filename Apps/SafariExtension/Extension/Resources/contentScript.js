function extractPageContext(documentLike = globalThis.document, selectionText = "") {
  return {
    page: {
      url: documentLike.location.href,
      title: documentLike.title || null
    },
    selection: String(selectionText || "").trim()
  };
}

function selectedText() {
  return String(globalThis.getSelection?.() || "").trim();
}

function ensurePanel() {
  let frame = document.getElementById("sloppy-safari-extension-panel");
  if (frame) {
    return frame;
  }

  frame = document.createElement("aside");
  frame.id = "sloppy-safari-extension-panel";
  frame.innerHTML = `
    <div class="sloppy-safari-extension-header">
      <strong>SafariExtension</strong>
      <button type="button" data-sloppy-close aria-label="Close">x</button>
    </div>
    <div class="sloppy-safari-extension-meta"></div>
    <label>Core URL<input data-sloppy-core-url placeholder="http://127.0.0.1:25101"></label>
    <label>Auth token<input data-sloppy-auth-token type="password" autocomplete="off"></label>
    <label>Agent ID<input data-sloppy-agent-id placeholder="sloppy"></label>
    <textarea data-sloppy-selection readonly></textarea>
    <textarea data-sloppy-prompt placeholder="Ask Sloppy about the selection"></textarea>
    <button type="button" data-sloppy-send>Send</button>
    <pre data-sloppy-output></pre>
  `;
  document.documentElement.appendChild(frame);
  frame.querySelector("[data-sloppy-close]").addEventListener("click", () => frame.remove());
  return frame;
}

async function openPanel() {
  const selection = selectedText();
  const context = extractPageContext(document, selection);
  const panel = ensurePanel();
  const settings = await chrome.runtime.sendMessage({ type: "sloppy.settings.get" });
  panel.querySelector("[data-sloppy-core-url]").value = settings?.coreURLString || "";
  panel.querySelector("[data-sloppy-auth-token]").value = settings?.authToken || "";
  panel.querySelector("[data-sloppy-agent-id]").value = settings?.defaultAgentID || "sloppy";
  panel.querySelector("[data-sloppy-selection]").value = context.selection;
  panel.querySelector("[data-sloppy-prompt]").value = "";
  panel.querySelector("[data-sloppy-output]").textContent = "";
  panel.querySelector("[data-sloppy-send]").onclick = async () => {
    const prompt = panel.querySelector("[data-sloppy-prompt]").value;
    await chrome.runtime.sendMessage({
      type: "sloppy.settings.save",
      settings: {
        coreURLString: panel.querySelector("[data-sloppy-core-url]").value,
        authToken: panel.querySelector("[data-sloppy-auth-token]").value,
        defaultAgentID: panel.querySelector("[data-sloppy-agent-id]").value
      }
    });
    const response = await chrome.runtime.sendMessage({
      type: "sloppy.browserContext.send",
      page: context.page,
      selection: context.selection,
      prompt
    });
    panel.querySelector("[data-sloppy-output]").textContent = response?.text || response?.error || "";
  };
  panel.querySelector("[data-sloppy-prompt]").focus();
}

if (typeof document !== "undefined" && typeof chrome !== "undefined" && chrome.runtime?.onMessage) {
  chrome.runtime.onMessage.addListener((message) => {
    if (message?.type === "sloppy.panel.open") {
      void openPanel();
    }
  });
}
