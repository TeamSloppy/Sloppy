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

function iconAsset(path) {
  const assetPath = String(path || "").trim();
  return typeof chrome !== "undefined" && typeof chrome.runtime?.getURL === "function"
    ? chrome.runtime.getURL(assetPath)
    : assetPath;
}

const iconSymbols = {
  close: "xmark",
  mic: "waveform",
  microphone: "microphone",
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
  sidebar: "sidebar.leading",
  model: "brain",
  project: "folder",
  customize: "gear",
  artifacts: "xmark.triangle.circle.square",
  trash: "trash"
};

function iconSymbol(name) {
  return iconSymbols[name] || "ellipsis";
}

function icon(name, hoverIcon = "") {
  const symbol = iconSymbol(name);
  const iconURL = iconAsset(`${symbol}.svg`);
  const safeIconURL = escapeHTML(iconURL);
  const hoverVariable = String(hoverIcon || "").trim()
    ? `; --sloppy-symbol-hover-url: url('${escapeHTML(iconAsset(hoverIcon))}')`
    : "";
  return `<span class="sloppy-symbol" aria-hidden="true" data-sf-symbol="${escapeHTML(symbol)}" style="--sloppy-symbol-base-url: url('${safeIconURL}'); --sloppy-symbol-url: url('${safeIconURL}')${hoverVariable}"></span>`;
}

function applySymbolFallbackVariables(frame) {
  const symbols = frame.querySelectorAll(".sloppy-symbol[data-sf-symbol]");
  symbols.forEach((symbolElement) => {
    const dataSymbol = String(symbolElement.getAttribute("data-sf-symbol") || "").trim();
    const symbol = iconSymbol(dataSymbol);
    const iconURL = iconAsset(`${symbol}.svg`);
    if (!iconURL) {
      return;
    }
    const safeIconURL = escapeHTML(iconURL);
    const baseVariable = symbolElement.style.getPropertyValue("--sloppy-symbol-base-url").trim();
    const fallbackVariable = symbolElement.style.getPropertyValue("--sloppy-symbol-url").trim();
    const isEmptyFallback = String(fallbackVariable).includes("url('')") || String(fallbackVariable).trim() === "";
    if (!baseVariable || isEmptyFallback) {
      symbolElement.style.setProperty("--sloppy-symbol-base-url", `url('${safeIconURL}')`);
    }
    if (!fallbackVariable || isEmptyFallback) {
      symbolElement.style.setProperty("--sloppy-symbol-url", `url('${safeIconURL}')`);
    }
  });
}

function setSidebarChevronIcon(button, baseIconName) {
  if (!button) {
    return;
  }
  const symbolContainer = button.querySelector(".sloppy-symbol");
  if (!symbolContainer) {
    return;
  }
  const symbol = iconSymbol(baseIconName);
  const baseURL = `url('${escapeHTML(iconAsset(`${symbol}.svg`))}')`;
  const hoverURL = `url('${escapeHTML(iconAsset("icons/chevron.down.svg"))}')`;
  symbolContainer.setAttribute("data-sf-symbol", symbol);
  symbolContainer.style.setProperty("--sloppy-symbol-base-url", baseURL);
  symbolContainer.style.setProperty("--sloppy-symbol-url", baseURL);
  symbolContainer.style.setProperty("--sloppy-symbol-active-url", baseURL);
  symbolContainer.style.setProperty("--sloppy-symbol-hover-url", hoverURL);
}

function refreshSidebarChevronIcons(frame) {
  const projectsButton = frame.querySelector("[data-sloppy-sidebar-projects]");
  const sessionsButton = frame.querySelector("[data-sloppy-sidebar-sessions]");
  const artifactsButton = frame.querySelector("[data-sloppy-sidebar-artifacts]");
  setSidebarChevronIcon(projectsButton, "project");
  setSidebarChevronIcon(artifactsButton, "artifacts");
  setSidebarChevronIcon(sessionsButton, "sessions");

  wireSidebarChevronHover(projectsButton);
  wireSidebarChevronHover(sessionsButton);
  wireSidebarChevronHover(artifactsButton);
}

const sidebarChevronBindings = new WeakMap();

function wireSidebarChevronHover(button) {
  if (!button) {
    return;
  }
  const cleanup = sidebarChevronBindings.get(button);
  if (cleanup) {
    button.removeEventListener("pointerenter", cleanup.onEnter);
    button.removeEventListener("pointerleave", cleanup.onLeave);
    button.removeEventListener("focus", cleanup.onEnter);
    button.removeEventListener("blur", cleanup.onLeave);
    button.removeEventListener("pointercancel", cleanup.onLeave);
  }

  const getSymbolState = () => {
    const symbol = button.querySelector(".sloppy-symbol");
    if (!symbol) {
      return null;
    }
    const baseIcon = symbol.style.getPropertyValue("--sloppy-symbol-base-url").trim();
    const hoverIcon = symbol.style.getPropertyValue("--sloppy-symbol-hover-url").trim();
    const fallbackIcon = symbol.style.getPropertyValue("--sloppy-symbol-url").trim();
    const base = baseIcon || fallbackIcon;
    if (!base) {
      return null;
    }
    return {
      symbol,
      base,
      hover: hoverIcon || base
    };
  };

  const setActive = (isHover) => {
    const state = getSymbolState();
    if (!state) {
      return;
    }
    state.symbol.style.setProperty("--sloppy-symbol-active-url", isHover ? state.hover : state.base);
  };

  const onEnter = () => setActive(true);
  const onLeave = () => setActive(false);

  button.addEventListener("pointerenter", onEnter);
  button.addEventListener("pointerleave", onLeave);
  button.addEventListener("focus", onEnter);
  button.addEventListener("blur", onLeave);
  button.addEventListener("pointercancel", onLeave);
  sidebarChevronBindings.set(button, { onEnter, onLeave });

  const initialState = getSymbolState();
  if (initialState) {
    initialState.symbol.style.setProperty("--sloppy-symbol-active-url", initialState.base);
  }
}

const sidebarMinWidth = 128;
const sidebarMaxWidth = 360;
const defaultSidebarWidth = 280;

function normalizeSidebarState(value = {}) {
  const width = Math.min(sidebarMaxWidth, Math.max(sidebarMinWidth, Number(value.width) || defaultSidebarWidth));
  return {
    width,
    collapsed: Boolean(value.collapsed)
  };
}

function sidebarStateAfterCollapseToggle(value = {}) {
  const sidebar = normalizeSidebarState(value);
  return {
    ...sidebar,
    collapsed: !sidebar.collapsed
  };
}

