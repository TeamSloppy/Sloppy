import "./i18n.js";
import { meshCoreFetch, normalizeMeshSettings } from "./mesh.js";

function t(key, params = {}) {
  return globalThis.SloppyI18n?.t(key, params) || key;
}

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

const maxStartPageShortcuts = 8;
const maxStartPageItems = 8;
const maxStartPageBackgroundImageLength = 750000;
const sidebarMinWidth = 128;
const sidebarMaxWidth = 360;
const defaultSidebarWidth = 168;
const widgetSizeDimensions = {
  small: { width: 160, height: 120 },
  medium: { width: 320, height: 180 },
  large: { width: 320, height: 320 }
};

export function normalizeSidebarState(value = {}) {
  const width = Math.min(sidebarMaxWidth, Math.max(sidebarMinWidth, Number(value.width) || defaultSidebarWidth));
  return {
    width,
    collapsed: Boolean(value.collapsed)
  };
}

export function sidebarStateAfterCollapseToggle(value = {}) {
  const state = normalizeSidebarState(value);
  return {
    ...state,
    collapsed: !state.collapsed
  };
}

export function sanitizeStartPageTheme(value) {
  return String(value || "dark").trim() === "light" ? "light" : "dark";
}

export function sanitizeStartPageBackgroundImage(value) {
  const image = String(value || "").trim();
  if (!image) {
    return "";
  }
  if (image.length > maxStartPageBackgroundImageLength) {
    return "";
  }
  return /^data:image\/(png|jpe?g|gif|webp);base64,[a-z0-9+/=\s]+$/i.test(image) ? image : "";
}

export function sanitizeStartPageShortcuts(records = []) {
  return (Array.isArray(records) ? records : [])
    .map((record) => {
      const rawURL = String(record?.url || "").trim();
      let url = null;
      try {
        url = new URL(rawURL);
      } catch {
        return null;
      }
      if (url.protocol !== "http:" && url.protocol !== "https:") {
        return null;
      }
      const hostTitle = url.host || url.href;
      return {
        title: String(record?.title || hostTitle).trim() || hostTitle,
        url: url.href
      };
    })
    .filter(Boolean)
    .slice(0, maxStartPageShortcuts);
}

function normalizedWidgetSize(value) {
  return Object.prototype.hasOwnProperty.call(widgetSizeDimensions, value) ? value : "small";
}

function sanitizeStartPageItems(records = [], legacyShortcuts = []) {
  const items = Array.isArray(records) && records.length
    ? records
    : sanitizeStartPageShortcuts(legacyShortcuts).map((shortcut) => ({ kind: "shortcut", ...shortcut }));
  return items
    .map((record) => {
      if (String(record?.kind || "").trim() === "widget") {
        const artifactId = String(record?.artifactId || record?.id || "").trim();
        if (!artifactId) {
          return null;
        }
        const size = normalizedWidgetSize(String(record?.size || "").trim());
        const defaults = widgetSizeDimensions[size];
        const widget = {
          kind: "widget",
          artifactId,
          title: String(record?.title || artifactId).trim() || artifactId,
          size,
          width: defaults.width,
          height: defaults.height
        };
        const html = String(record?.html || "").trim();
        if (html) {
          widget.html = html;
        }
        return widget;
      }
      const shortcut = sanitizeStartPageShortcuts([record])[0];
      return shortcut ? { kind: "shortcut", ...shortcut } : null;
    })
    .filter(Boolean)
    .slice(0, maxStartPageItems);
}

