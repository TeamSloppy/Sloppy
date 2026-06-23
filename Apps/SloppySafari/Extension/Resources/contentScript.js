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
    text: String(documentLike.body?.innerText || "").replace(/\s+/g, " ").trim().slice(0, 24000),
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

function t(key, params = {}) {
  return globalThis.SloppyI18n?.t(key, params) || key;
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
  const symbols = {
    close: "xmark",
    mic: "waveform",
    "arrow-up": "arrow.up",
    plus: "plus",
    settings: "gear",
    screenshot: "camera.on.rectangle",
    tab: "square.and.arrow.down",
    file: "square.and.arrow.down",
    tool: "brain",
    sessions: "list.bullet",
    fact: "checkmark.shield",
    define: "questionmark.text.page",
    summarize: "text.aligncenter",
    translate: "translate",
    hide: "eye.slash",
    more: "ellipsis",
    expand: "arrow.down.left.and.arrow.up.right",
    search: "magnifyingglass",
    model: "brain"
  };
  const symbol = symbols[name] || "ellipsis";
  const path = `${symbol}.svg`;
  const url = typeof chrome !== "undefined" && chrome.runtime?.getURL ? chrome.runtime.getURL(path) : path;
  return `<span class="sloppy-symbol" aria-hidden="true" data-sf-symbol="${escapeHTML(symbol)}" style="--sloppy-symbol-url: url('${escapeHTML(url)}')"></span>`;
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
    "fact-check": t("factCheckSelection"),
    define: t("defineSelection"),
    summarize: t("summarizeSelection"),
    translate: t("translateSelection")
  };
  return prompts[actionId] || "";
}

