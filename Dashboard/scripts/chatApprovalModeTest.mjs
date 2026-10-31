import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";
import { chromium } from "playwright";

// Exercise the real composer, hook and API client together against a local fixture Core.
const directory = await mkdtemp(join(tmpdir(), "sloppy-chat-approvals-"));
await build({
  stdin: {
    contents: `
      import React from "react";
      import { createRoot } from "react-dom/client";
      import { normalizeConfig } from "./src/features/config/configModel";
      window.normalizedApprovalDefault = (value) => normalizeConfig(value).defaultChatApprovalMode;
      import { ChatApprovalDefaultsEditor } from "./src/features/config/components/ChatApprovalDefaultsEditor";
      import { fetchDefaultChatApprovalPolicy, setDefaultChatApprovalPolicy } from "./src/api";
      import { AgentChatTab } from "./src/features/agents/components/AgentChatTab";
      import "./src/styles/index.css";
      window.localStorage.setItem("sloppy_api_base_override", window.location.origin);
      window.renderChat = (sessionId) => createRootOnce().render(
        <AgentChatTab agentId="approval-agent" initialSessionId={sessionId} />
      );
      let root;
      function createRootOnce() { return root ||= createRoot(document.getElementById("root")); }
      function Settings() {
        const [mode, setMode] = React.useState("ask_for_approval");
        const [saved, setSaved] = React.useState(false);
        React.useEffect(() => { fetchDefaultChatApprovalPolicy().then((policy) => setMode(policy.mode)); }, []);
        return <main style={{ padding: 24, maxWidth: 680 }}><ChatApprovalDefaultsEditor mode={mode} onChange={(mode) => { setMode(mode); setSaved(false); }} />
          <button onClick={async () => { const policy = await setDefaultChatApprovalPolicy(mode); setMode(policy.mode); setSaved(true); }}>Save settings</button>
          {saved && <p role="status">Saved default</p>}</main>;
      }
      window.renderSettings = () => createRootOnce().render(<Settings />);
      window.renderChat(new URLSearchParams(location.search).get("session"));
    `,
    resolveDir: fileURLToPath(new URL("..", import.meta.url)),
    loader: "tsx"
  },
  bundle: true, outdir: directory, entryNames: "app", format: "esm", external: ["/fonts/*"],
  define: { "import.meta.env": "{}", "process.env.NODE_ENV": '"production"', __APP_VERSION__: '"test"', __DASHBOARD_DEV__: "false" },
  loader: { ".woff2": "dataurl", ".woff": "dataurl", ".ttf": "dataurl", ".svg": "dataurl", ".png": "dataurl" }
});

