function extractPageContext(documentLike = globalThis.document, selectionText = "") {
  return {
    page: {
      url: documentLike.location.href,
      title: documentLike.title || null
    },
    selection: String(selectionText || "").trim()
  };
}

function buildDOMSnapshot(documentLike = globalThis.document) {
  const elements = Array.from(documentLike.querySelectorAll("a, button, input, textarea, select, [role='button'], [contenteditable='true']"))
    .slice(0, 80)
    .map((element, index) => {
      const rect = element.getBoundingClientRect?.() || {};
      return {
        index,
        tag: element.tagName?.toLowerCase() || null,
        selector: stableSelector(element),
        text: String(element.innerText || element.value || element.getAttribute?.("aria-label") || element.title || "").trim().slice(0, 180),
        role: element.getAttribute?.("role") || null,
        type: element.getAttribute?.("type") || null,
        disabled: Boolean(element.disabled),
        visible: rect.width > 0 && rect.height > 0
      };
    });
  return {
    title: documentLike.title || null,
    url: documentLike.location?.href || null,
    activeElement: stableSelector(documentLike.activeElement),
    elements
  };
}

function stableSelector(element) {
  if (!element || !element.tagName) {
    return null;
  }
  if (element.id) {
    return `#${cssEscape(element.id)}`;
  }
  const testId = element.getAttribute?.("data-testid") || element.getAttribute?.("data-test-id");
  if (testId) {
    return `[data-testid="${cssEscape(testId)}"]`;
  }
  const name = element.getAttribute?.("name");
  if (name) {
    return `${element.tagName.toLowerCase()}[name="${cssEscape(name)}"]`;
  }
  const aria = element.getAttribute?.("aria-label");
  if (aria) {
    return `${element.tagName.toLowerCase()}[aria-label="${cssEscape(aria)}"]`;
  }
  return element.tagName.toLowerCase();
}

