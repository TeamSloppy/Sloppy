import assert from "node:assert/strict";
import { test } from "node:test";
import {
  buildBrowserContextPayload,
  chooseAgentID,
  collectBrowserToolActions,
  decodeSSEBlock,
  describeCoreError,
  fallbackSelectionText,
  normalizeCoreURL,
  normalizeAgentSessions,
  postBrowserContext,
  postBrowserContextStreaming,
  renderMarkdown,
  sanitizeSettings
} from "../Resources/panel.js";

test("normalizeCoreURL adds http scheme and removes trailing slashes", () => {
  assert.equal(normalizeCoreURL("192.168.1.50:25101/"), "http://192.168.1.50:25101");
});

test("buildBrowserContextPayload creates typed Safari context payload", () => {
  const payload = buildBrowserContextPayload(
    { defaultAgentID: "sloppy" },
    { url: "https://example.com/a", title: "Article" },
    "Selected text",
    "Explain this",
    {
      tabs: [{ id: 7, url: "https://example.com/other", title: "Other" }],
      pageSnapshot: { elements: [{ selector: "#buy", text: "Buy" }] },
      attachments: [{ id: "att-1", name: "note.md", mimeType: "text/markdown", sizeBytes: 8, contentBase64: "IyBOb3Rl" }]
    }
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
    browser: {
      tabs: [{ id: 7, url: "https://example.com/other", title: "Other" }],
      pageSnapshot: { elements: [{ selector: "#buy", text: "Buy" }] }
    },
    attachments: [{ name: "note.md", mimeType: "text/markdown", sizeBytes: 8, contentBase64: "IyBOb3Rl" }],
    prompt: "Explain this",
    target: {
      agentId: "sloppy",
      sessionId: null
    },
    userId: "safari_extension"
  });
});

test("buildBrowserContextPayload allows chat without selected text", () => {
  const payload = buildBrowserContextPayload(
    { defaultAgentID: "sloppy", sessionId: "session-1" },
    { url: "https://example.com/a", title: "Article" },
    "   ",
    "What is this page about?"
  );

  assert.equal(fallbackSelectionText("   "), "No selected text.");
  assert.equal(payload.selection.text, "No selected text.");
  assert.equal(payload.target.sessionId, "session-1");
});

test("sanitizeSettings keeps a user-configured LAN Core URL for extension storage", () => {
  const settings = sanitizeSettings({
    coreURLString: "  192.168.1.50:25101/  ",
    authToken: "  token-1  ",
    defaultAgentID: "  web-agent  ",
    floatingButtonEnabled: true,
    selectionBubbleEnabled: false
  });

  assert.deepEqual(settings, {
    coreURLString: "http://192.168.1.50:25101",
    authToken: "token-1",
    defaultAgentID: "web-agent",
    floatingButtonEnabled: true,
    selectionBubbleEnabled: false
  });
});

test("sanitizeSettings keeps selection bubble enabled by default", () => {
  assert.equal(sanitizeSettings({}).selectionBubbleEnabled, true);
  assert.equal(sanitizeSettings({ selectionBubbleEnabled: false }).selectionBubbleEnabled, false);
});

test("normalizeAgentSessions maps Core sessions into sidebar rows", () => {
  const sessions = normalizeAgentSessions([
    { id: "s1", title: "Safari: example.com", updatedAt: "2026-06-22T10:00:00Z" },
    { sessionId: "s2", name: "Manual chat", createdAt: "2026-06-21T10:00:00Z" },
    { id: "   " }
  ]);

  assert.deepEqual(sessions, [
    { id: "s1", title: "Safari: example.com", subtitle: "2026-06-22T10:00:00Z" },
    { id: "s2", title: "Manual chat", subtitle: "2026-06-21T10:00:00Z" }
  ]);
});

test("renderMarkdown supports common assistant markdown and escapes unsafe html", () => {
  const html = renderMarkdown("**Bold** `code`\n\n- item\n\n<script>alert(1)</script>");

  assert.match(html, /<strong>Bold<\/strong>/);
  assert.match(html, /<code>code<\/code>/);
  assert.match(html, /<ul><li>item<\/li><\/ul>/);
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.equal(html.includes("<script>"), false);
});

test("collectBrowserToolActions normalizes agent browser actions", () => {
  const actions = collectBrowserToolActions({
    openTabs: ["https://example.com/new"],
    actions: [
      { type: "browser.capture_visible_tab" },
      { name: "browser.click_selector", input: { selector: "#buy" } }
    ],
    tool_calls: [
      { tool: "browser.type_text", arguments: { selector: "textarea", text: "hello" } },
      { name: "browser.scroll", arguments: { y: 500 } },
      { name: "browser.dom_snapshot" }
    ]
  });

  assert.deepEqual(actions, [
    { name: "browser.open_tab", input: { url: "https://example.com/new" } },
    { name: "browser.capture_visible_tab", input: {} },
    { name: "browser.click_selector", input: { selector: "#buy" } },
    { name: "browser.type_text", input: { selector: "textarea", text: "hello" } },
    { name: "browser.scroll", input: { y: 500 } },
    { name: "browser.dom_snapshot", input: {} }
  ]);
});

test("chooseAgentID falls back to first fetched agent when stored agent is unavailable", () => {
  assert.equal(
    chooseAgentID("missing", [
      { id: "alpha", title: "Alpha" },
      { id: "beta", title: "Beta" }
    ]),
    "alpha"
  );
  assert.equal(
    chooseAgentID("beta", [
      { id: "alpha", title: "Alpha" },
      { id: "beta", title: "Beta" }
    ]),
    "beta"
  );
});

