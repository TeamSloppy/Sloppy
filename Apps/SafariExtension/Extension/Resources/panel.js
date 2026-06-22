export function normalizeCoreURL(value) {
  let url = String(value || "").trim();
  if (!url) {
    url = "http://127.0.0.1:25101";
  }
  if (!url.includes("://")) {
    url = `http://${url}`;
  }
  return url.replace(/\/+$/, "");
}

export function sanitizeSettings(settings = {}) {
  const sanitized = {
    coreURLString: normalizeCoreURL(settings.coreURLString),
    authToken: String(settings.authToken || "").trim(),
    defaultAgentID: String(settings.defaultAgentID || "sloppy").trim() || "sloppy",
    floatingButtonEnabled: Boolean(settings.floatingButtonEnabled),
    selectionBubbleEnabled: settings.selectionBubbleEnabled !== false
  };
  if (settings.sessionId) {
    sanitized.sessionId = settings.sessionId;
  }
  return sanitized;
}

export function chooseAgentID(currentAgentID, agents = []) {
  const current = String(currentAgentID || "").trim();
  if (current && agents.some((agent) => agent.id === current)) {
    return current;
  }
  return agents[0]?.id || current || "sloppy";
}

export function fallbackSelectionText(selection) {
  return String(selection || "").trim() || "No selected text.";
}

export function normalizeAgentSessions(records = []) {
  return records
    .map((session) => {
      const id = String(session?.id || session?.sessionId || "").trim();
      if (!id) {
        return null;
      }
      return {
        id,
        title: String(session.title || session.name || id).trim() || id,
        subtitle: String(session.updatedAt || session.createdAt || "").trim()
      };
    })
    .filter(Boolean);
}

function sanitizeTabs(tabs = []) {
  return tabs
    .filter((tab) => tab && tab.url)
    .map((tab) => {
      const sanitized = {
        url: String(tab.url),
        title: tab.title ? String(tab.title) : null
      };
      if (Number.isFinite(tab.id)) {
        sanitized.id = tab.id;
      }
      if (tab.active) {
        sanitized.active = true;
      }
      return sanitized;
    });
}

function sanitizeAttachments(attachments = []) {
  return attachments
    .filter((attachment) => attachment && attachment.name)
    .map((attachment) => {
      const contentBase64 = attachment.contentBase64 || dataURLContent(attachment.dataURL);
      const sanitized = {
        name: String(attachment.name),
        mimeType: String(attachment.mimeType || attachment.type || "application/octet-stream"),
        sizeBytes: Number(attachment.sizeBytes || attachment.size || contentBase64?.length || 0)
      };
      if (contentBase64) {
        sanitized.contentBase64 = String(contentBase64);
      }
      return sanitized;
    });
}

function dataURLContent(dataURL) {
  const value = String(dataURL || "");
  const comma = value.indexOf(",");
  if (!value.startsWith("data:") || comma < 0) {
    return null;
  }
  return value.slice(comma + 1);
}

export function buildBrowserContextPayload(settings, page, selection, prompt, options = {}) {
  return {
    source: "safari_extension",
    page: {
      url: page.url,
      title: page.title || null
    },
    selection: {
      text: fallbackSelectionText(selection)
    },
    browser: {
      tabs: sanitizeTabs(options.tabs),
      ...(options.pageSnapshot ? { pageSnapshot: options.pageSnapshot } : {})
    },
    attachments: sanitizeAttachments(options.attachments),
    prompt: String(prompt || "").trim(),
    target: {
      agentId: String(settings.defaultAgentID || "sloppy").trim() || "sloppy",
      sessionId: settings.sessionId || null
    },
    userId: "safari_extension"
  };
}

function browserContextPrompt(page, selection, prompt) {
  const lines = [
    "Source: Safari Extension",
    `URL: ${page.url}`
  ];
  if (page.title) {
    lines.push(`Title: ${page.title}`);
  }
  lines.push("");
  lines.push("Selected text:");
  lines.push(fallbackSelectionText(selection));
  lines.push("");
  lines.push("User prompt:");
  lines.push(String(prompt || "").trim());
  return lines.join("\n");
}

