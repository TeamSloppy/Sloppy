import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

// Use the real component and all Dashboard styles: the original regression was
// caused by the global input width, and was only visible in a browser layout.
const html = `<!doctype html><html data-theme="minimal"><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><div id="root"></div><script type="module" src="/__migration-layout-entry.js"></script></body></html>`;
const entry = `
  import React from "react";
  import { createRoot } from "react-dom/client";
  import { MigrationLaunchNotice, MigrationWizard } from "/src/features/migrations/MigrationWizard.tsx";
  import "/src/styles/index.css";
  window.__SLOPPY_CONFIG__ = { apiBase: window.location.origin };
  const inline = new URLSearchParams(location.search).has("inline");
  createRoot(document.getElementById("root")).render(React.createElement("main", { className: "onboarding-panel" },
    React.createElement(inline ? MigrationWizard : MigrationLaunchNotice, { onboarding: true })));
`;
const server = await createServer({
  root: fileURLToPath(new URL("..", import.meta.url)),
  server: { host: "127.0.0.1", port: 0 },
  plugins: [{
    name: "migration-layout-fixture",
    resolveId(id) { if (id === "/__migration-layout-entry.js") return id; },
    load(id) { if (id === "/__migration-layout-entry.js") return entry; },
    configureServer(vite) {
      vite.middlewares.use(async (req, res, next) => {
        if (!req.url?.startsWith("/__migration-layout?")) return next();
        res.setHeader("Content-Type", "text/html");
        res.end(await vite.transformIndexHtml(req.url, html));
      });
    }
  }]
});
let browser;
const output = new URL("../../.build/migration-ui/", import.meta.url);
const sources = [
  { id: "codex", kind: "codex", path: "C:/Users/Vladislav/.codex", readable: true },
  { id: "claude", kind: "claude", path: `C:/Users/Vladislav/Development/${"long-project-folder-".repeat(12)}/.claude`, readable: true }
];
const items = sources.map((source, index) => ({
  id: `item-${index}`, source, externalID: `external-${index}`, profile: "default", category: "skill",
  title: `Skill from ${source.kind}`, projectPath: source.path,
  files: [], messages: [], warnings: []
}));
const requests = [];
const errors = [];
let availableSources = sources;
try {
  await server.listen();
  const address = server.httpServer.address();
  const base = `http://127.0.0.1:${address.port}`;
  browser = await chromium.launch(process.platform === "win32" ? { channel: "msedge" } : {});
  const page = await browser.newPage();
  page.setDefaultTimeout(10_000);
  await page.addInitScript(() => localStorage.clear());
  page.on("pageerror", error => errors.push(error.message));
  await page.route("**/v1/**", async route => {
    const path = new URL(route.request().url()).pathname;
    if (route.request().method() === "POST") requests.push({ path, body: route.request().postDataJSON() });
    let body = [];
    if (path === "/v1/migrations/sources") body = availableSources;
    else if (path === "/v1/migrations/scan") body = { sources, items, warnings: [] };
    else if (path === "/v1/migrations/preview") body = { totalBytes: 120, counts: { skill: 2 }, duplicates: [], conflicts: [], warnings: [] };
    await route.fulfill({ json: body, headers: { "Access-Control-Allow-Origin": "*" } });
  });
  await mkdir(output, { recursive: true });

  async function checkLayout() {
    const layout = await page.locator(".migration-wizard").evaluate(wizard => {
      const checks = [...wizard.querySelectorAll('input[type="checkbox"]')].map(input => input.getBoundingClientRect().width);
      const rows = [...wizard.querySelectorAll(".migration-choice")].map(row => ({
        width: row.querySelector("span").getBoundingClientRect().width,
        height: row.getBoundingClientRect().height
      }));
      return { checks, rows, overflow: wizard.scrollWidth > wizard.clientWidth + 1, pageOverflow: document.documentElement.scrollWidth > innerWidth };
    });
    assert.ok(layout.checks.every(width => width >= 16 && width <= 22), JSON.stringify(layout));
    assert.ok(layout.rows.every(row => row.width > 160 && row.height < 320), JSON.stringify(layout));
    assert.equal(layout.overflow, false);
    assert.equal(layout.pageOverflow, false);
  }

  for (const width of [1440, 640, 375]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(`${base}/__migration-layout?width=${width}`);
    await page.getByRole("button", { name: "Import data", exact: true }).click();
    await page.locator(".migration-choice").first().waitFor();
    await checkLayout();
    assert.equal(await page.locator(".migration-close").evaluate(button => button === document.activeElement), true);
    assert.equal(await page.locator(".migration-close").count(), 1);
    assert.equal(await page.locator(".migration-steps [aria-current=step]").innerText(), "1\nSources");
    await page.screenshot({ path: fileURLToPath(new URL(`sources-${width}.png`, output)) });
    const first = page.locator(".migration-choice input").first();
    await first.uncheck();
    assert.match(await page.locator(".migration-section-heading").innerText(), /1 selected/);
    await first.check();
    await page.locator(".migration-manual summary").click();
    await page.getByRole("button", { name: "Hermes", exact: true }).click();
    assert.equal(await page.locator(".migration-manual details").getAttribute("open"), null);
    await page.getByRole("button", { name: "Analyze sources" }).click();
    await page.getByRole("button", { name: "Choose destinations" }).waitFor();
    await checkLayout();
    await page.getByRole("button", { name: "Choose destinations" }).click();
    await page.getByRole("heading", { name: "Project folders on Core" }).waitFor();
    await checkLayout();
    await page.getByRole("button", { name: "Preview", exact: true }).click();
    await page.getByRole("button", { name: "Transfer selected data" }).waitFor();
    await checkLayout();
    if (width === 375) await page.keyboard.press("Escape");
    else await page.getByRole("button", { name: "Close", exact: true }).click();
    assert.equal(await page.getByRole("dialog").count(), 0);
  }

  // Settings embeds the same wizard without a modal or Close action.
  await page.goto(`${base}/__migration-layout?inline`);
  await page.locator(".migration-choice").first().waitFor();
  await checkLayout();
  assert.equal(await page.locator(".migration-close").count(), 0);
  assert.equal(await page.getByRole("textbox").evaluate(input => getComputedStyle(input).backgroundColor), "rgba(0, 0, 0, 0)");
  assert.equal(requests.filter(request => request.path.endsWith("/scan")).length, 3);
  assert.ok(requests.filter(request => request.path.endsWith("/scan")).every(request => request.body.sources.length === 2));
  availableSources = sources.slice(0, 1);
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto(`${base}/__migration-layout?single-source`);
  await page.getByRole("button", { name: "Import data", exact: true }).click();
  await page.locator(".migration-choice").waitFor();
  await checkLayout();
  await page.screenshot({ path: fileURLToPath(new URL("migration-desktop.png", output)) });
  assert.deepEqual(errors, []);
  console.log("Migration layout: desktop, tablet, mobile, long Windows paths, selection, dropdown, preview and inline settings passed.");
} finally {
  await browser?.close();
  await server.close();
}