export function sanitizeSettings(settings = {}) {
  const startPageShortcuts = sanitizeStartPageShortcuts(settings.startPageShortcuts);
  const sanitized = {
    coreURLString: normalizeCoreURL(settings.coreURLString),
    authToken: String(settings.authToken || "").trim(),
    defaultAgentID: String(settings.defaultAgentID || "sloppy").trim() || "sloppy",
    floatingButtonEnabled: settings.floatingButtonEnabled !== false,
    selectionBubbleEnabled: settings.selectionBubbleEnabled !== false,
    startPageEnabled: settings.startPageEnabled !== false,
    startPageTheme: sanitizeStartPageTheme(settings.startPageTheme),
    startPageBackgroundImage: sanitizeStartPageBackgroundImage(settings.startPageBackgroundImage),
    startPageShortcuts,
    startPageItems: sanitizeStartPageItems(settings.startPageItems, startPageShortcuts),
    voiceLanguage: normalizeVoiceLanguage(settings.voiceLanguage),
    mesh: normalizeMeshSettings(settings.mesh)
  };
  const voiceInputDeviceId = String(settings.voiceInputDeviceId || "").trim();
  if (voiceInputDeviceId) {
    sanitized.voiceInputDeviceId = voiceInputDeviceId;
  }
  if (settings.sessionId) {
    sanitized.sessionId = settings.sessionId;
  }
  const selectedModel = String(settings.selectedModel || "").trim();
  if (selectedModel && selectedModel !== "default") {
    sanitized.selectedModel = selectedModel;
  }
  return sanitized;
}

function normalizeVoiceLanguage(value) {
  const language = String(value || "auto").trim();
  return ["auto", "en-US", "ru-RU", "zh-CN"].includes(language) ? language : "auto";
}

export function publicMeshSettings(mesh = {}) {
  const normalized = normalizeMeshSettings(mesh);
  if (!normalized.identity || typeof normalized.identity !== "object") {
    return normalized;
  }
  const { privateKey: _privateKey, ...identity } = normalized.identity;
  return {
    ...normalized,
    identity
  };
}

export function publicSettings(settings = {}) {
  const sanitized = sanitizeSettings(settings);
  return {
    ...sanitized,
    mesh: publicMeshSettings(sanitized.mesh)
  };
}

export async function coreFetch(settings, path, options = {}, fetchImpl = fetch, meshFetchImpl = meshCoreFetch) {
  if (settings.mesh?.enabled) {
    return meshFetchImpl(settings, path, options);
  }
  return fetchImpl(`${normalizeCoreURL(settings.coreURLString)}${path}`, options);
}

export function normalizeVoiceConfig(config = {}) {
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
    openAI: {
      enabled: Boolean(config.openAI?.enabled),
      transcriptionModel: String(config.openAI?.transcriptionModel || "gpt-4o-mini-transcribe"),
      ttsModel: String(config.openAI?.ttsModel || "gpt-4o-mini-tts"),
      voice: String(config.openAI?.voice || "coral"),
      instructions: String(config.openAI?.instructions || "")
    },
    local: {
      enabled: config.local?.enabled !== false,
      voiceName: String(config.local?.voiceName || ""),
      rate: Number.isFinite(Number(config.local?.rate)) ? Number(config.local.rate) : 1,
      pitch: Number.isFinite(Number(config.local?.pitch)) ? Number(config.local.pitch) : 1
    }
  };
}

export function localSpeechAvailable(windowLike = globalThis) {
  return {
    recognition: typeof windowLike.SpeechRecognition === "function" || typeof windowLike.webkitSpeechRecognition === "function",
    synthesis: Boolean(windowLike.speechSynthesis)
  };
}

export function buildVoicePrompt(transcript) {
  return String(transcript || "").trim();
}

export function chooseAgentID(currentAgentID, agents = []) {
  const current = String(currentAgentID || "").trim();
  if (current && agents.some((agent) => agent.id === current)) {
    return current;
  }
  return agents[0]?.id || current || "sloppy";
}

export function fallbackSelectionText(selection) {
  return String(selection || "").trim() || t("noSelectedText");
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

export function normalizeProviderModels(records = []) {
  const models = Array.isArray(records?.models) ? records.models : Array.isArray(records) ? records : [];
  return [
    {
      id: "default",
      title: t("defaultModel"),
      subtitle: t("defaultModelSubtitle")
    },
    ...models
      .map((model) => {
        const id = String(model?.id || model?.model || model?.name || "").trim();
        if (!id || id === "default") {
          return null;
        }
        return {
          id,
          title: String(model.title || model.name || id).trim() || id,
          subtitle: String(model.description || model.contextWindow || model.provider || "").trim()
        };
      })
      .filter(Boolean)
  ];
}

export async function fetchProviderModels(settings, fetchImpl = fetch) {
  const response = await coreFetch(settings, "/v1/providers/models", {
    headers: headersForSettings(settings)
  }, fetchImpl);
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `models_failed_${response.status}`);
  }
  return normalizeProviderModels(body);
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
      tabs: sanitizeTabs(options.tabs)
    },
    attachments: sanitizeAttachments(options.attachments),
    prompt: String(prompt || "").trim(),
    target: {
      agentId: String(settings.defaultAgentID || "sloppy").trim() || "sloppy",
      sessionId: settings.sessionId || null,
      ...(settings.selectedModel ? { model: settings.selectedModel } : {})
    },
    userId: "safari_extension"
  };
}