function cssEscape(value) {
  if (globalThis.CSS?.escape) {
    return CSS.escape(String(value));
  }
  return String(value).replace(/["\\]/g, "\\$&");
}

function selectedText() {
  return String(globalThis.getSelection?.() || "").trim();
}

function escapeHTML(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function renderInlineMarkdown(value) {
  return escapeHTML(value)
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noreferrer">$1</a>');
}

function renderMarkdown(markdown = "") {
  const blocks = String(markdown || "").trim().split(/\n{2,}/);
  return blocks
    .map((block) => {
      const lines = block.split(/\n/);
      if (lines.every((line) => /^\s*-\s+/.test(line))) {
        return `<ul>${lines
          .map((line) => `<li>${renderInlineMarkdown(line.replace(/^\s*-\s+/, ""))}</li>`)
          .join("")}</ul>`;
      }
      if (/^```/.test(lines[0])) {
        const code = lines.slice(1, lines.at(-1)?.startsWith("```") ? -1 : undefined).join("\n");
        return `<pre><code>${escapeHTML(code)}</code></pre>`;
      }
      const heading = block.match(/^(#{1,3})\s+(.+)$/);
      if (heading) {
        const level = heading[1].length;
        return `<h${level}>${renderInlineMarkdown(heading[2])}</h${level}>`;
      }
      return `<p>${lines.map(renderInlineMarkdown).join("<br>")}</p>`;
    })
    .join("");
}

function icon(name) {
  const paths = {
    close: '<path d="M18 6 6 18M6 6l12 12"/>',
    mic: '<path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><path d="M12 19v3"/><path d="M8 22h8"/>',
    send: '<path d="m22 2-7 20-4-9-9-4Z"/><path d="M22 2 11 13"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    settings: '<path d="M12 15.5A3.5 3.5 0 1 0 12 8a3.5 3.5 0 0 0 0 7.5Z"/><path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06A1.7 1.7 0 0 0 15 19.4a1.7 1.7 0 0 0-1 .6 1.7 1.7 0 0 0-.35 1.1V21a2 2 0 1 1-4 0v-.09A1.7 1.7 0 0 0 8 19.4a1.7 1.7 0 0 0-1.88.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-.6-1 1.7 1.7 0 0 0-1.1-.35H3a2 2 0 1 1 0-4h.09A1.7 1.7 0 0 0 4.6 8a1.7 1.7 0 0 0-.34-1.88l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-.6 1.7 1.7 0 0 0 .35-1.1V3a2 2 0 1 1 4 0v.09A1.7 1.7 0 0 0 16 4.6a1.7 1.7 0 0 0 1.88-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.7 1.7 0 0 0 19.4 9c.23.38.6.66 1 .77.2.06.42.08.6.08H21a2 2 0 1 1 0 4h-.09A1.7 1.7 0 0 0 19.4 15Z"/>',
    screenshot: '<path d="M4 7V5a2 2 0 0 1 2-2h2"/><path d="M16 3h2a2 2 0 0 1 2 2v2"/><path d="M20 17v2a2 2 0 0 1-2 2h-2"/><path d="M8 21H6a2 2 0 0 1-2-2v-2"/><rect x="7" y="8" width="10" height="8" rx="1"/>',
    tab: '<path d="M4 5h16v14H4z"/><path d="M4 9h16"/>',
    file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z"/><path d="M14 2v6h6"/>',
    tool: '<path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18l3 3 6.3-6.3a4 4 0 0 0 5.4-5.4l-2.8 2.8-2-2Z"/>',
    sessions: '<path d="M8 6h13"/><path d="M8 12h13"/><path d="M8 18h13"/><path d="M3 6h.01"/><path d="M3 12h.01"/><path d="M3 18h.01"/>',
    fact: '<path d="M12 3 4.5 6v5.5c0 4.5 3.1 7.4 7.5 9.5 4.4-2.1 7.5-5 7.5-9.5V6Z"/><path d="m9 12 2 2 4-5"/>',
    define: '<path d="M4 6h8"/><path d="M4 12h8"/><path d="M4 18h5"/><path d="M15 8c1.2-1.2 3.8-1.1 4.7.2.8 1.2.2 2.9-1.4 3.5l-1.1.4c-1.5.5-2.2 1.4-2.2 2.9"/><path d="M15 20h.01"/>',
    summarize: '<path d="M5 7h14"/><path d="M5 12h10"/><path d="M5 17h7"/>',
    translate: '<path d="m5 8 6 6"/><path d="m4 14 6-6 2-3"/><path d="M2 5h12"/><path d="M7 2h1"/><path d="M22 22l-5-10-5 10"/><path d="M14 18h6"/>',
    hide: '<path d="M10.7 5.1A10.9 10.9 0 0 1 12 5c7 0 10 7 10 7a13.2 13.2 0 0 1-3 4.2"/><path d="M6.6 6.6C3.4 8.4 2 12 2 12a13.2 13.2 0 0 0 5.1 5.4A10.8 10.8 0 0 0 12 19a10.9 10.9 0 0 0 3.5-.6"/><path d="m2 2 20 20"/><path d="M9.9 9.9A3 3 0 0 0 14.1 14.1"/>',
    more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    expand: '<path d="M15 3h6v6"/><path d="m10 14 11-11"/><path d="M9 21H3v-6"/><path d="m14 10-11 11"/>',
    search: '<path d="m21 21-4.3-4.3"/><circle cx="11" cy="11" r="8"/>'
  };
  return `<svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${paths[name] || ""}</svg>`;
}

function logoURL() {
  return chrome.runtime.getURL("so_logo.svg");
}

function viewportMetrics(windowLike = globalThis) {
  const viewport = windowLike.visualViewport || {};
  const height = Number(viewport.height || windowLike.innerHeight || 0);
  const top = Number(viewport.offsetTop || 0);
  const layoutHeight = Number(windowLike.innerHeight || height || 0);
  return {
    width: Number(viewport.width || windowLike.innerWidth || 0),
    height,
    top,
    left: Number(viewport.offsetLeft || 0),
    bottomGap: Math.max(0, layoutHeight - top - height)
  };
}

function isMobileViewport(windowLike = globalThis) {
  const width = Number(windowLike.visualViewport?.width || windowLike.innerWidth || 0);
  const touchPoints = Number(windowLike.navigator?.maxTouchPoints || 0);
  return width > 0 && width <= 740 && (touchPoints > 0 || width <= 520);
}

function shouldCollapseContextByDefault(windowLike = globalThis) {
  return isMobileViewport(windowLike);
}

function supportsSpatialPanelEffects(windowLike = globalThis) {
  const width = Number(windowLike.visualViewport?.width || windowLike.innerWidth || 0);
  const touchPoints = Number(windowLike.navigator?.maxTouchPoints || 0);
  const hoverFine = windowLike.matchMedia?.("(hover: hover) and (pointer: fine)")?.matches || false;
  return width >= 740 && touchPoints > 0 && hoverFine;
}

function virtualKeyboardVisible(windowLike = globalThis) {
  const viewport = windowLike.visualViewport;
  if (!viewport || !isMobileViewport(windowLike)) {
    return false;
  }
  const layoutHeight = Number(windowLike.innerHeight || viewport.height || 0);
  const viewportHeight = Number(viewport.height || layoutHeight);
  const viewportTop = Number(viewport.offsetTop || 0);
  const bottomGap = Math.max(0, layoutHeight - viewportTop - viewportHeight);
  return layoutHeight - viewportHeight > 120 || bottomGap > 120;
}

function shouldSubmitPromptOnEnter(event, windowLike = globalThis) {
  if (event.key !== "Enter" || event.shiftKey || event.altKey || event.ctrlKey || event.metaKey || event.isComposing) {
    return false;
  }
  return !virtualKeyboardVisible(windowLike);
}

function searchQueryInfo(urlLike = globalThis.location?.href || "") {
  let url;
  try {
    url = new URL(String(urlLike));
  } catch {
    return null;
  }
  const host = url.hostname.replace(/^www\./, "").toLowerCase();
  const path = url.pathname.toLowerCase();
  const engine = (() => {
    if (/(^|\.)google\./.test(host) && path.startsWith("/search")) {
      return "google";
    }
    if (host === "bing.com" && path.startsWith("/search")) {
      return "bing";
    }
    if (/(^|\.)yandex\./.test(host) && path.startsWith("/search")) {
      return "yandex";
    }
    if ((host === "duckduckgo.com" || host === "html.duckduckgo.com") && (path === "/" || path.startsWith("/html"))) {
      return "duckduckgo";
    }
    return null;
  })();
  if (!engine) {
    return null;
  }
  const query = String(url.searchParams.get(engine === "yandex" ? "text" : "q") || "").trim();
  return query ? { engine, query } : null;
}

function eventKey(event) {
  if (event?.code === "KeyA") {
    return "a";
  }
  if (event?.code === "KeyP") {
    return "p";
  }
  return String(event?.key || "").toLowerCase();
}

function matchesPanelToggleShortcut(event) {
  return eventKey(event) === "a"
    && Boolean(event.altKey)
    && !event.metaKey
    && !event.ctrlKey
    && !event.shiftKey
    && !event.isComposing;
}

function matchesCommandPaletteShortcut(event) {
  return eventKey(event) === "p"
    && Boolean(event.metaKey)
    && Boolean(event.shiftKey)
    && !event.altKey
    && !event.ctrlKey
    && !event.isComposing;
}

function buildChatURL(baseURL, options = {}) {
  const url = new URL(String(baseURL));
  const add = (key, value) => {
    const text = String(value || "").trim();
    if (text) {
      url.searchParams.set(key, text);
    }
  };
  add("prompt", options.prompt);
  add("selection", options.selection);
  add("pageURL", options.page?.url);
  add("pageTitle", options.page?.title);
  add("sessionId", options.sessionId);
  return url.toString();
}

function chatLaunchOptionsFromURL(urlLike = globalThis.location?.href || "") {
  let url;
  try {
    url = new URL(String(urlLike));
  } catch {
    return {};
  }
  return {
    prompt: url.searchParams.get("prompt") || "",
    selection: url.searchParams.get("selection") || "",
    page: {
      url: url.searchParams.get("pageURL") || "about:blank",
      title: url.searchParams.get("pageTitle") || "Safari"
    },
    sessionId: url.searchParams.get("sessionId") || ""
  };
}

function isFullscreenChatPage(locationLike = globalThis.location) {
  return String(locationLike?.pathname || "").endsWith("/chat.html")
    || String(locationLike?.href || "").includes("/chat.html");
}

function selectionBubbleEnabled(settings = state.settings) {
  return settings?.selectionBubbleEnabled !== false;
}

function meshStatusText(mesh = {}) {
  if (!mesh?.relayURL) {
    return "Mesh is not configured.";
  }
  return `Mesh: ${mesh.networkName || mesh.networkId || mesh.relayURL} as ${mesh.identity?.nodeId || "unknown node"}`;
}

function updateViewportCSSVars() {
  if (typeof document === "undefined") {
    return;
  }
  const metrics = viewportMetrics(window);
  const root = document.documentElement;
  root.style.setProperty("--sloppy-viewport-width", `${metrics.width}px`);
  root.style.setProperty("--sloppy-viewport-height", `${metrics.height}px`);
  root.style.setProperty("--sloppy-viewport-top", `${metrics.top}px`);
  root.style.setProperty("--sloppy-viewport-left", `${metrics.left}px`);
  root.style.setProperty("--sloppy-viewport-bottom-gap", `${metrics.bottomGap}px`);
  root.style.setProperty("--sloppy-mobile-bottom-inset", isMobileViewport(window) ? "12px" : "0px");
  root.classList.toggle("sloppy-spatial-panel-effects", supportsSpatialPanelEffects(window));
}

const selectionActions = [
  { id: "fact-check", title: "Fact check", icon: "fact" },
  { id: "define", title: "Define", icon: "define" },
  { id: "summarize", title: "Summarize", icon: "summarize" },
  { id: "translate", title: "Translate", icon: "translate" }
];

function selectionActionPrompt(actionId) {
  const prompts = {
    "fact-check": "Fact check the selected text.",
    define: "Define the selected text.",
    summarize: "Summarize the selected text.",
    translate: "Translate the selected text."
  };
  return prompts[actionId] || "";
}

const state = {
  settings: null,
  agents: [],
  sessions: [],
  slashCommands: [],
  tabs: [],
  messages: [],
  attachments: [],
  context: null,
  contextCollapsed: false,
  streamingMessageId: null,
  streamingRequestId: null,
  streamingAnimation: null,
  selectionMenuText: "",
  selectionMenuRect: null,
  fullscreenLaunch: null,
  voiceConfig: {
    enabled: false,
    effectiveProvider: "local",
    input: { mode: "push_to_talk", language: "auto", previewBeforeSend: true },
    local: { enabled: true, voiceName: "", rate: 1, pitch: 1 }
  },
  voice: { state: "idle", transcript: "", recognition: null, recorder: null, cancelled: false }
};

function ensurePanel() {
  updateViewportCSSVars();
  let frame = document.getElementById("sloppy-safari-extension-panel");
  if (frame) {
    return frame;
  }

  state.contextCollapsed = shouldCollapseContextByDefault(window);
  frame = document.createElement("aside");
  frame.id = "sloppy-safari-extension-panel";
  frame.innerHTML = `
    <div class="sloppy-shell">
      <header class="sloppy-topbar">
        <div class="sloppy-brand">
          <img class="sloppy-mark" src="${logoURL()}" alt="" aria-hidden="true">
          <select data-sloppy-agent aria-label="Agent"></select>
        </div>
        <div class="sloppy-actions">
          <button class="sloppy-icon-button" type="button" data-sloppy-open-fullscreen aria-label="Open full-screen chat">${icon("expand")}</button>
          <button class="sloppy-icon-button" type="button" data-sloppy-sessions aria-label="Sessions">${icon("sessions")}</button>
          <button class="sloppy-icon-button" type="button" data-sloppy-settings aria-label="Settings">${icon("settings")}</button>
          <button class="sloppy-icon-button" type="button" data-sloppy-close aria-label="Close">${icon("close")}</button>
        </div>
      </header>

      <main class="sloppy-thread" data-sloppy-thread></main>

      <section class="sloppy-browser-context" data-sloppy-context></section>
      <div class="sloppy-command-menu" data-sloppy-command-menu hidden></div>

      <form class="sloppy-composer" data-sloppy-composer>
        <div class="sloppy-attachments" data-sloppy-attachments></div>
        <textarea data-sloppy-prompt rows="1" placeholder="Ask about this page"></textarea>
        <div class="sloppy-composer-bar">
          <button class="sloppy-icon-button sloppy-add" type="button" data-sloppy-attach aria-label="Attach file">${icon("plus")}</button>
          <input data-sloppy-file type="file" multiple hidden>
          <div class="sloppy-composer-tools">
            <button class="sloppy-icon-button" type="button" data-sloppy-capture aria-label="Attach screenshot">${icon("screenshot")}</button>
            <button class="sloppy-icon-button" type="button" data-sloppy-voice aria-label="Voice mode">${icon("mic")}</button>
            <button class="sloppy-send" type="submit" aria-label="Send">${icon("send")}</button>
          </div>
        </div>
      </form>
    </div>

    <section class="sloppy-voice" data-sloppy-voice-panel hidden>
      <div class="sloppy-voice-orb" data-sloppy-voice-orb></div>
      <p data-sloppy-voice-status>Say something...</p>
      <div class="sloppy-voice-actions">
        <button class="sloppy-icon-button" type="button" data-sloppy-voice-cancel aria-label="Cancel">${icon("close")}</button>
        <button class="sloppy-icon-button" type="button" data-sloppy-voice-record aria-label="Record">${icon("mic")}</button>
      </div>
    </section>

    <dialog class="sloppy-settings-dialog" data-sloppy-settings-dialog>
      <form method="dialog" class="sloppy-settings-card">
        <header>
          <strong>Connection</strong>
          <button class="sloppy-icon-button" value="cancel" aria-label="Close settings">${icon("close")}</button>
        </header>
        <label>Core URL<input data-sloppy-core-url placeholder="http://127.0.0.1:25101"></label>
        <label>Auth token<input data-sloppy-auth-token type="password" autocomplete="off"></label>
        <label>Default agent<input data-sloppy-default-agent placeholder="sloppy"></label>
        <div class="sloppy-settings-section">
          <strong>Mesh</strong>
          <label class="sloppy-settings-toggle">
            <input data-sloppy-mesh-enabled type="checkbox">
            <span>Use mesh relay</span>
          </label>
          <label>Invite token<textarea data-sloppy-mesh-invite rows="3"></textarea></label>
          <label>Target node<input data-sloppy-mesh-target-node></label>
          <button class="sloppy-settings-save" type="button" data-sloppy-mesh-join>Join mesh</button>
          <p class="sloppy-settings-note" data-sloppy-mesh-status>Mesh is not configured.</p>
        </div>
        <label class="sloppy-settings-toggle">
          <input data-sloppy-floating-button type="checkbox">
          <span>Show floating button</span>
        </label>
        <label class="sloppy-settings-toggle">
          <input data-sloppy-selection-bubble-enabled type="checkbox">
          <span>Show selection bubble</span>
        </label>
        <a class="sloppy-settings-link" href="https://sloppy.team" target="_blank" rel="noreferrer">Download Sloppy</a>
        <button class="sloppy-settings-save" type="button" data-sloppy-save-settings>Save settings</button>
      </form>
    </dialog>

    <dialog class="sloppy-sessions-dialog" data-sloppy-sessions-dialog>
      <form method="dialog" class="sloppy-sessions-card">
        <header>
          <strong>Sessions</strong>
          <button class="sloppy-icon-button" value="cancel" aria-label="Close sessions">${icon("close")}</button>
        </header>
        <div class="sloppy-session-list" data-sloppy-session-list></div>
        <button class="sloppy-settings-save" type="button" data-sloppy-new-session>New session</button>
      </form>
    </dialog>
  `;
  document.documentElement.appendChild(frame);
  wirePanel(frame);
  return frame;
}

function ensureFloatingButton() {
  let button = document.getElementById("sloppy-floating-button");
  if (button) {
    return button;
  }
  button = document.createElement("button");
  button.id = "sloppy-floating-button";
  button.type = "button";
  button.setAttribute("aria-label", "Open Sloppy assistant");
  button.innerHTML = `<img src="${logoURL()}" alt="" aria-hidden="true">`;
  button.addEventListener("click", () => {
    hideSelectionMenu();
    void openPanel();
  });
  document.documentElement.appendChild(button);
  return button;
}

function ensureSearchButton() {
  let button = document.getElementById("sloppy-search-ask-button");
  if (button) {
    return button;
  }
  button = document.createElement("button");
  button.id = "sloppy-search-ask-button";
  button.type = "button";
  button.innerHTML = `<span>${icon("search")}</span><strong>Ask Sloppy</strong>`;
  button.addEventListener("click", () => {
    const info = searchQueryInfo(document.location.href);
    if (info?.query) {
      void openFullscreenChat({
        prompt: `Search the web for: ${info.query}`,
        selection: info.query,
        page: {
          url: document.location.href,
          title: document.title || `${info.engine} search`
        }
      });
    }
  });
  document.documentElement.appendChild(button);
  return button;
}

function renderSearchButton() {
  const existing = document.getElementById("sloppy-search-ask-button");
  const info = searchQueryInfo(document.location.href);
  if (!info?.query || document.getElementById("sloppy-safari-extension-panel")) {
    if (existing) {
      existing.hidden = true;
    }
    return;
  }
  const button = ensureSearchButton();
  button.hidden = false;
}

function renderFloatingButton() {
  const existing = document.getElementById("sloppy-floating-button");
  const shouldShow = Boolean(state.settings?.floatingButtonEnabled)
    && !document.getElementById("sloppy-safari-extension-panel");
  if (!shouldShow) {
    if (existing) {
      existing.hidden = true;
    }
    return;
  }
  const button = ensureFloatingButton();
  button.hidden = false;
}

function ensureCommandPalette() {
  let palette = document.getElementById("sloppy-command-palette");
  if (palette) {
    return palette;
  }
  palette = document.createElement("div");
  palette.id = "sloppy-command-palette";
  palette.hidden = true;
  palette.innerHTML = `
    <form class="sloppy-command-palette-box" data-sloppy-command-palette-form>
      <span>${icon("search")}</span>
      <input data-sloppy-command-palette-input placeholder="Ask Sloppy" autocomplete="off">
    </form>
  `;
  palette.addEventListener("mousedown", (event) => {
    if (event.target === palette) {
      hideCommandPalette();
    }
  });
  palette.querySelector("[data-sloppy-command-palette-form]").addEventListener("submit", (event) => {
    event.preventDefault();
    const input = palette.querySelector("[data-sloppy-command-palette-input]");
    const prompt = input.value.trim();
    hideCommandPalette();
    void openFullscreenChat({ prompt });
  });
  document.documentElement.appendChild(palette);
  return palette;
}

function showCommandPalette() {
  const palette = ensureCommandPalette();
  const input = palette.querySelector("[data-sloppy-command-palette-input]");
  input.value = "";
  palette.hidden = false;
  input.focus();
}

function hideCommandPalette() {
  const palette = document.getElementById("sloppy-command-palette");
  if (palette) {
    palette.hidden = true;
  }
}

function ensureSelectionMenu() {
  let menu = document.getElementById("sloppy-selection-menu");
  if (menu) {
    return menu;
  }

  menu = document.createElement("div");
  menu.id = "sloppy-selection-menu";
  menu.hidden = true;
  menu.innerHTML = `
    <button class="sloppy-selection-bubble" type="button" data-sloppy-selection-bubble aria-label="Ask Sloppy about selection">
      <img src="${logoURL()}" alt="" aria-hidden="true">
    </button>
    <div class="sloppy-selection-popover" data-sloppy-selection-popover hidden>
      <form data-sloppy-selection-form>
        <input data-sloppy-selection-prompt placeholder="Ask anything..." autocomplete="off">
      </form>
      <div class="sloppy-selection-actions">
        ${selectionActions.map((action) => `
          <button type="button" data-sloppy-selection-action="${escapeHTML(action.id)}">
            ${icon(action.icon)}<span>${escapeHTML(action.title)}</span>
          </button>
        `).join("")}
      </div>
      <div class="sloppy-selection-divider"></div>
      <button class="sloppy-selection-hide" type="button" data-sloppy-selection-hide>
        ${icon("hide")}<span>Hide</span>
      </button>
    </div>
  `;
  document.documentElement.appendChild(menu);
  wireSelectionMenu(menu);
  return menu;
}

function wireSelectionMenu(menu) {
  const bubble = menu.querySelector("[data-sloppy-selection-bubble]");
  const openPopover = (event) => {
    event.preventDefault();
    event.stopPropagation();
    showSelectionPopover(menu);
  };
  bubble.addEventListener("pointerdown", openPopover);
  bubble.addEventListener("touchend", openPopover);
  bubble.addEventListener("click", openPopover);
  menu.querySelector("[data-sloppy-selection-form]").addEventListener("submit", (event) => {
    event.preventDefault();
    const input = menu.querySelector("[data-sloppy-selection-prompt]");
    const prompt = input.value.trim();
    if (prompt) {
      input.value = "";
      void sendSelectionPrompt(prompt);
    }
  });
  menu.querySelectorAll("[data-sloppy-selection-action]").forEach((button) => {
    button.addEventListener("click", () => {
      const prompt = selectionActionPrompt(button.dataset.sloppySelectionAction);
      if (prompt) {
        void sendSelectionPrompt(prompt);
      }
    });
  });
  menu.querySelector("[data-sloppy-selection-hide]").addEventListener("click", hideSelectionMenu);
}

function wirePanel(frame) {
  frame.querySelector("[data-sloppy-close]").addEventListener("click", () => {
    frame.remove();
    renderFloatingButton();
    renderSearchButton();
  });
  frame.querySelector("[data-sloppy-open-fullscreen]").addEventListener("click", () => {
    void openFullscreenChat({
      selection: state.context?.selection || selectedText(),
      page: state.context?.page || extractPageContext(document, selectedText()).page,
      sessionId: state.settings?.sessionId || ""
    });
  });
  frame.querySelector("[data-sloppy-settings]").addEventListener("click", () => openSettings(frame));
  frame.querySelector("[data-sloppy-sessions]").addEventListener("click", () => openSessions(frame));
  frame.querySelector("[data-sloppy-new-session]").addEventListener("click", () => selectSession(frame, null));
  frame.querySelector("[data-sloppy-save-settings]").addEventListener("click", () => saveSettings(frame));
  frame.querySelector("[data-sloppy-mesh-join]").addEventListener("click", async () => {
    const token = frame.querySelector("[data-sloppy-mesh-invite]").value;
    const status = frame.querySelector("[data-sloppy-mesh-status]");
    status.textContent = "Joining mesh...";
    try {
      const response = await chrome.runtime.sendMessage({ type: "sloppy.mesh.join", token });
      if (response?.error) {
        status.textContent = response.error;
        return;
      }
      const mesh = response?.mesh || {};
      state.settings = {
        ...(state.settings || {}),
        mesh
      };
      frame.querySelector("[data-sloppy-mesh-enabled]").checked = Boolean(mesh.enabled);
      frame.querySelector("[data-sloppy-mesh-target-node]").value = mesh.targetNodeId || "";
      status.textContent = meshStatusText(mesh);
    } catch (error) {
      status.textContent = error?.message || "Unable to join mesh.";
    }
  });
  frame.querySelector("[data-sloppy-attach]").addEventListener("click", () => frame.querySelector("[data-sloppy-file]").click());
  frame.querySelector("[data-sloppy-file]").addEventListener("change", (event) => addFiles(event.target.files, frame));
  frame.querySelector("[data-sloppy-capture]").addEventListener("click", () => captureScreenshot(frame));
  frame.querySelector("[data-sloppy-voice]")?.addEventListener("click", () => {
    void startVoice();
  });
  frame.querySelector("[data-sloppy-voice-record]")?.addEventListener("click", () => {
    void startVoice();
  });
  frame.querySelector("[data-sloppy-voice-cancel]")?.addEventListener("click", () => cancelVoice());
  frame.querySelector("[data-sloppy-agent]").addEventListener("change", (event) => {
    state.settings.defaultAgentID = event.target.value;
    delete state.settings.sessionId;
    void chrome.runtime.sendMessage({ type: "sloppy.settings.save", settings: state.settings });
    void loadSlashCommands(frame);
    renderContext(frame);
  });
  frame.querySelector("[data-sloppy-composer]").addEventListener("submit", (event) => {
    event.preventDefault();
    void sendPrompt(frame);
  });
  frame.querySelector("[data-sloppy-prompt]").addEventListener("paste", (event) => {
    void handleComposerPaste(event, frame);
  });
  frame.querySelector("[data-sloppy-prompt]").addEventListener("keydown", (event) => {
    if (shouldSubmitPromptOnEnter(event)) {
      event.preventDefault();
      hideCommandMenu(frame);
      void sendPrompt(frame);
      return;
    }
    if (event.key === "Escape") {
      hideCommandMenu(frame);
    }
  });
  frame.querySelector("[data-sloppy-prompt]").addEventListener("input", (event) => {
    event.target.style.height = "auto";
    event.target.style.height = `${Math.min(event.target.scrollHeight, 132)}px`;
    renderCommandMenu(frame);
  });
}

function buildVoicePrompt(transcript) {
  return String(transcript || "").trim();
}

function normalizeVoiceConfig(config = {}) {
  const provider = String(config.configuredProvider || config.provider || "auto").toLowerCase();
  const effectiveProvider = String(config.effectiveProvider || (provider === "openai" ? "unavailable" : "local")).toLowerCase();
  return {
    enabled: Boolean(config.enabled),
    configuredProvider: provider === "openai" || provider === "local" ? provider : "auto",
    effectiveProvider: effectiveProvider === "openai" ? "openai" : "local",
    openAIConfigured: Boolean(config.openAIConfigured),
    localAvailable: config.localAvailable !== false,
    input: {
      mode: config.input?.mode === "auto_submit" ? "auto_submit" : "push_to_talk",
      language: String(config.input?.language || "auto"),
      previewBeforeSend: config.input?.previewBeforeSend !== false
    },
    local: {
      enabled: config.local?.enabled !== false,
      voiceName: String(config.local?.voiceName || ""),
      rate: Number.isFinite(Number(config.local?.rate)) ? Number(config.local.rate) : 1,
      pitch: Number.isFinite(Number(config.local?.pitch)) ? Number(config.local.pitch) : 1
    }
  };
}

function setVoiceState(nextState, message = "") {
  state.voice.state = nextState;
  const panel = document.querySelector("[data-sloppy-voice-panel]");
  const status = document.querySelector("[data-sloppy-voice-status]");
  const orb = document.querySelector("[data-sloppy-voice-orb]");
  if (panel) {
    panel.hidden = nextState === "idle";
  }
  if (status) {
    status.textContent = message || (nextState === "listening" ? "Say something..." : nextState);
  }
  if (orb) {
    orb.dataset.state = nextState;
  }
}

async function loadVoiceConfig() {
  const response = await chrome.runtime.sendMessage({ type: "sloppy.voice.config.get" }).catch((error) => ({ error: error.message }));
  state.voiceConfig = normalizeVoiceConfig(response?.config || {});
  return state.voiceConfig;
}

function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || "").split(",")[1] || "");
    reader.onerror = () => reject(reader.error || new Error("Unable to read audio."));
    reader.readAsDataURL(blob);
  });
}