function headersForSettings(settings) {
  const headers = { "content-type": "application/json" };
  if (settings.authToken) {
    headers.authorization = `Bearer ${settings.authToken}`;
  }
  return headers;
}

function latestAssistantText(events = []) {
  const assistant = [...events].reverse().find((event) => event?.message?.role === "assistant");
  const segments = assistant?.message?.segments || [];
  return segments
    .map((segment) => segment?.text || "")
    .filter(Boolean)
    .join("\n");
}

function assistantTextFromStreamEvent(event = {}) {
  const record = event.event || event.sessionEvent || event;
  const message = record.message || event.message;
  if (message?.role !== "assistant") {
    return "";
  }
  return (message.segments || [])
    .map((segment) => segment?.text || segment?.content || "")
    .filter(Boolean)
    .join("\n");
}

function normalizeStreamEvent(event = {}) {
  const text = assistantTextFromStreamEvent(event);
  if (text) {
    return { ...event, type: "assistant_message", text };
  }
  if (!event.type && event.kind) {
    return { ...event, type: event.kind };
  }
  return event;
}

export function decodeSSEBlock(block) {
  const lines = String(block || "").split(/\r?\n/);
  const dataLines = [];
  let eventName = "";
  for (const line of lines) {
    if (line.startsWith("event:")) {
      eventName = line.slice(6).trim();
    } else if (line.startsWith("data:")) {
      dataLines.push(line.slice(5).trimStart());
    }
  }

  const data = dataLines.join("\n").trim();
  if (!data && !eventName) {
    return null;
  }
  if (data === "[DONE]") {
    return { type: "done" };
  }

  try {
    const parsed = data ? JSON.parse(data) : {};
    if (parsed && typeof parsed === "object") {
      return normalizeStreamEvent({
        ...parsed,
        type: parsed.type || eventName || parsed.kind || "message",
        sseEvent: eventName || parsed.sseEvent
      });
    }
    return { type: eventName || "delta", text: String(parsed || "") };
  } catch {
    return { type: eventName || "delta", text: data };
  }
}

async function readSSEStream(body, onEvent) {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    buffer += decoder.decode(value, { stream: true });
    const blocks = buffer.split(/\r?\n\r?\n/);
    buffer = blocks.pop() || "";
    for (const block of blocks) {
      const event = decodeSSEBlock(block);
      if (event) {
        onEvent(event);
      }
    }
  }
  const tail = buffer.trim();
  if (tail) {
    const event = decodeSSEBlock(tail);
    if (event) {
      onEvent(event);
    }
  }
}

async function ensureBrowserContextSession(coreURL, settings, payload, fetchImpl) {
  const encodedAgentId = encodeURIComponent(payload.target.agentId);
  let sessionId = payload.target.sessionId;
  if (!sessionId) {
    const hostTitle = (() => {
      try {
        return new URL(payload.page.url).host || "Safari";
      } catch {
        return "Safari";
      }
    })();
    const createResponse = await fetchImpl(`${coreURL}/v1/agents/${encodedAgentId}/sessions`, {
      method: "POST",
      headers: headersForSettings(settings),
      body: JSON.stringify({ title: `Safari: ${hostTitle}` })
    });
    const created = await parseJSONResponse(createResponse, { agentId: payload.target.agentId });
    sessionId = created.id || created.sessionId;
  }
  return { encodedAgentId, sessionId };
}

async function postSessionBrowserMessage(coreURL, settings, payload, encodedAgentId, sessionId, fetchImpl) {
  const messageResponse = await fetchImpl(`${coreURL}/v1/agents/${encodedAgentId}/sessions/${encodeURIComponent(sessionId)}/messages`, {
    method: "POST",
    headers: headersForSettings(settings),
    body: JSON.stringify({
      userId: payload.userId || "safari_extension",
      content: browserContextPrompt(payload.page, payload.selection.text, payload.prompt),
      attachments: payload.attachments || [],
      spawnSubSession: false,
      mode: "ask"
    })
  });
  return parseJSONResponse(messageResponse, { agentId: payload.target.agentId });
}

