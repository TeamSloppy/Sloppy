// Selection capture, delayed bubble and cached popover follow SloppySafari's contentScript.js.
// This script runs in a private WKContentWorld. Page text never becomes HTML or executable code.
(() => {
  if (globalThis.__sloppyBrowserSelection) return;
  const host = document.createElement("div");
  host.id = "sloppy-browser-selection";
  host.setAttribute("data-sloppy-browser-overlay", "selection");
  const root = host.attachShadow({ mode: "closed" });
  // Constructed sheets keep browser-owned UI independent of the site's inline-style CSP.
  const sheet = new CSSStyleSheet();
  sheet.replaceSync(`
      :host{all:initial;position:fixed;inset:0;z-index:2147483647;pointer-events:none;font:14px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#e8e6e3;color-scheme:dark}
      [hidden]{display:none!important}button,input{font:inherit;box-sizing:border-box}button{cursor:pointer}
      #bubble{position:absolute;width:20px;height:20px;border:1px solid #4a4a4a;border-radius:50%;background:#2b2b2b;color:#e8e6e3;pointer-events:auto;display:grid;place-items:center;padding:2px;transform-origin:center;transition:transform 120ms ease-out,background-color 120ms ease-out}
      #bubble svg{display:block;width:14px;height:14px;pointer-events:none}
      #bubble:hover{transform:scale(1.1);background:#3a3a3a}
      #bubble:focus-visible,button:focus-visible,input:focus-visible{outline:2px solid #929292;outline-offset:2px}
      #menu{box-sizing:border-box;position:absolute;width:300px;max-width:calc(100vw - 24px);padding:10px;border:1px solid #444;border-radius:12px;background:#252525;box-shadow:0 8px 24px #0005;pointer-events:auto}
      form{display:flex;gap:6px;margin-bottom:8px}input{min-width:0;flex:1;padding:9px;border:1px solid #444;border-radius:7px;background:#1f1f1f;color:inherit;caret-color:#e8e6e3}input::placeholder{color:#979591;opacity:1}
      #submit{border:0;border-radius:7px;background:#3b3b3b;color:#e8e6e3;padding:8px 10px}
      .action{display:block;width:100%;text-align:left;padding:8px;border:0;border-radius:6px;background:transparent;color:inherit}
      .action:hover{background:#383838}.divider{height:1px;background:#444;margin:6px 0}#status{font-size:12px;margin:6px;color:#e3a19a}
      @media(prefers-reduced-motion:reduce){#bubble{transition:none}}
  `);
  root.adoptedStyleSheets = [sheet];
  root.innerHTML = `
    <button id="bubble" hidden aria-label="Ask Sloppy about selection" title="Ask Sloppy about selection">
      <svg viewBox="0 0 66 66" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
<mask id="sloppySelectionIconMask" maskUnits="userSpaceOnUse" x="0" y="0" width="66" height="66">
<rect width="66" height="66" rx="8" fill="white"/>
</mask>
<g mask="url(#sloppySelectionIconMask)" fill="currentColor">
<path d="M66 -4V13.0262C66 13.8453 65.0699 14.3364 64.3926 13.8756C59.5423 10.5755 44.6691 1.13884 33 1C21.3401 0.861269 6.48106 10.4632 1.61882 13.8421C0.941775 14.3126 0 13.8221 0 12.9977V-4C0 -4.55228 0.447714 -5 0.999999 -5H65C65.5523 -5 66 -4.55228 66 -4Z"/>
<path d="M49.3243 54.7027L59.3243 45.5361C59.9657 44.9481 61 45.4031 61 46.2732V54.5316C61 54.8284 60.8682 55.1099 60.6402 55.2998L55.3598 59.7002C55.1318 59.8901 55 60.1716 55 60.4684V65C55 65.5523 54.5523 66 54 66H50C49.4477 66 49 65.5523 49 65V55.4399C49 55.1596 49.1176 54.8922 49.3243 54.7027Z"/>
<path d="M15.6757 54.7027L5.67572 45.5361C5.03432 44.9481 4 45.4031 4 46.2732V54.5316C4 54.8284 4.13182 55.1099 4.35982 55.2998L9.64018 59.7002C9.86818 59.8901 10 60.1716 10 60.4684V65C10 65.5523 10.4477 66 11 66H15C15.5523 66 16 65.5523 16 65V55.4399C16 55.1596 15.8824 54.8922 15.6757 54.7027Z"/>
<circle cx="32.5" cy="27.5" r="20.5" fill="none" stroke="currentColor" stroke-width="4"/>
<rect x="21" y="55" width="23" height="19" rx="3"/>
<path d="M29.0005 12C30.5801 12.0001 32.0814 12.3183 33.4386 12.8911C34.7115 13.4283 33.8821 15 32.5005 15C27.0751 15 22.397 18.0819 20.2514 22.5268C19.6875 23.6951 18.0005 23.7973 18.0005 22.5C18.0005 16.701 22.9254 12 29.0005 12Z"/>
</g>
</svg>
    </button>
    <div id="menu" hidden role="dialog" aria-label="Selection actions">
      <form><input id="prompt" placeholder="Ask about this selection…" aria-label="Ask about this selection" autocomplete="off"><button id="submit" aria-label="Prepare agent request">↑</button></form>
      <button class="action" id="annotate" hidden>Add as annotation</button>
      <button class="action" data-command="fact-check">Fact check</button>
      <button class="action" data-command="define">Define</button>
      <button class="action" data-command="summarize">Summarize</button>
      <button class="action" data-command="translate">Translate</button>
      <div class="divider"></div><button class="action" id="hide">Hide</button><p id="status" hidden role="status"></p>
    </div>`;
  const bubble = root.querySelector("#bubble");
  const menu = root.querySelector("#menu");
  const prompt = root.querySelector("#prompt");
  const annotate = root.querySelector("#annotate");
  const status = root.querySelector("#status");
  let cached = null;
  let timer;
  let sequence = 0;
  let dragging = false;

  function hide() {
    clearTimeout(timer);
    bubble.hidden = true;
    menu.hidden = true;
    cached = null;
  }
  function selectionInfo() {
    const selection = getSelection();
    const text = String(selection || "").trim();
    if (!text || !selection.rangeCount || text.length > 12000) return null;
    const excluded = node => {
      const element = node?.nodeType === Node.TEXT_NODE ? node.parentElement : node;
      return element?.closest?.("input,textarea,[contenteditable]:not([contenteditable='false']),#sloppy-browser-selection");
    };
    if (excluded(selection.anchorNode) || excluded(selection.focusNode)) return null;
    const range = selection.getRangeAt(selection.rangeCount - 1);
    const rect = [...range.getClientRects()].filter(r => r.width > 0 && r.height > 0).at(-1) || range.getBoundingClientRect();
    if (!rect || !rect.width || !rect.height) return null;
    return { text, rect, pageURL: location.href, title: document.title, requestID: ++sequence };
  }
  function place() {
    if (!cached) return;
    const { rect } = cached;
    const size = bubble.offsetWidth || 20;
    const left = Math.max(10, Math.min(rect.right - size / 2, innerWidth - size - 10));
    const top = Math.max(10, Math.min(rect.bottom + 8, innerHeight - size - 10));
    bubble.style.left = left + "px";
    bubble.style.top = top + "px";
    if (!menu.hidden) {
      menu.style.left = Math.max(12, Math.min(left, innerWidth - menu.offsetWidth - 12)) + "px";
      const y = innerHeight - top - size - 6 < menu.offsetHeight ? rect.top - menu.offsetHeight - 8 : top + size + 6;
      menu.style.top = Math.max(12, Math.min(y, innerHeight - menu.offsetHeight - 12)) + "px";
    }
  }
  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(() => {
      if (dragging || !menu.hidden) return;
      cached = selectionInfo();
      if (!cached) { hide(); return; }
      if (!host.isConnected) document.documentElement.append(host);
      bubble.hidden = false;
      place();
    }, 80);
  }
  function send(action, extra = {}) {
    if (!cached) return;
    window.webkit.messageHandlers.sloppyBrowserSelection.postMessage({ action, requestID: cached.requestID, ...extra });
  }
  bubble.addEventListener("pointerdown", event => { event.preventDefault(); event.stopPropagation(); });
  bubble.addEventListener("click", () => {
    if (!cached) return;
    menu.hidden = false;
    annotate.hidden = true;
    status.hidden = true;
    place();
    send("open", { text: cached.text, pageURL: cached.pageURL, title: cached.title });
    prompt.focus();
  });
  annotate.addEventListener("click", () => send("annotate", { prompt: prompt.value.trim() }));
  root.querySelector("form").addEventListener("submit", event => {
    event.preventDefault();
    if (prompt.value.trim()) send("ask", { command: "custom", prompt: prompt.value.trim() });
  });
  root.querySelectorAll("[data-command]").forEach(button => {
    button.addEventListener("click", () => send("ask", { command: button.dataset.command }));
  });
  root.querySelector("#hide").addEventListener("click", hide);
  document.addEventListener("selectionchange", schedule);
  document.addEventListener("pointerdown", event => {
    if (event.composedPath().includes(host)) return;
    dragging = true;
    hide();
  }, true);
  document.addEventListener("pointerup", () => { dragging = false; schedule(); }, true);
  document.addEventListener("pointercancel", () => { dragging = false; schedule(); }, true);
  document.addEventListener("keydown", event => { if (event.key === "Escape") hide(); }, true);
  window.addEventListener("scroll", hide, true);
  window.addEventListener("resize", hide);
  window.addEventListener("pagehide", hide);
  globalThis.__sloppyBrowserSelection = {
    hide,
    reply(requestID, available, error = "") {
      if (!cached || cached.requestID !== requestID) return;
      annotate.hidden = !available;
      status.textContent = error;
      status.hidden = !error;
      place();
    }
  };
})();