async function startVoice() {
  try {
    const config = await loadVoiceConfig();
    if (config.effectiveProvider === "openai") {
      await startOpenAIVoice(config);
      return;
    }
    startLocalVoice();
  } catch (error) {
    setVoiceState("error", error.message || "Voice mode failed.");
  }
}

async function startOpenAIVoice(config) {
  if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder !== "function") {
    setVoiceState("error", "Microphone recording is unavailable in this browser.");
    return;
  }
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  const chunks = [];
  const recorder = new MediaRecorder(stream);
  state.voice.recorder = recorder;
  state.voice.cancelled = false;
  state.voice.transcript = "";
  recorder.ondataavailable = (event) => {
    if (event.data?.size > 0) {
      chunks.push(event.data);
    }
  };
  recorder.onstop = () => {
    stream.getTracks().forEach((track) => track.stop());
    state.voice.recorder = null;
    if (state.voice.cancelled) {
      return;
    }
    void (async () => {
      try {
        setVoiceState("transcribing", "Transcribing...");
        const blob = new Blob(chunks, { type: recorder.mimeType || "audio/webm" });
        const audioBase64 = await blobToBase64(blob);
        const response = await chrome.runtime.sendMessage({
          type: "sloppy.voice.transcribe",
          payload: {
            audioBase64,
            mimeType: blob.type || "audio/webm",
            language: config.input.language,
            prompt: ""
          }
        });
        if (response?.error) {
          setVoiceState("error", response.error);
          return;
        }
        state.voice.transcript = response?.result?.text || "";
        submitVoiceTranscript();
      } catch (error) {
        setVoiceState("error", error.message || "Voice transcription failed.");
      }
    })();
  };
  setVoiceState("listening", "Say something...");
  recorder.start();
  window.setTimeout(() => {
    if (recorder.state === "recording") {
      recorder.stop();
    }
  }, 12000);
}