function browserMessageResult(sessionId, body, streamedText = "") {
  const assistantEvent = [...(body.appendedEvents || [])].reverse().find((event) => event?.message?.role === "assistant");
  return {
    sessionId,
    messageId: assistantEvent?.message?.id || assistantEvent?.id || null,
    status: "completed",
    text: latestAssistantText(body.appendedEvents) || streamedText
  };
}

async function postBrowserContextLegacy(coreURL, settings, payload, fetchImpl) {
  const { encodedAgentId, sessionId } = await ensureBrowserContextSession(coreURL, settings, payload, fetchImpl);
  const body = await postSessionBrowserMessage(coreURL, settings, payload, encodedAgentId, sessionId, fetchImpl);
  return browserMessageResult(sessionId, body);
}

async function postBrowserContextViaSessionStream(coreURL, settings, payload, options, fetchImpl) {
  const { encodedAgentId, sessionId } = await ensureBrowserContextSession(coreURL, settings, payload, fetchImpl);
  let streamedText = "";
  let abortController = null;
  let streamTask = Promise.resolve();

  if (typeof AbortController !== "undefined") {
    abortController = new AbortController();
  }

  const streamResponse = await fetchImpl(`${coreURL}/v1/agents/${encodedAgentId}/sessions/${encodeURIComponent(sessionId)}/stream`, {
    method: "GET",
    headers: {
      ...headersForSettings(settings),
      accept: "text/event-stream"
    },
    signal: abortController?.signal
  }).catch(() => null);

  const streamContentType = streamResponse?.headers?.get?.("content-type") || "";
  if (streamResponse?.ok && streamResponse.body && streamContentType.includes("text/event-stream")) {
    streamTask = readSSEStream(streamResponse.body, (event) => {
      const text = event.text || assistantTextFromStreamEvent(event);
      if (text) {
        streamedText = text;
      }
      options.onEvent?.(event);
    }).catch((error) => {
      if (error?.name !== "AbortError") {
        options.onEvent?.({ type: "session_error", message: String(error?.message || error) });
      }
    });
  }

  try {
    const body = await postSessionBrowserMessage(coreURL, settings, payload, encodedAgentId, sessionId, fetchImpl);
    const result = browserMessageResult(sessionId, body, streamedText);
    options.onEvent?.({ type: "complete", body: result });
    return result;
  } finally {
    abortController?.abort();
    await streamTask.catch(() => {});
  }
}

function shouldUseLegacyBrowserContext(response) {
  return response.status === 404;
}

async function parseJSONResponse(response, context = {}) {
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(describeCoreError({
      status: response.status,
      endpoint: response.url || null,
      agentId: context.agentId || null,
      error: body.error || `request_failed_${response.status}`,
      message: body.message || null
    }));
    error.details = body;
    error.status = response.status;
    error.endpoint = response.url || null;
    throw error;
  }
  return body;
}

export async function postBrowserContext(settings, page, selection, prompt, options = {}, fetchImpl = fetch) {
  const coreURL = normalizeCoreURL(settings.coreURLString);
  const payload = buildBrowserContextPayload(settings, page, selection, prompt, options);
  const response = await fetchImpl(`${coreURL}/v1/browser/context-message`, {
    method: "POST",
    headers: headersForSettings(settings),
    body: JSON.stringify(payload)
  });
  if (shouldUseLegacyBrowserContext(response)) {
    return postBrowserContextLegacy(coreURL, settings, payload, fetchImpl);
  }
  return parseJSONResponse(response, { agentId: payload.target.agentId });
}

