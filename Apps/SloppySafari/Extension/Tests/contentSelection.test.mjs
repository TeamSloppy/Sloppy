import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

function loadContentScriptSandbox() {
  const i18nSource = readFileSync(new URL("../Resources/i18n.js", import.meta.url), "utf8");
  const startPageCustomizeSource = readFileSync(new URL("../Resources/startPageCustomize.js", import.meta.url), "utf8");
  const source = readFileSync(new URL("../Resources/contentScript.js", import.meta.url), "utf8");
  assert.equal(/\bexport\s+function\b/.test(source), false);
  assert.equal(/\bexport\s+function\b/.test(startPageCustomizeSource), false);

  const sandbox = {
    chrome: undefined,
    document: undefined,
    navigator: { language: "en-US", languages: ["en-US"] },
    requestAnimationFrame(callback) {
      callback();
    },
    URL,
    window: {},
    globalThis: {}
  };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(i18nSource, sandbox);
  vm.runInNewContext(startPageCustomizeSource, sandbox);
  vm.runInNewContext(source, sandbox);
  return sandbox;
}

function loadContentScriptSandboxWithLocale(language) {
  const sandbox = loadContentScriptSandbox();
  sandbox.navigator = { language, languages: [language] };
  vm.runInNewContext("SloppyI18n.systemLocale(navigator);", sandbox);
  return sandbox;
}

function createPanelDocument() {
  const appended = [];
  const elementsById = new Map();

  function makeElement(tagName) {
    let html = "";
    const nodesBySelector = new Map();
    const ensureNode = (selector) => {
      if (!nodesBySelector.has(selector)) {
        const listeners = new Map();
        const toggled = new Map();
        nodesBySelector.set(selector, {
          selector,
          value: "",
          checked: false,
          textContent: "",
          innerHTML: "",
          hidden: false,
          style: {},
          dataset: {},
          classList: {
            toggled,
            toggle(name, force) {
              toggled.set(name, Boolean(force));
            },
            add(name) {
              toggled.set(name, true);
            },
            remove(name) {
              toggled.set(name, false);
            },
            contains(name) {
              return toggled.get(name) === true;
            }
          },
          listeners,
          addEventListener(type, listener) {
            listeners.set(type, listener);
          },
          removeEventListener(type) {
            listeners.delete(type);
          },
          appendChild() {},
          insertAdjacentHTML(_position, value) {
            this.innerHTML += String(value || "");
          },
          remove() {
            this.removed = true;
          },
          focus() {
            this.focusCount = (this.focusCount || 0) + 1;
          },
          async click() {
            const listener = listeners.get("click");
            if (listener) {
              return await listener({ currentTarget: this, preventDefault() {} });
            }
            return undefined;
          },
          showModal() {
            this.showModalCalled = true;
          },
          close() {
            this.closeCalled = true;
          },
          querySelector(selector) {
            const dataMatch = selector.match(/^\[([^\]]+)\]$/);
            if (!dataMatch) {
              return null;
            }
            return ensureNode(selector);
          },
          querySelectorAll(selector) {
            if (selector === "[data-sloppy-select-session]") {
              return Array.from(html.matchAll(/data-sloppy-select-session="([^"]*)"/g)).map((match) => {
                const node = ensureNode(`[data-sloppy-select-session="${match[1]}"]`);
                node.dataset.sloppySelectSession = match[1];
                return node;
              });
            }
            return [];
          }
        });
      }
      return nodesBySelector.get(selector);
    };
    return {
      tagName: String(tagName || "").toUpperCase(),
      id: "",
      style: { setProperty() {} },
      classList: {
        toggled: new Map(),
        toggle(name, force) {
          this.toggled.set(name, Boolean(force));
        },
        add(name) {
          this.toggled.set(name, true);
        },
        remove(name) {
          this.toggled.set(name, false);
        },
        contains(name) {
          return this.toggled.get(name) === true;
        }
      },
      addEventListener() {},
      set innerHTML(value) {
        html = String(value || "");
        for (const match of html.matchAll(/data-[a-z0-9-]+/g)) {
          ensureNode(`[${match[0]}]`);
        }
      },
      get innerHTML() {
        return html;
      },
      querySelector(selector) {
        const dataMatch = selector.match(/^\[([^\]]+)\]$/);
        if (!dataMatch) {
          return null;
        }
        return html.includes(dataMatch[1]) ? ensureNode(selector) : null;
      },
      querySelectorAll(selector) {
        if (selector === ".sloppy-symbol") {
          return [];
        }
        return [];
      }
    };
  }

  return {
    appended,
    elementsById,
    location: { href: "https://example.com/page" },
    title: "Example Page",
    documentElement: {
      style: { setProperty() {} },
      classList: { toggle() {}, add() {}, remove() {} },
      appendChild(node) {
        appended.push(node);
        if (node?.id) {
          elementsById.set(node.id, node);
        }
      }
    },
    getElementById(id) {
      return elementsById.get(id) || null;
    },
    createElement(tagName) {
      return makeElement(tagName);
    }
  };
}

test("extractPageContext trims selected text and reads page metadata", () => {
  const { extractPageContext } = loadContentScriptSandbox();
  const context = extractPageContext(
    {
      location: { href: "https://example.com/page" },
      title: "Example Page"
    },
    "  Selected text  "
  );

  assert.equal(context.page.url, "https://example.com/page");
  assert.equal(context.page.title, "Example Page");
  assert.equal(context.selection, "Selected text");
});

test("contextWithSelection updates only the chat context selection", () => {
  const { contextWithSelection } = loadContentScriptSandbox();
  const context = {
    page: { url: "https://example.com", title: "Example" },
    selection: ""
  };
  const updated = contextWithSelection(context, "Fresh selection");

  assert.equal(updated.page.url, "https://example.com");
  assert.equal(updated.selection, "Fresh selection");
  assert.equal(context.selection, "");
});

test("selectionActionPrompt maps quick actions to agent prompts", () => {
  const { selectionActionPrompt } = loadContentScriptSandbox();

  assert.equal(selectionActionPrompt("fact-check"), "Fact check the selected text.");
  assert.equal(selectionActionPrompt("define"), "Define the selected text.");
  assert.equal(selectionActionPrompt("summarize"), "Summarize the selected text.");
  assert.equal(selectionActionPrompt("translate"), "Translate the selected text.");
  assert.equal(selectionActionPrompt("unknown"), "");
});

test("selectionBubbleEnabled defaults on and can be disabled", () => {
  const { selectionBubbleEnabled } = loadContentScriptSandbox();

  assert.equal(selectionBubbleEnabled({}), true);
  assert.equal(selectionBubbleEnabled(null), true);
  assert.equal(selectionBubbleEnabled({ selectionBubbleEnabled: false }), false);
});

test("searchQueryInfo extracts supported search page queries", () => {
  const { searchQueryInfo } = loadContentScriptSandbox();

  assert.equal(JSON.stringify(searchQueryInfo("https://www.google.com/search?q=swift+testing")), JSON.stringify({
    engine: "google",
    query: "swift testing"
  }));
  assert.equal(JSON.stringify(searchQueryInfo("https://www.bing.com/search?q=sloppy+agent")), JSON.stringify({
    engine: "bing",
    query: "sloppy agent"
  }));
  assert.equal(JSON.stringify(searchQueryInfo("https://yandex.ru/search/?text=сафари+расширение")), JSON.stringify({
    engine: "yandex",
    query: "сафари расширение"
  }));
  assert.equal(JSON.stringify(searchQueryInfo("https://duckduckgo.com/?q=browser+chat")), JSON.stringify({
    engine: "duckduckgo",
    query: "browser chat"
  }));
  assert.equal(searchQueryInfo("https://example.com/?q=not-search"), null);
});

test("keyboard shortcut helpers match only the intended combinations", () => {
  const { matchesPanelToggleShortcut, matchesCommandPaletteShortcut } = loadContentScriptSandbox();

  assert.equal(matchesPanelToggleShortcut({ key: "a", altKey: true }), true);
  assert.equal(matchesPanelToggleShortcut({ key: "A", altKey: true }), true);
  assert.equal(matchesPanelToggleShortcut({ key: "å", code: "KeyA", altKey: true }), true);
  assert.equal(matchesPanelToggleShortcut({ key: "a", altKey: true, metaKey: true }), false);
  assert.equal(matchesCommandPaletteShortcut({ key: "p", metaKey: true, shiftKey: true }), true);
  assert.equal(matchesCommandPaletteShortcut({ key: "P", metaKey: true, shiftKey: true }), true);
  assert.equal(matchesCommandPaletteShortcut({ key: "P", code: "KeyP", metaKey: true, shiftKey: true }), true);
  assert.equal(matchesCommandPaletteShortcut({ key: "p", metaKey: true }), false);
});

test("buildChatURL encodes fullscreen chat launch parameters", () => {
  const { buildChatURL } = loadContentScriptSandbox();
  const url = new URL(buildChatURL("safari-extension://sloppy/chat.html", {
    prompt: "Ask Sloppy",
    selection: "Selected text",
    page: { url: "https://example.com/search?q=test", title: "Search" },
    sessionId: "session-1"
  }));

  assert.equal(url.pathname, "/chat.html");
  assert.equal(url.searchParams.get("prompt"), "Ask Sloppy");
  assert.equal(url.searchParams.get("selection"), "Selected text");
  assert.equal(url.searchParams.get("pageURL"), "https://example.com/search?q=test");
  assert.equal(url.searchParams.get("pageTitle"), "Search");
  assert.equal(url.searchParams.get("sessionId"), "session-1");
});

test("openFullscreenChat falls back when the background tab opener fails", async () => {
  const sandbox = loadContentScriptSandbox();
  const opened = [];
  sandbox.document = {
    location: { href: "https://example.com/page" },
    title: "Example Page"
  };
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      async sendMessage(message) {
        assert.equal(message.type, "sloppy.tabs.open");
        return { error: "Unable to open tab." };
      }
    }
  };
  sandbox.window = {
    open(url, target, features) {
      opened.push({ url, target, features });
    }
  };

  await sandbox.openFullscreenChat({
    selection: "Selected text",
    page: { url: "https://example.com/page", title: "Example Page" },
    sessionId: "session-1"
  });

  assert.equal(opened.length, 1);
  assert.equal(opened[0].target, "_blank");
  assert.equal(opened[0].features, "noopener");
  const url = new URL(opened[0].url);
  assert.equal(url.pathname, "/chat.html");
  assert.equal(url.searchParams.get("selection"), "Selected text");
  assert.equal(url.searchParams.get("sessionId"), "session-1");
});

test("quick chat sidebar handoff preserves context and active session", async () => {
  const sandbox = loadContentScriptSandbox();
  const opened = [];
  sandbox.document = {
    location: { href: "https://example.com/page" },
    title: "Example Page"
  };
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      async sendMessage(message) {
        assert.equal(message.type, "sloppy.tabs.open");
        opened.push(message.url);
        return { tab: { id: 1, url: message.url } };
      }
    }
  };
  vm.runInNewContext("state.settings = { sessionId: 'session-quick' };", sandbox);
  vm.runInNewContext(`
    state.quickChat = {
      context: {
        page: { url: "https://example.com/page", title: "Example Page" },
        selection: "Selected text"
      },
      sessionId: "session-quick"
    };
  `, sandbox);

  await sandbox.openQuickChatSidebar();

  assert.equal(opened.length, 1);
  const url = new URL(opened[0]);
  assert.equal(url.pathname, "/chat.html");
  assert.equal(url.searchParams.get("selection"), "Selected text");
  assert.equal(url.searchParams.get("pageURL"), "https://example.com/page");
  assert.equal(url.searchParams.get("sessionId"), "session-quick");
});

test("command palette includes an independent recent sessions scroll container", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;

  const palette = sandbox.ensureCommandPalette();

  assert.match(palette.innerHTML, /data-sloppy-command-palette-shell/);
  assert.match(palette.innerHTML, /data-sloppy-command-palette-sessions/);
});