function startLocalVoice() {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) {
    setVoiceState("error", "Speech recognition is unavailable in this browser.");
    return;
  }
  state.voice.recognition?.abort?.();
  const recognition = new SpeechRecognition();
  recognition.lang = state.voiceConfig?.input?.language === "auto" ? "" : state.voiceConfig?.input?.language || "";
  recognition.interimResults = true;
  recognition.continuous = false;
  state.voice.recognition = recognition;
  state.voice.cancelled = false;
  state.voice.transcript = "";
  recognition.onresult = (event) => {
    state.voice.transcript = Array.from(event.results)
      .map((result) => result[0]?.transcript || "")
      .join(" ")
      .trim();
    setVoiceState("listening", state.voice.transcript || "Say something...");
  };
  recognition.onerror = () => setVoiceState("error", "Microphone or speech recognition failed.");
  recognition.onend = () => {
    if (!state.voice.cancelled) {
      submitVoiceTranscript();
    }
  };
  setVoiceState("listening", "Say something...");
  recognition.start();
}

function cancelVoice() {
  state.voice.cancelled = true;
  state.voice.recognition?.abort?.();
  if (state.voice.recorder?.state === "recording") {
    state.voice.recorder.stop();
  }
  state.voice.recognition = null;
  state.voice.recorder = null;
  state.voice.transcript = "";
  setVoiceState("idle");
}

function submitVoiceTranscript() {
  const prompt = buildVoicePrompt(state.voice.transcript);
  if (!prompt) {
    setVoiceState("error", "No speech detected.");
    return;
  }
  const promptInput = document.querySelector("[data-sloppy-prompt]");
  if (promptInput) {
    promptInput.value = prompt;
  }
  setVoiceState("sending", "Sending...");
  document.querySelector("[data-sloppy-composer]")?.requestSubmit?.();
}

function render(frame) {
  renderAgents(frame);
  renderThread(frame);
  renderContext(frame);
  renderAttachments(frame);
}

function renderAgents(frame) {
  const select = frame.querySelector("[data-sloppy-agent]");
  const selected = state.settings?.defaultAgentID || "sloppy";
  const agents = state.agents.length ? state.agents : [{ id: selected, title: selected }];
  select.innerHTML = agents
    .map((agent) => `<option value="${escapeHTML(agent.id)}">${escapeHTML(agent.title || agent.id)}</option>`)
    .join("");
  select.value = selected;
}

function renderThread(frame) {
  const thread = frame.querySelector("[data-sloppy-thread]");
  if (!state.messages.length) {
    thread.innerHTML = `
      <div class="sloppy-empty">
        <img class="sloppy-empty-mark" src="${logoURL()}" alt="" aria-hidden="true">
        <h2>Assistant</h2>
      </div>
    `;
    return;
  }
  thread.innerHTML = state.messages.map(renderMessage).join("");
  thread.scrollTop = thread.scrollHeight;
}