test("describeCoreError includes status, endpoint, agent and server details", () => {
  const message = describeCoreError({
    status: 404,
    endpoint: "http://127.0.0.1:25101/v1/browser/context-message",
    agentId: "yadev",
    error: "agent_not_found",
    message: "Agent not found."
  });

  assert.match(message, /Core request failed/);
  assert.match(message, /404/);
  assert.match(message, /agent_not_found/);
  assert.match(message, /yadev/);
  assert.match(message, /\/v1\/browser\/context-message/);
});

test("describeCoreError explains missing browser context endpoint", () => {
  const message = describeCoreError({
    status: 404,
    endpoint: "http://192.168.3.199:25101/v1/browser/context-message",
    agentId: "sloppy",
    error: "not_found"
  });

  assert.match(message, /browser context endpoint/i);
  assert.match(message, /update or restart Sloppy Core/i);
  assert.match(message, /192\.168\.3\.199:25101/);
});

test("postBrowserContext falls back to session message endpoints when browser endpoint is missing", async () => {
  const requests = [];
  const fetchImpl = async (url, options) => {
    requests.push({ url, body: options?.body ? JSON.parse(options.body) : null });
    if (url.endsWith("/v1/browser/context-message")) {
      return new Response(JSON.stringify({ error: "not_found" }), { status: 404 });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions")) {
      return Response.json({ id: "session-1" });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/messages")) {
      return Response.json({
        appendedEvents: [
          {
            id: "event-1",
            message: {
              id: "message-1",
              role: "assistant",
              segments: [{ text: "Fallback answer" }]
            }
          }
        ]
      });
    }
    return new Response(JSON.stringify({ error: "unexpected" }), { status: 500 });
  };

  const result = await postBrowserContext(
    { coreURLString: "http://192.168.3.199:25101", defaultAgentID: "sloppy" },
    { url: "https://github.com/", title: "GitHub" },
    "",
    "Привет",
    { attachments: [{ name: "paste.png", mimeType: "image/png", sizeBytes: 4, contentBase64: "abcd" }] },
    fetchImpl
  );

  assert.equal(result.sessionId, "session-1");
  assert.equal(result.messageId, "message-1");
  assert.equal(result.status, "completed");
  assert.equal(result.text, "Fallback answer");
  assert.deepEqual(requests[2].body.attachments, [{ name: "paste.png", mimeType: "image/png", sizeBytes: 4, contentBase64: "abcd" }]);
  assert.equal(requests[2].body.mode, "ask");
  assert.match(requests[2].body.content, /No selected text\./);
  assert.match(requests[2].body.content, /Привет/);
});

test("decodeSSEBlock normalizes Core session stream assistant events", () => {
  const event = decodeSSEBlock([
    "id: 7",
    "event: session_event",
    'data: {"kind":"session_event","cursor":7,"event":{"message":{"role":"assistant","segments":[{"text":"Streaming answer"}]}}}'
  ].join("\n"));

  assert.equal(event.type, "assistant_message");
  assert.equal(event.text, "Streaming answer");
  assert.equal(event.sseEvent, "session_event");
});

test("postBrowserContextStreaming opens a session stream and posts the browser message", async () => {
  const requests = [];
  const encoder = new TextEncoder();
  const fetchImpl = async (url, options = {}) => {
    requests.push({ url, method: options.method || "GET", body: options.body ? JSON.parse(options.body) : null });
    if (url.endsWith("/v1/agents/sloppy/sessions")) {
      return Response.json({ id: "session-1" });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/stream")) {
      return new Response(new ReadableStream({
        start(controller) {
          controller.enqueue(encoder.encode([
            "event: session_event",
            'data: {"kind":"session_event","cursor":1,"event":{"message":{"role":"assistant","segments":[{"text":"Partial answer"}]}}}',
            "",
            ""
          ].join("\n")));
          controller.close();
        }
      }), {
        headers: { "content-type": "text/event-stream" }
      });
    }
    if (url.endsWith("/v1/agents/sloppy/sessions/session-1/messages")) {
      return Response.json({
        appendedEvents: [
          {
            id: "event-2",
            message: {
              id: "message-2",
              role: "assistant",
              segments: [{ text: "Final answer" }]
            }
          }
        ]
      });
    }
    return new Response(JSON.stringify({ error: "unexpected" }), { status: 500 });
  };
  const events = [];

  const result = await postBrowserContextStreaming(
    { coreURLString: "http://127.0.0.1:25101", defaultAgentID: "sloppy" },
    { url: "https://github.com/gpuweb/gpuweb/issues/425", title: "Issue" },
    "",
    "Summarize this page",
    { onEvent: (event) => events.push(event) },
    fetchImpl
  );

  assert.equal(result.sessionId, "session-1");
  assert.equal(result.messageId, "message-2");
  assert.equal(result.text, "Final answer");
  assert.equal(events.some((event) => event.type === "assistant_message" && event.text === "Partial answer"), true);
  assert.deepEqual(
    requests.map((request) => [request.method, request.url.replace("http://127.0.0.1:25101", "")]),
    [
      ["POST", "/v1/agents/sloppy/sessions"],
      ["GET", "/v1/agents/sloppy/sessions/session-1/stream"],
      ["POST", "/v1/agents/sloppy/sessions/session-1/messages"]
    ]
  );
});