test("panel shell localizes visible chrome from system language", () => {
  const sandbox = loadContentScriptSandboxWithLocale("ru-RU");
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage() {
        return Promise.resolve({ artifacts: [] });
      }
    }
  };

  const panel = sandbox.ensurePanel();

  assert.match(panel.innerHTML, /placeholder="Спросите что-нибудь\.\.\."/);
  assert.match(panel.innerHTML, /aria-label="Настройки"/);
  assert.match(panel.innerHTML, /Новая сессия/);
});

test("chat placeholders rotate across shared chat surfaces", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage() {
        return Promise.resolve({ artifacts: [] });
      }
    }
  };

  assert.equal(sandbox.chatPlaceholderText(0), "Ask something...");
  assert.equal(sandbox.chatPlaceholderText(1), "Type / for commands");
  assert.equal(sandbox.chatPlaceholderText(2), "Ask about this page");

  const panel = sandbox.ensurePanel();
  const source = readFileSync(new URL("../Resources/contentScript.js", import.meta.url), "utf8");

  assert.match(panel.innerHTML, /data-sloppy-prompt data-sloppy-chat-placeholder/);
  assert.match(source, /data-sloppy-command-palette-input data-sloppy-chat-placeholder/);
  assert.match(source, /data-sloppy-selection-prompt data-sloppy-chat-placeholder/);
  assert.doesNotMatch(source, /data-sloppy-quick-follow-up[\s\S]{0,160}data-sloppy-chat-placeholder/);
  assert.match(source, /data-sloppy-quick-follow-up[\s\S]*continueInChat/);
});

test("start page mode renders centered composer and shortcuts", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage() {
        return Promise.resolve({ artifacts: [] });
      }
    }
  };
  vm.runInNewContext(`
    globalThis.SloppyStartPageMode = true;
    state.settings = {
      startPageEnabled: true,
      startPageTheme: "light",
      startPageShortcuts: [{ title: "GitHub", url: "https://github.com/" }]
    };
  `, sandbox);

  const panel = sandbox.ensurePanel();
  sandbox.render(panel);
  const thread = panel.querySelector("[data-sloppy-thread]");

  assert.match(thread.innerHTML, /data-sloppy-start-surface/);
  assert.match(panel.querySelector("[data-sloppy-start-shortcuts]").innerHTML, /data-sloppy-start-shortcut="https:\/\/github\.com\/"/);
  assert.match(panel.querySelector("[data-sloppy-start-shortcuts]").innerHTML, /src="https:\/\/github\.com\/favicon\.ico"/);
  assert.match(thread.innerHTML, /data-sloppy-start-theme="light"/);
  assert.doesNotMatch(thread.innerHTML, /sloppy-empty-mark/);
  assert.match(panel.innerHTML, /data-sloppy-start-shortcuts/);
  assert.match(panel.innerHTML, /data-sloppy-customize/);
});

test("start page grid renders shortcuts and widget artifacts", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };
  vm.runInNewContext(`
    globalThis.SloppyStartPageMode = true;
    state.settings = {
      startPageEnabled: true,
      startPageShortcuts: [{ title: "GitHub", url: "https://github.com/" }],
      startPageItems: [
        { kind: "shortcut", title: "GitHub", url: "https://github.com/" },
        {
          kind: "widget",
          artifactId: "widget-1",
          title: "Clock",
          size: "small",
          width: 999,
          height: 1
        }
      ]
    };
    state.widgetHTMLByArtifactId = { "widget-1": "<html><body>Clock</body></html>" };
  `, sandbox);

  const panel = sandbox.ensurePanel();
  sandbox.render(panel);
  const shortcuts = panel.querySelector("[data-sloppy-start-shortcuts]");

  assert.match(shortcuts.innerHTML, /data-sloppy-start-shortcut="https:\/\/github\.com\/"/);
  assert.match(shortcuts.innerHTML, /data-sloppy-start-widget="widget-1"/);
  assert.match(shortcuts.innerHTML, /class="sloppy-start-shortcut-icon"[^>]*src="https:\/\/github\.com\/favicon\.ico"/);
  assert.match(shortcuts.innerHTML, /<strong>GitHub<\/strong>/);
  assert.match(shortcuts.innerHTML, /<span>https:\/\/github\.com\/<\/span>/);
  assert.match(shortcuts.innerHTML, /style="--sloppy-col-span:1;--sloppy-row-span:1;"/);
  assert.doesNotMatch(shortcuts.innerHTML, /width:160px;height:120px/);
  assert.match(shortcuts.innerHTML, /sandbox="allow-scripts"/);
});

test("start page shortcuts always render as one grid cell", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };
  vm.runInNewContext(`
    globalThis.SloppyStartPageMode = true;
    state.settings = {
      startPageEnabled: true,
      startPageItems: [
        {
          id: "shortcut-1",
          kind: "shortcut",
          title: "VK",
          url: "https://vk.com/",
          colSpan: 2,
          rowSpan: 2
        },
        {
          id: "widget-1",
          kind: "widget",
          artifactId: "widget-1",
          title: "Widget draft",
          colSpan: 2,
          rowSpan: 2
        }
      ]
    };
    state.widgetHTMLByArtifactId = { "widget-1": "<html><body>Widget</body></html>" };
  `, sandbox);

  const panel = sandbox.ensurePanel();
  sandbox.render(panel);
  const shortcuts = panel.querySelector("[data-sloppy-start-shortcuts]");

  assert.match(shortcuts.innerHTML, /class="sloppy-start-shortcut-card"[^>]*style="--sloppy-col-span:1;--sloppy-row-span:1;"/);
  assert.match(shortcuts.innerHTML, /class="sloppy-start-widget"[^>]*style="--sloppy-col-span:2;--sloppy-row-span:2;"/);
});

test("open customize enables editing controls on start shortcuts", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage() {
        return Promise.resolve({ artifacts: [] });
      }
    }
  };
  vm.runInNewContext(`
    globalThis.SloppyStartPageMode = true;
    state.settings = {
      startPageEnabled: true,
      startPageItems: [
        {
          id: "shortcut-1",
          kind: "shortcut",
          title: "GitHub",
          url: "https://github.com/",
          colSpan: 1,
          rowSpan: 1,
          order: 0
        }
      ]
    };
  `, sandbox);

  const panel = sandbox.ensurePanel();
  sandbox.render(panel);
  sandbox.openCustomize(panel);

  const customizeButton = panel.querySelector("[data-sloppy-customize]");
  const shortcuts = panel.querySelector("[data-sloppy-start-shortcuts]");
  const customizeBody = panel.querySelector("[data-sloppy-customize-body]");

  assert.equal(customizeButton.hidden, true);
  assert.equal(panel.classList.toggled.get("is-start-customizing"), true);
  assert.match(shortcuts.innerHTML, /data-sloppy-grid-draggable="shortcut-1"/);
  assert.match(shortcuts.innerHTML, /data-sloppy-start-item-menu="shortcut-1"/);
  assert.match(shortcuts.innerHTML, /data-sf-symbol="ellipsis"/);
  assert.match(shortcuts.innerHTML, /data-sloppy-start-item-menu-panel="shortcut-1" role="menu" hidden/);
  assert.match(shortcuts.innerHTML, /data-sloppy-grid-menu="shortcut-1" role="menuitem">Edit<\/button>/);
  assert.match(shortcuts.innerHTML, /data-sloppy-delete-item="shortcut-1" role="menuitem">Delete<\/button>/);
  assert.doesNotMatch(shortcuts.innerHTML, /data-sf-symbol="brain"/);
  assert.doesNotMatch(shortcuts.innerHTML, /data-sf-symbol="xmark"/);
  assert.doesNotMatch(shortcuts.innerHTML, /data-sloppy-resize-handle="shortcut-1"/);
  assert.doesNotMatch(shortcuts.innerHTML, /data-sloppy-resize-item="shortcut-1"/);
  assert.match(shortcuts.innerHTML, /style="--sloppy-col-span:1;--sloppy-row-span:1;"/);
  assert.doesNotMatch(customizeBody.innerHTML, /data-sloppy-resize-item="shortcut-1"/);
  assert.doesNotMatch(customizeBody.innerHTML, /sloppy-grid-item-controls/);
});

test("saving customize exits start page editing mode", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage(message) {
        if (message?.type === "sloppy.settings.save") {
          return Promise.resolve(message.settings);
        }
        return Promise.resolve({ artifacts: [] });
      }
    }
  };
  vm.runInNewContext(`
    globalThis.SloppyStartPageMode = true;
    state.settings = {
      startPageEnabled: true,
      startPageItems: [
        {
          id: "shortcut-1",
          kind: "shortcut",
          title: "GitHub",
          url: "https://github.com/",
          colSpan: 1,
          rowSpan: 1,
          order: 0
        }
      ]
    };
  `, sandbox);

  const panel = sandbox.ensurePanel();
  sandbox.render(panel);
  sandbox.openCustomize(panel);
  await sandbox.saveCustomize(panel);

  const customizeButton = panel.querySelector("[data-sloppy-customize]");
  const shortcuts = panel.querySelector("[data-sloppy-start-shortcuts]");

  assert.equal(customizeButton.hidden, false);
  assert.equal(panel.classList.toggled.get("is-start-customizing"), false);
  assert.equal(vm.runInNewContext("state.customizeNavigation.editing", sandbox), false);
  assert.doesNotMatch(shortcuts.innerHTML, /data-sloppy-grid-draggable="shortcut-1"/);
  assert.doesNotMatch(shortcuts.innerHTML, /data-sloppy-start-item-menu="shortcut-1"/);
  assert.match(shortcuts.innerHTML, /draggable="false"/);
});

