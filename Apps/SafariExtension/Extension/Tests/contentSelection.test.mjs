import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

function loadContentScriptSandbox() {
  const source = readFileSync(new URL("../Resources/contentScript.js", import.meta.url), "utf8");
  assert.equal(/\bexport\s+function\b/.test(source), false);

  const sandbox = {
    chrome: undefined,
    document: undefined,
    globalThis: {}
  };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(source, sandbox);
  return sandbox;
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