let defaultMode = "ask_for_approval";
let failSave = false;
let policyStatus = 200;
let saveGate = null;
let enteredSave = null;
const modes = new Map([["one", "ask_for_approval"], ["two", "ask_for_approval"]]);
const calls = [];
const sessions = new Map();
function summary(id) {
  return { id, agentId: "approval-agent", title: `Chat ${id}`, createdAt: "2026-10-26T10:00:00Z", updatedAt: "2026-10-26T10:00:00Z", messageCount: 0, kind: "standard" };
}
const server = createServer(async (request, response) => {
  const path = new URL(request.url, "http://localhost").pathname;
  if (path.startsWith("/fonts/")) {
    response.end(await readFile(new URL(`../public${path}`, import.meta.url)));
    return;
  }
  if (path === "/app.js" || path === "/app.css") {
    response.setHeader("content-type", path.endsWith("js") ? "application/javascript" : "text/css");
    response.end(await readFile(join(directory, path.slice(1))));
    return;
  }
  if (!path.startsWith("/v1/")) {
    response.setHeader("content-type", "text/html");
    response.end('<html><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/app.css"></head><body><div id="root" style="height:100vh"></div><script type="module" src="/app.js"></script></body></html>');
    return;
  }
  let raw = "";
  for await (const chunk of request) raw += chunk;
  const body = raw ? JSON.parse(raw) : null;
  calls.push({ path, method: request.method, body });
  let result = {};
  const policy = path.match(/\/sessions\/([^/]+)\/approval-policy$/);
  if (path === "/v1/config/chat-approval-default") {
    if (request.method === "PUT") defaultMode = body.mode;
    result = { mode: defaultMode };
  } else if (policy) {
    if (policyStatus !== 200) {
      response.writeHead(policyStatus, { "content-type": "application/json" });
      response.end(JSON.stringify({ error: "Unsupported endpoint" }));
      return;
    }
    if (request.method === "PUT") {
      enteredSave?.();
      if (saveGate) await saveGate;
      if (failSave) {
        response.writeHead(503, { "content-type": "application/json" });
        response.end(JSON.stringify({ error: "Approval storage unavailable" }));
        return;
      }
      modes.set(policy[1], body.mode);
    }
    result = { mode: modes.get(policy[1]) || "ask_for_approval" };
  } else if (path.endsWith("/config")) {
    result = { selectedModel: "mock:test", availableModels: [], runtime: { type: "native" } };
  } else if (path.endsWith("/sessions") && request.method === "POST") {
    const id = `created-${sessions.size}`;
    result = summary(id);
    sessions.set(id, result);
    modes.set(id, defaultMode);
  } else if (path.endsWith("/sessions")) {
    result = [...sessions.values()];
  } else if (path.match(/\/sessions\/[^/]+$/)) {
    const id = path.split("/").at(-1);
    result = { summary: sessions.get(id) || summary(id), events: [] };
  } else if (path.endsWith("/messages")) {
    result = { summary: summary(path.split("/").at(-2)), events: [] };
  } else if (path.endsWith("/slash-commands")) {
    result = { commands: [] };
  } else if (/\/(pending|projects|tasks|all|agents)$/.test(path)) {
    result = [];
  }
  response.writeHead(200, { "content-type": "application/json" });
  response.end(JSON.stringify(result));
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const baseURL = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,
  ...(process.platform === "win32" && !process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH ? { channel: "msedge" } : {})
});
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
page.setDefaultTimeout(15000);
const errors = [];
page.on("pageerror", (error) => errors.push(String(error)));

async function expectMode(title) {
  await page.getByRole("button", { name: `Approval mode: ${title}`, exact: true }).waitFor();
  await page.waitForFunction((title) => !document.querySelector(`[aria-label="Approval mode: ${title}"]`)?.disabled, title);
}
async function select(title) {
  await page.getByRole("button", { name: /^Approval mode:/ }).click();
  await page.getByRole("menuitemradio", { name: new RegExp(`^${title}`) }).click();
}