test("widgets customize grid lists create shortcut and available widgets independent of start layout", () => {
  const sandbox = loadContentScriptSandbox();
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };
  vm.runInNewContext(`
    globalThis.SloppyStartPageMode = true;
    state.settings = {
      startPageEnabled: true,
      startPageItems: [
        { id: "shortcut-1", kind: "shortcut", title: "VK", url: "https://vk.com/" },
        { id: "widget-start", kind: "widget", artifactId: "widget-start", title: "Placed widget", colSpan: 2, rowSpan: 2 }
      ]
    };
    state.artifacts = [
      { id: "widget-available", title: "Available widget", kind: "widget", size: "medium" }
    ];
  `, sandbox);

  const widgetsGrid = { innerHTML: "" };
  sandbox.renderWidgetsGrid({
    querySelector(selector) {
      return selector === "[data-sloppy-widgets-grid]" ? widgetsGrid : null;
    }
  });

  assert.match(widgetsGrid.innerHTML, /data-sloppy-create-widget-card[\s\S]*Create widget/);
  assert.match(widgetsGrid.innerHTML, /data-sloppy-pick-shortcut-widget[\s\S]*Shortcut[\s\S]*Add quick link/);
  assert.match(widgetsGrid.innerHTML, /data-sloppy-pick-ready-widget="widget-available"[\s\S]*Available widget/);
  assert.ok(widgetsGrid.innerHTML.indexOf("data-sloppy-create-widget-card") < widgetsGrid.innerHTML.indexOf("data-sloppy-pick-shortcut-widget"));
  assert.ok(widgetsGrid.innerHTML.indexOf("data-sloppy-pick-shortcut-widget") < widgetsGrid.innerHTML.indexOf("data-sloppy-pick-ready-widget"));
  assert.doesNotMatch(widgetsGrid.innerHTML, /VK|Placed widget|data-sloppy-grid-item|--sloppy-col-span/);

  const panelCSS = readFileSync(new URL("../Resources/panel.css", import.meta.url), "utf8");
  const createCardBlock = panelCSS.match(/^\.sloppy-widget-create-card\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const createCardHoverBlock = panelCSS.match(/^\.sloppy-widget-create-card:hover,\n\.sloppy-widget-create-card:focus-visible\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const createCardIconBlock = panelCSS.match(/^\.sloppy-widget-create-card span\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const createCardLabelBlock = panelCSS.match(/^\.sloppy-widget-create-card strong\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const pickerCardBlock = panelCSS.match(/^\.sloppy-widget-picker-card\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const pickerCardInteractiveBlock = panelCSS.match(/^\.sloppy-widget-picker-card:hover,\n\.sloppy-widget-picker-card:focus-visible\s*\{[\s\S]*?\n\}/m)?.[0] || "";

  assert.match(createCardBlock, /place-items:\s*center;/);
  assert.match(createCardBlock, /align-content:\s*center;/);
  assert.match(createCardBlock, /background:\s*transparent;/);
  assert.match(createCardBlock, /border:\s*1px dashed/);
  assert.match(createCardBlock, /cursor:\s*pointer;/);
  assert.match(createCardBlock, /transition:\s*transform 160ms ease/);
  assert.match(createCardHoverBlock, /transform:\s*translateY\(-2px\);/);
  assert.match(createCardHoverBlock, /background:\s*rgba\(255, 255, 255, 0\.06\);/);
  assert.match(pickerCardBlock, /cursor:\s*pointer;/);
  assert.match(pickerCardBlock, /transition:\s*transform 160ms ease/);
  assert.match(pickerCardInteractiveBlock, /transform:\s*translateY\(-2px\);/);
  assert.match(pickerCardInteractiveBlock, /border-color:\s*rgba\(183, 255, 0, 0\.46\);/);
  assert.match(createCardIconBlock, /line-height:\s*1;/);
  assert.match(createCardLabelBlock, /line-height:\s*1\.15;/);
});

test("start shortcut content keeps a fixed height inside resized grid cells", () => {
  const panelCSS = readFileSync(new URL("../Resources/panel.css", import.meta.url), "utf8");
  const startPageCustomize = readFileSync(new URL("../Resources/startPageCustomize.js", import.meta.url), "utf8");
  const startCardBlock = panelCSS.match(/\.sloppy-start-shortcut-card,\n\.sloppy-start-widget\s*\{[\s\S]*?\n\}/)?.[0] || "";
  const startLinkBlock = panelCSS.match(/\.sloppy-start-shortcuts a\s*\{[\s\S]*?\n\}/)?.[0] || "";
  const startShortcutCopyBlock = panelCSS.match(/^\.sloppy-start-shortcut-copy\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const startShortcutStrongBlock = panelCSS.match(/^\.sloppy-start-shortcut-copy strong\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const startShortcutSubtitleBlock = panelCSS.match(/^\.sloppy-start-shortcut-copy span\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const startWidgetBlock = Array.from(panelCSS.matchAll(/^\.sloppy-start-widget\s*\{[\s\S]*?\n\}/gm)).at(-1)?.[0] || "";
  const startConfigButtonBlock = panelCSS.match(/^\.sloppy-start-config-button\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const startConfigButtonHoverBlock = panelCSS.match(/^\.sloppy-start-config-button:hover,\n\.sloppy-start-config-button:focus-visible\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const startConfigBaseBlock = panelCSS.match(/\.sloppy-start-page #sloppy-safari-extension-panel \.sloppy-start-config-panel\s*\{[\s\S]*?\n\}/)?.[0] || "";
  const startConfigOpenBlock = panelCSS.match(/#sloppy-safari-extension-panel\.is-start-customizing \.sloppy-start-config-panel\s*\{[\s\S]*?\n\}/)?.[0] || "";
  const startComposerOpenBlock = panelCSS.match(/#sloppy-safari-extension-panel\.is-start-customizing \.sloppy-composer\s*\{[\s\S]*?\n\}/)?.[0] || "";
  const customizeDialogBlock = panelCSS.match(/^\.sloppy-customize-dialog\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const startItemMenuBlock = panelCSS.match(/^\.sloppy-start-item-menu\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const startItemControlsBlock = panelCSS.match(/^\.sloppy-start-item-controls\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const startItemMenuHiddenBlock = panelCSS.match(/^\.sloppy-start-item-menu\[hidden\]\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const startItemMenuButtonBlock = panelCSS.match(/^\.sloppy-start-item-menu button\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const startItemMenuOpenBlock = panelCSS.match(/\.sloppy-start-shortcut-card:has\(\.sloppy-start-item-menu:not\(\[hidden\]\)\),\n\.sloppy-start-widget:has\(\.sloppy-start-item-menu:not\(\[hidden\]\)\)\s*\{[\s\S]*?\n\}/)?.[0] || "";
  const editingWidgetIframeBlock = panelCSS.match(/^#sloppy-safari-extension-panel\.is-start-customizing \.sloppy-start-widget iframe\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const startMotionBlock = panelCSS.match(/^\.sloppy-start-shortcut-card,\n\.sloppy-start-widget\s*\{[\s\S]*?\n\}/m)?.[0] || "";
  const reducedMotionBlock = panelCSS.match(/@media \(prefers-reduced-motion: reduce\)\s*\{[\s\S]*?\.sloppy-start-shortcut-card,\n\s*\.sloppy-start-widget\s*\{[\s\S]*?\n\s*\}/)?.[0] || "";

  assert.match(panelCSS, /\.sloppy-start-shortcuts\s*\{[\s\S]*grid-template-columns:\s*repeat\(4, minmax\(0, 1fr\)\);[\s\S]*grid-auto-rows:\s*88px;/);
  assert.match(startConfigBaseBlock, /left:\s*50%;/);
  assert.match(startConfigBaseBlock, /right:\s*auto;/);
  assert.match(startConfigBaseBlock, /width:\s*min\(620px, calc\(100% - 32px\)\);/);
  assert.match(startConfigBaseBlock, /transform:\s*translateX\(-50%\);/);
  assert.match(startConfigButtonBlock, /cursor:\s*pointer;/);
  assert.match(startConfigButtonBlock, /transition:\s*transform 160ms ease/);
  assert.match(startConfigButtonHoverBlock, /transform:\s*translateY\(-2px\);/);
  assert.match(startConfigButtonHoverBlock, /border-color:\s*rgba\(183, 255, 0, 0\.46\);/);
  assert.match(startConfigOpenBlock, /position:\s*static;/);
  assert.match(startConfigOpenBlock, /width:\s*min\(620px, calc\(100% - 32px\)\);/);
  assert.match(startConfigOpenBlock, /transform:\s*none;/);
  assert.match(startConfigOpenBlock, /margin-top:\s*auto;/);
  assert.match(startConfigOpenBlock, /pointer-events:\s*auto;/);
  assert.match(panelCSS, /#sloppy-safari-extension-panel\.is-start-customizing \.sloppy-shell\s*\{[\s\S]*justify-content:\s*flex-start;[\s\S]*overflow-y:\s*auto;/);
  assert.match(startComposerOpenBlock, /margin-top:\s*auto;/);
  assert.match(startComposerOpenBlock, /margin-inline:\s*auto;/);
  assert.match(customizeDialogBlock, /width:\s*100%;/);
  assert.match(customizeDialogBlock, /box-sizing:\s*border-box;/);
  assert.match(panelCSS, /\.sloppy-customize-dialog \.sloppy-settings-card\s*\{[\s\S]*width:\s*100%;[\s\S]*box-sizing:\s*border-box;/);
  assert.match(panelCSS, /\.sloppy-start-shortcut-card\s*\{[\s\S]*align-content:\s*start;/);
  assert.match(panelCSS, /\.sloppy-start-shortcut-card\s*\{[\s\S]*grid-column:\s*span 1;[\s\S]*grid-row:\s*span 1;/);
  assert.match(startItemMenuBlock, /position:\s*absolute;[\s\S]*top:\s*30px;[\s\S]*right:\s*0;/);
  assert.match(startItemControlsBlock, /z-index:\s*4;/);
  assert.match(startItemMenuBlock, /min-width:\s*86px;/);
  assert.match(startItemMenuHiddenBlock, /display:\s*none;/);
  assert.match(startItemMenuButtonBlock, /padding:\s*5px 7px;[\s\S]*background:\s*transparent;[\s\S]*border:\s*0;/);
  assert.match(startItemMenuOpenBlock, /overflow:\s*visible;[\s\S]*z-index:\s*5;/);
  assert.match(editingWidgetIframeBlock, /pointer-events:\s*none;/);
  assert.match(startMotionBlock, /transition:\s*transform 220ms cubic-bezier\(0\.22, 1, 0\.36, 1\),\s*opacity 180ms ease,\s*border-color 180ms ease,\s*box-shadow 180ms ease;/);
  assert.match(reducedMotionBlock, /transition:\s*none;/);
  assert.match(startCardBlock, /background:\s*rgba\(255, 255, 255, 0\.04\);/);
  assert.match(startCardBlock, /border:\s*1px solid rgba\(255, 255, 255, 0\.1\);/);
  assert.match(startCardBlock, /border-radius:\s*16px;/);
  assert.match(startLinkBlock, /background:\s*transparent;/);
  assert.match(startLinkBlock, /border:\s*0;/);
  assert.match(startLinkBlock, /grid-template-rows:\s*auto 1fr auto;/);
  assert.match(startShortcutCopyBlock, /align-self:\s*end;/);
  assert.match(startShortcutStrongBlock, /font-weight:\s*700;/);
  assert.match(startShortcutSubtitleBlock, /color:\s*rgba\(232, 232, 232, 0\.56\);/);
  assert.match(startWidgetBlock, /width:\s*100%;[\s\S]*height:\s*100%;/);
  assert.match(startLinkBlock, /height:\s*100%;/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\s*\{[^}]*cursor:\s*nwse-resize;[^}]*animation:\s*sloppy-resize-handle-appear/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\s*\{[^}]*z-index:\s*3;/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\s*\{[^}]*top 0\.26s cubic-bezier/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle::before\s*\{[^}]*width:\s*30px;[^}]*height:\s*6px;[^}]*border-radius:\s*999px;/);
  assert.match(panelCSS, /@keyframes sloppy-resize-handle-appear/);
  assert.doesNotMatch(panelCSS, /\.sloppy-start-resize-handle\s*\{[^}]*radial-gradient/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-moving/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-edge-bottom\s*\{[^}]*top:\s*calc\(100% - 52px\);[\s\S]*left:\s*calc\(50% - 26px\);[\s\S]*cursor:\s*ns-resize;/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-edge-right\s*\{[^}]*top:\s*calc\(50% - 26px\);[\s\S]*left:\s*calc\(100% - 52px\);[\s\S]*cursor:\s*ew-resize;/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-edge-bottom\.is-edge-right\s*\{[^}]*top:\s*calc\(100% - 52px\);[\s\S]*left:\s*calc\(100% - 52px\);[\s\S]*cursor:\s*nwse-resize;/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-edge-top\.is-edge-left\s*\{[^}]*top:\s*0;[\s\S]*left:\s*0;[\s\S]*cursor:\s*nwse-resize;/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-edge-top\.is-edge-right\s*\{[^}]*top:\s*0;[\s\S]*left:\s*calc\(100% - 52px\);[\s\S]*cursor:\s*nesw-resize;/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-edge-bottom\.is-edge-left\s*\{[^}]*top:\s*calc\(100% - 52px\);[\s\S]*left:\s*0;[\s\S]*cursor:\s*nesw-resize;/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-edge-left::before,\n\.sloppy-start-resize-handle\.is-edge-right::before\s*\{[^}]*rotate\(90deg\)/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-edge-top\.is-edge-left::before,\n\.sloppy-start-resize-handle\.is-edge-top\.is-edge-right::before,\n\.sloppy-start-resize-handle\.is-edge-bottom\.is-edge-left::before,\n\.sloppy-start-resize-handle\.is-edge-bottom\.is-edge-right::before\s*\{[\s\S]*width:\s*24px;[\s\S]*height:\s*24px;[\s\S]*background:\s*transparent;[\s\S]*border:\s*solid rgba\(255, 255, 255, 0\.94\);[\s\S]*border-width:\s*0;[\s\S]*border-radius:\s*0;[\s\S]*box-sizing:\s*border-box;/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-edge-bottom\.is-edge-right::before\s*\{[\s\S]*border-width:\s*0 6px 6px 0;[\s\S]*border-bottom-right-radius:\s*16px;/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-edge-bottom\.is-edge-left::before\s*\{[\s\S]*border-width:\s*0 0 6px 6px;[\s\S]*border-bottom-left-radius:\s*16px;/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-edge-top\.is-edge-right::before\s*\{[\s\S]*border-width:\s*6px 6px 0 0;[\s\S]*border-top-right-radius:\s*16px;/);
  assert.match(panelCSS, /\.sloppy-start-resize-handle\.is-edge-top\.is-edge-left::before\s*\{[\s\S]*border-width:\s*6px 0 0 6px;[\s\S]*border-top-left-radius:\s*16px;/);
  assert.match(startPageCustomize, /const cornerActivationInset = 36;/);
  assert.match(startPageCustomize, /return verticalEdge;/);
  assert.match(startPageCustomize, /return horizontalEdge;/);
  assert.match(panelCSS, /\.sloppy-customize-dialog \.sloppy-customize-toolbar \.sloppy-settings-save\s*\{[\s\S]*background:\s*transparent;[\s\S]*border-color:\s*transparent;/);
  assert.match(startPageCustomize, /function renderStartPageItemsAnimated\(frame, mutate\)/);
  assert.match(startPageCustomize, /function captureStartPageLayout\(frame\)/);
  assert.match(startPageCustomize, /function animateStartPageLayout\(frame, beforeRects\)/);
  assert.match(startPageCustomize, /const customizeMotionSelectors = \[/);
  assert.match(startPageCustomize, /function captureCustomizeMotion\(frame\)/);
  assert.match(startPageCustomize, /function animateCustomizeMotion\(frame, beforeRects\)/);
  assert.doesNotMatch(startPageCustomize.match(/const customizeMotionSelectors = \[[\s\S]*?\];/)?.[0] || "", /data-sloppy-customize-dialog/);
  assert.match(startPageCustomize, /requestAnimationFrame\?\.\(\(\) => animateCustomizeMotion\(frame, motionRects\)\)/);
  assert.match(startPageCustomize, /duration:\s*280,\s*easing:\s*"cubic-bezier\(0\.22, 1, 0\.36, 1\)"/);
  assert.match(panelCSS, /\.sloppy-start-page #sloppy-safari-extension-panel \.sloppy-app-layout,\n\.sloppy-start-page #sloppy-safari-extension-panel \.sloppy-shell\s*\{[\s\S]*transition:\s*transform 280ms cubic-bezier\(0\.22, 1, 0\.36, 1\),\s*opacity 220ms ease;/);
  assert.match(panelCSS, /\.sloppy-start-shortcuts\s*\{[\s\S]*transition:\s*transform 280ms cubic-bezier\(0\.22, 1, 0\.36, 1\),\s*opacity 220ms ease;/);
  assert.match(startPageCustomize, /function startPageDropIndexForEvent\(root, event\)/);
  assert.match(startPageCustomize, /function moveStartPageItemToIndex\(activeId, targetIndex\)/);
  assert.match(startPageCustomize, /node\.animate\?\.\(\[/);
  assert.match(startPageCustomize, /prefers-reduced-motion: reduce/);
  assert.match(startPageCustomize, /renderStartPageItemsAnimated\(frame, \(\) => \{\s*resizeStartPageItem/);
  assert.match(startPageCustomize, /renderStartPageItemsAnimated\(frame, \(\) => \{\s*removeStartPageItem/);
  assert.match(startPageCustomize, /root\.addEventListener\("dragover"/);
  assert.match(startPageCustomize, /moveStartPageItemToIndex\(state\.gridDrag\.activeId, dropIndex\)/);
  assert.match(startPageCustomize, /class="sloppy-grid-landing-slot"/);
  assert.match(panelCSS, /\.sloppy-grid-landing-slot\s*\{[\s\S]*border:\s*1px dashed rgba\(183, 255, 0, 0\.64\);/);
});

test("start page initializes the chat UI immediately", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage(message) {
        if (message?.type === "sloppy.settings.get") {
          return Promise.resolve({
            startPageEnabled: true,
            startPageTheme: "dark",
            startPageShortcuts: []
          });
        }
        return Promise.resolve({});
      }
    }
  };

  assert.equal(typeof sandbox.initializeStartPage, "function");
  await sandbox.initializeStartPage();

  assert.ok(documentLike.getElementById("sloppy-safari-extension-panel"));
  assert.equal(documentLike.getElementById("sloppy-safari-extension-panel").querySelector("[data-sloppy-prompt]").focusCount || 0, 0);
});

test("mobile fullscreen chat does not autofocus the prompt on open", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  documentLike.location.href = "safari-extension://sloppy/chat.html";
  documentLike.location.pathname = "/chat.html";
  sandbox.document = documentLike;
  sandbox.window = {
    innerWidth: 390,
    innerHeight: 760,
    navigator: { maxTouchPoints: 5 },
    visualViewport: { width: 390, height: 680, offsetTop: 0, offsetLeft: 0 }
  };
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage(message) {
        if (message?.type === "sloppy.settings.get") {
          return Promise.resolve({});
        }
        if (message?.type === "sloppy.agents.list") {
          return Promise.resolve({ agents: [] });
        }
        if (message?.type === "sloppy.models.list") {
          return Promise.resolve({ models: [] });
        }
        if (message?.type === "sloppy.tabs.list") {
          return Promise.resolve({ tabs: [] });
        }
        if (message?.type === "sloppy.slashCommands.list") {
          return Promise.resolve({ commands: [] });
        }
        return Promise.resolve({});
      }
    }
  };

  assert.equal(typeof sandbox.initializeFullscreenChat, "function");
  await sandbox.initializeFullscreenChat();

  const prompt = documentLike.getElementById("sloppy-safari-extension-panel").querySelector("[data-sloppy-prompt]");
  assert.equal(prompt.focusCount || 0, 0);
});

test("settings and customize use separate dialogs", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };

  const panel = sandbox.ensurePanel();
  sandbox.renderCustomizeDialog(panel);
  const customizeBody = panel.querySelector("[data-sloppy-customize-body]");
  const startPageCustomize = readFileSync(new URL("../Resources/startPageCustomize.js", import.meta.url), "utf8");

  assert.match(panel.innerHTML, /data-sloppy-settings-dialog/);
  assert.match(panel.innerHTML, /data-sloppy-customize-dialog/);
  assert.doesNotMatch(panel.innerHTML.match(/data-sloppy-settings-dialog[\s\S]*?<\/dialog>/)?.[0] || "", /data-sloppy-start-page-theme/);
  assert.match(customizeBody?.innerHTML || "", /data-sloppy-widgets-grid/);
  assert.match(startPageCustomize, /data-sloppy-create-widget-card/);
  assert.match(startPageCustomize, /data-sloppy-pick-shortcut-widget/);
  assert.match(startPageCustomize, /data-sloppy-pick-ready-widget/);
  assert.doesNotMatch(customizeBody?.innerHTML || "", /sloppy-customize-toolbar-actions/);
});

test("customize includes describe widget controls", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };

  const panel = sandbox.ensurePanel();
  sandbox.openWidgetEditor(panel);
  const customizeBody = panel.querySelector("[data-sloppy-customize-body]");
  const customizeDialog = panel.querySelector("[data-sloppy-customize-dialog]");
  const panelCSS = readFileSync(new URL("../Resources/panel.css", import.meta.url), "utf8");
  const editorScreenBlock = panelCSS.match(/\.sloppy-widget-editor-screen\s*\{[\s\S]*?\n\}/)?.[0] || "";

  assert.equal(customizeDialog.classList.toggled.get("is-widget-editor"), true);
  assert.equal(panel.classList.toggled.get("is-widget-editing"), true);
  assert.match(customizeBody?.innerHTML || "", /sloppy-widget-editor-canvas/);
  assert.match(customizeBody?.innerHTML || "", /sloppy-widget-editor-topbar/);
  assert.match(customizeBody?.innerHTML || "", /sloppy-widget-editor-actions[\s\S]*data-sloppy-widget-editor-done[\s\S]*data-sloppy-widget-editor-cancel/);
  assert.match(customizeBody?.innerHTML || "", /sloppy-widget-editor-title/);
  assert.match(customizeBody?.innerHTML || "", /data-sloppy-widget-editor-resize="2x1"/);
  assert.match(customizeBody?.innerHTML || "", /sloppy-widget-editor-layout/);
  assert.match(customizeBody?.innerHTML || "", /sloppy-widget-editor-preview-pane[\s\S]*data-sloppy-widget-preview/);
  assert.match(customizeBody?.innerHTML || "", /--sloppy-widget-preview-width:306px;--sloppy-widget-preview-height:88px;/);
  assert.doesNotMatch(customizeBody?.innerHTML || "", /data-sloppy-widget-editor-prompt/);
  assert.doesNotMatch(customizeBody?.innerHTML || "", /data-sloppy-widget-editor-send/);
  assert.doesNotMatch(customizeBody?.innerHTML || "", /sloppy-widget-editor-rail/);
  assert.doesNotMatch(customizeBody?.innerHTML || "", /sloppy-widget-editor-chat-shell/);
  assert.doesNotMatch(customizeBody?.innerHTML || "", /sloppy-widget-editor-composer/);
  assert.doesNotMatch(customizeBody?.innerHTML || "", /sloppy-quick-shell/);
  assert.match(panel.innerHTML, /data-sloppy-thread/);
  assert.match(panel.innerHTML, /data-sloppy-composer/);
  assert.match(panelCSS, /\.sloppy-customize-dialog\.is-widget-editor\s*\{[\s\S]*position:\s*fixed;[\s\S]*inset:\s*0 0 0 calc\(-1 \* \(100vw - var\(--sloppy-widget-chat-width, 0px\)\)\);[\s\S]*z-index:\s*30;/);
  assert.match(editorScreenBlock, /min-height:\s*100vh;/);
  assert.match(editorScreenBlock, /background:\s*#242424;/);
  assert.doesNotMatch(editorScreenBlock, /background-image:/);
  assert.match(panelCSS, /\.sloppy-widget-editor-layout\s*\{[\s\S]*grid-template-columns:\s*minmax\(0, 1fr\);/);
  assert.match(panelCSS, /\.sloppy-widget-editor-controls\s*\{[\s\S]*position:\s*absolute;[\s\S]*bottom:\s*24px;/);
  assert.match(panelCSS, /\.sloppy-widget-editor-preview\s*\{[\s\S]*width:\s*min\(var\(--sloppy-widget-preview-width, 306px\), calc\(100% - 32px\)\);[\s\S]*height:\s*var\(--sloppy-widget-preview-height, 88px\);[\s\S]*border-radius:\s*18px;[\s\S]*backdrop-filter:\s*blur\(18px\) saturate\(1\.08\);/);
  assert.match(panelCSS, /#sloppy-safari-extension-panel\.is-widget-editing \.sloppy-app-layout[\s\S]*grid-template-columns:\s*minmax\(0, 1fr\) var\(--sloppy-widget-chat-width\);/);
  assert.match(panelCSS, /#sloppy-safari-extension-panel\.is-widget-editing \.sloppy-app-layout > \.sloppy-shell\s*\{[\s\S]*grid-column:\s*2;[\s\S]*overflow:\s*visible;/);
  assert.match(panelCSS, /#sloppy-safari-extension-panel\.is-widget-editing > \.sloppy-app-layout > \.sloppy-shell > \.sloppy-thread\s*\{[\s\S]*display:\s*flex;/);
  assert.match(panelCSS, /#sloppy-safari-extension-panel\.is-widget-editing > \.sloppy-app-layout > \.sloppy-shell > \.sloppy-composer\s*\{[\s\S]*display:\s*block;/);
  assert.doesNotMatch(panelCSS, /sloppy-widget-editor-chat-shell/);
  assert.doesNotMatch(panelCSS, /sloppy-widget-editor-composer/);
  assert.match(panelCSS, /@media\s*\(max-width:\s*760px\)\s*\{[\s\S]*\.sloppy-widget-editor-layout\s*\{[\s\S]*grid-template-columns:\s*1fr;/);
});

test("widget editor sends widget slash command through the shared side chat composer", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  const sentMessages = [];
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage(message) {
        sentMessages.push(message);
        if (message?.type === "sloppy.browserContext.stream") {
          return Promise.resolve({ sessionId: "session-widget", text: "Widget created" });
        }
        if (message?.type === "sloppy.artifacts.list") {
          return Promise.resolve({ artifacts: [{ id: "widget-clock", title: "Clock", kind: "widget" }] });
        }
        if (message?.type === "sloppy.artifacts.widget") {
          return Promise.resolve({
            artifactId: "widget-clock",
            html: "<!doctype html><html><body>Clock</body></html>",
            size: "medium"
          });
        }
        return Promise.resolve({});
      }
    }
  };

  const panel = sandbox.ensurePanel();
  vm.runInNewContext(`
    state.settings = { defaultAgentID: "sloppy", sessionId: "session-old" };
    state.context = { page: { url: "https://example.com", title: "Example" }, selection: "" };
  `, sandbox);
  sandbox.openWidgetEditor(panel);
  const promptField = panel.querySelector("[data-sloppy-prompt]");
  promptField.value = "make a clock";

  await sandbox.sendPrompt(panel);

  assert.equal(sentMessages.some((message) => message?.type === "sloppy.artifacts.widget.generate"), false);
  const streamMessage = sentMessages.find((message) => message?.type === "sloppy.browserContext.stream");
  assert.match(streamMessage?.prompt || "", /^\/widget make a clock/);
  assert.match(streamMessage?.prompt || "", /Widget session context:/);
  assert.match(streamMessage?.prompt || "", /This session is dedicated only to generating and iterating the start-page widget preview\./);
  assert.equal(streamMessage?.sessionId, "");
  assert.equal(streamMessage?.widgetSession?.mode, "widget_editor");
  assert.equal(streamMessage?.widgetSession?.isolated, true);
  assert.equal(streamMessage?.widgetSession?.widget?.title, "Widget draft");
  assert.equal(streamMessage?.widgetSession?.widget?.size, "2x1");
  assert.equal(streamMessage?.page.url, "https://example.com");
  assert.equal(vm.runInNewContext("state.settings.sessionId", sandbox), "session-old");
  assert.equal(vm.runInNewContext("state.customizeNavigation.widgetSessionId", sandbox), "session-widget");
  assert.equal(panel.classList.toggled.get("is-widget-editing"), true);
  assert.match(panel.querySelector("[data-sloppy-thread]").innerHTML, /Widget created/);
});

test("sidebar keeps sessions expanded below projects and no settings item", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };

  const panel = sandbox.ensurePanel();
  const projectsIndex = panel.innerHTML.indexOf("data-sloppy-sidebar-projects");
  const sessionsIndex = panel.innerHTML.indexOf("data-sloppy-sidebar-sessions");
  const listIndex = panel.innerHTML.indexOf("data-sloppy-sidebar-session-list");
  const collapseIndex = panel.innerHTML.indexOf("data-sloppy-sidebar-collapse");

  assert.ok(projectsIndex >= 0);
  assert.ok(collapseIndex >= 0);
  assert.ok(sessionsIndex > projectsIndex);
  assert.ok(listIndex > sessionsIndex);
  assert.doesNotMatch(panel.innerHTML, /data-sloppy-sidebar-session-list hidden/);
  assert.doesNotMatch(panel.innerHTML, /data-sloppy-sidebar-settings/);
  assert.doesNotMatch(panel.innerHTML, /data-sloppy-sidebar-collapse[\s\S]*<span>Hide sidebar<\/span>/);
});

test("sidebar includes artifacts item", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };

  const panel = sandbox.ensurePanel();

  assert.match(panel.innerHTML, /data-sloppy-sidebar-artifacts/);
});

test("loadArtifacts shows an error state when artifact fetch fails", async () => {
  const sandbox = loadContentScriptSandbox();
  const picker = { innerHTML: "" };
  const frame = {
    querySelector(selector) {
      if (selector === "[data-sloppy-widget-picker]") {
        return picker;
      }
      return null;
    }
  };
  sandbox.chrome = {
    runtime: {
      sendMessage() {
        return Promise.resolve({ error: "Artifacts unavailable." });
      }
    }
  };
  vm.runInNewContext("state.artifacts = [{ id: 'stale-widget', title: 'Old', kind: 'widget' }];", sandbox);

  await sandbox.loadArtifacts(frame);

  assert.equal(picker.innerHTML, "");
  assert.equal(vm.runInNewContext("state.artifactError", sandbox), "Artifacts unavailable.");
  assert.deepEqual(JSON.parse(vm.runInNewContext("JSON.stringify(state.artifacts)", sandbox)), []);
});

test("loadArtifacts refreshes widgets customize catalog", async () => {
  const sandbox = loadContentScriptSandbox();
  const picker = { innerHTML: "" };
  const widgetsGrid = { innerHTML: "" };
  const frame = {
    querySelector(selector) {
      if (selector === "[data-sloppy-widget-picker]") {
        return picker;
      }
      if (selector === "[data-sloppy-widgets-grid]") {
        return widgetsGrid;
      }
      return null;
    }
  };
  sandbox.chrome = {
    runtime: {
      sendMessage() {
        return Promise.resolve({
          artifacts: [{ id: "weather-widget", title: "Weather", kind: "widget", size: "medium" }]
        });
      }
    }
  };

  await sandbox.loadArtifacts(frame);

  assert.match(widgetsGrid.innerHTML, /data-sloppy-create-widget-card/);
  assert.match(widgetsGrid.innerHTML, /data-sloppy-pick-shortcut-widget/);
  assert.match(widgetsGrid.innerHTML, /data-sloppy-pick-ready-widget="weather-widget"[\s\S]*Weather/);
  assert.match(widgetsGrid.innerHTML, /data-sloppy-delete-ready-widget="weather-widget"/);
  assert.match(widgetsGrid.innerHTML, /data-sloppy-delete-ready-widget="weather-widget"[\s\S]*sloppy-symbol[\s\S]*trash\.svg/);
});

test("deleteCreatedWidget removes generated widget artifacts and placed items", async () => {
  const sandbox = loadContentScriptSandbox();
  const savedRequests = [];
  sandbox.chrome = {
    runtime: {
      sendMessage(message) {
        savedRequests.push(message);
        return Promise.resolve(message.settings);
      }
    }
  };
  vm.runInNewContext(`
    state.settings = {
      startPageItems: [
        { id: "shortcut-1", kind: "shortcut", title: "Docs", url: "https://docs.example/" },
        { id: "placed-weather", kind: "widget", artifactId: "weather-widget", title: "Weather" }
      ]
    };
    state.artifacts = [
      { id: "weather-widget", title: "Weather", kind: "widget" },
      { id: "clock-widget", title: "Clock", kind: "widget" }
    ];
    state.widgetHTMLByArtifactId = {
      "weather-widget": "<div>weather</div>",
      "clock-widget": "<div>clock</div>"
    };
  `, sandbox);
  const frame = {
    querySelector() {
      return null;
    }
  };

  await sandbox.deleteCreatedWidget(frame, "weather-widget", { persist: true });

  assert.deepEqual(
    JSON.parse(vm.runInNewContext("JSON.stringify(state.artifacts)", sandbox)),
    [{ id: "clock-widget", title: "Clock", kind: "widget" }]
  );
  assert.deepEqual(
    JSON.parse(vm.runInNewContext("JSON.stringify(state.settings.startPageItems)", sandbox)),
    [{ id: "shortcut-1", kind: "shortcut", title: "Docs", url: "https://docs.example/", order: 0, colSpan: 1, rowSpan: 1 }]
  );
  assert.equal(vm.runInNewContext("state.widgetHTMLByArtifactId['weather-widget']", sandbox), undefined);
  assert.equal(savedRequests.at(-1)?.type, "sloppy.settings.save");
});

test("clicking sidebar artifacts opens the widgets customize screen", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage() {
        return Promise.resolve({
          artifacts: [{ id: "widget-1", title: "Clock", kind: "widget" }]
        });
      }
    }
  };

  const panel = sandbox.ensurePanel();
  const artifactsButton = panel.querySelector("[data-sloppy-sidebar-artifacts]");
  const dialog = panel.querySelector("[data-sloppy-customize-dialog]");
  await artifactsButton?.listeners?.get("click")?.();

  assert.equal(dialog?.showModalCalled, true);
  assert.equal(vm.runInNewContext("state.customizeNavigation.screen", sandbox), "widgets");
});

test("addWidgetToStartPage adds widget to start page items", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  const savedRequests = [];
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage(message) {
        if (message?.type === "sloppy.artifacts.widget") {
          return Promise.resolve({
            artifactId: "widget-1",
            title: "Clock",
            size: "medium",
            width: 999,
            height: 1,
            html: "<html><body>Clock</body></html>"
          });
        }
        if (message?.type === "sloppy.settings.save") {
          savedRequests.push(message);
          return Promise.resolve(message.settings);
        }
        return Promise.resolve({});
      }
    }
  };
  vm.runInNewContext(`
    state.settings = {
      startPageShortcuts: [{ title: "GitHub", url: "https://github.com/" }],
      startPageItems: [{ kind: "shortcut", title: "GitHub", url: "https://github.com/" }]
    };
    state.artifacts = [{ id: "widget-1", title: "Clock", kind: "widget" }];
  `, sandbox);

  const panel = sandbox.ensurePanel();
  await sandbox.addWidgetToStartPage(panel, "widget-1", { persist: true });

  assert.deepEqual(
    JSON.parse(vm.runInNewContext("JSON.stringify(state.settings.startPageItems)", sandbox)),
    [
      { kind: "shortcut", title: "GitHub", url: "https://github.com/" },
      {
        kind: "widget",
        artifactId: "widget-1",
        title: "Clock",
        size: "medium",
        width: 320,
        height: 180
      }
    ]
  );
  assert.equal(
    vm.runInNewContext("state.widgetHTMLByArtifactId['widget-1']", sandbox),
    "<html><body>Clock</body></html>"
  );
  assert.equal(savedRequests.length, 1);
  assert.deepEqual(
    JSON.parse(JSON.stringify(savedRequests[0].settings.startPageShortcuts)),
    [{ title: "GitHub", url: "https://github.com/" }]
  );
});

test("fullscreen chat shell includes the shared app sidebar", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };
  vm.runInNewContext("document.documentElement.classList.add('sloppy-fullscreen-chat-page');", sandbox);

  const panel = sandbox.ensurePanel();

  assert.match(panel.innerHTML, /data-sloppy-app-sidebar/);
  assert.match(panel.innerHTML, /data-sloppy-sidebar-new/);
  assert.match(panel.innerHTML, /data-sloppy-sidebar-sessions/);
  assert.doesNotMatch(panel.innerHTML, /data-sloppy-sidebar-settings/);
});

test("mobile start page initializes with the app sidebar collapsed behind the toggle", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.window = {
    innerWidth: 390,
    innerHeight: 760,
    navigator: { maxTouchPoints: 5 },
    visualViewport: { width: 390, height: 680, offsetTop: 0, offsetLeft: 0 }
  };
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };

  const panel = sandbox.ensurePanel();
  const layout = panel.querySelector("[data-sloppy-app-layout]");

  assert.equal(layout.classList.toggled?.get("is-sidebar-collapsed"), true);
  assert.match(panel.innerHTML, /data-sloppy-sidebar-restore/);
});

test("topbar sessions button opens the sessions dialog instead of the app sidebar list", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage(message) {
        if (message?.type === "sloppy.sessions.list") {
          return Promise.resolve({
            selectedSessionId: "session-2",
            sessions: [
              { id: "session-1", title: "First", subtitle: "Older" },
              { id: "session-2", title: "Second", subtitle: "Recent" }
            ]
          });
        }
        return Promise.resolve({});
      }
    }
  };

  const panel = sandbox.ensurePanel();
  await panel.querySelector("[data-sloppy-sessions]").click();

  const dialog = panel.querySelector("[data-sloppy-sessions-dialog]");
  const dialogList = panel.querySelector("[data-sloppy-session-list]");
  const sidebarList = panel.querySelector("[data-sloppy-sidebar-session-list]");
  assert.equal(dialog.showModalCalled, true);
  assert.match(dialogList.innerHTML, /Second/);
  assert.doesNotMatch(sidebarList.innerHTML, /Second/);
});

test("shortcut editor surfaces available browser bookmarks", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage(message) {
        if (message?.type === "sloppy.bookmarks.list") {
          return Promise.resolve([
            { id: "1", title: "GitHub", url: "https://github.com/" },
            { id: "2", title: "Safari", url: "https://developer.apple.com/safari/" }
          ]);
        }
        return Promise.resolve({});
      }
    }
  };
  vm.runInNewContext("state.settings = { startPageItems: [] };", sandbox);
  const panel = sandbox.ensurePanel();

  await sandbox.openShortcutEditor(panel);
  await new Promise((resolve) => setImmediate(resolve));
  const customizeBody = panel.querySelector("[data-sloppy-customize-body]");

  assert.match(customizeBody?.innerHTML || "", /data-sloppy-shortcut-bookmarks/);
  assert.match(customizeBody?.innerHTML || "", /Bookmarks/);
  assert.match(customizeBody?.innerHTML || "", /Pick a saved site/);
  assert.match(customizeBody?.innerHTML || "", /sloppy-shortcut-bookmark-card/);
  assert.match(customizeBody?.innerHTML || "", /data-sloppy-pick-bookmark="1"/);
  assert.match(customizeBody?.innerHTML || "", /GitHub/);
  assert.match(customizeBody?.innerHTML || "", /https:\/\/github\.com\//);
});

test("shortcut bookmark cards update the draft after async bookmark render", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage(message) {
        if (message?.type === "sloppy.bookmarks.list") {
          return Promise.resolve([
            { id: "vk", title: "vk.com", url: "https://vk.com/" },
            { id: "github", title: "GitHub", url: "https://github.com/" }
          ]);
        }
        return Promise.resolve({});
      }
    }
  };
  vm.runInNewContext("state.settings = { startPageItems: [] };", sandbox);
  const panel = sandbox.ensurePanel();

  await sandbox.openShortcutEditor(panel);
  await new Promise((resolve) => setImmediate(resolve));
  const customizeBody = panel.querySelector("[data-sloppy-customize-body]");
  await customizeBody.listeners.get("click")({
    target: {
      closest(selector) {
        if (selector === "[data-sloppy-pick-bookmark]") {
          return { dataset: { sloppyPickBookmark: "github" } };
        }
        return null;
      }
    }
  });

  assert.deepEqual(
    JSON.parse(vm.runInNewContext("JSON.stringify(state.customizeNavigation.widgetDraft)", sandbox)),
    {
      id: JSON.parse(vm.runInNewContext("JSON.stringify(state.customizeNavigation.widgetDraft.id)", sandbox)),
      kind: "shortcut",
      title: "GitHub",
      url: "https://github.com/",
      colSpan: 1,
      rowSpan: 1
    }
  );
  assert.match(customizeBody?.innerHTML || "", /value="GitHub"/);
  assert.match(customizeBody?.innerHTML || "", /value="https:\/\/github\.com\/"/);
});

test("shortcut editor hides bookmark list when bookmarks are unavailable", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage(message) {
        if (message?.type === "sloppy.bookmarks.list") {
          return Promise.resolve({ error: "bookmarks_unavailable" });
        }
        return Promise.resolve({});
      }
    }
  };
  vm.runInNewContext("state.settings = { startPageItems: [] };", sandbox);
  const panel = sandbox.ensurePanel();

  await sandbox.openShortcutEditor(panel);
  await Promise.resolve();

  assert.equal(panel.querySelector("[data-sloppy-shortcut-bookmarks]"), null);
});

test("transitionStartPageToChat exits start mode before sending", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage() {
        return Promise.resolve({ artifacts: [] });
      }
    }
  };
  vm.runInNewContext("globalThis.SloppyStartPageMode = true;", sandbox);
  const panel = sandbox.ensurePanel();
  sandbox.openCustomize(panel);
  const customizeButton = panel.querySelector("[data-sloppy-customize]");
  const customizeDialog = panel.querySelector("[data-sloppy-customize-dialog]");
  customizeDialog.open = true;

  sandbox.transitionStartPageToChat(panel);

  assert.equal(sandbox.SloppyStartPageMode, false);
  assert.equal(customizeButton.hidden, false);
  assert.equal(panel.classList.toggled.get("is-start-customizing"), false);
  assert.equal(vm.runInNewContext("state.customizeNavigation.editing", sandbox), false);
  assert.equal(customizeDialog.closeCalled, true);
});

test("transitionStartPageToChat closes customize even after start mode already ended", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage() {
        return Promise.resolve({ artifacts: [] });
      }
    }
  };
  vm.runInNewContext("globalThis.SloppyStartPageMode = false;", sandbox);
  const panel = sandbox.ensurePanel();
  sandbox.openCustomize(panel);
  const customizeButton = panel.querySelector("[data-sloppy-customize]");
  const customizeDialog = panel.querySelector("[data-sloppy-customize-dialog]");
  customizeDialog.open = true;

  sandbox.transitionStartPageToChat(panel);

  assert.equal(sandbox.SloppyStartPageMode, false);
  assert.equal(customizeButton.hidden, false);
  assert.equal(panel.classList.toggled.get("is-start-customizing"), false);
  assert.equal(vm.runInNewContext("state.customizeNavigation.editing", sandbox), false);
  assert.equal(customizeDialog.closeCalled, true);
});

test("sidebar new session closes start page customize editing", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      },
      sendMessage() {
        return Promise.resolve({ artifacts: [] });
      }
    }
  };
  vm.runInNewContext("globalThis.SloppyStartPageMode = true;", sandbox);
  const panel = sandbox.ensurePanel();
  sandbox.openCustomize(panel);
  const customizeButton = panel.querySelector("[data-sloppy-customize]");
  const customizeDialog = panel.querySelector("[data-sloppy-customize-dialog]");
  customizeDialog.open = true;

  await panel.querySelector("[data-sloppy-sidebar-new]").listeners.get("click")();

  assert.equal(customizeButton.hidden, false);
  assert.equal(panel.classList.toggled.get("is-start-customizing"), false);
  assert.equal(vm.runInNewContext("state.customizeNavigation.editing", sandbox), false);
  assert.equal(customizeDialog.closeCalled, true);
});

test("browser context messages do not attach automatic Safari DOM snapshots", () => {
  const source = readFileSync(new URL("../Resources/contentScript.js", import.meta.url), "utf8");

  assert.doesNotMatch(source, /pageSnapshot:\s*buildDOMSnapshot\(document\)/);
  assert.match(source, /browser\.dom_snapshot/);
});

test("floating button hides while the search ask button is visible", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        return `safari-extension://sloppy/${path}`;
      }
    }
  };
  vm.runInNewContext("state.settings = { floatingButtonEnabled: true };", sandbox);
  documentLike.location.href = "https://www.google.com/search?q=sloppy";

  sandbox.renderSearchButton();
  sandbox.renderFloatingButton();

  const searchButton = documentLike.getElementById("sloppy-search-ask-button");
  const floatingButton = documentLike.getElementById("sloppy-floating-button");
  assert.equal(searchButton.hidden, false);
  assert.equal(floatingButton, null);
});