function starButtonBackgroundMarkup() {
  return `
    <svg class="sloppy-star-button-stars" width="100%" height="100%" preserveAspectRatio="none" viewBox="0 0 100 40" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
      <g clip-path="url(#sloppy-star-button-clip)">
        <path d="M32.34 26.68C32.34 26.3152 32.0445 26.02 31.68 26.02C31.3155 26.02 31.02 26.3152 31.02 26.68C31.02 27.0448 31.3155 27.34 31.68 27.34C32.0445 27.34 32.34 27.0448 32.34 26.68Z" fill="black"/>
        <path fill-rule="evenodd" clip-rule="evenodd" d="M56.1 3.96C56.4645 3.96 56.76 4.25519 56.76 4.62C56.76 4.98481 56.4645 5.28 56.1 5.28C55.9131 5.28 55.7443 5.20201 55.624 5.07762C55.5632 5.01446 55.5147 4.93904 55.4829 4.8559C55.4552 4.78243 55.44 4.70315 55.44 4.62C55.44 4.5549 55.4494 4.49174 55.4668 4.43244C55.4906 4.35188 55.5292 4.27775 55.5795 4.21329C55.7004 4.05926 55.8885 3.96 56.1 3.96ZM40.26 17.16C40.6245 17.16 40.92 17.4552 40.92 17.82C40.92 18.1848 40.6245 18.48 40.26 18.48C39.8955 18.48 39.6 18.1848 39.6 17.82C39.6 17.4552 39.8955 17.16 40.26 17.16ZM74.58 5.28C74.7701 5.28 74.9413 5.36057 75.0618 5.48882C75.073 5.50043 75.0837 5.51268 75.094 5.52557C75.1088 5.54426 75.1231 5.56359 75.1359 5.58357L75.1479 5.60291L75.1595 5.62353C75.1711 5.64481 75.1814 5.66672 75.1906 5.68928C75.2226 5.76662 75.24 5.85106 75.24 5.94C75.24 6.1585 75.1336 6.3525 74.9699 6.47238C74.9158 6.51234 74.8555 6.54393 74.7908 6.56584C74.7247 6.58775 74.6538 6.6 74.58 6.6C74.2156 6.6 73.92 6.30481 73.92 5.94C73.92 5.87684 73.929 5.8156 73.9455 5.7576C73.9596 5.70862 73.979 5.66221 74.0032 5.61903C74.0657 5.50688 74.1595 5.41471 74.2728 5.35541C74.3647 5.30707 74.4691 5.28 74.58 5.28ZM21.66 33.52C22.0245 33.52 22.32 33.8152 22.32 34.18C22.32 34.5448 22.0245 34.84 21.66 34.84C21.2955 34.84 21 34.5448 21 34.18C21 33.8152 21.2955 33.52 21.66 33.52ZM8.16 32.86C8.16 32.4952 7.8645 32.2 7.5 32.2C7.1355 32.2 6.84 32.4952 6.84 32.86C6.84 33.2248 7.1355 33.52 7.5 33.52C7.8645 33.52 8.16 33.2248 8.16 32.86ZM7.5 23.68C7.8645 23.68 8.16 23.9752 8.16 24.34C8.16 24.7048 7.8645 25 7.5 25C7.1355 25 6.84 24.7048 6.84 24.34C6.84 23.9752 7.1355 23.68 7.5 23.68ZM19.32 18.48C19.32 18.1152 19.0245 17.82 18.66 17.82C18.2955 17.82 18 18.1152 18 18.48C18 18.8448 18.2955 19.14 18.66 19.14C19.0245 19.14 19.32 18.8448 19.32 18.48ZM5.66 11.84C6.0245 11.84 6.32001 12.1352 6.32001 12.5C6.32001 12.8648 6.0245 13.16 5.66 13.16C5.2955 13.16 5 12.8648 5 12.5C5 12.1352 5.2955 11.84 5.66 11.84ZM35.16 35.5C35.16 35.1352 34.8645 34.84 34.5 34.84C34.1355 34.84 33.84 35.1352 33.84 35.5C33.84 35.8648 34.1355 36.16 34.5 36.16C34.8645 36.16 35.16 35.8648 35.16 35.5ZM53.5 36.18C53.8645 36.18 54.16 36.4752 54.16 36.84C54.16 37.2048 53.8645 37.5 53.5 37.5C53.1355 37.5 52.84 37.2048 52.84 36.84C52.84 36.4752 53.1355 36.18 53.5 36.18ZM48.5 28.66C48.5 28.2952 48.2045 28 47.84 28C47.4755 28 47.18 28.2952 47.18 28.66C47.18 29.0248 47.4755 29.32 47.84 29.32C48.2045 29.32 48.5 29.0248 48.5 28.66ZM60.34 27.34C60.7045 27.34 61 27.6352 61 28C61 28.3648 60.7045 28.66 60.34 28.66C59.9755 28.66 59.68 28.3648 59.68 28C59.68 27.6352 59.9755 27.34 60.34 27.34ZM56.284 16.5C56.284 16.1352 55.9885 15.84 55.624 15.84C55.2595 15.84 54.964 16.1352 54.964 16.5C54.964 16.8648 55.2595 17.16 55.624 17.16C55.9885 17.16 56.284 16.8648 56.284 16.5ZM46.2 7.26C46.2 6.89519 45.9045 6.6 45.54 6.6C45.5174 6.6 45.4953 6.60129 45.4733 6.60387L45.453 6.60579L45.4124 6.61225L45.3857 6.61804L45.3845 6.61836C45.3675 6.62277 45.3504 6.62721 45.3341 6.63287C45.2522 6.65929 45.1774 6.70184 45.1134 6.75597C45.0627 6.79916 45.0186 6.84943 44.9828 6.90551C44.9178 7.00799 44.88 7.12981 44.88 7.26C44.88 7.62481 45.1755 7.92 45.54 7.92C45.7372 7.92 45.9141 7.83363 46.0353 7.69635C46.0808 7.64478 46.1182 7.58613 46.1459 7.52232C46.1807 7.4424 46.2 7.35346 46.2 7.26ZM33 9.34C33 8.9752 32.7045 8.68 32.34 8.68C31.9755 8.68 31.68 8.9752 31.68 9.34C31.68 9.7048 31.9755 10 32.34 10C32.7045 10 33 9.7048 33 9.34ZM16 4.8559C16.3645 4.8559 16.66 5.1511 16.66 5.5159C16.66 5.8807 16.3645 6.1759 16 6.1759C15.6355 6.1759 15.34 5.8807 15.34 5.5159C15.34 5.1511 15.6355 4.8559 16 4.8559ZM69.66 21.16C69.66 20.7952 69.3645 20.5 69 20.5C68.6355 20.5 68.34 20.7952 68.34 21.16C68.34 21.5248 68.6355 21.82 69 21.82C69.3645 21.82 69.66 21.5248 69.66 21.16ZM80.52 15.18C80.52 14.8152 80.2245 14.52 79.86 14.52C79.4956 14.52 79.2 14.8152 79.2 15.18C79.2 15.5448 79.4956 15.84 79.86 15.84C80.2245 15.84 80.52 15.5448 80.52 15.18ZM78.16 34.84C78.16 34.4752 77.5 34.18 77.5 34.18C77.5 34.18 76.84 34.4752 76.84 34.84C76.84 35.2048 77.1355 35.5 77.5 35.5C77.8645 35.5 78.16 35.2048 78.16 34.84ZM85.66 24.34C86.0245 24.34 86.32 24.6352 86.32 25C86.32 25.3648 86.0245 25.66 85.66 25.66C85.2955 25.66 85 25.3648 85 25C85 24.6352 85.2955 24.34 85.66 24.34ZM91.32 10C91.32 9.6352 91.0245 9.34 90.66 9.34C90.2955 9.34 90 9.6352 90 10C90 10.3648 90.2955 10.66 90.66 10.66C91.0245 10.66 91.32 10.3648 91.32 10ZM138.6 0H0V46.2H138.6V0ZM92.64 34.84C92.64 34.4752 91.98 34.18 91.98 34.18C91.98 34.18 91.32 34.4752 91.32 34.84C91.32 35.2048 91.6155 35.5 91.98 35.5C92.3445 35.5 92.64 35.2048 92.64 34.84Z" fill="currentColor"/>
      </g>
      <defs><clipPath id="sloppy-star-button-clip"><rect width="100" height="40" fill="white"/></clipPath></defs>
    </svg>
  `;
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
    if (/(^|\.)ya\./.test(host) && path.startsWith("/search")) {
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
  const isYandex = engine === "yandex" || engine === "ya";
  const query = String(url.searchParams.get(isYandex ? "text" : "q") || "").trim();
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
  const safeWidth = Math.max(Number(metrics.width || 0), Number(window.innerWidth || 0));
  const safeHeight = Math.max(Number(metrics.height || 0), Number(window.innerHeight || 0));
  const root = document.documentElement;
  root.style.setProperty("--sloppy-viewport-width", `${safeWidth}px`);
  root.style.setProperty("--sloppy-viewport-height", `${safeHeight}px`);
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

function selectionActionTitle(actionId) {
  return selectionActions.find((action) => action.id === actionId)?.title || t("assistant");
}

const state = {
  settings: null,
  agentsLoaded: false,
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
  streamingStatusTimer: null,
  selectionMenuText: "",
  selectionMenuRect: null,
  fullscreenLaunch: null,
  quickChat: null,
  sidebar: normalizeSidebarState(),
  artifacts: [],
  widgetHTMLByArtifactId: {},
  widgetPickerSheet: { open: false },
  gridDrag: {
    activeId: null,
    overId: null,
    dropPosition: null
  },
  availableBookmarks: [],
  customizeNavigation: {
    screen: "home",
    editing: false,
    widgetDraft: null,
    widgetDraftSourceId: null
  },
  voiceConfig: {
    enabled: false,
    effectiveProvider: "local",
    input: { mode: "push_to_talk", language: "auto", deviceId: "", previewBeforeSend: true },
    local: { enabled: true, voiceName: "", rate: 1, pitch: 1 }
  },
  voiceInputDevices: [],
  voice: { state: "idle", transcript: "", recognition: null, recorder: null, cancelled: false }
};

const chatPlaceholderKeys = [
  "chatPlaceholderAskSomething",
  "chatPlaceholderSlashCommands",
  "chatPlaceholderUseContext"
];

function chatPlaceholderText(index = Math.floor(Date.now() / 3200)) {
  const key = chatPlaceholderKeys[Math.abs(index) % chatPlaceholderKeys.length];
  return t(key);
}

function applyRotatingChatPlaceholders(root = document, index) {
  const text = chatPlaceholderText(index);
  Array.from(root.querySelectorAll?.("[data-sloppy-chat-placeholder]") || []).forEach((element) => {
    if ("value" in element && String(element.value || "").trim()) {
      element.classList?.remove("is-placeholder-swapping");
      return;
    }
    const current = "placeholder" in element ? element.placeholder : element.textContent;
    if (current === text) {
      return;
    }
    element.classList?.add("is-placeholder-swapping");
    const applyText = () => {
      if ("placeholder" in element) {
        element.placeholder = text;
      } else {
        element.textContent = text;
      }
      element.classList?.remove("is-placeholder-swapping");
    };
    if (index === undefined) {
      if (typeof window.setTimeout === "function") {
        window.setTimeout(applyText, 120);
      } else {
        applyText();
      }
      return;
    }
    if ("placeholder" in element) {
      element.placeholder = text;
      return;
    }
    element.textContent = text;
    element.classList?.remove("is-placeholder-swapping");
  });
}

function ensureSettings() {
  state.settings = state.settings || {};
  return state.settings;
}

function isStartPageMode() {
  return Boolean(globalThis.SloppyStartPageMode)
    && !document.documentElement.classList.contains?.("sloppy-fullscreen-chat-page");
}

function setStartPageMode(active) {
  globalThis.SloppyStartPageMode = Boolean(active);
  document.documentElement.classList.toggle("sloppy-start-page", Boolean(active));
  document.documentElement.classList.toggle("sloppy-fullscreen-chat-page", !active);
}

function ensurePanel() {
  updateViewportCSSVars();
  let frame = document.getElementById("sloppy-safari-extension-panel");
  const isFullscreen = document.documentElement.classList.contains?.("sloppy-fullscreen-chat-page");
  if (frame) {
    const isMobile = isMobileViewport(window);
    state.sidebar = normalizeSidebarState({
      ...state.sidebar,
      collapsed: isFullscreen ? isMobile : (state.sidebar?.collapsed || isMobile)
    });
    if (!isFullscreen) {
      frame.querySelectorAll?.("[data-sloppy-sidebar-restore], .sloppy-sidebar-restore").forEach((button) => button.remove());
    } else {
      frame.querySelector("[data-sloppy-sidebar-restore]")?.remove();
    }
    if (isFullscreen) {
      frame.querySelector("[data-sloppy-sessions]")?.remove();
    }
    refreshSidebarChevronIcons(frame);
    applySidebarState(frame);
    if (isFullscreen) {
      frame.querySelector("[data-sloppy-capture]")?.remove();
    }
    applySymbolFallbackVariables(frame);
    return frame;
  }

  const isMobile = isMobileViewport(window);
  state.contextCollapsed = shouldCollapseContextByDefault(window);
  state.sidebar = normalizeSidebarState({
    ...state.sidebar,
    collapsed: isFullscreen ? isMobile : (state.sidebar?.collapsed || isMobile)
  });
  frame = document.createElement("aside");
  frame.id = "sloppy-safari-extension-panel";
  frame.innerHTML = `
    <div class="sloppy-app-layout" data-sloppy-app-layout>
      <nav class="sloppy-app-sidebar" data-sloppy-app-sidebar aria-label="${escapeHTML(t("navigation"))}">
        <button class="sloppy-icon-button sloppy-sidebar-collapse" type="button" data-sloppy-sidebar-collapse aria-label="${escapeHTML(t("hideSidebar"))}">${icon("sidebar")}</button>
        <button class="sloppy-sidebar-item" type="button" data-sloppy-sidebar-new>${icon("plus")}<span>${escapeHTML(t("newSession"))}</span></button>
        <button class="sloppy-sidebar-item" type="button" data-sloppy-sidebar-artifacts>${icon("artifacts", "icons/chevron.down.svg")}<span>${escapeHTML(t("artifacts"))}</span></button>
        <button class="sloppy-sidebar-item" type="button" data-sloppy-sidebar-projects>${icon("project", "icons/chevron.down.svg")}<span>${escapeHTML(t("projects"))}</span></button>
        <button class="sloppy-sidebar-item" type="button" data-sloppy-sidebar-sessions>${icon("sessions", "icons/chevron.down.svg")}<span>${escapeHTML(t("sessions"))}</span></button>
        <div class="sloppy-sidebar-session-list" data-sloppy-sidebar-session-list></div>
      </nav>
      <div class="sloppy-sidebar-resizer" data-sloppy-sidebar-resizer role="separator" aria-orientation="vertical" aria-label="${escapeHTML(t("sessions"))}" tabindex="0"></div>

      <div class="sloppy-shell">
      <button class="sloppy-widget-chat-sheet-toggle" type="button" data-sloppy-widget-chat-sheet-toggle aria-label="Toggle widget chat">
        <span aria-hidden="true"></span>
      </button>
      <header class="sloppy-topbar">
        <div class="sloppy-topbar-leading">
          ${isFullscreen || isMobile || isStartPageMode() ? `<button class="sloppy-icon-button sloppy-sidebar-toggle sloppy-sidebar-restore" type="button" data-sloppy-sidebar-restore aria-label="${escapeHTML(t("showSidebar"))}">${icon("sidebar")}</button>` : ""}
          <div class="sloppy-brand">
            <img class="sloppy-mark" src="${logoURL()}" alt="" aria-hidden="true">
            <label class="sloppy-agent-select" style="--sloppy-agent-chevron-url: url('${escapeHTML(iconAsset("icons/chevron.down.svg"))}')">
              <select data-sloppy-agent aria-label="${escapeHTML(t("agent"))}"></select>
            </label>
          </div>
        </div>
        <div class="sloppy-actions">
          <button class="sloppy-icon-button" type="button" data-sloppy-open-fullscreen aria-label="${escapeHTML(t("openFullscreenChat"))}">${icon("expand")}</button>
          <button class="sloppy-icon-button" type="button" data-sloppy-settings aria-label="${escapeHTML(t("settings"))}">${icon("settings")}</button>
          <button class="sloppy-icon-button" type="button" data-sloppy-close aria-label="${escapeHTML(t("close"))}">${icon("close")}</button>
        </div>
      </header>

      <main class="sloppy-thread" data-sloppy-thread></main>

      <section class="sloppy-browser-context" data-sloppy-context></section>
      <div class="sloppy-command-menu" data-sloppy-command-menu hidden></div>
      <div class="sloppy-agent-warning" data-sloppy-agent-warning hidden></div>

      <form class="sloppy-composer" data-sloppy-composer>
        <div class="sloppy-attachments" data-sloppy-attachments></div>
        <textarea data-sloppy-prompt data-sloppy-chat-placeholder rows="1" placeholder="${escapeHTML(chatPlaceholderText(0))}"></textarea>
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
      <div class="sloppy-start-shortcuts" data-sloppy-start-shortcuts></div>
      <div class="sloppy-start-config-panel">
        <dialog class="sloppy-settings-dialog sloppy-customize-dialog" data-sloppy-customize-dialog>
          <form method="dialog" class="sloppy-settings-card">
            <div class="sloppy-customize-body" data-sloppy-customize-body></div>
          </form>
        </dialog>
        <button class="sloppy-start-config-button" type="button" data-sloppy-customize>${icon("customize")}<span>${escapeHTML(t("customize"))}</span></button>
      </div>
      </div>
    </div>

    <section class="sloppy-voice" data-sloppy-voice-panel hidden>
      <label class="sloppy-voice-settings sloppy-voice-language-settings" data-sloppy-voice-settings aria-label="${escapeHTML(t("voiceLanguage"))}">
        <span aria-hidden="true">${icon("settings")}</span>
        <select class="sloppy-voice-language" data-sloppy-voice-language aria-label="${escapeHTML(t("voiceLanguage"))}">
          <option value="auto">${escapeHTML(t("voiceLanguageAuto"))}</option>
          <option value="en-US">${escapeHTML(t("voiceLanguageEnglish"))}</option>
          <option value="ru-RU">${escapeHTML(t("voiceLanguageRussian"))}</option>
          <option value="zh-CN">${escapeHTML(t("voiceLanguageChinese"))}</option>
        </select>
      </label>
      <label class="sloppy-voice-settings sloppy-voice-microphone-settings" data-sloppy-voice-microphone-settings aria-label="${escapeHTML(t("voiceMicrophone"))}">
        <span aria-hidden="true">${icon("microphone")}</span>
        <select class="sloppy-voice-microphone" data-sloppy-voice-microphone aria-label="${escapeHTML(t("voiceMicrophone"))}">
          <option value="">${escapeHTML(t("voiceMicrophoneDefault"))}</option>
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
  if (isFullscreen) {
    frame.querySelector("[data-sloppy-capture]")?.remove();
  }
  applySymbolFallbackVariables(frame);
  document.documentElement.appendChild(frame);
  wirePanel(frame);
  applySidebarState(frame);
  applyRotatingChatPlaceholders(frame);
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
  button.innerHTML = `
    <span class="sloppy-star-button-light" aria-hidden="true"></span>
    <span class="sloppy-star-button-background" aria-hidden="true">${starButtonBackgroundMarkup()}</span>
    <span class="sloppy-star-button-logo" style="--sloppy-logo-url: url('${escapeHTML(logoURL())}')" aria-hidden="true"></span>
    <strong>${escapeHTML(t("askSloppy"))}</strong>
  `;
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
  if (typeof requestAnimationFrame === "function") {
    requestAnimationFrame(() => updateSearchButtonPath(button));
  } else {
    updateSearchButtonPath(button);
  }
  return button;
}

function updateSearchButtonPath(button) {
  if (!button) {
    return;
  }
  button.style.setProperty("--sloppy-star-path", `path('M 0 0 H ${button.offsetWidth} V ${button.offsetHeight} H 0 V 0')`);
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
  updateSearchButtonPath(button);
  const floating = document.getElementById("sloppy-floating-button");
  if (floating) {
    floating.hidden = true;
  }
}

function ensureQuickChat() {
  let chat = document.getElementById("sloppy-quick-chat");
  if (chat) {
    return chat;
  }
  chat = document.createElement("aside");
  chat.id = "sloppy-quick-chat";
  document.documentElement.appendChild(chat);
  return chat;
}

function removeQuickChat() {
  const chat = document.getElementById("sloppy-quick-chat");
  if (chat) {
    chat.remove();
  }
  state.quickChat = null;
}

function quickChatPlacementStyle(rect, windowLike = window) {
  if (!rect) {
    return null;
  }
  const padding = 16;
  const viewportWidth = Number(windowLike.innerWidth || document.documentElement.clientWidth || 0);
  const viewportHeight = Number(windowLike.innerHeight || document.documentElement.clientHeight || 0);
  const quickWidth = Math.min(360, Math.max(0, viewportWidth - padding * 2));
  const estimatedHeight = 300;
  const anchorGap = 12;
  const spaceBelow = viewportHeight - rect.bottom - padding;
  const shouldOpenAbove = spaceBelow < estimatedHeight || rect.top > viewportHeight / 2;
  const preferredLeft = Number(rect.right || rect.left || 0) - 26;
  const maxLeft = Math.max(padding, viewportWidth - quickWidth - padding);
  const left = Math.min(Math.max(preferredLeft, padding), maxLeft);
  const top = shouldOpenAbove
    ? Math.max(padding, Number(rect.top || 0) - anchorGap)
    : Math.min(Math.max(Number(rect.bottom || 0) + anchorGap, padding), Math.max(padding, viewportHeight - padding));
  return {
    left: `${Math.round(left)}px`,
    top: `${Math.round(top)}px`,
    transform: shouldOpenAbove ? "translateY(-100%)" : "none"
  };
}

function applyQuickChatPlacement(chat, anchorRect) {
  const style = quickChatPlacementStyle(anchorRect);
  if (!style) {
    chat.classList.remove("is-anchored");
    chat.style.removeProperty("--sloppy-quick-left");
    chat.style.removeProperty("--sloppy-quick-top");
    chat.style.removeProperty("--sloppy-quick-transform");
    return;
  }
  chat.classList.add("is-anchored");
  chat.style.setProperty("--sloppy-quick-left", style.left);
  chat.style.setProperty("--sloppy-quick-top", style.top);
  chat.style.setProperty("--sloppy-quick-transform", style.transform);
}

function quickChatTitle(prompt = "") {
  return String(prompt || "").trim() || t("assistant");
}

function renderQuickChat() {
  const quick = state.quickChat;
  if (!quick) {
    return;
  }
  const chat = ensureQuickChat();
  applyQuickChatPlacement(chat, quick.anchorRect);
  const assistantHTML = quick.assistantText
    ? renderMarkdown(quick.assistantText)
    : `<p class="sloppy-quick-status">${escapeHTML(quick.streaming ? t("thinking") : "")}</p>`;
  chat.innerHTML = `
    <div class="sloppy-quick-shell">
      <header class="sloppy-quick-header">
        <div class="sloppy-quick-title">
          <img class="sloppy-mark" src="${logoURL()}" alt="" aria-hidden="true">
          <strong>${escapeHTML(quickChatTitle(quick.title))}</strong>
        </div>
        <div class="sloppy-quick-actions">
          <button class="sloppy-icon-button" type="button" data-sloppy-quick-sidebar aria-label="${escapeHTML(t("openFullscreenChat"))}">${icon("sidebar")}</button>
          <button class="sloppy-icon-button" type="button" data-sloppy-quick-close aria-label="${escapeHTML(t("close"))}">${icon("close")}</button>
        </div>
      </header>
      <main class="sloppy-quick-body">
        ${quick.userText ? `<div class="sloppy-quick-user">${escapeHTML(quick.userText)}</div>` : ""}
        <div class="sloppy-quick-assistant ${quick.streaming ? "is-streaming" : ""}">${assistantHTML}</div>
      </main>
      <footer class="sloppy-quick-footer">
        <button class="sloppy-quick-follow-up" type="button" data-sloppy-quick-follow-up>${icon("plus")}<span>${escapeHTML(t("continueInChat"))}</span></button>
      </footer>
    </div>
  `;
  chat.querySelector("[data-sloppy-quick-close]")?.addEventListener("click", removeQuickChat);
  chat.querySelector("[data-sloppy-quick-sidebar]")?.addEventListener("click", () => {
    void openQuickChatSidebar();
  });
  chat.querySelector("[data-sloppy-quick-follow-up]")?.addEventListener("click", () => {
    void openQuickChatSidebar();
  });
  applyRotatingChatPlaceholders(chat);
}

async function openQuickChatSidebar() {
  const quick = state.quickChat || {};
  const context = quick.context || state.context || extractPageContext(document, selectedText());
  await openFullscreenChat({
    selection: context.selection || "",
    page: context.page,
    sessionId: quick.sessionId || state.settings?.sessionId || ""
  });
}

async function loadQuickChatTabs() {
  const response = await chrome.runtime.sendMessage({ type: "sloppy.tabs.list" }).catch(() => ({ tabs: [] }));
  return response?.tabs || [];
}

async function updateQuickChatStreaming(event = {}) {
  const quick = state.quickChat;
  if (!quick) {
    return;
  }
  let nextText = assistantTextFromStreamEvent(event);
  if (event.type === "delta") {
    nextText = event.replace ? (event.text || event.delta || "") : `${quick.assistantText || ""}${event.text || event.delta || ""}`;
  }
  if (event.type === "assistant_message") {
    nextText = event.text || nextText;
  }
  if (nextText) {
    quick.assistantText = nextText;
  }
  if (event.type === "complete" || event.type === "done") {
    if (event.body) {
      const finalText = agentResponseText(event.body, quick.assistantText);
      quick.assistantText = finalText || quick.assistantText;
      quick.streaming = false;
      if (event.body?.sessionId) {
        quick.sessionId = event.body.sessionId;
      }
    }
  }
  if (event.type === "session_error") {
    quick.assistantText = event.message || quick.assistantText || "Session stream failed.";
    quick.streaming = false;
  }
  renderQuickChat();
}

async function openQuickChatForPrompt(prompt, options = {}) {
  const context = options.context || extractPageContext(document, options.selection || selectedText());
  state.context = context;
  state.settings = state.settings || await chrome.runtime.sendMessage({ type: "sloppy.settings.get" });
  state.quickChat = {
    context,
    prompt,
    title: options.title || t("assistant"),
    userText: options.userText || "",
    anchorRect: options.anchorRect || null,
    assistantText: "",
    sessionId: state.settings?.sessionId || "",
    requestId: globalThis.crypto?.randomUUID?.() || `${Date.now()}-quick`,
    streaming: true
  };
  hideSelectionMenu();
  renderQuickChat();

  let response = null;
  try {
    response = await chrome.runtime.sendMessage({
      type: "sloppy.browserContext.stream",
      requestId: state.quickChat.requestId,
      sessionId: state.settings?.sessionId || "",
      page: context.page,
      selection: context.selection,
      prompt,
      tabs: await loadQuickChatTabs(),
      attachments: [],
      model: state.settings?.selectedModel || "default"
    });
  } catch (error) {
    response = { error: error.message || "Sloppy Core unavailable." };
  }

  const quick = state.quickChat;
  if (!quick) {
    return;
  }
  if (response?.error) {
    quick.assistantText = response.error;
    quick.streaming = false;
  } else {
    quick.assistantText = agentResponseText(response, quick.assistantText);
    quick.sessionId = response?.sessionId || quick.sessionId;
    await rememberSession(response, null);
  }
  quick.streaming = false;
  renderQuickChat();
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
        <input data-sloppy-command-palette-input data-sloppy-chat-placeholder placeholder="${escapeHTML(chatPlaceholderText(0))}" autocomplete="off">
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
  applyRotatingChatPlaceholders(palette);
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
        <input data-sloppy-selection-prompt data-sloppy-chat-placeholder placeholder="${escapeHTML(chatPlaceholderText(0))}" autocomplete="off">
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
  applyRotatingChatPlaceholders(menu);
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
      const actionId = button.dataset.sloppySelectionAction;
      const prompt = selectionActionPrompt(actionId);
      if (prompt) {
        void sendSelectionPrompt(prompt, selectionActionTitle(actionId));
      }
    });
  });
  menu.querySelector("[data-sloppy-selection-hide]").addEventListener("click", hideSelectionMenu);
}

function wirePanel(frame) {
  frame.addEventListener("pointerdown", focusPanelControlFromEvent, true);
  frame.addEventListener("click", focusPanelControlFromEvent, true);
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
  frame.querySelector("[data-sloppy-sessions]")?.addEventListener("click", () => openSessions(frame, { presentation: "dialog" }));
  frame.querySelector("[data-sloppy-new-session]").addEventListener("click", () => selectSession(frame, null));
  frame.querySelector("[data-sloppy-save-settings]").addEventListener("click", () => saveSettings(frame));
  frame.querySelector("[data-sloppy-customize]")?.addEventListener("click", () => openCustomize(frame));
  const customizeDialog = frame.querySelector("[data-sloppy-customize-dialog]");
  customizeDialog?.addEventListener("close", () => {
    if (state.ignoreCustomizeCloseReset) {
      customizeDialog.classList.remove("sloppy-customize-dialog-open");
      return;
    }
    exitCustomizeMode(frame);
    render(frame);
  });
  frame.querySelector("[data-sloppy-customize-body]")?.addEventListener("click", (event) => {
    if (event.target?.closest?.("[data-sloppy-open-general]")) {
      navigateCustomize(frame, "general");
      return;
    }
    if (event.target?.closest?.("[data-sloppy-open-widgets]")) {
      navigateCustomize(frame, "widgets");
      return;
    }
    if (event.target?.closest?.("[data-sloppy-customize-back]")) {
      navigateCustomize(frame, "widgets");
      return;
    }
    if (event.target?.closest?.("[data-sloppy-save-customize]")) {
      void saveCustomize(frame);
      return;
    }
    if (event.target?.closest?.("[data-sloppy-open-widget-picker]")) {
      openWidgetPickerSheet(frame);
      return;
    }
    if (event.target?.closest?.("[data-sloppy-widget-picker-done]")) {
      closeWidgetPickerSheet(frame);
      return;
    }
    if (event.target?.closest?.("[data-sloppy-create-widget-card]")) {
      closeWidgetPickerSheet(frame);
      openWidgetEditor(frame);
      return;
    }
    const deleteReadyWidget = event.target?.closest?.("[data-sloppy-delete-ready-widget]");
    if (deleteReadyWidget) {
      void deleteCreatedWidget(frame, deleteReadyWidget.dataset.sloppyDeleteReadyWidget, { persist: true });
      return;
    }
    const pickReadyWidget = event.target?.closest?.("[data-sloppy-pick-ready-widget]");
    if (pickReadyWidget) {
      void addWidgetToStartPage(frame, pickReadyWidget.dataset.sloppyPickReadyWidget, { persist: false });
      closeWidgetPickerSheet(frame);
      return;
    }
    const pickShortcutWidget = event.target?.closest?.("[data-sloppy-pick-shortcut-widget]");
    if (pickShortcutWidget) {
      void openShortcutEditor(frame);
      return;
    }
    const pickBookmark = event.target?.closest?.("[data-sloppy-pick-bookmark]");
    if (pickBookmark) {
      const bookmarkId = String(pickBookmark.dataset.sloppyPickBookmark || "").trim();
      const bookmark = state.availableBookmarks.find((candidate) => String(candidate.id || "") === bookmarkId);
      if (!bookmark?.id) {
        return;
      }
      state.customizeNavigation = {
        ...state.customizeNavigation,
        widgetDraft: {
          ...(state.customizeNavigation?.widgetDraft || {}),
          title: String(bookmark.title || "").trim() || String(bookmark.url || "").trim(),
          url: String(bookmark.url || "").trim(),
          kind: "shortcut",
          colSpan: 1,
          rowSpan: 1
        }
      };
      renderCustomizeDialog(frame);
      return;
    }
    const gridMenuButton = event.target?.closest?.("[data-sloppy-grid-menu]");
    if (gridMenuButton) {
      const itemId = String(gridMenuButton.dataset.sloppyGridMenu || "").trim();
      const item = normalizedStartPageItems(state.settings).find((candidate) => String(candidate.id || "") === itemId);
      if (!item?.id) {
        return;
      }
      if (String(item.kind || "").trim() === "shortcut") {
        void openShortcutEditor(frame, item.id);
        return;
      }
      if (String(item.kind || "").trim() === "widget") {
        openWidgetEditor(frame, item.id);
        return;
      }
    }
    if (event.target?.closest?.("[data-sloppy-open-widget-editor]")) {
      openWidgetEditor(frame);
      return;
    }
    if (event.target?.closest?.("[data-sloppy-start-page-clear-background]")) {
      state.settings = {
        ...(state.settings || {}),
        startPageBackgroundImage: ""
      };
      const startPageError = frame.querySelector("[data-sloppy-start-page-error]");
      if (startPageError) {
        startPageError.textContent = "";
      }
      return;
    }
    const widgetButton = event.target?.closest?.("[data-sloppy-pick-widget]");
    if (widgetButton) {
      void addWidgetToStartPage(frame, widgetButton.dataset.sloppyPickWidget);
      return;
    }
    const moveButton = event.target?.closest?.("[data-sloppy-move-item]");
    if (moveButton) {
      moveStartPageItem(moveButton.dataset.sloppyMoveItem, moveButton.dataset.direction);
      renderCustomizeDialog(frame);
      return;
    }
    const deleteButton = event.target?.closest?.("[data-sloppy-delete-item]");
    if (deleteButton) {
      removeStartPageItem(deleteButton.dataset.sloppyDeleteItem);
      renderCustomizeDialog(frame);
      return;
    }
    const editWidgetButton = event.target?.closest?.("[data-sloppy-edit-widget]");
    if (editWidgetButton) {
      openWidgetEditor(frame, editWidgetButton.dataset.sloppyEditWidget);
      return;
    }
    const resizeButton = event.target?.closest?.("[data-sloppy-resize-item]");
    if (resizeButton) {
      const itemId = resizeButton.dataset.sloppyResizeItem;
      const item = normalizedStartPageItems(state.settings).find((candidate) => candidate.id === itemId);
      if (item) {
        const nextSpan = item.colSpan === 1 && item.rowSpan === 1
          ? { colSpan: 2, rowSpan: 1 }
          : item.colSpan === 2 && item.rowSpan === 1
            ? { colSpan: 2, rowSpan: 2 }
            : { colSpan: 1, rowSpan: 1 };
        resizeStartPageItem(itemId, nextSpan.colSpan, nextSpan.rowSpan);
        renderCustomizeDialog(frame);
      }
      return;
    }
    if (event.target?.closest?.("[data-sloppy-widget-editor-cancel]")) {
      state.customizeNavigation = {
        ...state.customizeNavigation,
        screen: "widgets",
        widgetDraft: null,
        widgetDraftSourceId: null
      };
      renderCustomizeDialog(frame);
      return;
    }
    if (event.target?.closest?.("[data-sloppy-widget-editor-done]")) {
      commitWidgetDraft(frame);
      return;
    }
    if (event.target?.closest?.("[data-sloppy-shortcut-editor-cancel]")) {
      navigateCustomize(frame, "widgets");
      return;
    }
    if (event.target?.closest?.("[data-sloppy-shortcut-editor-done]")) {
      commitShortcutDraft(frame);
      return;
    }
    const widgetEditorResizeButton = event.target?.closest?.("[data-sloppy-widget-editor-resize]");
    if (widgetEditorResizeButton) {
      const nextSpan = parseGridSpan(widgetEditorResizeButton.dataset.sloppyWidgetEditorResize);
      state.customizeNavigation = {
        ...state.customizeNavigation,
        widgetDraft: {
          ...(state.customizeNavigation?.widgetDraft || {}),
          ...nextSpan
        }
      };
      renderCustomizeDialog(frame);
      return;
    }
    if (event.target?.closest?.("[data-sloppy-generate-widget]")) {
      const prompt = frame.querySelector("[data-sloppy-describe-widget]")?.value?.trim() || "";
      if (prompt) {
        openWidgetEditor(frame);
        void updateWidgetDraftFromPrompt(frame, prompt);
      }
    }
  });
  frame.querySelector("[data-sloppy-customize-body]")?.addEventListener("change", (event) => {
    if (event.target?.matches?.("[data-sloppy-start-page-background]")) {
      void readStartPageBackgroundImage(event.target.files?.[0], frame);
    }
    const titleInput = event.target?.matches?.("[data-sloppy-shortcut-title]");
    const urlInput = event.target?.matches?.("[data-sloppy-shortcut-url]");
    if (!titleInput && !urlInput) {
      return;
    }
    const currentDraft = state.customizeNavigation?.widgetDraft || {};
    state.customizeNavigation = {
      ...state.customizeNavigation,
      widgetDraft: {
        ...currentDraft,
        title: titleInput ? String(event.target.value || "").trim() : String(currentDraft.title || ""),
        url: urlInput ? String(event.target.value || "").trim() : String(currentDraft.url || "")
      }
    };
  });
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
  frame.querySelector("[data-sloppy-start-page-clear-background]")?.addEventListener("click", () => {
    state.settings = {
      ...(state.settings || {}),
      startPageBackgroundImage: ""
    };
    frame.querySelector("[data-sloppy-start-page-error]").textContent = "";
  });
  frame.querySelector("[data-sloppy-shortcut-editor-cancel]")?.addEventListener("click", () => {
    navigateCustomize(frame, "widgets");
  });
  frame.querySelector("[data-sloppy-shortcut-editor-done]")?.addEventListener("click", () => {
    commitShortcutDraft(frame);
  });
  frame.querySelector("[data-sloppy-open-widget-picker]")?.addEventListener("click", () => {
    openWidgetPickerSheet(frame);
  });
  frame.querySelector("[data-sloppy-pick-shortcut-widget]")?.addEventListener("click", () => {
    void openShortcutEditor(frame);
  });
  frame.querySelector("[data-sloppy-widget-chat-sheet-toggle]")?.addEventListener("click", (event) => {
    const expanded = !state.customizeNavigation?.widgetChatExpanded;
    state.customizeNavigation = {
      ...(state.customizeNavigation || {}),
      widgetChatExpanded: expanded
    };
    frame.classList.toggle("is-widget-chat-expanded", expanded);
    event.currentTarget?.setAttribute?.("aria-expanded", expanded ? "true" : "false");
  });
  frame.querySelector("[data-sloppy-start-page-background]")?.addEventListener("change", (event) => {
    void readStartPageBackgroundImage(event.target.files?.[0], frame);
  });
  frame.querySelector("[data-sloppy-sidebar-collapse]")?.addEventListener("click", () => {
    state.sidebar = sidebarStateAfterCollapseToggle(state.sidebar);
    applySidebarState(frame);
  });
  frame.querySelector("[data-sloppy-sidebar-restore]")?.addEventListener("click", () => {
    state.sidebar = sidebarStateAfterCollapseToggle(state.sidebar);
    applySidebarState(frame);
  });
  wireSidebarResizer(frame);
  frame.querySelector("[data-sloppy-sidebar-new]")?.addEventListener("click", () => {
    closeCustomize(frame);
    state.messages = [];
    delete ensureSettings().sessionId;
    setStartPageMode(Boolean(globalThis.SloppyStartPageMode));
    render(frame);
  });
  frame.querySelector("[data-sloppy-sidebar-artifacts]")?.addEventListener("click", () => {
    const sessionList = frame.querySelector("[data-sloppy-sidebar-session-list]");
    if (sessionList) {
      sessionList.hidden = true;
    }
    openCustomize(frame);
    navigateCustomize(frame, "widgets");
    void loadArtifacts(frame);
  });
  frame.querySelector("[data-sloppy-sidebar-projects]")?.addEventListener("click", () => {
    appendMessage({ role: "assistant", label: t("assistant"), text: t("projectsUnavailable") });
    transitionStartPageToChat(frame);
    render(frame);
  });
  frame.querySelector("[data-sloppy-sidebar-sessions]")?.addEventListener("click", () => {
    const sessionList = frame.querySelector("[data-sloppy-sidebar-session-list]");
    if (sessionList && !sessionList.hidden) {
      sessionList.hidden = true;
      return;
    }
    void openSessions(frame, { presentation: "sidebar" });
  });
  wireSidebarChevronHover(frame.querySelector("[data-sloppy-sidebar-projects]"));
  wireSidebarChevronHover(frame.querySelector("[data-sloppy-sidebar-sessions]"));
  wireSidebarChevronHover(frame.querySelector("[data-sloppy-sidebar-artifacts]"));
  frame.querySelector("[data-sloppy-widget-picker]")?.addEventListener("click", (event) => {
    const button = event.target?.closest?.("[data-sloppy-pick-widget]");
    if (!button) {
      return;
    }
    void addWidgetToStartPage(frame, button.dataset.sloppyPickWidget);
  });
  frame.querySelector("[data-sloppy-generate-widget]")?.addEventListener("click", async () => {
    const prompt = frame.querySelector("[data-sloppy-describe-widget]")?.value?.trim() || "";
    if (prompt) {
      openWidgetEditor(frame);
      await updateWidgetDraftFromPrompt(frame, prompt);
    }
  });
  frame.querySelector("[data-sloppy-attach]").addEventListener("click", () => frame.querySelector("[data-sloppy-file]").click());
  frame.querySelector("[data-sloppy-file]").addEventListener("change", (event) => addFiles(event.target.files, frame));
  frame.querySelector("[data-sloppy-capture]")?.addEventListener("click", () => captureScreenshot(frame));
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
  frame.querySelector("[data-sloppy-voice-microphone]")?.addEventListener("change", (event) => {
    const deviceId = normalizeVoiceInputDeviceId(event.target.value);
    state.settings = {
      ...(state.settings || {}),
      voiceInputDeviceId: deviceId
    };
    if (!deviceId) {
      delete state.settings.voiceInputDeviceId;
    }
    state.voiceConfig = {
      ...state.voiceConfig,
      input: {
        ...(state.voiceConfig?.input || {}),
        deviceId
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
    renderAgentSetupWarning(frame);
    renderComposerAction(frame);
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

function applySidebarState(frame) {
  const sidebar = normalizeSidebarState(state.sidebar);
  state.sidebar = sidebar;
  frame.style.setProperty("--sloppy-sidebar-width", `${sidebar.width}px`);
  frame.querySelector("[data-sloppy-app-layout]")?.classList.toggle("is-sidebar-collapsed", sidebar.collapsed);
}

function wireSidebarResizer(frame) {
  const handle = frame.querySelector("[data-sloppy-sidebar-resizer]");
  if (!handle) {
    return;
  }
  let drag = null;
  const endDrag = () => {
    drag = null;
    document.removeEventListener("pointermove", onPointerMove);
    document.removeEventListener("pointerup", endDrag);
    document.removeEventListener("pointercancel", endDrag);
  };
  const onPointerMove = (event) => {
    if (!drag) {
      return;
    }
    state.sidebar = normalizeSidebarState({
      width: drag.width + event.clientX - drag.x,
      collapsed: false
    });
    applySidebarState(frame);
  };
  handle.addEventListener("pointerdown", (event) => {
    if (state.sidebar?.collapsed) {
      return;
    }
    drag = {
      x: event.clientX,
      width: normalizeSidebarState(state.sidebar).width
    };
    event.preventDefault?.();
    handle.setPointerCapture?.(event.pointerId);
    document.addEventListener("pointermove", onPointerMove);
    document.addEventListener("pointerup", endDrag);
    document.addEventListener("pointercancel", endDrag);
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
      deviceId: normalizeVoiceInputDeviceId(config.input?.deviceId),
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
  const deviceId = normalizeVoiceInputDeviceId(state.settings?.voiceInputDeviceId || config.input.deviceId);
  state.voiceConfig = {
    ...config,
    input: {
      ...config.input,
      language,
      deviceId
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
    const frame = document.getElementById("sloppy-safari-extension-panel");
    if (frame) {
      await refreshVoiceInputDevices(frame);
    }
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
  const stream = await navigator.mediaDevices.getUserMedia({ audio: voiceAudioConstraints(config.input.deviceId) });
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
  renderVoiceControls(frame);
  renderAgentSetupWarning(frame);
  if (isStartPageMode() && state.settings?.startPageEnabled !== false && !state.messages.length) {
    renderStartPageSurface(frame);
    renderAttachments(frame);
    renderComposerAction(frame);
    return;
  }
  renderThread(frame);
  renderContext(frame);
  renderAttachments(frame);
  renderComposerAction(frame);
  renderStartPageShortcuts(frame, []);
}

function transitionStartPageToChat(frame) {
  const isCustomizing = frame?.classList?.contains?.("is-start-customizing") || state.customizeNavigation?.editing;
  if (isCustomizing) {
    closeCustomize(frame);
  }
  if (!isStartPageMode()) {
    return;
  }
  setStartPageMode(false);
  frame.classList.remove("sloppy-theme-light");
}

function widgetEditorIsActive(frame) {
  return Boolean(frame?.classList?.contains?.("is-widget-editing") && state.customizeNavigation?.screen === "widget-editor");
}

function normalizeVoiceLanguage(value) {
  const language = String(value || "auto").trim();
  return ["auto", "en-US", "ru-RU", "zh-CN"].includes(language) ? language : "auto";
}

function normalizeVoiceInputDeviceId(value) {
  return String(value || "").trim();
}

function voiceAudioConstraints(deviceId) {
  const normalizedDeviceId = normalizeVoiceInputDeviceId(deviceId);
  if (!normalizedDeviceId) {
    return true;
  }
  return {
    deviceId: { exact: normalizedDeviceId }
  };
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

function renderVoiceControls(frame) {
  const select = frame.querySelector("[data-sloppy-voice-language]");
  if (select) {
    select.value = normalizeVoiceLanguage(state.settings?.voiceLanguage || state.voiceConfig?.input?.language);
  }
  renderVoiceMicrophone(frame);
}

function renderVoiceMicrophone(frame) {
  const select = frame.querySelector("[data-sloppy-voice-microphone]");
  if (!select) {
    return;
  }
  const selected = normalizeVoiceInputDeviceId(state.settings?.voiceInputDeviceId || state.voiceConfig?.input?.deviceId);
  const options = [
    { id: "", label: t("voiceMicrophoneDefault") },
    ...state.voiceInputDevices.map((device, index) => ({
      id: device.deviceId,
      label: device.label || `${t("voiceMicrophone")} ${index + 1}`
    }))
  ];
  select.innerHTML = options
    .map((device) => `<option value="${escapeHTML(device.id)}">${escapeHTML(device.label)}</option>`)
    .join("");
  select.value = options.some((device) => device.id === selected) ? selected : "";
}

async function refreshVoiceInputDevices(frame) {
  if (!navigator.mediaDevices?.enumerateDevices) {
    renderVoiceMicrophone(frame);
    return;
  }
  const devices = await navigator.mediaDevices.enumerateDevices().catch(() => []);
  state.voiceInputDevices = devices.filter((device) => device.kind === "audioinput" && device.deviceId);
  renderVoiceMicrophone(frame);
}

function composerHasPayload(frame) {
  const prompt = frame.querySelector("[data-sloppy-prompt]")?.value?.trim() || "";
  return Boolean(prompt || state.attachments.length);
}

function renderComposerAction(frame) {
  const hasPayload = composerHasPayload(frame);
  const action = frame.querySelector("[data-sloppy-primary-action]");
  const canSend = isAgentConfigured();
  if (action) {
    const isSendDisabled = hasPayload && !canSend;
    action.innerHTML = icon(hasPayload ? "arrow-up" : "mic");
    action.disabled = Boolean(isSendDisabled);
    action.setAttribute?.("aria-label", hasPayload ? (canSend ? t("send") : t("agentNotConfiguredTitle")) : t("voiceMode"));
    action.dataset.sloppyAction = hasPayload ? "send" : "voice";
  }
}

function renderThread(frame) {
  const thread = frame.querySelector("[data-sloppy-thread]");
  if (!state.messages.length) {
    thread.innerHTML = `
      <div class="sloppy-empty" data-sloppy-empty>
        <img class="sloppy-empty-mark" src="${logoURL()}" alt="" aria-hidden="true">
        <h2>${escapeHTML(t("assistant"))}</h2>
      </div>
    `;
    return;
  }
  thread.innerHTML = state.messages.map(renderMessage).join("");
  thread.scrollTop = thread.scrollHeight;
}

function formatStreamingElapsed(milliseconds = 0) {
  const seconds = Math.round((Math.max(0, Number(milliseconds) || 0) / 1000) * 10) / 10;
  return `${seconds.toFixed(1)}s`;
}

function assistantElapsedText(message, now = Date.now()) {
  if (message.role !== "assistant") {
    return "";
  }
  if (typeof message.elapsedMs === "number") {
    return formatStreamingElapsed(message.elapsedMs);
  }
  if (message.streaming && typeof message.startedAt === "number") {
    return formatStreamingElapsed(now - message.startedAt);
  }
  return "";
}

function renderMessage(message) {
  const attachments = message.attachments?.length
    ? `<div class="sloppy-message-attachments">${message.attachments.map(renderAttachmentChip).join("")}</div>`
    : "";
  const tools = message.toolCalls?.length ? `<div class="sloppy-tools">${message.toolCalls.map(renderToolCall).join("")}</div>` : "";
  const elapsed = assistantElapsedText(message);
  const thinking = message.role === "assistant" && message.streaming && !message.text
    ? `<div class="sloppy-thinking" aria-label="${escapeHTML(t("thinking"))}"><span>${escapeHTML(t("thinking"))}</span></div>`
    : "";
  const body = message.role === "assistant"
    ? `${thinking}<div class="sloppy-markdown">${renderMarkdown(message.text || "")}</div>`
    : `<p>${escapeHTML(message.text || "")}</p>`;
  const meta = message.role === "assistant"
    ? (elapsed ? `<div class="sloppy-message-meta sloppy-message-meta-assistant">${escapeHTML(elapsed)}</div>` : "")
    : `<div class="sloppy-message-meta">${escapeHTML(message.label || message.role)}</div>`;
  return `
    <article class="sloppy-message sloppy-message-${message.role}">
      ${meta}
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
  const fallbackContextIcon = typeof chrome !== "undefined" && chrome.runtime?.getURL ? chrome.runtime.getURL("icons/globe.svg") : "icons/globe.svg";
  const pageIcon = shortcutIconURL(context?.page?.url);
  const root = frame.querySelector("[data-sloppy-context]");
  root.classList.toggle("is-collapsed", state.contextCollapsed);
  root.innerHTML = `
    <div class="sloppy-context-row" data-sloppy-context-toggle>
      <img class="sloppy-context-favicon" data-sloppy-context-favicon src="${escapeHTML(pageIcon || fallbackContextIcon)}" alt="" aria-hidden="true">
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
  const contextFavicon = root.querySelector("[data-sloppy-context-favicon]");
  contextFavicon?.addEventListener("error", (event) => {
    const image = event.currentTarget;
    if (image?.dataset?.fallback !== "1") {
      image.dataset.fallback = "1";
      image.src = fallbackContextIcon;
    }
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
  Array.from(frame.querySelectorAll?.("[data-sloppy-remove-attachment-id]") || []).forEach((button) => {
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

function openPanelDialog(dialog) {
  if (!dialog || dialog.open) {
    return;
  }
  if (typeof dialog.show === "function") {
    dialog.show();
    return;
  }
  dialog.setAttribute?.("open", "");
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
  openPanelDialog(frame.querySelector("[data-sloppy-settings-dialog]"));
}

async function saveSettings(frame) {
  const settings = {
    coreURLString: frame.querySelector("[data-sloppy-core-url]").value,
    authToken: frame.querySelector("[data-sloppy-auth-token]").value,
    defaultAgentID: frame.querySelector("[data-sloppy-default-agent]").value,
    selectedModel: state.settings?.selectedModel || "",
    voiceLanguage: normalizeVoiceLanguage(state.settings?.voiceLanguage),
    voiceInputDeviceId: normalizeVoiceInputDeviceId(state.settings?.voiceInputDeviceId),
    sessionId: state.settings?.sessionId || null,
    mesh: {
      ...(state.settings?.mesh || {}),
      enabled: frame.querySelector("[data-sloppy-mesh-enabled]").checked,
      targetNodeId: frame.querySelector("[data-sloppy-mesh-target-node]").value
    },
    floatingButtonEnabled: frame.querySelector("[data-sloppy-floating-button]").checked,
    selectionBubbleEnabled: frame.querySelector("[data-sloppy-selection-bubble-enabled]").checked,
    startPageEnabled: state.settings?.startPageEnabled !== false,
    startPageTheme: state.settings?.startPageTheme || "dark",
    startPageBackgroundImage: state.settings?.startPageBackgroundImage || "",
    startPageShortcuts: startPageShortcutItems(state.settings),
    startPageItems: state.settings?.startPageItems || []
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

async function openSessions(frame, options = {}) {
  const presentation = options.presentation || "sidebar";
  const list = sessionListRoot(frame, presentation);
  const dialog = presentation === "dialog" ? frame.querySelector("[data-sloppy-sessions-dialog]") : null;
  list.innerHTML = `<p class="sloppy-session-empty">${escapeHTML(t("loadingSessions"))}</p>`;
  list.hidden = false;
  openPanelDialog(dialog);

  const response = await chrome.runtime.sendMessage({
    type: "sloppy.sessions.list",
    agentId: state.settings?.defaultAgentID || "sloppy"
  }).catch((error) => ({ error: error?.message || t("sessionsUnavailable") }));
  if (response?.error) {
    list.innerHTML = `<p class="sloppy-session-empty">${escapeHTML(response.error)}</p>`;
    return;
  }
  state.sessions = response?.sessions || [];
  if (response?.selectedSessionId) {
    ensureSettings().sessionId = response.selectedSessionId;
  }
  renderSessionList(frame, { presentation });
  if (frame.querySelector("[data-sloppy-context]")?.querySelector) {
    renderContext(frame);
  }
}

function sessionListRoot(frame, presentation = "sidebar") {
  if (presentation === "dialog") {
    return frame.querySelector("[data-sloppy-session-list]") || frame.querySelector("[data-sloppy-sidebar-session-list]");
  }
  return frame.querySelector("[data-sloppy-sidebar-session-list]") || frame.querySelector("[data-sloppy-session-list]");
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

function commandSuggestions(query, limit = Infinity) {
  const normalized = String(query || "").toLowerCase();
  const maxSuggestions = Number.isFinite(Number(limit)) ? Math.max(1, Math.floor(Number(limit))) : state.slashCommands.length;
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
    .slice(0, maxSuggestions);
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

function panelFocusableControlFromEvent(event) {
  const selector = "input, textarea, select, button, a[href], [tabindex]:not([tabindex='-1'])";
  const target = event.target;
  const directControl = target?.closest?.(selector);
  if (directControl) {
    return directControl;
  }
  const labelControl = target?.closest?.("label")?.querySelector?.("input, textarea, select");
  return labelControl || null;
}

function focusPanelControlFromEvent(event) {
  const control = panelFocusableControlFromEvent(event);
  if (!control || control.disabled || control.hidden) {
    return;
  }
  control.focus?.({ preventScroll: true });
}

function slashHelpText() {
  const lines = state.slashCommands.length
    ? state.slashCommands.map((command) => `/${command.name} - ${command.description || command.argument || "Command"}`)
    : ["/help - Show available commands"];
  return `Available commands:\n${lines.join("\n")}\n\nAny other message is forwarded to the agent.`;
}

function renderSessionList(frame, options = {}) {
  const selectedSessionId = state.settings?.sessionId || "";
  const list = sessionListRoot(frame, options.presentation || "sidebar");
  if (!list) {
    return;
  }
  list.hidden = false;
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
  frame.querySelector("[data-sloppy-sessions-dialog]")?.close();
  transitionStartPageToChat(frame);
  render(frame);
}

async function loadSessionSelection(sessionId) {
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.sessions.select",
    sessionId: sessionId || "",
    agentId: state.settings?.defaultAgentID || "sloppy"
  }).catch((error) => ({ error: error?.message || t("sessionsUnavailable") }));
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
  await Promise.all([
    loadAgents(panel),
    loadModels(panel),
    refreshTabs(panel),
    loadSlashCommands(panel),
    openSessions(panel, { presentation: "sidebar" })
  ]);
  render(panel);
  renderFloatingButton();
  renderSearchButton();
  return panel;
}

async function sendSelectionPrompt(prompt, title = t("assistant")) {
  const selection = state.selectionMenuText || selectedText();
  if (!selection.trim()) {
    return;
  }
  await openQuickChatForPrompt(prompt, {
    selection,
    title,
    userText: selection,
    anchorRect: state.selectionMenuRect
  });
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
  const response = await chrome.runtime.sendMessage({ type: "sloppy.tabs.list" }).catch(() => ({ tabs: [] }));
  state.tabs = response?.tabs || [];
  renderContext(frame);
}

async function loadAgents(frame) {
  const response = await chrome.runtime.sendMessage({ type: "sloppy.agents.list" }).catch(() => ({ agents: [] }));
  state.agents = response?.agents || [];
  state.agentsLoaded = true;
  if (response?.selectedAgentId) {
    ensureSettings().defaultAgentID = response.selectedAgentId;
  }
  renderAgents(frame);
  renderAgentSetupWarning(frame);
  renderComposerAction(frame);
}

function isAgentConfigured() {
  const selectedAgentId = String(state.settings?.defaultAgentID || "").trim();
  if (!selectedAgentId) {
    return false;
  }
  if (!state.agentsLoaded) {
    return true;
  }
  return state.agents.some((agent) => String(agent.id || "") === selectedAgentId);
}

function renderAgentSetupWarning(frame) {
  const warning = frame.querySelector("[data-sloppy-agent-warning]");
  if (!warning) {
    return;
  }
  const configured = isAgentConfigured();
  warning.hidden = configured;
  if (configured) {
    return;
  }
  warning.innerHTML = `
    <strong>${escapeHTML(t("agentNotConfiguredTitle"))}</strong>
    <span>${escapeHTML(t("agentNotConfiguredBody"))}</span>
  `;
}

async function loadModels(frame) {
  const response = await chrome.runtime.sendMessage({ type: "sloppy.models.list" }).catch(() => ({ models: [] }));
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
  }).catch(() => null);
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
    streaming: Boolean(message.streaming),
    startedAt: message.startedAt ?? (message.streaming ? Date.now() : null),
    elapsedMs: typeof message.elapsedMs === "number" ? message.elapsedMs : null
  });
}

function stopStreamingStatusTimer() {
  if (state.streamingStatusTimer) {
    const clearTimer = window.clearTimeout?.bind(window) || globalThis.clearTimeout?.bind(globalThis) || (() => {});
    clearTimer(state.streamingStatusTimer);
    state.streamingStatusTimer = null;
  }
}

function startStreamingStatusTimer(frame) {
  if (!frame || state.streamingStatusTimer) {
    return;
  }
  const setTimer = window.setTimeout?.bind(window) || globalThis.setTimeout?.bind(globalThis);
  if (!setTimer) {
    return;
  }
  const tick = () => {
    if (!state.messages.some((message) => message.streaming && message.role === "assistant")) {
      state.streamingStatusTimer = null;
      return;
    }
    render(frame);
    state.streamingStatusTimer = setTimer(tick, 100);
  };
  state.streamingStatusTimer = setTimer(tick, 100);
}

function completeAssistantStreaming(message) {
  if (!message) {
    return;
  }
  message.elapsedMs = typeof message.startedAt === "number"
    ? Math.max(0, Date.now() - message.startedAt)
    : 0;
  message.streaming = false;
  stopStreamingStatusTimer();
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
    completeAssistantStreaming(message);
  }
  if (event.type === "complete") {
    const finalText = agentResponseText(event.body, message.text);
    await animateAssistantText(message, finalText, frame);
    applyAgentResponse(message, { ...event.body, text: finalText });
    await rememberSession(event.body, frame);
    await performAgentBrowserActions(event.body, message);
    completeAssistantStreaming(message);
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
    } else if (message.streaming) {
      return;
    }
    completeAssistantStreaming(message);
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
  if (!isAgentConfigured()) {
    renderAgentSetupWarning(frame);
    return;
  }
  const textarea = frame.querySelector("[data-sloppy-prompt]");
  const prompt = textarea.value.trim();
  if (!prompt && !state.attachments.length) {
    return;
  }
  if (widgetEditorIsActive(frame)) {
    hideCommandMenu(frame);
    const userAttachments = [...state.attachments];
    appendMessage({ role: "user", label: t("you"), text: prompt, attachments: userAttachments });
    textarea.value = "";
    textarea.style.height = "auto";
    state.attachments = [];
    const assistantId = globalThis.crypto?.randomUUID?.() || `${Date.now()}-assistant`;
    appendMessage({ id: assistantId, role: "assistant", label: t("assistant"), text: "", streaming: true });
    render(frame);
    startStreamingStatusTimer(frame);

    const result = typeof updateWidgetDraftFromPrompt === "function"
      ? await updateWidgetDraftFromPrompt(frame, prompt)
      : { error: "Widget editor is unavailable." };
    const message = state.messages.find((candidate) => candidate.id === assistantId);
    if (message) {
      message.text = result?.error || result?.text || t("widgetPreviewUpdated");
      completeAssistantStreaming(message);
    }
    render(frame);
    return;
  }
  transitionStartPageToChat(frame);
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
  startStreamingStatusTimer(frame);

  const requestId = globalThis.crypto?.randomUUID?.() || `${Date.now()}-request`;
  state.streamingRequestId = requestId;
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.browserContext.stream",
    requestId,
    sessionId: state.settings?.sessionId || "",
    page: state.context.page,
    selection: state.context.selection,
    prompt,
    tabs: state.tabs,
    attachments: userAttachments,
    model: state.settings?.selectedModel || "default"
  });
  const message = state.messages.find((candidate) => candidate.id === assistantId);
  if (response?.error) {
    stopStreamingAnimation();
    message.text = response.error;
    completeAssistantStreaming(message);
  } else {
    const finalText = agentResponseText(response, message.text);
    await animateAssistantText(message, finalText, frame);
    applyAgentResponse(message, { ...response, text: finalText });
    await rememberSession(response, frame);
    await performAgentBrowserActions(response, message);
    completeAssistantStreaming(message);
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

async function initializeStartPage() {
  setStartPageMode(true);
  state.context = {
    page: { url: document.location?.href || "", title: document.title || t("startPage") },
    selection: ""
  };
  state.settings = state.settings || await chrome.runtime.sendMessage({ type: "sloppy.settings.get" }).catch(() => ({}));
  const panel = ensurePanel();
  await Promise.allSettled([loadAgents(panel), loadModels(panel), loadSlashCommands(panel)]);
  render(panel);
  await openSessions(panel);
  return panel;
}

async function initializeFullscreenChat() {
  document.documentElement.classList.add("sloppy-fullscreen-chat-page");
  const launch = chatLaunchOptionsFromURL(document.location.href);
  state.fullscreenLaunch = launch;
  state.context = {
    page: launch.page,
    selection: launch.selection || ""
  };
  state.settings = state.settings || await chrome.runtime.sendMessage({ type: "sloppy.settings.get" }).catch(() => ({}));
  if (launch.sessionId) {
    state.settings.sessionId = launch.sessionId;
  }
  const panel = ensurePanel();
  await Promise.allSettled([loadAgents(panel), loadModels(panel), refreshTabs(panel), loadSlashCommands(panel)]);
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
  } else if (!isMobileViewport(window)) {
    panel.querySelector("[data-sloppy-prompt]").focus();
  }
}

if (typeof document !== "undefined" && typeof chrome !== "undefined" && chrome.runtime?.onMessage) {
  updateViewportCSSVars();
  applyRotatingChatPlaceholders(document);
  window.setInterval?.(() => applyRotatingChatPlaceholders(document), 3200);
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
    if (!isFullscreenChatPage(document.location) && !isStartPageMode() && matchesPanelToggleShortcut(event)) {
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
  } else if (isStartPageMode()) {
    void initializeStartPage();
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
        await openQuickChatForPrompt(summarizePagePrompt(), {
          selection: selectedText(),
          title: t("summarizePage"),
          anchorRect: selectedTextInfo()?.rect || state.selectionMenuRect
        });
      })();
      return;
    }
    if (message?.type === "sloppy.browserContext.streamEvent" && message.requestId === state.streamingRequestId) {
      const panel = document.getElementById("sloppy-safari-extension-panel");
      void updateStreamingMessage(message.event || {}, panel);
      return;
    }
    if (message?.type === "sloppy.browserContext.streamEvent" && message.requestId === state.quickChat?.requestId) {
      void updateQuickChatStreaming(message.event || {});
    }
  });
}
