import assert from "node:assert/strict";
import { test } from "node:test";
import { buildBrowserContextPayload, normalizeCoreURL } from "../Resources/panel.js";

test("normalizeCoreURL adds http scheme and removes trailing slashes", () => {
  assert.equal(normalizeCoreURL("192.168.1.50:25101/"), "http://192.168.1.50:25101");
});

test("buildBrowserContextPayload creates typed Safari context payload", () => {
  const payload = buildBrowserContextPayload(
    { defaultAgentID: "sloppy" },
    { url: "https://example.com/a", title: "Article" },
    "Selected text",
    "Explain this"
  );

  assert.deepEqual(payload, {
    source: "safari_extension",
    page: {
      url: "https://example.com/a",
      title: "Article"
    },
    selection: {
      text: "Selected text"
    },
    prompt: "Explain this",
    target: {
      agentId: "sloppy",
      sessionId: null
    },
    userId: "safari_extension"
  });
});