test("cachedSelectionInfo falls back to the last mobile selection rect", () => {
  const { cachedSelectionInfo } = loadContentScriptSandbox();
  const rect = { left: 10, top: 20, right: 40, bottom: 60, width: 30, height: 40 };

  assert.equal(
    JSON.stringify(cachedSelectionInfo(null, { selectionMenuText: "Selected text", selectionMenuRect: rect })),
    JSON.stringify({ text: "Selected text", rect })
  );
  assert.equal(cachedSelectionInfo(null, { selectionMenuText: "", selectionMenuRect: rect }), null);
});

test("quickChatPlacementStyle anchors the mini chat to the selection menu position", () => {
  const { quickChatPlacementStyle } = loadContentScriptSandbox();
  const rect = { left: 420, top: 120, right: 520, bottom: 144, width: 100, height: 24 };
  const style = quickChatPlacementStyle(rect, {
    innerWidth: 1200,
    innerHeight: 800,
    navigator: { maxTouchPoints: 0 }
  });

  assert.equal(JSON.stringify(style), JSON.stringify({
    left: "494px",
    top: "156px",
    transform: "none"
  }));
});

test("quickChatPlacementStyle flips above low selections", () => {
  const { quickChatPlacementStyle } = loadContentScriptSandbox();
  const rect = { left: 900, top: 710, right: 990, bottom: 734, width: 90, height: 24 };
  const style = quickChatPlacementStyle(rect, {
    innerWidth: 1200,
    innerHeight: 800,
    navigator: { maxTouchPoints: 0 }
  });

  assert.equal(JSON.stringify(style), JSON.stringify({
    left: "824px",
    top: "698px",
    transform: "translateY(-100%)"
  }));
});