const state = {
  settings: null,
  agents: [],
  models: [],
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

function ensureSettings() {
  state.settings = state.settings || {};
  return state.settings;
}

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
          <select data-sloppy-agent aria-label="${escapeHTML(t("agent"))}"></select>
        </div>
        <div class="sloppy-actions">
          <button class="sloppy-icon-button" type="button" data-sloppy-open-fullscreen aria-label="${escapeHTML(t("openFullscreenChat"))}">${icon("expand")}</button>
          <button class="sloppy-icon-button" type="button" data-sloppy-sessions aria-label="${escapeHTML(t("sessions"))}">${icon("sessions")}</button>
          <button class="sloppy-icon-button" type="button" data-sloppy-settings aria-label="${escapeHTML(t("settings"))}">${icon("settings")}</button>
          <button class="sloppy-icon-button" type="button" data-sloppy-close aria-label="${escapeHTML(t("close"))}">${icon("close")}</button>
        </div>
      </header>

      <main class="sloppy-thread" data-sloppy-thread></main>

      <section class="sloppy-browser-context" data-sloppy-context></section>
      <div class="sloppy-command-menu" data-sloppy-command-menu hidden></div>

      <form class="sloppy-composer" data-sloppy-composer>
        <div class="sloppy-attachments" data-sloppy-attachments></div>
        <textarea data-sloppy-prompt rows="1" placeholder="${escapeHTML(t("askAboutPage"))}"></textarea>
        <div class="sloppy-composer-bar">
          <button class="sloppy-icon-button sloppy-add" type="button" data-sloppy-attach aria-label="${escapeHTML(t("attachFile"))}">${icon("plus")}</button>
          <input data-sloppy-file type="file" multiple hidden>
          <div class="sloppy-composer-tools">
            <label class="sloppy-model-picker" aria-label="${escapeHTML(t("model"))}">
              <span aria-hidden="true">${icon("model")}</span>
              <select data-sloppy-model aria-label="${escapeHTML(t("model"))}"></select>
            </label>
            <button class="sloppy-icon-button" type="button" data-sloppy-capture aria-label="${escapeHTML(t("attachScreenshot"))}">${icon("screenshot")}</button>
            <button class="sloppy-primary-action" type="button" data-sloppy-primary-action aria-label="${escapeHTML(t("voiceMode"))}">${icon("mic")}</button>
          </div>
        </div>
      </form>
    </div>

    <section class="sloppy-voice" data-sloppy-voice-panel hidden>
      <label class="sloppy-voice-settings" data-sloppy-voice-settings aria-label="${escapeHTML(t("voiceSettings"))}">
        <span aria-hidden="true">${icon("settings")}</span>
        <select class="sloppy-voice-language" data-sloppy-voice-language aria-label="${escapeHTML(t("voiceLanguage"))}">
          <option value="auto">${escapeHTML(t("voiceLanguageAuto"))}</option>
          <option value="en-US">${escapeHTML(t("voiceLanguageEnglish"))}</option>
          <option value="ru-RU">${escapeHTML(t("voiceLanguageRussian"))}</option>
          <option value="zh-CN">${escapeHTML(t("voiceLanguageChinese"))}</option>
        </select>
      </label>
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
          <button class="sloppy-icon-button" value="cancel" aria-label="${escapeHTML(t("closeSettings"))}">${icon("close")}</button>
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
        <a class="sloppy-settings-link" href="https://sloppy.team" target="_blank" rel="noreferrer">${escapeHTML(t("downloadSloppy"))}</a>
        <button class="sloppy-settings-save" type="button" data-sloppy-save-settings>Save settings</button>
      </form>
    </dialog>

    <dialog class="sloppy-sessions-dialog" data-sloppy-sessions-dialog>
      <form method="dialog" class="sloppy-sessions-card">
        <header>
          <strong>${escapeHTML(t("sessions"))}</strong>
          <button class="sloppy-icon-button" value="cancel" aria-label="${escapeHTML(t("closeSessions"))}">${icon("close")}</button>
        </header>
        <div class="sloppy-session-list" data-sloppy-session-list></div>
        <button class="sloppy-settings-save" type="button" data-sloppy-new-session>${escapeHTML(t("newSession"))}</button>
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
  button.setAttribute("aria-label", t("openSloppyAssistant"));
  button.innerHTML = `<img src="${logoURL()}" alt="" aria-hidden="true">`;
  button.addEventListener("pointerdown", snapshotSelectionForFloatingButton);
  button.addEventListener("touchstart", snapshotSelectionForFloatingButton, { passive: true });
  button.addEventListener("mousedown", snapshotSelectionForFloatingButton);
  button.addEventListener("click", () => {
    const info = cachedSelectionInfo(selectedTextInfo());
    void openPanelWithSelection(info?.text || "").then(() => hideSelectionMenu());
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
  button.innerHTML = `<span>${icon("search")}</span><strong>${escapeHTML(t("askSloppy"))}</strong>`;
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
  const floating = document.getElementById("sloppy-floating-button");
  if (floating) {
    floating.hidden = true;
  }
}

function searchAskButtonVisible() {
  const searchButton = document.getElementById("sloppy-search-ask-button");
  return Boolean(searchButton && !searchButton.hidden);
}

function renderFloatingButton() {
  const existing = document.getElementById("sloppy-floating-button");
  const shouldShow = Boolean(state.settings?.floatingButtonEnabled)
    && !document.getElementById("sloppy-safari-extension-panel")
    && !searchAskButtonVisible();
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
    <div class="sloppy-command-palette-shell" data-sloppy-command-palette-shell>
      <form class="sloppy-command-palette-box" data-sloppy-command-palette-form>
        <span>${icon("search")}</span>
        <input data-sloppy-command-palette-input placeholder="${escapeHTML(t("askSloppy"))}" autocomplete="off">
      </form>
      <div class="sloppy-command-palette-sessions" data-sloppy-command-palette-sessions hidden></div>
    </div>
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
  palette.querySelector("[data-sloppy-command-palette-sessions]").addEventListener("click", (event) => {
    const button = event.target?.closest?.("[data-sloppy-command-palette-session]");
    if (!button) {
      return;
    }
    const sessionId = button.dataset.sloppyCommandPaletteSession || "";
    if (!sessionId) {
      return;
    }
    hideCommandPalette();
    void openFullscreenChat({ sessionId });
  });
  document.documentElement.appendChild(palette);
  return palette;
}

async function loadCommandPaletteSessions(palette) {
  const container = palette?.querySelector?.("[data-sloppy-command-palette-sessions]");
  if (!container) {
    return;
  }
  container.hidden = false;
  container.innerHTML = `<p class="sloppy-command-palette-empty">${escapeHTML(t("loadingRecentSessions"))}</p>`;
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.sessions.list",
    agentId: state.settings?.defaultAgentID || "sloppy"
  }).catch((error) => ({ sessions: [], error: error.message || t("sessionsUnavailable") }));
  const sessions = (response?.sessions || []).slice(0, 12);
  if (!sessions.length) {
    container.innerHTML = `<p class="sloppy-command-palette-empty">${escapeHTML(response?.error || t("noRecentSessions"))}</p>`;
    return;
  }
  container.innerHTML = sessions.map((session) => `
    <button type="button" data-sloppy-command-palette-session="${escapeHTML(session.id)}">
      <strong>${escapeHTML(session.title || session.id)}</strong>
      <span>${escapeHTML(session.subtitle || session.id)}</span>
    </button>
  `).join("");
}

