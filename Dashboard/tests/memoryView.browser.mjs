// UI integration with fixture API responses. Run: node tests/memoryView.browser.mjs
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { tmpdir } from "node:os";
import { chromium } from "playwright";

const root = fileURLToPath(new URL("../", import.meta.url));
const harness = await mkdtemp(path.join(root, ".memory-view-test-"));
const port = 25113;
const server = spawn(process.execPath, ["node_modules/vite/bin/vite.js", "--host", "127.0.0.1", "--port", String(port), "--strictPort"], { cwd: root, stdio: "pipe" });
let browser;
try {
  await writeFile(path.join(harness, "index.html"), '<html><div id="root"></div><script type="module" src="./main.tsx"></script></html>');
  await writeFile(path.join(harness, "main.tsx"), `import React from "react";
import { createRoot } from "react-dom/client";
import { MemoryView } from "../src/features/memory/MemoryView";
import { SidebarView } from "../src/components/SidebarView";
import { useDashboardRoute } from "../src/app/routing/useDashboardRoute";
import "../src/styles/index.css";
document.documentElement.classList.add("icons-ready");
function App() {
  const {route,setMemoryRoute,setSection}=useDashboardRoute();
  return <div className="layout"><SidebarView items={[{id:"overview",label:{title:"Overview",icon:"dashboard"}},{id:"agents",label:{title:"Agents",icon:"support_agent"}},{id:"memory",label:{title:"Memory",icon:"neurology"}},{id:"config",label:{title:"Settings",icon:"settings"}}]} activeItemId={route.section} isCompact={false} onToggleCompact={()=>{}} onSelect={setSection}/><div className="page"><MemoryView tab={route.memoryTab} scopeType={route.memoryScopeType} scopeId={route.memoryScopeId} onRouteChange={setMemoryRoute}/></div></div>;
}
createRoot(document.getElementById("root")!).render(<App/>);`);
  for (let attempt = 0; ; attempt++) {
    try { if ((await fetch(`http://127.0.0.1:${port}`)).ok) break; } catch { /* Wait for Vite. */ }
    if (attempt === 100) throw new Error("Vite did not start");
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  browser = await chromium.launch({ headless: true, ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  let config = { workspace: { name: "preserve-me", basePath: "/tmp/memory-ui" }, models: [], memory: { backend: "sqlite", provider: { mode: "local", timeoutMs: 2500 }, embedding: { enabled: false, model: "text-embedding-3-small" } }, visor: { autodream: { enabled: true, intervalSeconds: 21600 } } };
  let saves = 0;
  let failConfig = false;
  const records = [
    { id: "one", note: "Prefer concise answers", kind: "preference", scope: { type: "agent", id: "helper" } },
    { id: "two", note: "Use SQLite for Aurora", kind: "decision", scope: { type: "project", id: "aurora" } },
    { id: "three", note: "Shared team convention", kind: "fact", scope: { type: "global", id: "shared" } }
  ];
  await page.route("**/*", async (route) => {
    if (route.request().resourceType() === "document") return route.fulfill({ contentType: "text/html", body: `<html><div id="root"></div><script type="module" src="/${path.basename(harness)}/main.tsx"></script></html>` });
    return route.fallback();
  });
  await page.route("**/v1/**", async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    if (req.method() === "OPTIONS") return route.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "GET, PUT, POST" } });
    let data = {};
    if (url.pathname === "/v1/config") {
      if (failConfig) return route.fulfill({ status: 503, json: { error: "unavailable" }, headers: { "access-control-allow-origin": "*" } });
      if (req.method() === "PUT") { config = req.postDataJSON(); saves++; }
      data = config;
    } else if (url.pathname === "/v1/agents") data = [{ id: "helper", displayName: "Helper" }];
    else if (url.pathname === "/v1/projects") data = [{ id: "aurora", name: "Aurora" }];
    else if (url.pathname.endsWith("/config") && url.pathname.includes("/agents/")) data = { documents: { memoryMarkdown: "# Curated memory\nKeep existing notes." } };
    else if (url.pathname.endsWith("/graph")) data = { nodes: [], edges: [], seedIds: [], truncated: false };
    else if (url.pathname.endsWith("/memories")) {
      let items = records.filter((item) => !url.searchParams.get("search") || item.note.toLowerCase().includes(url.searchParams.get("search").toLowerCase()));
      if (url.searchParams.get("scope") === "global") items = items.filter((item) => item.scope.type === "global");
      if (url.pathname.includes("/agents/")) items = items.filter((item) => item.scope.type === "agent");
      if (url.pathname.includes("/projects/")) items = items.filter((item) => item.scope.type === "project");
      data = { items, total: items.length, limit: 20, offset: 0 };
    } else if (url.pathname.includes("models") || url.pathname.includes("plugins")) data = [];
    await route.fulfill({ json: data, headers: { "access-control-allow-origin": "*" } });
  });
  const base = `http://127.0.0.1:${port}`;
  await page.goto(`${base}/memory/overview`);
  await page.getByText("Built-in local", { exact: true }).waitFor();
  assert.equal(await page.getByTestId("sidebar-nav-memory").getAttribute("class"), "sidebar-item active");
  await page.screenshot({ path: path.join(tmpdir(), "sloppy-memory-overview.png"), fullPage: true, animations: "disabled" });
  await page.getByRole("button", { name: "Memories", exact: true }).click();
  await page.getByText("Shared team convention", { exact: true }).first().waitFor();
  await page.getByLabel("Search all memory").fill("SQLite");
  await page.getByText("1 matching records.", { exact: false }).waitFor();
  await page.getByRole("combobox", { name: "Memory scope" }).click();
  await page.getByRole("option", { name: "Helper Agents" }).click();
  await page.getByRole("button", { name: "Import memory", exact: true }).waitFor();
  await page.getByText("MEMORY.md", { exact: true }).click();
  await page.getByText("Keep existing notes.", { exact: false }).waitFor();
  assert.match(page.url(), /memory\/memories\/agent\/helper$/);
  await page.reload();
  await page.getByRole("button", { name: "Import memory", exact: true }).waitFor();
  await page.getByRole("button", { name: "Settings", exact: true }).click();
  await page.getByText("Config loaded", { exact: true }).waitFor();
  assert.equal(await page.locator("select").count(), 0);
  await page.getByLabel("Memory Timeout (ms)", { exact: false }).fill("900");
  await page.getByRole("button", { name: "Apply", exact: true }).click();
  await page.getByText("Config saved", { exact: true }).waitFor();
  assert.equal(config.memory.provider.timeoutMs, 900);
  assert.equal(config.workspace.name, "preserve-me");
  assert.equal(saves, 1);
  assert.deepEqual(await page.evaluate(() => ({ scroll: window.scrollX, overflow: document.documentElement.scrollWidth > window.innerWidth })), { scroll: 0, overflow: false });
  await page.screenshot({ path: path.join(tmpdir(), "sloppy-memory-settings.png"), fullPage: true, animations: "disabled" });
  await page.getByRole("button", { name: "Dreams", exact: true }).click();
  await page.getByRole("heading", { name: "Autodream", exact: true }).waitFor();
  await page.locator('input[type="checkbox"]').uncheck();
  await page.getByRole("button", { name: "Apply", exact: true }).click();
  await page.getByText("Config saved", { exact: true }).waitFor();
  assert.equal(config.visor.autodream.enabled, false);
  assert.equal(config.memory.provider.timeoutMs, 900);
  await page.goto(`${base}/projects/aurora/memory`);
  await page.getByRole("heading", { name: /Memory/ }).first().waitFor();
  assert.match(page.url(), /memory\/memories\/project\/aurora$/);
  await page.getByRole("button", { name: "Overview", exact: true }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
  failConfig = true;
  await page.goto(`${base}/memory/settings`);
  await page.getByText("Failed to load config", { exact: true }).waitFor();
  assert.equal(await page.getByLabel("Memory Timeout (ms)", { exact: false }).count(), 0);
  assert.deepEqual(errors, []);
  console.log("Memory section UI passed: sidebar, all records, search, scope, import, document, reload, settings save, Dreams save, legacy route, mobile.");

} finally {
  await browser?.close();
  server.kill("SIGTERM");
  if (server.exitCode === null) await once(server, "exit");
  await rm(harness, { recursive: true, force: true });
}