test("icon URLs match flattened Safari extension SVG resources", () => {
  const sandbox = loadContentScriptSandbox();
  const requestedPaths = [];
  sandbox.chrome = {
    runtime: {
      getURL(path) {
        requestedPaths.push(path);
        return `safari-web-extension://extension-id/${path}`;
      }
    }
  };

  const html = sandbox.icon("sessions");

  assert.deepEqual(requestedPaths, ["list.bullet.svg"]);
  assert.match(html, /safari-web-extension:\/\/extension-id\/list\.bullet\.svg/);
  assert.doesNotMatch(html, /icons\/list\.bullet\.svg/);
});

test("snapshotSelectionForFloatingButton preserves selection before mobile Safari collapses it", () => {
  const sandbox = loadContentScriptSandbox();
  const rect = { left: 10, top: 20, right: 40, bottom: 60, width: 30, height: 40 };
  const range = {
    getClientRects() {
      return [rect];
    },
    getBoundingClientRect() {
      return rect;
    }
  };
  sandbox.getSelection = () => ({
    anchorNode: {},
    focusNode: {},
    rangeCount: 1,
    getRangeAt() {
      return range;
    },
    toString() {
      return " Selected text ";
    }
  });

  const info = sandbox.snapshotSelectionForFloatingButton();
  const cached = vm.runInNewContext(
    "({ text: state.selectionMenuText, rect: state.selectionMenuRect })",
    sandbox
  );

  assert.equal(info.text, "Selected text");
  assert.equal(cached.text, "Selected text");
  assert.equal(cached.rect, rect);
});

