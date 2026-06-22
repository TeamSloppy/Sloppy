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

export function buildBrowserContextPayload(settings, page, selection, prompt) {
  return {
    source: "safari_extension",
    page: {
      url: page.url,
      title: page.title || null
    },
    selection: {
      text: String(selection || "").trim()
    },
    prompt: String(prompt || "").trim(),
    target: {
      agentId: String(settings.defaultAgentID || "sloppy").trim() || "sloppy",
      sessionId: settings.sessionId || null
    },
    userId: "safari_extension"
  };
}

export async function postBrowserContext(settings, page, selection, prompt, fetchImpl = fetch) {
  const coreURL = normalizeCoreURL(settings.coreURLString);
  const payload = buildBrowserContextPayload(settings, page, selection, prompt);
  const headers = { "content-type": "application/json" };
  if (settings.authToken) {
    headers.authorization = `Bearer ${settings.authToken}`;
  }
  const response = await fetchImpl(`${coreURL}/v1/browser/context-message`, {
    method: "POST",
    headers,
    body: JSON.stringify(payload)
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `request_failed_${response.status}`);
  }
  return body;
}