function showCommandPalette() {
  const palette = ensureCommandPalette();
  const input = palette.querySelector("[data-sloppy-command-palette-input]");
  input.value = "";
  palette.hidden = false;
  input.focus();
  void loadCommandPaletteSessions(palette);
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
    <button class="sloppy-selection-bubble" type="button" data-sloppy-selection-bubble aria-label="${escapeHTML(t("askSelection"))}">
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
  frame.querySelector("[data-sloppy-primary-action]")?.addEventListener("click", () => {
    if (composerHasPayload(frame)) {
      void sendPrompt(frame);
      return;
    }
    void startVoice();
  });
  frame.querySelector("[data-sloppy-voice-record]")?.addEventListener("click", () => {
    void startVoice();
  });
  frame.querySelector("[data-sloppy-voice-cancel]")?.addEventListener("click", () => cancelVoice());
  frame.querySelector("[data-sloppy-voice-language]")?.addEventListener("change", (event) => {
    state.settings = {
      ...(state.settings || {}),
      voiceLanguage: normalizeVoiceLanguage(event.target.value)
    };
    state.voiceConfig = {
      ...state.voiceConfig,
      input: {
        ...(state.voiceConfig?.input || {}),
        language: state.settings.voiceLanguage
      }
    };
    void chrome.runtime.sendMessage({ type: "sloppy.settings.save", settings: state.settings });
  });
  frame.querySelector("[data-sloppy-agent]").addEventListener("change", (event) => {
    const settings = ensureSettings();
    settings.defaultAgentID = event.target.value;
    delete settings.sessionId;
    void chrome.runtime.sendMessage({ type: "sloppy.settings.save", settings });
    void loadSlashCommands(frame);
    renderContext(frame);
  });
  frame.querySelector("[data-sloppy-model]").addEventListener("change", (event) => {
    const settings = ensureSettings();
    const selectedModel = String(event.target.value || "").trim();
    if (selectedModel && selectedModel !== "default") {
      settings.selectedModel = selectedModel;
    } else {
      delete settings.selectedModel;
    }
    void chrome.runtime.sendMessage({ type: "sloppy.settings.save", settings });
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
    renderComposerAction(frame);
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
  const config = normalizeVoiceConfig(response?.config || {});
  const language = normalizeVoiceLanguage(state.settings?.voiceLanguage || config.input.language);
  state.voiceConfig = {
    ...config,
    input: {
      ...config.input,
      language
    }
  };
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
    setVoiceState("error", error.message || t("voiceModeFailed"));
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
  setVoiceState("sending", t("sending"));
  document.querySelector("[data-sloppy-composer]")?.requestSubmit?.();
}

function render(frame) {
  renderAgents(frame);
  renderModels(frame);
  renderVoiceLanguage(frame);
  renderThread(frame);
  renderContext(frame);
  renderAttachments(frame);
  renderComposerAction(frame);
}

function normalizeVoiceLanguage(value) {
  const language = String(value || "auto").trim();
  return ["auto", "en-US", "ru-RU", "zh-CN"].includes(language) ? language : "auto";
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

function renderModels(frame) {
  const select = frame.querySelector("[data-sloppy-model]");
  if (!select) {
    return;
  }
  const selected = state.settings?.selectedModel || "default";
  const models = state.models.length
    ? state.models
    : [{ id: "default", title: t("defaultModel"), subtitle: t("defaultModelSubtitle") }];
  select.innerHTML = models
    .map((model) => `<option value="${escapeHTML(model.id)}">${escapeHTML(model.title || model.id)}</option>`)
    .join("");
  select.value = models.some((model) => model.id === selected) ? selected : "default";
}

function renderVoiceLanguage(frame) {
  const select = frame.querySelector("[data-sloppy-voice-language]");
  if (select) {
    select.value = normalizeVoiceLanguage(state.settings?.voiceLanguage || state.voiceConfig?.input?.language);
  }
}

function composerHasPayload(frame) {
  const prompt = frame.querySelector("[data-sloppy-prompt]")?.value?.trim() || "";
  return Boolean(prompt || state.attachments.length);
}

function renderComposerAction(frame) {
  const hasPayload = composerHasPayload(frame);
  const action = frame.querySelector("[data-sloppy-primary-action]");
  if (action) {
    action.innerHTML = icon(hasPayload ? "arrow-up" : "mic");
    action.setAttribute("aria-label", hasPayload ? t("send") : t("voiceMode"));
    action.dataset.sloppyAction = hasPayload ? "send" : "voice";
  }
}

function renderThread(frame) {
  const thread = frame.querySelector("[data-sloppy-thread]");
  if (!state.messages.length) {
    thread.innerHTML = `
      <div class="sloppy-empty">
        <img class="sloppy-empty-mark" src="${logoURL()}" alt="" aria-hidden="true">
        <h2>${escapeHTML(t("assistant"))}</h2>
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
    ? `<div class="sloppy-thinking" aria-label="${escapeHTML(t("thinking"))}"><span>${escapeHTML(t("thinking"))}</span></div>`
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
      <summary>${icon("tool")}<span>${escapeHTML(tool.name || t("toolCall"))}</span><small>${escapeHTML(tool.status || t("done"))}</small></summary>
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
        label: message.role === "assistant" ? t("assistant") : t("you"),
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
        <span>${selection ? escapeHTML(t("selectedChars", { count: selection.length })) : escapeHTML(t("noSelection"))}</span>
        <span>${escapeHTML(t("accessibleTabs", { count: tabCount }))}</span>
        <span>${escapeHTML(selectedSession?.title || (state.settings?.sessionId ? t("selectedSession") : t("newSession")))}</span>
      </div>
      <div class="sloppy-context-actions">
        <button type="button" data-sloppy-summarize-page>${icon("summarize")}<span>${escapeHTML(t("summarizePage"))}</span></button>
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
      renderComposerAction(frame);
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

function summarizePagePrompt() {
  return t("summarizePagePrompt");
}

async function summarizePage(frame) {
  const textarea = frame.querySelector("[data-sloppy-prompt]");
  textarea.value = summarizePagePrompt();
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
    selectedModel: state.settings?.selectedModel || "",
    voiceLanguage: normalizeVoiceLanguage(state.settings?.voiceLanguage),
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
  await loadModels(frame);
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
  list.innerHTML = `<p class="sloppy-session-empty">${escapeHTML(t("loadingSessions"))}</p>`;
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
  const response = await loadSessionSelection(sessionId);
  if (response?.error) {
    appendMessage({ role: "assistant", label: t("assistant"), text: response.error });
    render(frame);
    return;
  }
  state.messages = sessionId ? normalizeSessionMessages(response?.session?.events || []) : [];
  frame.querySelector("[data-sloppy-sessions-dialog]").close();
  render(frame);
}

async function loadSessionSelection(sessionId) {
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.sessions.select",
    sessionId: sessionId || "",
    agentId: state.settings?.defaultAgentID || "sloppy"
  });
  if (!response?.error) {
    state.settings = response?.settings || state.settings;
  }
  return response;
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

function snapshotSelectionForFloatingButton() {
  const info = cachedSelectionInfo(selectedTextInfo());
  if (!info) {
    return null;
  }
  state.selectionMenuText = info.text;
  state.selectionMenuRect = info.rect;
  return info;
}

function selectionMenuShouldUseBottomSheet(windowLike = window) {
  const touchPoints = Number(windowLike.navigator?.maxTouchPoints || globalThis.navigator?.maxTouchPoints || 0);
  const touchCapable = touchPoints > 0 || "ontouchstart" in windowLike;
  return touchCapable && isMobileViewport(windowLike);
}

function positionSelectionMenu(menu, rect, showPopover = false) {
  const useBottomSheet = showPopover && selectionMenuShouldUseBottomSheet(window);
  if (useBottomSheet) {
    menu.style.left = "0px";
    menu.style.top = "0px";
    menu.style.setProperty("--sloppy-selection-popover-x", "0px");
    menu.classList.toggle("is-popover-open", true);
    menu.classList.toggle("is-popover-above", false);
    menu.classList.toggle("is-mobile-sheet", true);
    return;
  }

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
  menu.classList.toggle("is-mobile-sheet", false);
}

function refreshSelectionMenuPlacement() {
  const menu = document.getElementById("sloppy-selection-menu");
  if (!menu || menu.hidden || !state.selectionMenuRect) {
    return false;
  }
  positionSelectionMenu(menu, state.selectionMenuRect, selectionPopoverIsOpen());
  return true;
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
  menu.classList.remove("is-mobile-sheet");
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
  await Promise.all([loadAgents(panel), loadModels(panel), refreshTabs(panel), loadSlashCommands(panel)]);
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
  renderComposerAction(frame);
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
    ensureSettings().defaultAgentID = response.selectedAgentId;
  }
  renderAgents(frame);
}

async function loadModels(frame) {
  const response = await chrome.runtime.sendMessage({ type: "sloppy.models.list" });
  state.models = response?.models || [];
  const settings = ensureSettings();
  if (response?.selectedModel && response.selectedModel !== "default") {
    settings.selectedModel = response.selectedModel;
  } else {
    delete settings.selectedModel;
  }
  renderModels(frame);
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
    appendMessage({ role: "assistant", label: t("assistant"), text: response.error });
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
  let nextAssistantText = "";
  const assistantText = assistantTextFromStreamEvent(event);
  if (assistantText) {
    nextAssistantText = assistantText;
  }
  if (event.type === "delta") {
    if (event.replace) {
      nextAssistantText = event.text || event.delta || "";
    } else {
      nextAssistantText = message.text + (event.text || event.delta || "");
    }
  }
  if (event.type === "assistant_message") {
    nextAssistantText = event.text || nextAssistantText;
  }
  if (nextAssistantText && nextAssistantText !== message.text) {
    await animateAssistantText(message, nextAssistantText, frame);
  }
  if (event.type === "tool_call") {
    message.toolCalls.push(event.tool || event.toolCall || event.tool_call || event);
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

function textFromContentValue(value) {
  if (!value) {
    return "";
  }
  if (typeof value === "string") {
    return value.trim();
  }
  if (Array.isArray(value)) {
    return value
      .map((item) => textFromContentValue(item))
      .filter(Boolean)
      .join("\n");
  }
  if (typeof value === "object") {
    const kind = value.kind || value.type;
    if (kind && kind !== "text") {
      return "";
    }
    return textFromContentValue(value.text ?? value.content ?? value.value ?? value.delta ?? "");
  }
  return String(value || "").trim();
}

function textFromSessionMessage(message = {}) {
  const segmentsText = (message.segments || [])
    .filter((segment) => !segment.kind || segment.kind === "text")
    .map((segment) => textFromContentValue(segment.text ?? segment.content ?? segment.value ?? segment))
    .filter(Boolean)
    .join("\n");
  return segmentsText
    || textFromContentValue(message.content)
    || textFromContentValue(message.text)
    || textFromContentValue(message.delta)
    || textFromContentValue(message.output);
}

function messageFromEvent(event = {}) {
  return event?.message || (event?.role === "assistant" ? event : null);
}

function latestAssistantTextFromEvents(events = []) {
  const assistant = [...events].reverse().find((event) => messageFromEvent(event)?.role === "assistant");
  return textFromSessionMessage(messageFromEvent(assistant) || {});
}

function latestInterruptedRunStatusText(events = []) {
  const statusEvent = [...events].reverse().find((event) => {
    const status = event?.runStatus || event?.run_status;
    const stage = String(status?.stage || "").toLowerCase();
    return stage === "interrupted" || stage === "failed" || stage === "error";
  });
  const status = statusEvent?.runStatus || statusEvent?.run_status;
  return String(status?.details || status?.message || status?.label || "").trim();
}

function assistantTextFromStreamEvent(event = {}) {
  const record = event.event || event.sessionEvent || event;
  const message = messageFromEvent(record) || messageFromEvent(event);
  if (message?.role !== "assistant") {
    return "";
  }
  return textFromSessionMessage(message);
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
    || latestInterruptedRunStatusText(response.appendedEvents || response.events || [])
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
    const clearTimer = window.clearTimeout?.bind(window) || globalThis.clearTimeout?.bind(globalThis) || (() => {});
    clearTimer(state.streamingAnimation);
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
      const setTimer = window.setTimeout?.bind(window) || globalThis.setTimeout?.bind(globalThis) || ((callback) => {
        callback();
        return null;
      });
      state.streamingAnimation = setTimer(tick, 18);
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
        status: t("done"),
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
  if (!prompt && !state.attachments.length) {
    return;
  }
  hideCommandMenu(frame);
  if (prompt.toLowerCase() === "/help") {
    appendMessage({ role: "user", label: t("you"), text: prompt });
    appendMessage({ role: "assistant", label: t("assistant"), text: slashHelpText() });
    textarea.value = "";
    textarea.style.height = "auto";
    render(frame);
    return;
  }
  if (prompt.toLowerCase() === "/status") {
    appendMessage({ role: "user", label: t("you"), text: prompt });
    appendMessage({
      role: "assistant",
      label: t("assistant"),
      text: `Agent: ${state.settings?.defaultAgentID || "sloppy"}\nSession: ${state.settings?.sessionId || "none"}\nState: idle`
    });
    textarea.value = "";
    textarea.style.height = "auto";
    render(frame);
    return;
  }
  const userAttachments = [...state.attachments];
  appendMessage({ role: "user", label: t("you"), text: prompt, attachments: userAttachments });
  textarea.value = "";
  textarea.style.height = "auto";
  state.attachments = [];

  const assistantId = globalThis.crypto?.randomUUID?.() || `${Date.now()}-assistant`;
  state.streamingMessageId = assistantId;
  appendMessage({ id: assistantId, role: "assistant", label: t("assistant"), text: "", streaming: true });
  if (state.voice.state === "sending") {
    setVoiceState("answering", t("thinking"));
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
    attachments: userAttachments,
    model: state.settings?.selectedModel || "default"
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
  let response = null;
  try {
    response = await chrome.runtime.sendMessage({ type: "sloppy.tabs.open", url });
  } catch (_error) {
    response = null;
  }
  if (!response || response.error) {
    window.open(url, "_blank", "noopener");
  }
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
  await Promise.all([loadAgents(panel), loadModels(panel), refreshTabs(panel), loadSlashCommands(panel)]);
  if (launch.sessionId) {
    const response = await loadSessionSelection(launch.sessionId);
    if (response?.error) {
      appendMessage({ role: "assistant", label: t("assistant"), text: response.error });
    } else {
      state.messages = normalizeSessionMessages(response?.session?.events || []);
    }
  }
  render(panel);
  const prompt = String(launch.prompt || "").trim();
  if (prompt) {
    const textarea = panel.querySelector("[data-sloppy-prompt]");
    textarea.value = prompt;
    renderComposerAction(panel);
    await sendPrompt(panel);
  } else {
    panel.querySelector("[data-sloppy-prompt]").focus();
  }
}

if (typeof document !== "undefined" && typeof chrome !== "undefined" && chrome.runtime?.onMessage) {
  updateViewportCSSVars();
  const refreshViewportDependentUI = () => {
    updateViewportCSSVars();
    refreshSelectionMenuPlacement();
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
  window.addEventListener("scroll", () => {
    updateViewportCSSVars();
    if (!refreshSelectionMenuPlacement()) {
      hideSelectionMenu();
    }
  }, true);

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
    if (message?.type === "sloppy.page.summarize") {
      void (async () => {
        const panel = await openPanelWithSelection(selectedText());
        await summarizePage(panel);
      })();
      return;
    }
    if (message?.type === "sloppy.browserContext.streamEvent" && message.requestId === state.streamingRequestId) {
      const panel = document.getElementById("sloppy-safari-extension-panel");
      void updateStreamingMessage(message.event || {}, panel);
    }
  });
}