test("positionSelectionMenu opens the popover above lower viewport selections", () => {
  const sandbox = loadContentScriptSandbox();
  const { positionSelectionMenu } = sandbox;
  const toggles = new Map();
  const properties = new Map();
  const menu = {
    style: {
      left: "",
      top: "",
      setProperty(name, value) {
        properties.set(name, value);
      }
    },
    classList: {
      toggle(name, value) {
        toggles.set(name, value);
      }
    }
  };

  sandbox.window = { innerWidth: 390, innerHeight: 700 };
  sandbox.document = { documentElement: { clientWidth: 390, clientHeight: 700 } };
  positionSelectionMenu(menu, { top: 620, right: 220, bottom: 650 }, true);

  assert.equal(menu.style.top, "586px");
  assert.equal(toggles.get("is-popover-open"), true);
  assert.equal(toggles.get("is-popover-above"), true);
  assert.equal(properties.get("--sloppy-selection-popover-x"), "-137px");
});

test("positionSelectionMenu keeps the popover below upper viewport selections", () => {
  const sandbox = loadContentScriptSandbox();
  const { positionSelectionMenu } = sandbox;
  const toggles = new Map();
  const menu = {
    style: { setProperty() {} },
    classList: {
      toggle(name, value) {
        toggles.set(name, value);
      }
    }
  };

  sandbox.window = { innerWidth: 800, innerHeight: 700 };
  sandbox.document = { documentElement: { clientWidth: 800, clientHeight: 700 } };
  positionSelectionMenu(menu, { top: 80, right: 220, bottom: 110 }, true);

  assert.equal(menu.style.top, "118px");
  assert.equal(toggles.get("is-popover-open"), true);
  assert.equal(toggles.get("is-popover-above"), false);
});