function renderMessage(message) {
  const attachments = message.attachments?.length
    ? `<div class="sloppy-message-attachments">${message.attachments.map(renderAttachmentChip).join("")}</div>`
    : "";
  const tools = message.toolCalls?.length ? `<div class="sloppy-tools">${message.toolCalls.map(renderToolCall).join("")}</div>` : "";
  const thinking = message.role === "assistant" && message.streaming && !message.text
    ? '<div class="sloppy-thinking" aria-label="Waiting for response"><span></span><span></span><span></span></div>'
    : "";
  const body = message.role === "assistant"
    ? `${thinking}<div class="sloppy-markdown">${renderMarkdown(message.text || "")}</div>`
    : `<p>${escapeHTML(message.text || "")}</p>`;
  const streaming = message.streaming ? '<span class="sloppy-streaming">Streaming</span>' : "";
  return `
    <article class="sloppy-message sloppy-message-${message.role}">
      <div class="sloppy-message-meta">${escapeHTML(message.label || message.role)}${streaming}</div>
      <div class="sloppy-message-body">${body}${attachments}${tools}</div>
    </article>
  `;
}

function renderToolCall(tool) {
  return `
    <details class="sloppy-tool" ${tool.open ? "open" : ""}>
      <summary>${icon("tool")}<span>${escapeHTML(tool.name || "Tool call")}</span><small>${escapeHTML(tool.status || "done")}</small></summary>
      <pre>${escapeHTML(JSON.stringify(tool.input || tool.output || tool, null, 2))}</pre>
    </details>
  `;
}

function renderAttachmentChip(attachment) {
  return `<span class="sloppy-attachment-chip">${icon("file")}${escapeHTML(attachment.name)}</span>`;
}

function textFromSessionSegments(segments = []) {
  return segments
    .filter((segment) => !segment.kind || segment.kind === "text")
    .map((segment) => segment?.text || segment?.content || "")
    .filter(Boolean)
    .join("\n");
}

function attachmentsFromSessionSegments(segments = []) {
  return segments
    .map((segment) => segment?.attachment)
    .filter(Boolean)
    .map(normalizeAttachment);
}

function displayTextFromSessionMessage(message = {}) {
  const text = textFromSessionSegments(message.segments || []);
  if (message.role === "user") {
    const marker = "\nUser prompt:\n";
    const markerIndex = text.lastIndexOf(marker);
    if (markerIndex >= 0) {
      return text.slice(markerIndex + marker.length).trim();
    }
  }
  return text;
}

function normalizeSessionMessages(events = []) {
  return events
    .filter((event) => event?.message?.role === "user" || event?.message?.role === "assistant")
    .map((event) => {
      const message = event.message;
      return {
        id: message.id || event.id || globalThis.crypto?.randomUUID?.() || `${Date.now()}`,
        role: message.role,
        label: message.role === "assistant" ? "Assistant" : "You",
        text: displayTextFromSessionMessage(message),
        attachments: attachmentsFromSessionSegments(message.segments || []),
        toolCalls: [],
        streaming: false
      };
    })
    .filter((message) => message.text || message.attachments.length);
}

function renderContext(frame) {
  const context = state.context;
  const selection = context?.selection || "";
  const tabCount = state.tabs.length;
  const selectedSession = state.sessions.find((session) => session.id === state.settings?.sessionId);
  const root = frame.querySelector("[data-sloppy-context]");
  root.classList.toggle("is-collapsed", state.contextCollapsed);
  root.innerHTML = `
    <div class="sloppy-context-row" data-sloppy-context-toggle>
      <span>${icon("tab")}</span>
      <strong>${escapeHTML(context?.page.title || "Current page")}</strong>
      <button class="sloppy-context-icon" type="button" data-sloppy-context-collapse aria-label="${state.contextCollapsed ? "Expand page context" : "Collapse page context"}">
        ${icon(state.contextCollapsed ? "more" : "hide")}
      </button>
    </div>
    <div class="sloppy-context-details">
      <div class="sloppy-context-url">${escapeHTML(context?.page.url || "")}</div>
      <div class="sloppy-context-pills">
        <span>${selection ? `${selection.length} selected chars` : "No selection"}</span>
        <span>${tabCount} accessible tabs</span>
        <span>${escapeHTML(selectedSession?.title || (state.settings?.sessionId ? "Selected session" : "New session"))}</span>
      </div>
      <div class="sloppy-context-actions">
        <button type="button" data-sloppy-summarize-page>${icon("summarize")}<span>Summarize page</span></button>
      </div>
    </div>
  `;
  root.querySelector("[data-sloppy-context-collapse]").addEventListener("click", (event) => {
    event.stopPropagation();
    state.contextCollapsed = !state.contextCollapsed;
    renderContext(frame);
  });
  root.querySelector("[data-sloppy-context-toggle]").addEventListener("dblclick", () => {
    state.contextCollapsed = !state.contextCollapsed;
    renderContext(frame);
  });
  root.querySelector("[data-sloppy-summarize-page]")?.addEventListener("click", () => summarizePage(frame));
}

function renderAttachments(frame) {
  state.attachments = state.attachments.map(normalizeAttachment);
  frame.querySelector("[data-sloppy-attachments]").innerHTML = state.attachments
    .map((attachment) => `
      <button class="sloppy-attachment-chip" type="button" data-sloppy-remove-attachment-id="${escapeHTML(attachment.id)}" aria-label="Remove ${escapeHTML(attachment.name)}">
        ${icon("file")}<span class="sloppy-attachment-name">${escapeHTML(attachment.name)}</span><span class="sloppy-attachment-remove">${icon("close")}</span>
      </button>
    `)
    .join("");
  frame.querySelectorAll("[data-sloppy-remove-attachment-id]").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.preventDefault();
      const id = event.currentTarget?.dataset?.sloppyRemoveAttachmentId || "";
      state.attachments = state.attachments.filter((attachment) => attachment.id !== id);
      renderAttachments(frame);
    });
  });
}

function normalizeAttachment(attachment) {
  if (attachment?.id) {
    return attachment;
  }
  return {
    ...attachment,
    id: `${Date.now()}-${globalThis.crypto?.randomUUID?.() || attachment?.name || "attachment"}`
  };
}

async function summarizePage(frame) {
  const textarea = frame.querySelector("[data-sloppy-prompt]");
  textarea.value = "Summarize this page. Focus on the main points and any actionable details.";
  await sendPrompt(frame);
}

function openSettings(frame) {
  const mesh = state.settings?.mesh || { enabled: false };
  frame.querySelector("[data-sloppy-core-url]").value = state.settings?.coreURLString || "";
  frame.querySelector("[data-sloppy-auth-token]").value = state.settings?.authToken || "";
  frame.querySelector("[data-sloppy-default-agent]").value = state.settings?.defaultAgentID || "sloppy";
  frame.querySelector("[data-sloppy-mesh-enabled]").checked = Boolean(mesh.enabled);
  frame.querySelector("[data-sloppy-mesh-invite]").value = "";
  frame.querySelector("[data-sloppy-mesh-target-node]").value = mesh.targetNodeId || "";
  frame.querySelector("[data-sloppy-mesh-status]").textContent = meshStatusText(mesh);
  frame.querySelector("[data-sloppy-floating-button]").checked = Boolean(state.settings?.floatingButtonEnabled);
  frame.querySelector("[data-sloppy-selection-bubble-enabled]").checked = selectionBubbleEnabled();
  frame.querySelector("[data-sloppy-settings-dialog]").showModal();
}

async function saveSettings(frame) {
  const settings = {
    coreURLString: frame.querySelector("[data-sloppy-core-url]").value,
    authToken: frame.querySelector("[data-sloppy-auth-token]").value,
    defaultAgentID: frame.querySelector("[data-sloppy-default-agent]").value,
    sessionId: state.settings?.sessionId || null,
    mesh: {
      ...(state.settings?.mesh || {}),
      enabled: frame.querySelector("[data-sloppy-mesh-enabled]").checked,
      targetNodeId: frame.querySelector("[data-sloppy-mesh-target-node]").value
    },
    floatingButtonEnabled: frame.querySelector("[data-sloppy-floating-button]").checked,
    selectionBubbleEnabled: frame.querySelector("[data-sloppy-selection-bubble-enabled]").checked
  };
  state.settings = await chrome.runtime.sendMessage({ type: "sloppy.settings.save", settings });
  frame.querySelector("[data-sloppy-settings-dialog]").close();
  await loadAgents(frame);
  render(frame);
  renderFloatingButton();
  if (!selectionBubbleEnabled()) {
    hideSelectionMenu();
  } else {
    scheduleSelectionMenuUpdate();
  }
}

async function openSessions(frame) {
  const list = frame.querySelector("[data-sloppy-session-list]");
  list.innerHTML = '<p class="sloppy-session-empty">Loading sessions...</p>';
  frame.querySelector("[data-sloppy-sessions-dialog]").showModal();

  const response = await chrome.runtime.sendMessage({
    type: "sloppy.sessions.list",
    agentId: state.settings?.defaultAgentID || "sloppy"
  });
  if (response?.error) {
    list.innerHTML = `<p class="sloppy-session-empty">${escapeHTML(response.error)}</p>`;
    return;
  }
  state.sessions = response?.sessions || [];
  if (response?.selectedSessionId) {
    state.settings.sessionId = response.selectedSessionId;
  }
  renderSessionList(frame);
  renderContext(frame);
}

