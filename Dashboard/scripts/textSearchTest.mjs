import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { build } from "esbuild";
import { chromium } from "playwright";

const directory = await mkdtemp(join(tmpdir(), "sloppy-text-search-"));
await build({
  stdin: {
    contents: `import React from "react"; import { createRoot } from "react-dom/client";
      import { TextSearchDialog } from "./src/features/search/TextSearchDialog";
      import { createCoreApi } from "./src/shared/api/coreApi";
      localStorage.setItem("sloppy_api_base_override", location.origin);
      const api = createCoreApi(); const root = createRoot(document.getElementById("root"));
      root.render(<TextSearchDialog coreApi={api} onClose={() => root.render(<p>Closed</p>)} onOpenSession={(hit) => { window.openedHit = hit; }} />);`,
    resolveDir: new URL("..", import.meta.url).pathname,
    loader: "tsx"
  }, bundle: true, format: "esm", outdir: directory, entryNames: "app", define: { "process.env.NODE_ENV": '"test"' }
});
const hit = { id: "match", source: "agent", agentId: "helper", sessionId: "s", title: "Earlier conversation", eventId: "e", before: "200", kind: "message", role: "assistant", createdAt: "2026-10-26T12:00:00Z", snippet: "Found \uE000SessionFile\uE001 in code <script>unsafe</script>" };
const requests = [];
const server = createServer(async (request, response) => {
  const url = new URL(request.url, "http://localhost");
  if (url.pathname === "/app.js" || url.pathname === "/app.css") {
    response.setHeader("content-type", url.pathname.endsWith("js") ? "application/javascript" : "text/css");
    response.end(await readFile(join(directory, url.pathname.slice(1)))); return;
  }
  if (url.pathname === "/v1/search") {
    requests.push(url);
    response.setHeader("content-type", "application/json");
    if (url.searchParams.get("q") === "failure") { response.statusCode = 503; response.end('{"error":"index unavailable"}'); return; }
    if (url.searchParams.get("q") === "slow") await new Promise((resolve) => setTimeout(resolve, 500));
    response.end(JSON.stringify({ items: [{ ...hit, title: url.searchParams.get("q") === "slow" ? "Stale result" : hit.title }], hasMore: url.searchParams.get("offset") === "0", indexing: false, indexedSources: 100, failedSources: 0, durationMs: 2 })); return;
  }
  if (url.pathname === "/v1/search/document") {
    response.setHeader("content-type", "application/json"); response.end(JSON.stringify({ hit, text: "Full AgentSessionFileStore content\n<script>window.injected=true</script>" })); return;
  }
  response.setHeader("content-type", "text/html");
  response.end('<html><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/app.css"></head><body><div id="root"></div><script type="module" src="/app.js"></script></body></html>');
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const browser = await chromium.launch({ headless: true, executablePath: process.env.SLOPPY_TEST_BROWSER_EXECUTABLE });
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  const input = page.getByRole("searchbox");
  await input.fill("C++ & SessionFile");
  await page.getByRole("button", { name: /Earlier conversation/ }).waitFor();
  assert.equal(requests.at(-1).searchParams.get("q"), "C++ & SessionFile");
  assert.equal(await page.locator("mark").textContent(), "SessionFile");
  await input.press("ArrowDown");
  await page.keyboard.press("Enter");
  await page.getByText("Full AgentSessionFileStore content", { exact: false }).waitFor();
  assert.equal(await page.evaluate(() => window.injected), undefined);
  await page.screenshot({ path: "/tmp/sloppy-text-search-desktop.png" });
  await Promise.all([
    page.waitForResponse((response) => new URL(response.url()).searchParams.get("mode") === "words"),
    page.getByRole("button", { name: "Words", exact: true }).click()
  ]);
  await page.waitForFunction(() => document.querySelector(".text-search-hit"));
  assert.equal(requests.at(-1).searchParams.get("mode"), "words");
  await Promise.all([
    page.waitForResponse((response) => new URL(response.url()).searchParams.get("offset") === "50"),
    page.getByRole("button", { name: "Next", exact: true }).click()
  ]);
  await page.waitForFunction(() => document.querySelector(".text-search-hit"));
  assert.equal(requests.at(-1).searchParams.get("offset"), "50");
  await input.fill("slow");
  await page.waitForTimeout(180);
  await input.fill("latest");
  await page.getByRole("button", { name: /Earlier conversation/ }).waitFor();
  await page.waitForTimeout(600);
  assert.equal(await page.getByText("Stale result").count(), 0);
  await input.fill("failure");
  await page.getByRole("alert").waitFor();
  assert.match(await page.getByRole("alert").textContent(), /Search unavailable/);
  await input.fill("SessionFile");
  await page.getByRole("button", { name: /Earlier conversation/ }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByText("Full AgentSessionFileStore content", { exact: false }).waitFor();
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
  await page.screenshot({ path: "/tmp/sloppy-text-search-mobile.png" });
  await page.getByRole("button", { name: "Open chat ↗" }).click();
  assert.equal((await page.evaluate(() => window.openedHit)).sessionId, "s");
  await page.getByText("Closed", { exact: true }).waitFor();
  assert.deepEqual(errors, []);
  console.log("Text search browser checks passed: literals, highlighting, preview, pagination, cancellation, errors, mobile, navigation.");
} finally {
  await browser.close();
  await new Promise((resolve) => server.close(resolve));
  await rm(directory, { recursive: true, force: true });
}