test("positionSelectionMenu uses a mobile bottom sheet on touch viewports", () => {
  const sandbox = loadContentScriptSandbox();
  const { positionSelectionMenu } = sandbox;
  const toggles = new Map();
  const properties = new Map();
  const menu = {
    style: {
      left: "",
      top: "",
      setProperty(name, value) {
        properties.set(name, value);
      }
    },
    classList: {
      toggle(name, value) {
        toggles.set(name, value);
      }
    }
  };

  sandbox.window = { innerWidth: 390, innerHeight: 700, navigator: { maxTouchPoints: 5 } };
  sandbox.document = { documentElement: { clientWidth: 390, clientHeight: 700 } };
  positionSelectionMenu(menu, { top: 620, right: 220, bottom: 650 }, true);

  assert.equal(menu.style.left, "0px");
  assert.equal(menu.style.top, "0px");
  assert.equal(toggles.get("is-popover-open"), true);
  assert.equal(toggles.get("is-mobile-sheet"), true);
  assert.equal(toggles.get("is-popover-above"), false);
  assert.equal(properties.get("--sloppy-selection-popover-x"), "0px");
});

test("updateSelectionMenu keeps mobile selection sheet closed until the bubble is tapped", () => {
  const sandbox = loadContentScriptSandbox();
  const toggles = new Map();
  const rect = { left: 10, top: 20, right: 40, bottom: 60, width: 30, height: 40 };
  const popover = { hidden: false };
  const menu = {
    hidden: true,
    style: { left: "", top: "", setProperty() {} },
    classList: {
      toggle(name, value) {
        toggles.set(name, value);
      }
    },
    querySelector(selector) {
      return selector === "[data-sloppy-selection-popover]" ? popover : null;
    }
  };
  const range = {
    getClientRects() {
      return [rect];
    },
    getBoundingClientRect() {
      return rect;
    }
  };

  sandbox.window = { innerWidth: 390, innerHeight: 700, navigator: { maxTouchPoints: 5 }, clearTimeout() {}, setTimeout(callback) { callback(); } };
  sandbox.document = {
    activeElement: null,
    documentElement: { clientWidth: 390, clientHeight: 700 },
    getElementById(id) {
      return id === "sloppy-selection-menu" ? menu : null;
    }
  };
  sandbox.getSelection = () => ({
    anchorNode: {},
    focusNode: {},
    rangeCount: 1,
    getRangeAt() {
      return range;
    },
    toString() {
      return "Selected text";
    }
  });
  sandbox.ensureSelectionMenu = () => menu;

  sandbox.updateSelectionMenu();

  assert.equal(menu.hidden, false);
  assert.equal(popover.hidden, true);
  assert.equal(toggles.get("is-mobile-sheet"), false);
});

test("selectionPopoverIsOpen detects an open selection popover after mobile selection collapses", () => {
  const sandbox = loadContentScriptSandbox();
  const { selectionPopoverIsOpen } = sandbox;
  const popover = { hidden: false };
  const menu = {
    hidden: false,
    querySelector(selector) {
      return selector === "[data-sloppy-selection-popover]" ? popover : null;
    }
  };

  sandbox.document = {
    getElementById(id) {
      return id === "sloppy-selection-menu" ? menu : null;
    }
  };

  assert.equal(selectionPopoverIsOpen(), true);
  popover.hidden = true;
  assert.equal(selectionPopoverIsOpen(), false);
});

test("viewportMetrics tracks the visible Safari viewport for keyboard positioning", () => {
  const { viewportMetrics } = loadContentScriptSandbox();
  const metrics = viewportMetrics({
    innerWidth: 430,
    innerHeight: 932,
    visualViewport: {
      width: 430,
      height: 612,
      offsetTop: 180,
      offsetLeft: 0
    }
  });

  assert.equal(metrics.width, 430);
  assert.equal(metrics.height, 612);
  assert.equal(metrics.top, 180);
  assert.equal(metrics.left, 0);
  assert.equal(metrics.bottomGap, 140);
});

test("isMobileViewport detects narrow touch-style Safari viewports", () => {
  const { isMobileViewport } = loadContentScriptSandbox();

  assert.equal(isMobileViewport({ innerWidth: 430, navigator: { maxTouchPoints: 5 } }), true);
  assert.equal(isMobileViewport({ innerWidth: 1180, navigator: { maxTouchPoints: 5 } }), false);
  assert.equal(isMobileViewport({ innerWidth: 430, navigator: { maxTouchPoints: 0 } }), true);
});

test("mobile viewports collapse page context by default", () => {
  const { shouldCollapseContextByDefault } = loadContentScriptSandbox();

  assert.equal(shouldCollapseContextByDefault({ innerWidth: 430, navigator: { maxTouchPoints: 5 } }), true);
  assert.equal(shouldCollapseContextByDefault({ innerWidth: 900, navigator: { maxTouchPoints: 5 } }), false);
});

test("spatial panel effects require wide touch and hover-capable input", () => {
  const { supportsSpatialPanelEffects } = loadContentScriptSandbox();

  assert.equal(
    supportsSpatialPanelEffects({
      innerWidth: 1024,
      navigator: { maxTouchPoints: 5 },
      matchMedia: () => ({ matches: true })
    }),
    true
  );
  assert.equal(
    supportsSpatialPanelEffects({
      innerWidth: 430,
      navigator: { maxTouchPoints: 5 },
      matchMedia: () => ({ matches: true })
    }),
    false
  );
  assert.equal(
    supportsSpatialPanelEffects({
      innerWidth: 1024,
      navigator: { maxTouchPoints: 0 },
      matchMedia: () => ({ matches: true })
    }),
    false
  );
});

test("shouldSubmitPromptOnEnter sends only when the virtual keyboard is not visible", () => {
  const { shouldSubmitPromptOnEnter, virtualKeyboardVisible } = loadContentScriptSandbox();
  const physicalKeyboardViewport = {
    innerWidth: 430,
    innerHeight: 932,
    navigator: { maxTouchPoints: 5 },
    visualViewport: {
      width: 430,
      height: 932,
      offsetTop: 0,
      offsetLeft: 0
    }
  };
  const virtualKeyboardViewport = {
    innerWidth: 430,
    innerHeight: 932,
    navigator: { maxTouchPoints: 5 },
    visualViewport: {
      width: 430,
      height: 612,
      offsetTop: 180,
      offsetLeft: 0
    }
  };

  assert.equal(virtualKeyboardVisible(virtualKeyboardViewport), true);
  assert.equal(shouldSubmitPromptOnEnter({ key: "Enter" }, physicalKeyboardViewport), true);
  assert.equal(shouldSubmitPromptOnEnter({ key: "Enter" }, virtualKeyboardViewport), false);
  assert.equal(shouldSubmitPromptOnEnter({ key: "Enter", shiftKey: true }, physicalKeyboardViewport), false);
  assert.equal(shouldSubmitPromptOnEnter({ key: "Enter", isComposing: true }, physicalKeyboardViewport), false);
});

test("commandQueryForTextarea detects slash command text at the caret", () => {
  const { commandQueryForTextarea } = loadContentScriptSandbox();

  assert.equal(
    JSON.stringify(commandQueryForTextarea({ value: "hello /sta", selectionStart: 10 })),
    JSON.stringify({ query: "sta", start: 6, end: 10 })
  );
  assert.equal(commandQueryForTextarea({ value: "hello/not", selectionStart: 9 }), null);
  assert.equal(commandQueryForTextarea({ value: "/model gpt", selectionStart: 10 }), null);
});

test("normalizeAttachment assigns an id for screenshot attachments", () => {
  const { normalizeAttachment } = loadContentScriptSandbox();
  const attachment = normalizeAttachment({ name: "safari-tab.png", mimeType: "image/png" });

  assert.equal(attachment.name, "safari-tab.png");
  assert.equal(typeof attachment.id, "string");
  assert.equal(attachment.id.length > 0, true);
});

test("summarizePagePrompt asks the agent to use attached Safari page context", () => {
  const { summarizePagePrompt } = loadContentScriptSandbox();
  const prompt = summarizePagePrompt();

  assert.match(prompt, /Safari page context/i);
  assert.match(prompt, /do not use web\.fetch/i);
});

test("summarizePagePrompt localizes prompt text from system language", () => {
  const { summarizePagePrompt } = loadContentScriptSandboxWithLocale("zh-CN");
  const prompt = summarizePagePrompt();

  assert.match(prompt, /总结此页面/);
  assert.match(prompt, /Safari 页面上下文/);
  assert.match(prompt, /不要.*web\.fetch/);
});

test("buildDOMSnapshot includes compact page body text for summaries", () => {
  const { buildDOMSnapshot } = loadContentScriptSandbox();
  const snapshot = buildDOMSnapshot({
    title: "Article",
    location: { href: "https://example.com/article" },
    activeElement: null,
    body: { innerText: " First paragraph.\n\nSecond paragraph. " },
    querySelectorAll() {
      return [];
    }
  });

  assert.equal(snapshot.text, "First paragraph. Second paragraph.");
});

test("applyAgentResponse reads assistant text from appended events", () => {
  const { applyAgentResponse } = loadContentScriptSandbox();
  const message = { text: "", attachments: [], toolCalls: [] };

  applyAgentResponse(message, {
    appendedEvents: [
      {
        message: {
          role: "assistant",
          segments: [{ text: "Answer from session events" }]
        }
      }
    ]
  });

  assert.equal(message.text, "Answer from session events");
});

test("animatedTextSteps reveals final assistant text progressively", () => {
  const { animatedTextSteps } = loadContentScriptSandbox();
  const steps = animatedTextSteps("", "Streaming answer");

  assert.equal(steps.at(-1), "Streaming answer");
  assert.equal(steps.length > 1, true);
  assert.equal(steps.every((step, index) => index === 0 || step.length >= steps[index - 1].length), true);
});

test("animatedTextSteps continues from already streamed assistant text", () => {
  const { animatedTextSteps } = loadContentScriptSandbox();
  const steps = animatedTextSteps("Partial", "Partial answer");

  assert.equal(JSON.stringify(steps), JSON.stringify(["Partial a", "Partial ans", "Partial answe", "Partial answer"]));
});

test("agentResponseText ignores thinking-only assistant messages when final text is available", () => {
  const { agentResponseText } = loadContentScriptSandbox();
  const text = agentResponseText({
    appendedEvents: [
      {
        message: {
          role: "assistant",
          segments: [{ kind: "thinking", text: "Thinking privately" }]
        }
      },
      {
        message: {
          role: "assistant",
          segments: [{ kind: "text", text: "Final answer" }]
        }
      }
    ]
  });

  assert.equal(text, "Final answer");
});

test("agentResponseText reads assistant content fields from appended events", () => {
  const { agentResponseText } = loadContentScriptSandbox();
  const text = agentResponseText({
    appendedEvents: [
      {
        message: {
          role: "assistant",
          content: "Content answer"
        }
      }
    ]
  });

  assert.equal(text, "Content answer");
});

test("agentResponseText falls back to interrupted run status details when no assistant text exists", () => {
  const { agentResponseText } = loadContentScriptSandbox();
  const text = agentResponseText({
    appendedEvents: [
      {
        message: {
          role: "assistant",
          segments: [{ kind: "thinking", text: "Inspecting privately" }]
        }
      },
      {
        type: "run_status",
        runStatus: {
          stage: "interrupted",
          label: "Error",
          details: "Model provider error: unsupportedModel(\"opencode:openai-yandex-team/gpt-5.4\")"
        }
      }
    ]
  });

  assert.equal(text, "Model provider error: unsupportedModel(\"opencode:openai-yandex-team/gpt-5.4\")");
});

test("updateStreamingMessage replaces accumulated session deltas", async () => {
  const sandbox = loadContentScriptSandbox();
  const message = { id: "assistant-1", text: "", attachments: [], toolCalls: [], streaming: true };
  sandbox.__testMessage = message;
  vm.runInNewContext("state.messages = [__testMessage]; state.streamingMessageId = 'assistant-1';", sandbox);

  await sandbox.updateStreamingMessage({ type: "delta", text: "Hel", replace: true });
  await sandbox.updateStreamingMessage({ type: "delta", text: "Hello", replace: true });

  assert.equal(message.text, "Hello");
});