function commandQueryForTextarea(textarea) {
  const value = String(textarea.value || "");
  const caret = textarea.selectionStart ?? value.length;
  const beforeCaret = value.slice(0, caret);
  const match = beforeCaret.match(/(^|\s)\/([a-z0-9_-]*)$/i);
  if (!match) {
    return null;
  }
  const query = match[2] || "";
  return {
    query,
    start: beforeCaret.length - query.length - 1,
    end: caret
  };
}

function commandSuggestions(query, limit = 7) {
  const normalized = String(query || "").toLowerCase();
  return state.slashCommands
    .filter((command) => {
      const name = String(command.name || "").toLowerCase();
      return name && (!normalized || name.includes(normalized));
    })
    .sort((lhs, rhs) => {
      const lhsName = String(lhs.name || "").toLowerCase();
      const rhsName = String(rhs.name || "").toLowerCase();
      if (normalized) {
        const lhsStarts = lhsName.startsWith(normalized);
        const rhsStarts = rhsName.startsWith(normalized);
        if (lhsStarts !== rhsStarts) {
          return lhsStarts ? -1 : 1;
        }
      }
      return lhsName.localeCompare(rhsName);
    })
    .slice(0, limit);
}

function renderCommandMenu(frame) {
  const textarea = frame.querySelector("[data-sloppy-prompt]");
  const menu = frame.querySelector("[data-sloppy-command-menu]");
  const query = commandQueryForTextarea(textarea);
  const suggestions = query ? commandSuggestions(query.query) : [];
  if (!suggestions.length) {
    hideCommandMenu(frame);
    return;
  }
  menu.innerHTML = suggestions.map((command) => `
    <button type="button" data-sloppy-command="${escapeHTML(command.name)}">
      <strong>/${escapeHTML(command.name)}</strong>
      <span>${escapeHTML(command.description || command.argument || "Command")}</span>
    </button>
  `).join("");
  menu.hidden = false;
  menu.querySelectorAll("[data-sloppy-command]").forEach((button) => {
    button.addEventListener("click", () => {
      applyCommandSuggestion(frame, button.dataset.sloppyCommand || "", query);
    });
  });
}

function hideCommandMenu(frame) {
  const menu = frame?.querySelector?.("[data-sloppy-command-menu]");
  if (menu) {
    menu.hidden = true;
    menu.innerHTML = "";
  }
}

function applyCommandSuggestion(frame, commandName, query) {
  const textarea = frame.querySelector("[data-sloppy-prompt]");
  const value = String(textarea.value || "");
  const replacement = `/${commandName} `;
  const start = query?.start ?? value.length;
  const end = query?.end ?? value.length;
  textarea.value = `${value.slice(0, start)}${replacement}${value.slice(end)}`;
  const caret = start + replacement.length;
  textarea.setSelectionRange(caret, caret);
  textarea.focus();
  hideCommandMenu(frame);
}

function slashHelpText() {
  const lines = state.slashCommands.length
    ? state.slashCommands.map((command) => `/${command.name} - ${command.description || command.argument || "Command"}`)
    : ["/help - Show available commands"];
  return `Available commands:\n${lines.join("\n")}\n\nAny other message is forwarded to the agent.`;
}

function renderSessionList(frame) {
  const selectedSessionId = state.settings?.sessionId || "";
  const list = frame.querySelector("[data-sloppy-session-list]");
  if (!state.sessions.length) {
    list.innerHTML = '<p class="sloppy-session-empty">No sessions yet.</p>';
    return;
  }
  list.innerHTML = state.sessions
    .map((session) => `
      <button class="sloppy-session-row ${session.id === selectedSessionId ? "is-selected" : ""}" type="button" data-sloppy-select-session="${escapeHTML(session.id)}">
        <strong>${escapeHTML(session.title)}</strong>
        <span>${escapeHTML(session.subtitle || session.id)}</span>
      </button>
    `)
    .join("");
  list.querySelectorAll("[data-sloppy-select-session]").forEach((button) => {
    button.addEventListener("click", () => selectSession(frame, button.dataset.sloppySelectSession));
  });
}

async function selectSession(frame, sessionId) {
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.sessions.select",
    sessionId: sessionId || "",
    agentId: state.settings?.defaultAgentID || "sloppy"
  });
  if (response?.error) {
    appendMessage({ role: "assistant", label: "Assistant", text: response.error });
    render(frame);
    return;
  }
  state.settings = response?.settings || state.settings;
  state.messages = sessionId ? normalizeSessionMessages(response?.session?.events || []) : [];
  frame.querySelector("[data-sloppy-sessions-dialog]").close();
  render(frame);
}

function extensionRootForNode(node) {
  const textNodeType = globalThis.Node?.TEXT_NODE || 3;
  const element = node?.nodeType === textNodeType ? node.parentElement : node;
  return element?.closest?.("#sloppy-safari-extension-panel, #sloppy-selection-menu") || null;
}

function selectedTextInfo() {
  const selection = globalThis.getSelection?.();
  const text = String(selection || "").trim();
  if (!selection || !text || !selection.rangeCount) {
    return null;
  }
  if (extensionRootForNode(selection.anchorNode) || extensionRootForNode(selection.focusNode)) {
    return null;
  }
  const range = selection.getRangeAt(selection.rangeCount - 1);
  const rects = Array.from(range.getClientRects()).filter((rect) => rect.width > 0 && rect.height > 0);
  const rect = rects.at(-1) || range.getBoundingClientRect();
  if (!rect || rect.width <= 0 || rect.height <= 0) {
    return null;
  }
  return { text, rect };
}

function cachedSelectionInfo(info, stateLike = state) {
  if (info) {
    return info;
  }
  if (!stateLike.selectionMenuText || !stateLike.selectionMenuRect) {
    return null;
  }
  return {
    text: stateLike.selectionMenuText,
    rect: stateLike.selectionMenuRect
  };
}

function positionSelectionMenu(menu, rect, showPopover = false) {
  const padding = 10;
  const bubbleSize = 26;
  const viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
  const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
  const estimatedPopoverHeight = 300;
  const spaceBelow = viewportHeight - rect.bottom - padding;
  const shouldOpenAbove = showPopover && (spaceBelow < estimatedPopoverHeight || rect.top > viewportHeight / 2);
  const preferredTop = shouldOpenAbove ? rect.top - bubbleSize - 8 : rect.bottom + 8;
  const top = Math.min(Math.max(preferredTop, padding), Math.max(padding, viewportHeight - bubbleSize - padding));
  const left = Math.min(Math.max(rect.right - bubbleSize / 2, padding), Math.max(padding, viewportWidth - bubbleSize - padding));
  const popoverWidth = Math.min(310, Math.max(0, viewportWidth - 24));
  const popoverOffset = Math.min(0, viewportWidth - padding - left - popoverWidth);
  menu.style.left = `${left}px`;
  menu.style.top = `${top}px`;
  menu.style.setProperty("--sloppy-selection-popover-x", `${popoverOffset}px`);
  menu.classList.toggle("is-popover-open", showPopover);
  menu.classList.toggle("is-popover-above", shouldOpenAbove);
}

function selectionMenuHasFocus() {
  const menu = document.getElementById("sloppy-selection-menu");
  return Boolean(menu && !menu.hidden && document.activeElement && menu.contains(document.activeElement));
}

function selectionPopoverIsOpen() {
  const menu = document.getElementById("sloppy-selection-menu");
  const popover = menu?.querySelector("[data-sloppy-selection-popover]");
  return Boolean(menu && !menu.hidden && popover && !popover.hidden);
}

function updateSelectionMenu() {
  if (!selectionBubbleEnabled()) {
    hideSelectionMenu();
    return;
  }
  if (selectionMenuHasFocus() || selectionPopoverIsOpen()) {
    return;
  }
  const info = selectedTextInfo();
  if (!info) {
    hideSelectionMenu();
    return;
  }
  const menu = ensureSelectionMenu();
  state.selectionMenuText = info.text;
  state.selectionMenuRect = info.rect;
  menu.hidden = false;
  menu.querySelector("[data-sloppy-selection-popover]").hidden = true;
  positionSelectionMenu(menu, info.rect, false);
}

function showSelectionPopover(menu) {
  const info = cachedSelectionInfo(selectedTextInfo());
  if (!info) {
    hideSelectionMenu();
    return;
  }
  state.selectionMenuText = info.text;
  state.selectionMenuRect = info.rect;
  const popover = menu.querySelector("[data-sloppy-selection-popover]");
  popover.hidden = false;
  positionSelectionMenu(menu, info.rect, true);
  menu.querySelector("[data-sloppy-selection-prompt]").focus();
}

function hideSelectionMenu() {
  const menu = document.getElementById("sloppy-selection-menu");
  if (!menu) {
    return;
  }
  menu.hidden = true;
  state.selectionMenuRect = null;
  menu.classList.remove("is-popover-open");
  menu.classList.remove("is-popover-above");
  menu.querySelector("[data-sloppy-selection-popover]").hidden = true;
}

function contextWithSelection(context, selection) {
  if (!context?.page) {
    return context;
  }
  return {
    ...context,
    selection: String(selection || "")
  };
}

