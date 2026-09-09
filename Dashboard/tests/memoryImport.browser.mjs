// UI integration with fixture API responses. Run: node tests/memoryImport.browser.mjs
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { tmpdir } from "node:os";
import { chromium } from "playwright";

const root = fileURLToPath(new URL("../", import.meta.url));
const harness = await mkdtemp(path.join(root, ".memory-import-test-"));
const port = 25112;
const server = spawn(process.execPath, ["node_modules/vite/bin/vite.js", "--host", "127.0.0.1", "--port", String(port), "--strictPort"], { cwd: root, stdio: "pipe" });
let browser;
try {
  await writeFile(path.join(harness, "index.html"), '<html><div id="root"></div><script type="module" src="./main.tsx"></script></html>');
  await writeFile(path.join(harness, "main.tsx"), `import React from "react";
import { createRoot } from "react-dom/client";
import { AgentMemoryImport } from "../src/features/agents/components/AgentMemoryImport";
import "../src/styles/index.css";
createRoot(document.getElementById("root")!).render(<main style={{maxWidth: 840, padding: 24, margin: "auto"}}><AgentMemoryImport agentId="import-test" onUpdated={() => {}} /></main>);`);
  for (let attempt = 0; ; attempt++) {
    try { if ((await fetch(`http://127.0.0.1:${port}`)).ok) break; } catch { /* Wait for Vite. */ }
    if (attempt === 100) throw new Error("Vite did not start");
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  browser = await chromium.launch({ headless: true, ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage({ viewport: { width: 1100, height: 1000 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  let events = [];
  let posted;
  let failRequest = false;
  await page.route("**/v1/**", async (route) => {
    const request = route.request();
    if (request.method() === "OPTIONS") return route.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*" } });
    let body;
    if (request.method() === "POST" && request.url().endsWith("/sessions")) body = { id: "import-session" };
    else if (request.method() === "POST" && request.url().endsWith("/messages")) {
      if (failRequest) return route.fulfill({ status: 503, json: { error: "unavailable" }, headers: { "access-control-allow-origin": "*" } });
      posted = request.postDataJSON();
      events = [
        { type: "tool_result", toolResult: { tool: "memory.save", ok: true, data: { id: "saved-one" } } },
        { type: "run_status", runStatus: { stage: "done" } }
      ];
      body = { summary: { id: "import-session" }, appendedEvents: events };
    } else body = { summary: { id: "import-session" }, events };
    await route.fulfill({ json: body, headers: { "access-control-allow-origin": "*" } });
  });
  const url = `http://127.0.0.1:${port}/${path.basename(harness)}/index.html`;
  await page.goto(url);
  await page.getByRole("button", { name: "Import memory", exact: true }).click();
  await page.getByText("Export prompt", { exact: true }).click();
  assert.match(await page.getByLabel("Memory export prompt").inputValue(), /Export the useful memory/);
  await page.getByText("Export prompt", { exact: true }).click();
  await page.locator('input[type="file"]').setInputFiles({ name: "wrong.txt", mimeType: "text/plain", buffer: Buffer.from("bad") });
  await page.getByRole("alert").filter({ hasText: "only Markdown" }).waitFor();
  await page.locator('input[type="file"]').setInputFiles([
    { name: "profile.md", mimeType: "text/markdown", buffer: Buffer.from("# Profile\nПредпочитаю Swift") },
    { name: "project.md", mimeType: "text/markdown", buffer: Buffer.from("# Project\nUse SQLite") }
  ]);
  await page.getByRole("button", { name: "Remove project.md", exact: true }).click();
  const drop = await page.evaluateHandle(() => {
    const data = new DataTransfer();
    data.items.add(new File(["# Project\nUse SQLite"], "project.md", { type: "text/markdown" }));
    return data;
  });
  await page.dispatchEvent(".memory-import-drop", "drop", { dataTransfer: drop });
  await page.screenshot({ path: path.join(tmpdir(), "sloppy-memory-import-ui.png"), fullPage: true });
  await page.getByRole("button", { name: "Import into this agent", exact: true }).click();
  await page.getByRole("status").filter({ hasText: "1 memory records saved" }).waitFor();
  assert.equal(posted.attachments.length, 2);
  assert.equal(Buffer.from(posted.attachments[0].contentBase64, "base64").toString(), "# Profile\nПредпочитаю Swift");
  assert.match(posted.content, /bundled\/memory-import/);
  assert.equal(await page.getByRole("link", { name: "Open import session" }).getAttribute("href"), "/agents/import-test/chat/import-session");
  await page.reload();
  await page.getByRole("status").filter({ hasText: "1 memory records saved" }).waitFor();
  events.push({ type: "run_status", runStatus: { stage: "paused" } });
  await page.evaluate(() => window.dispatchEvent(new Event("focus")));
  await page.getByRole("status").filter({ hasText: "Needs your input" }).waitFor();
  events.push({ type: "tool_result", toolResult: { tool: "memory.save", ok: true, data: { id: "saved-two" } } });
  events.push({ type: "run_status", runStatus: { stage: "done" } });
  await page.evaluate(() => window.dispatchEvent(new Event("focus")));
  await page.getByRole("status").filter({ hasText: "2 memory records saved" }).waitFor();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole("button", { name: "Import memory", exact: true }).click();
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
  await page.evaluate(() => localStorage.clear());
  events = [];
  failRequest = true;
  await page.reload();
  await page.getByRole("button", { name: "Import memory", exact: true }).click();
  await page.locator('input[type="file"]').setInputFiles({ name: "retry.md", mimeType: "text/markdown", buffer: Buffer.from("# Retry") });
  await page.getByRole("button", { name: "Import into this agent", exact: true }).click();
  await page.getByRole("alert").filter({ hasText: "Check the session before retrying" }).waitFor();
  await page.getByRole("status").filter({ hasText: "Request failed" }).waitFor();
  assert.equal(await page.getByRole("button", { name: "Remove retry.md", exact: true }).count(), 1);
  assert.equal(await page.getByRole("link", { name: "Open import session" }).count(), 1);
  assert.deepEqual(errors, []);
  console.log("Memory import UI passed: prompt, validation, upload, drop, removal, typed progress, session link, reload, mobile layout, API failure recovery.");
} finally {
  await browser?.close();
  server.kill("SIGTERM");
  if (server.exitCode === null) await once(server, "exit");
  await rm(harness, { recursive: true, force: true });
}