test("updateStreamingMessage reveals incoming assistant deltas with typing ticks", async () => {
  const sandbox = loadContentScriptSandbox();
  const message = { id: "assistant-1", text: "", attachments: [], toolCalls: [], streaming: true };
  let tickCount = 0;
  sandbox.window.setTimeout = (callback) => {
    tickCount += 1;
    callback();
    return tickCount;
  };
  sandbox.window.clearTimeout = () => {};
  sandbox.__testMessage = message;
  vm.runInNewContext("state.messages = [__testMessage]; state.streamingMessageId = 'assistant-1';", sandbox);

  await sandbox.updateStreamingMessage({ type: "delta", text: "Animated streaming answer", replace: true });

  assert.equal(message.text, "Animated streaming answer");
  assert.equal(tickCount > 0, true);
});

test("updateStreamingMessage reveals assistant content field events", async () => {
  const sandbox = loadContentScriptSandbox();
  const message = { id: "assistant-1", text: "", attachments: [], toolCalls: [], streaming: true };
  sandbox.__testMessage = message;
  vm.runInNewContext("state.messages = [__testMessage]; state.streamingMessageId = 'assistant-1';", sandbox);

  await sandbox.updateStreamingMessage({
    type: "assistant_message",
    event: {
      type: "message",
      message: {
        role: "assistant",
        content: "Stream content answer"
      }
    }
  });

  assert.equal(message.text, "Stream content answer");
});

test("normalizeSessionMessages maps session detail events into chat messages", () => {
  const { normalizeSessionMessages } = loadContentScriptSandbox();
  const messages = normalizeSessionMessages([
    {
      id: "event-user",
      message: {
        id: "message-user",
        role: "user",
        segments: [{
          kind: "text",
          text: [
            "Source: Safari Extension",
            "URL: https://example.com",
            "",
            "Selected text:",
            "No selected text.",
            "",
            "User prompt:",
            "Привет"
          ].join("\n")
        }]
      }
    },
    {
      id: "event-assistant",
      message: {
        id: "message-assistant",
        role: "assistant",
        segments: [
          { kind: "thinking", text: "Looking..." },
          { kind: "text", text: "Здравствуйте!" },
          { kind: "attachment", attachment: { name: "answer.txt", mimeType: "text/plain" } }
        ]
      }
    },
    {
      id: "event-tool",
      type: "tool_call",
      toolCall: { name: "browser.capture_visible_tab" }
    }
  ]);

  assert.equal(messages.length, 2);
  assert.equal(messages[0].id, "message-user");
  assert.equal(messages[0].role, "user");
  assert.equal(messages[0].text, "Привет");
  assert.equal(messages[1].role, "assistant");
  assert.equal(messages[1].text, "Здравствуйте!");
  assert.equal(messages[1].attachments[0].name, "answer.txt");
  assert.equal(typeof messages[1].attachments[0].id, "string");
});

test("settings dialog includes mesh invite and target node controls", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.window = {
    innerWidth: 1280,
    innerHeight: 900,
    navigator: { maxTouchPoints: 0 },
    matchMedia: () => ({ matches: false })
  };
  sandbox.chrome = {
    runtime: {
      getURL: (path) => `safari-extension://sloppy/${path}`
    }
  };
  sandbox.wirePanel = () => {};
  sandbox.updateViewportCSSVars = () => {};

  const frame = sandbox.ensurePanel();

  assert.ok(frame.querySelector("[data-sloppy-mesh-enabled]"));
  assert.ok(frame.querySelector("[data-sloppy-mesh-invite]"));
  assert.ok(frame.querySelector("[data-sloppy-mesh-target-node]"));
  assert.ok(frame.querySelector("[data-sloppy-mesh-join]"));
  assert.ok(frame.querySelector("[data-sloppy-mesh-status]"));
});

test("openSettings loads mesh settings values into the dialog", () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  sandbox.document = documentLike;
  sandbox.window = {
    innerWidth: 1280,
    innerHeight: 900,
    navigator: { maxTouchPoints: 0 },
    matchMedia: () => ({ matches: false })
  };
  sandbox.chrome = {
    runtime: {
      getURL: (path) => `safari-extension://sloppy/${path}`,
      sendMessage: async (request) => {
        if (request.type === "sloppy.settings.get") {
          return {
            coreURLString: "http://127.0.0.1:25101",
            authToken: "token",
            defaultAgentID: "sloppy",
            floatingButtonEnabled: true,
            selectionBubbleEnabled: false,
            mesh: {
              enabled: true,
              targetNodeId: "node-42",
              relayURL: "https://relay.example.com",
              networkName: "Test Mesh",
              identity: { nodeId: "local-node" }
            }
          };
        }
        return {};
      }
    }
  };
  sandbox.wirePanel = () => {};
  sandbox.updateViewportCSSVars = () => {};
  sandbox.loadAgents = async () => {};
  sandbox.refreshTabs = async () => {};
  sandbox.loadSlashCommands = async () => {};
  sandbox.render = () => {};
  sandbox.renderFloatingButton = () => {};
  sandbox.renderSearchButton = () => {};

  return sandbox.openPanelWithSelection("Selected text").then((panel) => {
    sandbox.openSettings(panel);

    assert.equal(panel.querySelector("[data-sloppy-mesh-enabled]").checked, true);
    assert.equal(panel.querySelector("[data-sloppy-mesh-target-node]").value, "node-42");
    assert.equal(panel.querySelector("[data-sloppy-mesh-status]").textContent, "Mesh: Test Mesh as local-node");
    assert.equal(panel.querySelector("[data-sloppy-settings-dialog]").showModalCalled, true);
  });
});

test("saveSettings persists mesh enabled and target node settings", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  const savedRequests = [];
  sandbox.document = documentLike;
  sandbox.window = {
    innerWidth: 1280,
    innerHeight: 900,
    navigator: { maxTouchPoints: 0 },
    matchMedia: () => ({ matches: false })
  };
  sandbox.chrome = {
    runtime: {
      getURL: (path) => `safari-extension://sloppy/${path}`,
      sendMessage: async (request) => {
        savedRequests.push(request);
        if (request.type === "sloppy.settings.get") {
          return {
            coreURLString: "http://127.0.0.1:25101",
            authToken: "token",
            defaultAgentID: "sloppy",
            sessionId: "session-1",
            floatingButtonEnabled: false,
            selectionBubbleEnabled: true,
            mesh: {
              relayURL: "https://relay.example.com",
              networkId: "mesh-1"
            }
          };
        }
        return request.settings;
      }
    }
  };
  sandbox.wirePanel = () => {};
  sandbox.updateViewportCSSVars = () => {};
  sandbox.loadAgents = async () => {};
  sandbox.refreshTabs = async () => {};
  sandbox.loadSlashCommands = async () => {};
  sandbox.render = () => {};
  sandbox.renderFloatingButton = () => {};
  sandbox.hideSelectionMenu = () => {};
  sandbox.scheduleSelectionMenuUpdate = () => {};
  sandbox.renderSearchButton = () => {};

  const panel = await sandbox.openPanelWithSelection("Selected text");
  panel.querySelector("[data-sloppy-core-url]").value = "http://127.0.0.1:25101";
  panel.querySelector("[data-sloppy-auth-token]").value = "token";
  panel.querySelector("[data-sloppy-default-agent]").value = "sloppy";
  panel.querySelector("[data-sloppy-floating-button]").checked = true;
  panel.querySelector("[data-sloppy-selection-bubble-enabled]").checked = true;
  panel.querySelector("[data-sloppy-mesh-enabled]").checked = true;
  panel.querySelector("[data-sloppy-mesh-target-node]").value = "node-99";

  await sandbox.saveSettings(panel);

  const saveRequest = savedRequests.find((request) => request.type === "sloppy.settings.save");
  assert.ok(saveRequest);
  assert.equal(saveRequest.settings.mesh.enabled, true);
  assert.equal(saveRequest.settings.mesh.targetNodeId, "node-99");
  assert.equal(saveRequest.settings.mesh.relayURL, "https://relay.example.com");
  assert.equal(panel.querySelector("[data-sloppy-settings-dialog]").closeCalled, true);
});

test("voice language picker persists language setting", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  const savedRequests = [];
  sandbox.document = documentLike;
  sandbox.window = {
    innerWidth: 1280,
    innerHeight: 900,
    navigator: { maxTouchPoints: 0 },
    matchMedia: () => ({ matches: false })
  };
  sandbox.chrome = {
    runtime: {
      getURL: (path) => `safari-extension://sloppy/${path}`,
      sendMessage: async (request) => {
        savedRequests.push(request);
        if (request.type === "sloppy.settings.save") {
          return request.settings;
        }
        return {};
      }
    }
  };

  const panel = sandbox.ensurePanel();
  vm.runInNewContext("state.settings = { defaultAgentID: 'sloppy', voiceLanguage: 'auto', mesh: { enabled: false } };", sandbox);
  sandbox.wirePanel(panel);
  const language = panel.querySelector("[data-sloppy-voice-language]");
  language.value = "ru-RU";
  await language.listeners.get("change")({ target: language });

  const saveRequest = savedRequests.find((request) => request.type === "sloppy.settings.save");
  assert.ok(saveRequest);
  assert.equal(saveRequest.settings.voiceLanguage, "ru-RU");
});

test("mesh join updates public settings state and status without exposing private keys", async () => {
  const sandbox = loadContentScriptSandbox();
  const documentLike = createPanelDocument();
  const sentRequests = [];
  sandbox.document = documentLike;
  sandbox.window = {
    innerWidth: 1280,
    innerHeight: 900,
    navigator: { maxTouchPoints: 0 },
    matchMedia: () => ({ matches: false })
  };
  sandbox.chrome = {
    runtime: {
      getURL: (path) => `safari-extension://sloppy/${path}`,
      sendMessage: async (request) => {
        sentRequests.push(request);
        if (request.type === "sloppy.settings.get") {
          return {
            coreURLString: "http://127.0.0.1:25101",
            authToken: "token",
            defaultAgentID: "sloppy",
            floatingButtonEnabled: false,
            selectionBubbleEnabled: true,
            mesh: {
              enabled: false,
              targetNodeId: "node-join",
              relayURL: "https://relay.example.com",
              networkName: "Before Mesh",
              identity: { nodeId: "node-before", publicKey: "ed25519:before" }
            }
          };
        }
        if (request.type === "sloppy.mesh.join") {
          return {
            mesh: {
              enabled: true,
              targetNodeId: "node-join",
              relayURL: "https://relay.example.com",
              networkName: "Joined Mesh",
              identity: {
                nodeId: "node-after",
                publicKey: "ed25519:after"
              }
            }
          };
        }
        if (request.type === "sloppy.settings.save") {
          return request.settings;
        }
        return {};
      }
    }
  };
  sandbox.updateViewportCSSVars = () => {};
  sandbox.loadAgents = async () => {};
  sandbox.refreshTabs = async () => {};
  sandbox.loadSlashCommands = async () => {};
  sandbox.render = () => {};
  sandbox.renderFloatingButton = () => {};
  sandbox.renderSearchButton = () => {};
  sandbox.hideSelectionMenu = () => {};
  sandbox.scheduleSelectionMenuUpdate = () => {};

  const panel = await sandbox.openPanelWithSelection("Selected text");
  sandbox.openSettings(panel);
  panel.querySelector("[data-sloppy-mesh-invite]").value = "slp_mesh_token";

  await panel.querySelector("[data-sloppy-mesh-join]").click();

  const joinRequest = sentRequests.find((request) => request.type === "sloppy.mesh.join");
  assert.equal(joinRequest.type, "sloppy.mesh.join");
  assert.equal(joinRequest.token, "slp_mesh_token");
  assert.equal(panel.querySelector("[data-sloppy-mesh-status]").textContent, "Mesh: Joined Mesh as node-after");

  sandbox.openSettings(panel);

  assert.equal(panel.querySelector("[data-sloppy-mesh-enabled]").checked, true);
  assert.equal(panel.querySelector("[data-sloppy-mesh-target-node]").value, "node-join");
  assert.equal(panel.querySelector("[data-sloppy-mesh-status]").textContent, "Mesh: Joined Mesh as node-after");

  await sandbox.saveSettings(panel);
  const saveRequest = sentRequests.find((request) => request.type === "sloppy.settings.save");
  assert.equal(saveRequest.settings.mesh.identity.privateKey, undefined);
  assert.deepEqual(saveRequest.settings.mesh.identity, {
    nodeId: "node-after",
    publicKey: "ed25519:after"
  });
});