function syncPanelSelectionContext(frame = document.getElementById("sloppy-safari-extension-panel")) {
  if (!frame || !state.context?.page) {
    return false;
  }
  const info = selectedTextInfo();
  const nextSelection = info?.text || "";
  if (state.context.selection === nextSelection) {
    return false;
  }
  state.context = contextWithSelection(state.context, nextSelection);
  renderContext(frame);
  return true;
}

function scheduleSelectionMenuUpdate() {
  window.clearTimeout(scheduleSelectionMenuUpdate.timer);
  scheduleSelectionMenuUpdate.timer = window.setTimeout(() => {
    updateSelectionMenu();
    syncPanelSelectionContext();
  }, 80);
}

async function openPanelWithSelection(selectionText) {
  state.context = extractPageContext(document, selectionText);
  const panel = ensurePanel();
  state.settings = state.settings || await chrome.runtime.sendMessage({ type: "sloppy.settings.get" });
  await Promise.all([loadAgents(panel), refreshTabs(panel), loadSlashCommands(panel)]);
  render(panel);
  renderFloatingButton();
  renderSearchButton();
  return panel;
}

async function sendSelectionPrompt(prompt) {
  const selection = state.selectionMenuText || selectedText();
  if (!selection.trim()) {
    return;
  }
  const panel = await openPanelWithSelection(selection);
  hideSelectionMenu();
  const textarea = panel.querySelector("[data-sloppy-prompt]");
  textarea.value = prompt;
  await sendPrompt(panel);
}

async function addFiles(fileList, frame) {
  const files = Array.from(fileList || []);
  const attachments = await Promise.all(files.map(fileToAttachment));
  state.attachments.push(...attachments);
  frame.querySelector("[data-sloppy-file]").value = "";
  renderAttachments(frame);
}

function readFileAsDataURL(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.addEventListener("load", () => resolve(String(reader.result || "")));
    reader.addEventListener("error", () => reject(reader.error || new Error("Unable to read file.")));
    reader.readAsDataURL(file);
  });
}

async function fileToAttachment(file) {
  const dataURL = await readFileAsDataURL(file);
  const fallbackName = file.type?.startsWith("image/") ? "clipboard-image.png" : "clipboard-file";
  return {
    id: `${Date.now()}-${globalThis.crypto?.randomUUID?.() || file.name || "attachment"}`,
    name: file.name || fallbackName,
    kind: file.type?.startsWith("image/") ? "image" : "file",
    mimeType: file.type || "application/octet-stream",
    sizeBytes: Number(file.size || 0),
    dataURL,
    contentBase64: dataURL.includes(",") ? dataURL.slice(dataURL.indexOf(",") + 1) : null
  };
}

async function handleComposerPaste(event, frame) {
  const files = Array.from(event.clipboardData?.items || [])
    .map((item) => item.kind === "file" ? item.getAsFile() : null)
    .filter(Boolean);
  if (!files.length) {
    return;
  }
  if (!event.clipboardData?.getData("text/plain")) {
    event.preventDefault();
  }
  await addFiles(files, frame);
}

async function refreshTabs(frame) {
  const response = await chrome.runtime.sendMessage({ type: "sloppy.tabs.list" });
  state.tabs = response?.tabs || [];
  renderContext(frame);
}

async function loadAgents(frame) {
  const response = await chrome.runtime.sendMessage({ type: "sloppy.agents.list" });
  state.agents = response?.agents || [];
  if (response?.selectedAgentId) {
    state.settings.defaultAgentID = response.selectedAgentId;
  }
  renderAgents(frame);
}

async function loadSlashCommands(frame) {
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.commands.list",
    agentId: state.settings?.defaultAgentID || "sloppy"
  });
  state.slashCommands = response?.commands?.length
    ? response.commands
    : [
        { name: "help", description: "Show available commands" },
        { name: "status", description: "Show current Safari chat status" }
      ];
  renderCommandMenu(frame);
}

async function captureScreenshot(frame) {
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.browserTool.run",
    action: { name: "browser.capture_visible_tab", input: {} }
  });
  if (response?.attachment) {
    state.attachments.push(normalizeAttachment(response.attachment));
    renderAttachments(frame);
    return;
  }
  if (response?.error) {
    appendMessage({ role: "assistant", label: "Assistant", text: response.error });
    render(frame);
  }
}

function appendMessage(message) {
  state.messages.push({
    id: message.id || globalThis.crypto?.randomUUID?.() || `${Date.now()}`,
    role: message.role,
    label: message.label,
    text: message.text || "",
    attachments: message.attachments || [],
    toolCalls: message.toolCalls || [],
    streaming: Boolean(message.streaming)
  });
}

async function updateStreamingMessage(event, frame) {
  const message = state.messages.find((candidate) => candidate.id === state.streamingMessageId);
  if (!message) {
    return;
  }
  const assistantText = assistantTextFromStreamEvent(event);
  if (assistantText) {
    message.text = assistantText;
  }
  if (event.type === "delta") {
    message.text += event.text || event.delta || "";
  }
  if (event.type === "assistant_message") {
    message.text = event.text || message.text;
  }
  if (event.type === "tool_call") {
    message.toolCalls.push(event.tool || event);
  }
  if (event.type === "session_error") {
    stopStreamingAnimation();
    message.text = event.message || message.text || "Session stream failed.";
  }
  if (event.type === "complete") {
    const finalText = agentResponseText(event.body, message.text);
    await animateAssistantText(message, finalText, frame);
    applyAgentResponse(message, { ...event.body, text: finalText });
    await rememberSession(event.body, frame);
    await performAgentBrowserActions(event.body, message);
    message.streaming = false;
    if (state.voice.state === "answering") {
      setVoiceState("idle");
    }
  }
  if (event.type === "done") {
    if (event.body) {
      const finalText = agentResponseText(event.body, message.text);
      await animateAssistantText(message, finalText, frame);
    } else if (state.streamingAnimation) {
      return;
    }
    message.streaming = false;
    if (state.voice.state === "answering") {
      setVoiceState("idle");
    }
  }
  if (frame) {
    render(frame);
  }
}

function textFromMessageSegments(message = {}) {
  return (message.segments || [])
    .map((segment) => segment?.text || segment?.content || "")
    .filter(Boolean)
    .join("\n");
}

function latestAssistantTextFromEvents(events = []) {
  const assistant = [...events].reverse().find((event) => event?.message?.role === "assistant");
  return textFromMessageSegments(assistant?.message || {});
}

function assistantTextFromStreamEvent(event = {}) {
  const record = event.event || event.sessionEvent || event;
  const message = record.message || event.message;
  if (message?.role !== "assistant") {
    return "";
  }
  return textFromMessageSegments(message);
}

function applyAgentResponse(message, response = {}) {
  message.text = agentResponseText(response, message.text);
  message.attachments = response.attachments || message.attachments || [];
  message.toolCalls = response.toolCalls || response.tool_calls || message.toolCalls || [];
}

function agentResponseText(response = {}, fallback = "") {
  return response.text
    || response.message
    || response.output
    || latestAssistantTextFromEvents(response.appendedEvents || response.events || [])
    || fallback;
}

function animatedTextSteps(currentText = "", targetText = "") {
  const current = String(currentText || "");
  const target = String(targetText || "");
  if (!target || current === target) {
    return [];
  }
  const prefix = target.startsWith(current) ? current : "";
  const remaining = target.slice(prefix.length);
  const chunkSize = Math.max(2, Math.min(10, Math.ceil(remaining.length / 48)));
  const steps = [];
  for (let index = chunkSize; index < remaining.length; index += chunkSize) {
    steps.push(prefix + remaining.slice(0, index));
  }
  steps.push(target);
  return steps;
}

function stopStreamingAnimation() {
  if (state.streamingAnimation) {
    window.clearTimeout(state.streamingAnimation);
    state.streamingAnimation = null;
  }
}

function animateAssistantText(message, targetText, frame) {
  const steps = animatedTextSteps(message.text, targetText);
  if (!steps.length) {
    message.text = targetText || message.text;
    return Promise.resolve();
  }
  stopStreamingAnimation();
  return new Promise((resolve) => {
    const tick = () => {
      const nextText = steps.shift();
      if (typeof nextText === "string") {
        message.text = nextText;
        if (frame) {
          render(frame);
        }
      }
      if (!steps.length) {
        state.streamingAnimation = null;
        resolve();
        return;
      }
      state.streamingAnimation = window.setTimeout(tick, 18);
    };
    tick();
  });
}

async function rememberSession(response, frame) {
  if (!response?.sessionId || state.settings?.sessionId === response.sessionId) {
    return;
  }
  state.settings.sessionId = response.sessionId;
  await chrome.runtime.sendMessage({ type: "sloppy.settings.save", settings: state.settings });
  if (frame) {
    renderContext(frame);
  }
}

