import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const vite = await createServer({
  root: fileURLToPath(new URL("..", import.meta.url)), server: { host: "127.0.0.1", port: 0 }
});
const now = new Date().toISOString();
const agent = { id: "fixture-agent", displayName: "Fixture" };
const session = { id: "fixture-chat", agentId: agent.id, projectId: "fixture-project",
  title: "Prompt suggestion fixture", kind: "chat", createdAt: now, updatedAt: now };
const project = { id: session.projectId, name: "Fixture project", tasks: [], channels: [], actors: [], teams: [] };
const events = [];
const writes = [];
let browser;
let resolveSocket;
const readySocket = new Promise((resolve) => { resolveSocket = resolve; });
let releaseSecond;
const secondResponse = new Promise((resolve) => { releaseSecond = resolve; });

try {
  await vite.listen();
  const base = `http://127.0.0.1:${vite.httpServer.address().port}`;
  browser = await chromium.launch({ executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH });
  const page = await browser.newPage();
  page.setDefaultTimeout(15000);
  await page.route("**/config.json", (route) => route.fulfill({ json: { apiBase: base } }));
  await page.route("**/health", (route) => route.fulfill({ json: { status: "ok" } }));
  await page.routeWebSocket(/\/v1\//, (socket) => {
    if (!new URL(socket.url()).pathname.endsWith(`/sessions/${session.id}/ws`)) return;
    socket.send(JSON.stringify({ kind: "session_ready", cursor: 1, summary: session }));
    resolveSocket(socket);
  });
  await page.route("**/v1/**", async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    if (request.method() === "POST") writes.push(path);
    if (path.endsWith("/prompt-suggestion")) {
      const { sourceRunId } = request.postDataJSON();
      if (sourceRunId === "run-2") await secondResponse;
      return route.fulfill({ json: { sourceRunId, text: sourceRunId === "run-1" ? "Make the draft shorter." : "Stale prediction." } })
        .catch(() => {});
    }
    let data = [];
    if (path === "/v1/config") data = { onboarding: { completed: true } };
    else if (path === "/v1/agents") data = [agent];
    else if (path === "/v1/projects") data = [project];
    else if (path === `/v1/projects/${project.id}`) data = project;
    else if (path === "/v1/agent-sessions" || path.endsWith("/sessions")) data = [session];
    else if (path.endsWith(`/sessions/${session.id}`)) data = { summary: session, events };
    else if (path.endsWith("/agents/fixture-agent/config")) data = { availableModels: [] };
    else if (path.endsWith("/approval-policy")) data = { mode: "ask_for_approval" };
    return route.fulfill({ json: data });
  });

  await page.goto(`${base}/work`, { waitUntil: "domcontentloaded" });
  await page.getByRole("button", { name: session.title, exact: true }).click();
  const input = page.getByTestId("agent-chat-compose-input");
  await input.waitFor();
  const socket = await Promise.race([
    readySocket, page.waitForTimeout(12000).then(() => { throw new Error("Chat socket did not open."); })
  ]);
  function complete(runId, cursor, turnDiff) {
    const event = { id: `event-${runId}`, agentId: agent.id, sessionId: session.id, type: "run_status",
      createdAt: now, runStatus: { id: runId, stage: "done", label: "Done", turnDiff } };
    events.push(event);
    socket.send(JSON.stringify({ kind: "session_event", cursor, summary: session, event }));
  }
  assert.ok(!writes.some((path) => path.endsWith("/prompt-suggestion")));
  complete("run-1", 2, {
    truncated: false,
    files: [
      { path: "/checkout/A.swift", attribution: "verified", additions: 1, deletions: 0, patch: "+let value = 1" },
      { path: "/checkout/B.swift", attribution: "interleaved", additions: 0, deletions: 0 }
    ]
  });
  const diff = page.getByTestId("agent-turn-diff");
  await diff.locator("summary").click();
  await diff.getByText("+let value = 1", { exact: true }).waitFor();
  await diff.getByText("The file changed outside this turn.", { exact: true }).waitFor();
  await page.locator('[data-testid="agent-chat-compose-input"][data-placeholder*="Make the draft shorter."]').waitFor();
  assert.equal(await input.innerText(), "");
  await input.press("Tab");
  assert.equal(await input.innerText(), "Make the draft shorter.");
  assert.equal(writes.filter((path) => path.endsWith("/messages")).length, 0);
  await input.fill("Make it three sentences.");
  assert.equal(await input.innerText(), "Make it three sentences.");

  await input.fill("");
  const requested = page.waitForRequest((request) => request.url().endsWith("/prompt-suggestion") && request.postDataJSON()?.sourceRunId === "run-2");
  complete("run-2", 3);
  await requested;
  await input.fill("My own next prompt");
  releaseSecond();
  assert.equal(await input.innerText(), "My own next prompt");
  assert.ok(!(await input.getAttribute("data-placeholder")).includes("Stale prediction."));
  assert.equal(writes.filter((path) => path.endsWith("/messages")).length, 0);
  console.log("Dashboard prediction appears after completion and Tab only edits the draft.");
} finally {
  releaseSecond();
  await browser?.close();
  await vite.close();
}
