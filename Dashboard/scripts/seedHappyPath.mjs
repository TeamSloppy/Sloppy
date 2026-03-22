import fs from "node:fs/promises";
import { CONSOLE_LOG_PATH, CORE_API_BASE, HAPPY_PATH_FIXTURE, OUTPUT_DIR, SEED_STATE_PATH } from "./happyPathConfig.mjs";

async function ensureOutputDir() {
  await fs.mkdir(OUTPUT_DIR, { recursive: true });
}

function safeParseJSON(text) {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

async function request(pathname, options = {}) {
  const url = `${CORE_API_BASE}${pathname}`;
  const headers = new Headers(options.headers || {});
  const hasBody = options.body !== undefined;

  if (hasBody && !headers.has("content-type")) {
    headers.set("content-type", "application/json");
  }

  const response = await fetch(url, {
    method: options.method || (hasBody ? "POST" : "GET"),
    headers,
    body: hasBody ? JSON.stringify(options.body) : undefined
  });

  const text = await response.text();
  const data = text ? safeParseJSON(text) : null;

  if (!response.ok) {
    throw new Error(`Sloppy request failed for ${pathname}: ${response.status} ${text}`);
  }

  return data;
}

async function requestOrNull(pathname) {
  const response = await fetch(`${CORE_API_BASE}${pathname}`);
  if (response.status === 404) {
    return null;
  }

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Sloppy request failed for ${pathname}: ${response.status} ${text}`);
  }

  return text ? safeParseJSON(text) : null;
}

async function ensureProject() {
  const existing = await requestOrNull(`/v1/projects/${encodeURIComponent(HAPPY_PATH_FIXTURE.projectId)}`);
  if (existing) {
    return existing;
  }

  return request("/v1/projects", {
    method: "POST",
    body: {
      id: HAPPY_PATH_FIXTURE.projectId,
      name: HAPPY_PATH_FIXTURE.projectName,
      description: HAPPY_PATH_FIXTURE.projectDescription,
      channels: []
    }
  });
}

async function ensureAgent() {
  const existing = await requestOrNull(`/v1/agents/${encodeURIComponent(HAPPY_PATH_FIXTURE.agentId)}`);
  if (existing) {
    return existing;
  }

  return request("/v1/agents", {
    method: "POST",
    body: {
      id: HAPPY_PATH_FIXTURE.agentId,
      displayName: HAPPY_PATH_FIXTURE.agentDisplayName,
      role: HAPPY_PATH_FIXTURE.agentRole,
      isSystem: false
    }
  });
}

async function ensureSession() {
  const sessions = await request(`/v1/agents/${encodeURIComponent(HAPPY_PATH_FIXTURE.agentId)}/sessions`);
  const existing = Array.isArray(sessions)
    ? sessions.find((session) => String(session?.title || "").trim() === HAPPY_PATH_FIXTURE.sessionTitle)
    : null;

  if (existing) {
    return existing;
  }

  return request(`/v1/agents/${encodeURIComponent(HAPPY_PATH_FIXTURE.agentId)}/sessions`, {
    method: "POST",
    body: {
      title: HAPPY_PATH_FIXTURE.sessionTitle
    }
  });
}

async function markOnboardingComplete() {
  const config = await request("/v1/config");
  const nextConfig = {
    ...config,
    onboarding: {
      ...(typeof config?.onboarding === "object" && config.onboarding ? config.onboarding : {}),
      completed: true
    }
  };

  await request("/v1/config", {
    method: "PUT",
    body: nextConfig
  });
}

async function main() {
  await ensureOutputDir();
  await fs.writeFile(CONSOLE_LOG_PATH, "", "utf8");

  await markOnboardingComplete();
  const project = await ensureProject();
  const agent = await ensureAgent();
  const session = await ensureSession();

  const state = {
    coreApiBase: CORE_API_BASE,
    projectId: String(project?.id || HAPPY_PATH_FIXTURE.projectId),
    projectName: String(project?.name || HAPPY_PATH_FIXTURE.projectName),
    agentId: String(agent?.id || HAPPY_PATH_FIXTURE.agentId),
    agentDisplayName: String(agent?.displayName || HAPPY_PATH_FIXTURE.agentDisplayName),
    sessionId: String(session?.id || ""),
    sessionTitle: String(session?.title || HAPPY_PATH_FIXTURE.sessionTitle),
    messageText: HAPPY_PATH_FIXTURE.messageText
  };

  await fs.writeFile(SEED_STATE_PATH, `${JSON.stringify(state, null, 2)}\n`, "utf8");
  process.stdout.write(`Seeded dashboard happy path data in ${SEED_STATE_PATH}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.stack || error.message : String(error)}\n`);
  process.exitCode = 1;
});