function collectBrowserToolActions(response = {}) {
  const direct = response.openTabs || response.open_tabs || [];
  const actions = response.actions || [];
  const toolCalls = response.toolCalls || response.tool_calls || [];
  return [
    ...direct.map((url) => ({ name: "browser.open_tab", input: { url } })),
    ...actions,
    ...toolCalls
  ]
    .map((item) => {
      const name = item?.type === "open_tab" ? "browser.open_tab" : item?.name || item?.tool || item?.type;
      if (!name?.startsWith("browser.")) {
        return null;
      }
      return {
        name,
        input: {
          ...(item.input || {}),
          ...(item.arguments || {}),
          ...(item.url ? { url: item.url } : {})
        }
      };
    })
    .filter(Boolean);
}

async function runPageBrowserTool(action) {
  const input = action.input || {};
  if (action.name === "browser.dom_snapshot") {
    return { snapshot: buildDOMSnapshot(document) };
  }
  if (action.name === "browser.click_selector") {
    const element = document.querySelector(input.selector);
    if (!element) {
      throw new Error(`Element not found: ${input.selector}`);
    }
    element.scrollIntoView?.({ block: "center", inline: "center" });
    element.click();
    return { clicked: input.selector };
  }
  if (action.name === "browser.type_text") {
    const element = document.querySelector(input.selector);
    if (!element) {
      throw new Error(`Element not found: ${input.selector}`);
    }
    element.focus?.();
    if ("value" in element) {
      element.value = input.text || "";
      element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: input.text || "" }));
      element.dispatchEvent(new Event("change", { bubbles: true }));
    } else {
      element.textContent = input.text || "";
      element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: input.text || "" }));
    }
    return { typed: input.selector, length: String(input.text || "").length };
  }
  if (action.name === "browser.scroll") {
    window.scrollBy({
      left: Number(input.x || 0),
      top: Number(input.y || input.deltaY || 0),
      behavior: input.behavior === "smooth" ? "smooth" : "auto"
    });
    return { scrolled: { x: Number(input.x || 0), y: Number(input.y || input.deltaY || 0) } };
  }
  return null;
}

async function runBrowserToolAction(action) {
  const pageResult = await runPageBrowserTool(action);
  if (pageResult) {
    return pageResult;
  }
  const response = await chrome.runtime.sendMessage({ type: "sloppy.browserTool.run", action });
  if (response?.error) {
    throw new Error(response.error);
  }
  return response;
}

async function performAgentBrowserActions(response, message) {
  const actions = collectBrowserToolActions(response);
  for (const action of actions) {
    try {
      const output = await runBrowserToolAction(action);
      message.toolCalls.push({
        name: action.name,
        status: "done",
        input: action.input,
        output
      });
      if (output?.attachment) {
        message.attachments.push(output.attachment);
      }
    } catch (error) {
      message.toolCalls.push({
        name: action.name,
        status: "failed",
        input: action.input,
        output: error.message || "Browser tool failed."
      });
    }
  }
}

async function sendPrompt(frame) {
  const textarea = frame.querySelector("[data-sloppy-prompt]");
  const prompt = textarea.value.trim();
  if (!prompt) {
    return;
  }
  hideCommandMenu(frame);
  if (prompt.toLowerCase() === "/help") {
    appendMessage({ role: "user", label: "You", text: prompt });
    appendMessage({ role: "assistant", label: "Assistant", text: slashHelpText() });
    textarea.value = "";
    textarea.style.height = "auto";
    render(frame);
    return;
  }
  if (prompt.toLowerCase() === "/status") {
    appendMessage({ role: "user", label: "You", text: prompt });
    appendMessage({
      role: "assistant",
      label: "Assistant",
      text: `Agent: ${state.settings?.defaultAgentID || "sloppy"}\nSession: ${state.settings?.sessionId || "none"}\nState: idle`
    });
    textarea.value = "";
    textarea.style.height = "auto";
    render(frame);
    return;
  }
  const userAttachments = [...state.attachments];
  appendMessage({ role: "user", label: "You", text: prompt, attachments: userAttachments });
  textarea.value = "";
  textarea.style.height = "auto";
  state.attachments = [];

  const assistantId = globalThis.crypto?.randomUUID?.() || `${Date.now()}-assistant`;
  state.streamingMessageId = assistantId;
  appendMessage({ id: assistantId, role: "assistant", label: "Assistant", text: "", streaming: true });
  if (state.voice.state === "sending") {
    setVoiceState("answering", "Assistant is answering...");
  }
  render(frame);

  const requestId = globalThis.crypto?.randomUUID?.() || `${Date.now()}-request`;
  state.streamingRequestId = requestId;
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.browserContext.stream",
    requestId,
    page: state.context.page,
    selection: state.context.selection,
    prompt,
    tabs: state.tabs,
    pageSnapshot: buildDOMSnapshot(document),
    attachments: userAttachments
  });
  const message = state.messages.find((candidate) => candidate.id === assistantId);
  if (response?.error) {
    stopStreamingAnimation();
    message.text = response.error;
    message.streaming = false;
  } else {
    const finalText = agentResponseText(response, message.text);
    await animateAssistantText(message, finalText, frame);
    applyAgentResponse(message, { ...response, text: finalText });
    await rememberSession(response, frame);
    await performAgentBrowserActions(response, message);
    message.streaming = false;
  }
  state.streamingRequestId = null;
  if (state.voice.state === "sending" || state.voice.state === "answering") {
    setVoiceState("idle");
  }
  render(frame);
}

async function openPanel() {
  const panel = await openPanelWithSelection(selectedText());
  panel.querySelector("[data-sloppy-prompt]").focus();
}

async function togglePanel() {
  const panel = document.getElementById("sloppy-safari-extension-panel");
  if (panel) {
    panel.remove();
    renderFloatingButton();
    renderSearchButton();
    return;
  }
  await openPanel();
}

async function openFullscreenChat(options = {}) {
  const context = extractPageContext(document, options.selection || selectedText());
  const page = options.page || context.page;
  const url = buildChatURL(chrome.runtime.getURL("chat.html"), {
    prompt: options.prompt,
    selection: options.selection || context.selection,
    page,
    sessionId: options.sessionId || state.settings?.sessionId || ""
  });
  await chrome.runtime.sendMessage({ type: "sloppy.tabs.open", url });
}

async function initializeFullscreenChat() {
  document.documentElement.classList.add("sloppy-fullscreen-chat-page");
  const launch = chatLaunchOptionsFromURL(document.location.href);
  state.fullscreenLaunch = launch;
  state.context = {
    page: launch.page,
    selection: launch.selection || ""
  };
  state.settings = state.settings || await chrome.runtime.sendMessage({ type: "sloppy.settings.get" });
  if (launch.sessionId) {
    state.settings.sessionId = launch.sessionId;
  }
  const panel = ensurePanel();
  await Promise.all([loadAgents(panel), refreshTabs(panel), loadSlashCommands(panel)]);
  render(panel);
  const prompt = String(launch.prompt || "").trim();
  if (prompt) {
    const textarea = panel.querySelector("[data-sloppy-prompt]");
    textarea.value = prompt;
    await sendPrompt(panel);
  } else {
    panel.querySelector("[data-sloppy-prompt]").focus();
  }
}

if (typeof document !== "undefined" && typeof chrome !== "undefined" && chrome.runtime?.onMessage) {
  updateViewportCSSVars();
  const refreshViewportDependentUI = () => {
    updateViewportCSSVars();
    renderFloatingButton();
    renderSearchButton();
  };
  window.visualViewport?.addEventListener("resize", refreshViewportDependentUI);
  window.visualViewport?.addEventListener("scroll", refreshViewportDependentUI);
  window.addEventListener("resize", refreshViewportDependentUI);
  document.addEventListener("selectionchange", scheduleSelectionMenuUpdate);
  document.addEventListener("mousedown", (event) => {
    if (!extensionRootForNode(event.target)) {
      const menu = document.getElementById("sloppy-selection-menu");
      if (menu && !menu.hidden && !menu.contains(event.target)) {
        menu.querySelector("[data-sloppy-selection-popover]").hidden = true;
        menu.classList.remove("is-popover-open");
      }
    }
  }, true);
  document.addEventListener("keydown", (event) => {
    if (matchesPanelToggleShortcut(event)) {
      event.preventDefault();
      void togglePanel();
      return;
    }
    if (matchesCommandPaletteShortcut(event)) {
      event.preventDefault();
      showCommandPalette();
      return;
    }
    if (event.key === "Escape") {
      hideCommandPalette();
      hideSelectionMenu();
    }
  });
  window.addEventListener("scroll", hideSelectionMenu, true);

  if (isFullscreenChatPage(document.location)) {
    void initializeFullscreenChat();
  } else {
    void chrome.runtime.sendMessage({ type: "sloppy.settings.get" }).then((settings) => {
    if (!settings?.error) {
      state.settings = settings;
      renderFloatingButton();
      renderSearchButton();
      if (!selectionBubbleEnabled()) {
        hideSelectionMenu();
      }
    }
    }).catch(() => {});
  }

  chrome.runtime.onMessage.addListener((message) => {
    if (message?.type === "sloppy.panel.open") {
      void openPanel();
      return;
    }
    if (message?.type === "sloppy.browserContext.streamEvent" && message.requestId === state.streamingRequestId) {
      const panel = document.getElementById("sloppy-safari-extension-panel");
      void updateStreamingMessage(message.event || {}, panel);
    }
  });
}
