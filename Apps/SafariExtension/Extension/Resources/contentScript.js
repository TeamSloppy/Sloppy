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
  panel.querySelector("[data-sloppy-selection]").value = context.selection;
  panel.querySelector("[data-sloppy-prompt]").value = "";
  panel.querySelector("[data-sloppy-output]").textContent = "";
  panel.querySelector("[data-sloppy-send]").onclick = async () => {
    const prompt = panel.querySelector("[data-sloppy-prompt]").value;
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
