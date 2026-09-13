// Browser integration with fixture API responses.
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
createRoot(document.getElementById("root")!).render(<main style={{maxWidth:840,padding:24,margin:"auto"}}><AgentMemoryImport agentId="import-test" onUpdated={()=>{}} /></main>);`);
  for (let attempt = 0; ; attempt++) {
    try { if ((await fetch(`http://127.0.0.1:${port}`)).ok) break; } catch {}
    if (attempt === 100) throw new Error("Vite did not start");
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  browser = await chromium.launch({ headless: true, ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage({ viewport: { width: 1100, height: 1100 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  let job = null, posted, failRequest = false, legacyRequests = 0;
  const makeJob = () => ({ id: "00000000-0000-0000-0000-000000000001", agentId: "import-test", sessionId: "import-session", status: "running",
    totalUnits: 8, completedUnits: 2, savedCount: 2, duplicateCount: 0, ignoredCount: 0,
    parts: Array.from({ length: 8 }, (_, index) => ({ id: `part-${index}`, sourceId: "00000000-0000-0000-0000-000000000002", startUTF8: index * 2048, endUTF8: (index + 1) * 2048, completed: index < 2, disposition: "retained", reason: "Technical fact", memoryIds: index < 2 ? [`memory-${index}`] : [] })),
    sources: [{ id: "00000000-0000-0000-0000-000000000002", name: "profile.md", sha256: "abc", totalUnits: 8, completedUnits: 2 }] });
  await page.route("**/v1/**", async (route) => {
    const request = route.request(), url = new URL(request.url());
    if (request.method() === "OPTIONS") return route.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*" } });
    let body;
    if (request.method() === "POST" && url.pathname.endsWith("/sessions")) body = { id: "import-session" };
    else if (request.method() === "POST" && url.pathname.endsWith("/memory-imports")) {
      if (failRequest) return route.fulfill({ status: 503, json: { error: "unavailable" }, headers: { "access-control-allow-origin": "*" } });
      posted = request.postDataJSON(); job = makeJob(); body = job;
    } else if (url.pathname.includes("/from-session/")) { legacyRequests++; job = makeJob(); body = job; }
    else if (url.pathname.endsWith("/resume")) { job = { ...job, status: "running", error: null }; body = job; }
    else if (url.pathname.includes("/sources/")) body = { name: "profile.md", sha256: "abc", content: "# Archived source\nПредпочитаю Swift. Original file deleted." };
    else if (url.pathname.endsWith("/memory-imports")) body = job ? [job] : [];
    else body = job;
    await route.fulfill({ json: body, headers: { "access-control-allow-origin": "*" } });
  });
  await page.goto(`http://127.0.0.1:${port}/${path.basename(harness)}/index.html`);
  await page.getByRole("button", { name: "Import memory", exact: true }).click();
  await page.getByText("Export prompt", { exact: true }).click();
  assert.match(await page.getByLabel("Memory export prompt").inputValue(), /Export the useful memory/);
  await page.getByText("Export prompt", { exact: true }).click();
  await page.locator('input[type="file"]').setInputFiles({ name: "wrong.txt", mimeType: "text/plain", buffer: Buffer.from("bad") });
  await page.getByRole("alert").filter({ hasText: "only Markdown" }).waitFor();
  await page.locator('input[type="file"]').setInputFiles({ name: "profile.md", mimeType: "text/markdown", buffer: Buffer.from("# Profile\nПредпочитаю Swift") });
  const drop = await page.evaluateHandle(() => { const data = new DataTransfer(); data.items.add(new File(["# Project\nUse SQLite"], "project.md", { type: "text/markdown" })); return data; });
  await page.dispatchEvent(".memory-import-drop", "drop", { dataTransfer: drop });
  await page.getByRole("button", { name: "Import into this agent", exact: true }).click();
  await page.getByRole("status").filter({ hasText: "2/8 parts verified" }).waitFor();
  assert.equal(posted.attachments.length, 2);
  assert.equal(Buffer.from(posted.attachments[0].contentBase64, "base64").toString(), "# Profile\nПредпочитаю Swift");
  assert.equal(posted.sessionId, "import-session");
  assert.equal(await page.getByText("Import complete", { exact: true }).count(), 0);
  job = { ...job, status: "failed", error: "Coverage reviewer found omitted details" };
  await page.evaluate(() => window.dispatchEvent(new Event("focus")));
  await page.getByText("Import needs attention", { exact: true }).waitFor();
  await page.getByRole("button", { name: "Resume remaining work", exact: true }).click();
  await page.getByText("Import continues in the background", { exact: true }).waitFor();
  job = { ...job, status: "completed", completedUnits: 8, savedCount: 8, parts: job.parts.map((part) => ({ ...part, completed: true })), sources: job.sources.map((source) => ({ ...source, completedUnits: 8 })) };
  await page.evaluate(() => window.dispatchEvent(new Event("focus")));
  await page.getByText("Import complete", { exact: true }).waitFor();
  await page.reload();
  await page.getByText("Import complete", { exact: true }).waitFor();
  await page.getByText("Coverage report (8/8)", { exact: true }).click();
  assert.equal(await page.locator(".memory-import-coverage li").count(), 8);
  await page.getByText("Archived source files (1)", { exact: true }).click();
  await page.getByRole("button", { name: "profile.md · 8/8 parts", exact: true }).click();
  await page.getByText("Original file deleted.", { exact: false }).waitFor();
  await page.screenshot({ path: path.join(tmpdir(), "sloppy-durable-memory-import.png"), fullPage: true, animations: "disabled" });
  await page.evaluate(() => { localStorage.clear(); localStorage.setItem("sloppy:memory-import:import-test", "old-session"); });
  job = null;
  await page.reload();
  await page.getByRole("button", { name: "Import memory", exact: true }).click();
  await page.getByRole("button", { name: "Continue previous import from saved attachments", exact: true }).click();
  await page.getByText("Import continues in the background", { exact: true }).waitFor();
  assert.equal(legacyRequests, 1);
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
  failRequest = true;
  await page.locator('input[type="file"]').setInputFiles({ name: "retry.md", mimeType: "text/markdown", buffer: Buffer.from("# Retry") });
  await page.getByRole("button", { name: "Import into this agent", exact: true }).click();
  await page.getByRole("alert").filter({ hasText: "Check import history" }).waitFor();
  assert.equal(await page.getByRole("button", { name: "Remove retry.md", exact: true }).count(), 1);
  assert.deepEqual(errors, []);
  console.log("Durable import UI passed: verified coverage, background state, resume, source snapshot, reload, legacy migration, upload, mobile, API failure.");
} finally {
  await browser?.close(); server.kill("SIGTERM");
  if (server.exitCode === null) await once(server, "exit");
  await rm(harness, { recursive: true, force: true });
}