export async function postBrowserContextStreaming(settings, page, selection, prompt, options = {}, fetchImpl = fetch) {
  const coreURL = normalizeCoreURL(settings.coreURLString);
  const payload = buildBrowserContextPayload(settings, page, selection, prompt, options);
  try {
    return await postBrowserContextViaSessionStream(coreURL, settings, payload, options, fetchImpl);
  } catch (error) {
    if (error?.status !== 404) {
      throw error;
    }
  }

  const response = await fetchImpl(`${coreURL}/v1/browser/context-message`, {
    method: "POST",
    headers: {
      ...headersForSettings(settings),
      accept: "text/event-stream, application/json"
    },
    body: JSON.stringify(payload)
  });

  if (shouldUseLegacyBrowserContext(response)) {
    const body = await postBrowserContextLegacy(coreURL, settings, payload, fetchImpl);
    options.onEvent?.({ type: "complete", body });
    return body;
  }

  const contentType = response.headers?.get?.("content-type") || "";
  if (!response.body || !contentType.includes("text/event-stream")) {
    const body = await parseJSONResponse(response, { agentId: payload.target.agentId });
    options.onEvent?.({ type: "complete", body });
    return body;
  }
  if (!response.ok) {
    throw new Error(`request_failed_${response.status}`);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let finalBody = {};
  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    buffer += decoder.decode(value, { stream: true });
    const blocks = buffer.split(/\r?\n\r?\n/);
    buffer = blocks.pop() || "";
    for (const block of blocks) {
      const event = decodeSSEBlock(block);
      if (!event) {
        continue;
      }
      if (event.type === "complete" || event.type === "done") {
        finalBody = event.body || finalBody;
      }
      options.onEvent?.(event);
    }
  }
  if (buffer.trim()) {
    const event = decodeSSEBlock(buffer);
    if (event) {
      options.onEvent?.(event);
    }
  }
  options.onEvent?.({ type: "done", body: finalBody });
  return finalBody;
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

export function renderMarkdown(markdown = "") {
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

const browserToolNames = new Set([
  "browser.open_tab",
  "browser.capture_visible_tab",
  "browser.click_selector",
  "browser.type_text",
  "browser.scroll",
  "browser.dom_snapshot"
]);

function browserToolName(item) {
  if (!item || typeof item === "string") {
    return null;
  }
  if (item.type === "open_tab") {
    return "browser.open_tab";
  }
  const name = item.name || item.tool || item.type;
  return browserToolNames.has(name) ? name : null;
}

function browserToolInput(item) {
  if (typeof item === "string") {
    return { url: item };
  }
  return {
    ...(item?.input || {}),
    ...(item?.arguments || {}),
    ...(item?.url ? { url: item.url } : {})
  };
}

export function collectBrowserToolActions(response = {}) {
  const openTabs = response.openTabs || response.open_tabs || [];
  const actions = response.actions || [];
  const toolCalls = response.toolCalls || response.tool_calls || [];
  return [...openTabs.map((url) => ({ name: "browser.open_tab", input: { url } })), ...actions, ...toolCalls]
    .map((item) => {
      if (item?.name === "browser.open_tab" && item.input?.url) {
        return item;
      }
      const name = browserToolName(item);
      if (!name) {
        return null;
      }
      return {
        name,
        input: browserToolInput(item)
      };
    })
    .filter(Boolean);
}

export function describeCoreError(details = {}) {
  const parts = ["Core request failed"];
  if (details.status) {
    parts.push(`HTTP ${details.status}`);
  }
  if (details.error) {
    parts.push(`error: ${details.error}`);
  }
  if (details.message) {
    parts.push(`message: ${details.message}`);
  }
  if (details.agentId) {
    parts.push(`agent: ${details.agentId}`);
  }
  if (details.endpoint) {
    parts.push(`endpoint: ${details.endpoint}`);
  }
  if (details.status === 404 && String(details.endpoint || "").includes("/v1/browser/context-message")) {
    parts.push("The configured Core does not expose the browser context endpoint.");
    parts.push("Update or restart Sloppy Core on this host, then reopen the Safari extension.");
  }
  return parts.join("\n");
}