try {
  await page.goto(`${baseURL}/?session=one`);
  await expectMode("Ask for approval");
  assert.equal(await page.evaluate(() => window.normalizedApprovalDefault({})), null);
  assert.equal(await page.evaluate(() => window.normalizedApprovalDefault({ defaultChatApprovalMode: "approve_for_me" })), "approve_for_me");
  await page.getByRole("button", { name: /^Approval mode:/ }).click();
  await page.keyboard.press("ArrowUp");
  assert.match(await page.evaluate(() => document.activeElement.textContent), /^Approve for me/);
  await page.keyboard.press("Enter");
  await expectMode("Approve for me");
  assert.equal(modes.get("one"), "approve_for_me");
  await page.reload();
  await expectMode("Approve for me");
  await page.evaluate(() => window.renderChat("two"));
  await expectMode("Ask for approval");

  // A pending save followed by A -> B -> A must restore the saved policy.
  let release;
  saveGate = new Promise((resolve) => { release = resolve; });
  const started = new Promise((resolve) => { enteredSave = resolve; });
  await select("Approve for me");
  await started;
  assert.equal(await page.getByTestId("agent-chat-send").isDisabled(), true);
  await page.evaluate(() => window.renderChat("one"));
  await expectMode("Approve for me");
  await page.evaluate(() => window.renderChat("two"));
  release(); saveGate = null; enteredSave = null;
  await expectMode("Approve for me");
  assert.equal(modes.get("two"), "approve_for_me");

  failSave = true;
  await select("Ask for approval");
  await page.getByRole("alert").filter({ hasText: "Approval storage unavailable" }).waitFor();
  assert.equal(modes.get("two"), "approve_for_me");
  failSave = false;
  await page.getByRole("button", { name: "Retry", exact: true }).click();
  await expectMode("Approve for me");

  policyStatus = 404;
  await page.reload();
  await page.getByRole("alert").filter({ hasText: "Update Sloppy Core" }).waitFor();
  policyStatus = 200;
  await page.getByRole("button", { name: "Retry", exact: true }).click();
  await expectMode("Approve for me");

  await select("Ask for approval");
  await expectMode("Ask for approval");

  // Saving the Settings choice changes future drafts without changing existing chats.
  await page.evaluate(() => window.renderSettings());
  await expectMode("Ask for approval");
  await select("Approve for me");
  await page.getByRole("button", { name: "Save settings", exact: true }).click();
  await page.getByRole("status").filter({ hasText: "Saved default" }).waitFor();
  assert.equal(defaultMode, "approve_for_me");
  assert.equal(modes.get("one"), "ask_for_approval");
  const policyWritesBefore = calls.filter((call) => call.path.endsWith("/approval-policy") && call.method === "PUT").length;
  await page.goto(baseURL);
  await expectMode("Approve for me");
  const defaultPosted = page.waitForResponse((response) => response.url().endsWith("/messages") && response.request().method() === "POST");
  await page.getByTestId("agent-chat-compose-input").fill("Use the saved default");
  await page.getByTestId("agent-chat-send").click();
  await defaultPosted;
  assert.equal(calls.filter((call) => call.path.endsWith("/approval-policy") && call.method === "PUT").length, policyWritesBefore);
  assert.equal(modes.get("created-0"), "approve_for_me");
  sessions.clear(); calls.length = 0; defaultMode = "ask_for_approval";

  // A brand-new chat must save its chosen policy before posting the first turn.
  await page.goto(baseURL);
  await expectMode("Ask for approval");
  await select("Approve for me");
  await page.getByTestId("agent-chat-compose-input").fill("Read the project overview");
  failSave = true;
  await page.getByTestId("agent-chat-send").click();
  await page.waitForFunction(() => document.body.textContent.includes("Could not save approval mode"));
  assert.equal(calls.filter((call) => call.path.endsWith("/messages")).length, 0);
  assert.equal(await page.getByTestId("agent-chat-compose-input").textContent(), "Read the project overview");
  failSave = false;
  const posted = page.waitForResponse((response) => response.url().endsWith("/messages") && response.request().method() === "POST");
  await page.getByTestId("agent-chat-send").click();
  await posted;
  const messageIndex = calls.findIndex((call) => call.path.endsWith("/messages") && call.method === "POST");
  assert.ok(messageIndex >= 0);
  const policyPath = calls[messageIndex].path.replace(/messages$/, "approval-policy");
  assert.ok(calls.slice(0, messageIndex).some((call) => call.path === policyPath && call.method === "PUT" && call.body.mode === "approve_for_me"));

  for (const width of [1280, 390]) {
    await page.setViewportSize({ width, height: 900 });
    await page.getByRole("button", { name: /^Approval mode:/ }).click();
    const bounds = await page.getByRole("menu", { name: "Chat approval mode" }).boundingBox();
    assert.ok(bounds && bounds.x >= 0 && bounds.x + bounds.width <= width + 1);
    await page.evaluate(() => document.fonts.ready);
    if (process.env.SLOPPY_APPROVAL_SCREENSHOTS) {
      await page.screenshot({ path: join(process.env.SLOPPY_APPROVAL_SCREENSHOTS, `dashboard-approvals-${width}.png`) });
    }
    await page.keyboard.press("Escape");
  }
  assert.deepEqual(errors, []);
  console.log("PASS: settings default, configuration compatibility, composer persistence, session isolation, save/navigation race, API failure, draft first-turn ordering, desktop/mobile layout");
} finally {
  await browser.close();
  await new Promise((resolve) => server.close(resolve));
  await rm(directory, { recursive: true, force: true });
}