function browserContextPrompt(page, selection, browser, prompt) {
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
  lines.push("Safari tools:");
  lines.push("Use `safari.dom_snapshot` only when live page details are needed. Use `safari.click`, `safari.type`, and other `safari.*` tools for the user's current Safari tab; do not use `browser.*` for this Safari page.");
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

function textFromMessage(message = {}) {
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

function latestAssistantText(events = []) {
  const assistant = [...events].reverse().find((event) => messageFromEvent(event)?.role === "assistant");
  return textFromMessage(messageFromEvent(assistant) || {});
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
  return textFromMessage(message);
}

function streamEventRecord(event = {}) {
  return event.event || event.sessionEvent || event;
}

function firstString(...values) {
  return values.map((value) => String(value || "").trim()).find(Boolean) || "";
}

function basename(path) {
  const value = String(path || "").trim();
  if (!value) {
    return "";
  }
  return value.split(/[\\/]/).filter(Boolean).at(-1) || value;
}

function toolDisplayName(toolName, input = {}) {
  const name = String(toolName || "").trim();
  if (!name) {
    return t("toolCall");
  }
  if (name === "web.fetch" || name === "web.request" || name === "web.read") {
    return `${t("readWeb")}${firstString(input.url, input.uri) ? `: ${firstString(input.url, input.uri)}` : ""}`;
  }
  if (name === "web.search") {
    return `${t("searchWeb")}${firstString(input.query, input.q) ? `: ${firstString(input.query, input.q)}` : ""}`;
  }
  if (name === "files.read" || name === "files.read_file" || name === "mcp.read_resource") {
    return `${t("readFile")}${firstString(basename(input.path), basename(input.file), input.uri) ? `: ${firstString(basename(input.path), basename(input.file), input.uri)}` : ""}`;
  }
  if (name === "files.write" || name === "files.edit") {
    return `${t("writeFile")}${firstString(basename(input.path), basename(input.file)) ? `: ${firstString(basename(input.path), basename(input.file))}` : ""}`;
  }
  if (name === "memory.save" || name === "project.meta_memory") {
    return t("saveMemory");
  }
  return name
    .replace(/[_-]+/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function normalizeToolCallEvent(record = {}) {
  const call = record.toolCall || record.tool_call || record.tool || record;
  const toolName = call.tool || call.name || record.tool || record.name;
  const input = call.arguments || call.input || record.arguments || {};
  return {
    name: toolDisplayName(toolName, input),
    tool: toolName,
    status: "running",
    input,
    reason: call.reason || record.reason || null
  };
}

function normalizeToolResultEvent(record = {}) {
  const result = record.toolResult || record.tool_result || record;
  const toolName = result.tool || result.name;
  return {
    name: toolDisplayName(toolName, {}),
    tool: toolName,
    status: result.ok === false ? "failed" : "done",
    output: result.data || result.error || result
  };
}

function normalizeMemoryCheckpointEvent(record = {}) {
  const checkpoint = record.memoryCheckpoint || record.memory_checkpoint || record;
  return {
    name: t("saveMemory"),
    tool: "memory.save",
    status: checkpoint.status || "done",
    output: checkpoint.message || checkpoint.reason || checkpoint
  };
}

function normalizeStreamEvent(event = {}) {
  if (event.kind === "session_delta" || event.type === "session_delta") {
    const deltaText = firstString(
      event.message,
      event.text,
      textFromContentValue(event.delta),
      textFromContentValue(event.content),
      textFromContentValue(event.value)
    );
    return {
      ...event,
      type: "delta",
      text: deltaText,
      replace: true
    };
  }

  const record = streamEventRecord(event);
  const recordType = record.type || event.type || event.kind;
  const text = assistantTextFromStreamEvent(event);
  if (text) {
    return { ...event, type: "assistant_message", text };
  }
  if (recordType === "message" && record.message?.role === "assistant") {
    return { ...event, type: "thinking" };
  }
  if (recordType === "tool_call" || record.toolCall || record.tool_call) {
    return { ...event, type: "tool_call", tool: normalizeToolCallEvent(record) };
  }
  if (recordType === "tool_result" || record.toolResult || record.tool_result) {
    return { ...event, type: "tool_call", tool: normalizeToolResultEvent(record) };
  }
  if (recordType === "memory_checkpoint" || record.memoryCheckpoint || record.memory_checkpoint) {
    return { ...event, type: "tool_call", tool: normalizeMemoryCheckpointEvent(record) };
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

function waitForStreamCatchup(streamTask, timeoutMs = 800) {
  return Promise.race([
    streamTask,
    new Promise((resolve) => setTimeout(resolve, timeoutMs))
  ]).catch(() => {});
}

async function ensureBrowserContextSession(settings, payload, fetchImpl) {
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
    const createResponse = await coreFetch(settings, `/v1/agents/${encodedAgentId}/sessions`, {
      method: "POST",
      headers: headersForSettings(settings),
      body: JSON.stringify({ title: `Safari: ${hostTitle}` })
    }, fetchImpl);
    const created = await parseJSONResponse(createResponse, {
      agentId: payload.target.agentId,
      endpoint: `/v1/agents/${encodedAgentId}/sessions`
    });
    sessionId = created.id || created.sessionId;
  }
  return { encodedAgentId, sessionId };
}

async function postSessionBrowserMessage(settings, payload, encodedAgentId, sessionId, fetchImpl) {
  const endpoint = `/v1/agents/${encodedAgentId}/sessions/${encodeURIComponent(sessionId)}/messages`;
  const messageResponse = await coreFetch(settings, endpoint, {
    method: "POST",
    headers: headersForSettings(settings),
    body: JSON.stringify({
      userId: payload.userId || "safari_extension",
      content: browserContextPrompt(payload.page, payload.selection.text, payload.browser, payload.prompt),
      attachments: payload.attachments || [],
      spawnSubSession: false,
      mode: "auto",
      ...(payload.target.model ? { model: payload.target.model } : {})
    })
  }, fetchImpl);
  return parseJSONResponse(messageResponse, { agentId: payload.target.agentId, endpoint });
}

function browserMessageResult(sessionId, body, streamedText = "") {
  const assistantEvent = [...(body.appendedEvents || [])].reverse().find((event) => messageFromEvent(event)?.role === "assistant");
  const assistantMessage = messageFromEvent(assistantEvent);
  return {
    sessionId,
    messageId: assistantMessage?.id || assistantEvent?.id || null,
    status: "completed",
    text: latestAssistantText(body.appendedEvents) || latestInterruptedRunStatusText(body.appendedEvents) || streamedText
  };
}

async function postBrowserContextLegacy(settings, payload, fetchImpl) {
  const { encodedAgentId, sessionId } = await ensureBrowserContextSession(settings, payload, fetchImpl);
  const body = await postSessionBrowserMessage(settings, payload, encodedAgentId, sessionId, fetchImpl);
  return browserMessageResult(sessionId, body);
}

async function postBrowserContextViaSessionStream(settings, payload, options, fetchImpl) {
  const { encodedAgentId, sessionId } = await ensureBrowserContextSession(settings, payload, fetchImpl);
  let streamedText = "";
  let sawAssistantMessage = false;
  let abortController = null;
  let streamTask = Promise.resolve();

  if (typeof AbortController !== "undefined") {
    abortController = new AbortController();
  }

  const streamResponse = await coreFetch(settings, `/v1/agents/${encodedAgentId}/sessions/${encodeURIComponent(sessionId)}/stream`, {
    method: "GET",
    headers: {
      ...headersForSettings(settings),
      accept: "text/event-stream"
    },
    signal: abortController?.signal
  }, fetchImpl).catch(() => null);

  const streamContentType = streamResponse?.headers?.get?.("content-type") || "";
  if (streamResponse?.ok && streamResponse.body && streamContentType.includes("text/event-stream")) {
    streamTask = readSSEStream(streamResponse.body, (event) => {
      const text = event.text || assistantTextFromStreamEvent(event);
      if (text) {
        streamedText = text;
      }
      if (event.type === "assistant_message") {
        sawAssistantMessage = true;
      }
      options.onEvent?.(event);
    }).catch((error) => {
      if (error?.name !== "AbortError") {
        options.onEvent?.({ type: "session_error", message: String(error?.message || error) });
      }
    });
  }

  try {
    const body = await postSessionBrowserMessage(settings, payload, encodedAgentId, sessionId, fetchImpl);
    const immediateText = latestAssistantText(body.appendedEvents || []);
    if (!immediateText && !sawAssistantMessage) {
      await waitForStreamCatchup(streamTask);
    }
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
      endpoint: response.url || context.endpoint || null,
      agentId: context.agentId || null,
      error: body.error || `request_failed_${response.status}`,
      message: body.message || null
    }));
    error.details = body;
    error.status = response.status;
    error.endpoint = response.url || context.endpoint || null;
    throw error;
  }
  return body;
}

export async function postBrowserContext(settings, page, selection, prompt, options = {}, fetchImpl = fetch) {
  const payload = buildBrowserContextPayload(settings, page, selection, prompt, options);
  const response = await coreFetch(settings, "/v1/browser/context-message", {
    method: "POST",
    headers: headersForSettings(settings),
    body: JSON.stringify(payload)
  }, fetchImpl);
  if (shouldUseLegacyBrowserContext(response)) {
    return postBrowserContextLegacy(settings, payload, fetchImpl);
  }
  return parseJSONResponse(response, {
    agentId: payload.target.agentId,
    endpoint: "/v1/browser/context-message"
  });
}

export async function fetchVoiceConfig(settings, fetchImpl = fetch) {
  const response = await coreFetch(settings, "/v1/voice/config", {
    headers: headersForSettings(settings)
  }, fetchImpl);
  return normalizeVoiceConfig(await parseJSONResponse(response));
}

export async function transcribeVoiceAudio(settings, payload, fetchImpl = fetch) {
  const response = await coreFetch(settings, "/v1/voice/transcriptions", {
    method: "POST",
    headers: headersForSettings(settings),
    body: JSON.stringify(payload)
  }, fetchImpl);
  return parseJSONResponse(response);
}

export async function synthesizeVoiceSpeech(settings, payload, fetchImpl = fetch) {
  const response = await coreFetch(settings, "/v1/voice/speech", {
    method: "POST",
    headers: headersForSettings(settings),
    body: JSON.stringify(payload)
  }, fetchImpl);
  return parseJSONResponse(response);
}

export async function postBrowserContextStreaming(settings, page, selection, prompt, options = {}, fetchImpl = fetch) {
  const payload = buildBrowserContextPayload(settings, page, selection, prompt, options);
  if (settings.mesh?.enabled) {
    const body = await postBrowserContext(settings, page, selection, prompt, options, fetchImpl);
    options.onEvent?.({ type: "complete", body });
    options.onEvent?.({ type: "done", body });
    return body;
  }
  try {
    return await postBrowserContextViaSessionStream(settings, payload, options, fetchImpl);
  } catch (error) {
    if (error?.status !== 404) {
      throw error;
    }
  }

  const response = await coreFetch(settings, "/v1/browser/context-message", {
    method: "POST",
    headers: {
      ...headersForSettings(settings),
      accept: "text/event-stream, application/json"
    },
    body: JSON.stringify(payload)
  }, fetchImpl);

  if (shouldUseLegacyBrowserContext(response)) {
    const body = await postBrowserContextLegacy(settings, payload, fetchImpl);
    options.onEvent?.({ type: "complete", body });
    return body;
  }

  const contentType = response.headers?.get?.("content-type") || "";
  if (!response.body || !contentType.includes("text/event-stream")) {
    const body = await parseJSONResponse(response, {
      agentId: payload.target.agentId,
      endpoint: "/v1/browser/context-message"
    });
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
