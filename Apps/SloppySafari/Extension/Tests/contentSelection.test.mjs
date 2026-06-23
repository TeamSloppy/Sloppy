import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

function loadContentScriptSandbox() {
  const i18nSource = readFileSync(new URL("../Resources/i18n.js", import.meta.url), "utf8");
  const source = readFileSync(new URL("../Resources/contentScript.js", import.meta.url), "utf8");
  assert.equal(/\bexport\s+function\b/.test(source), false);

  const sandbox = {
    chrome: undefined,
    document: undefined,
    navigator: { language: "en-US", languages: ["en-US"] },
    URL,
    window: {},
    globalThis: {}
  };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(i18nSource, sandbox);
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
        nodesBySelector.set(selector, {
          selector,
          value: "",
          checked: false,
          textContent: "",
          innerHTML: "",
          hidden: false,
          style: {},
          dataset: {},
          classList: { toggle() {}, add() {}, remove() {} },
          listeners,
          addEventListener(type, listener) {
            listeners.set(type, listener);
          },
          appendChild() {},
          focus() {},
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
          }
        });
      }
      return nodesBySelector.get(selector);
    };
    return {
      tagName: String(tagName || "").toUpperCase(),
      id: "",
      style: { setProperty() {} },
      classList: { toggle() {}, add() {}, remove() {} },
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
      }
    }
  };

  const panel = sandbox.ensurePanel();

  assert.match(panel.innerHTML, /placeholder="Спросить об этой странице"/);
  assert.match(panel.innerHTML, /aria-label="Настройки"/);
  assert.match(panel.innerHTML, /Новая сессия/);
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
