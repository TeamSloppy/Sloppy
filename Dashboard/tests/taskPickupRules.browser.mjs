import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { chromium } from "playwright";
const root = fileURLToPath(new URL("../", import.meta.url));
const harness = await mkdtemp(path.join(root, ".pickup-rules-test-"));
const port = 25119;
const server = spawn(process.execPath, ["node_modules/vite/bin/vite.js", "--host", "127.0.0.1", "--port", String(port), "--strictPort"], { cwd: root, stdio: "pipe" });
let browser;
try {
  await writeFile(path.join(harness, "index.html"), '<html><div id="root"></div><script type="module" src="./main.jsx"></script></html>');
  await writeFile(path.join(harness, "main.jsx"), `import React from "react";
import { createRoot } from "react-dom/client";
import { ProjectSettingsTab } from "../src/views/Projects/ProjectSettingsTab";
import { markMaterialSymbolsReady } from "../src/app/iconFont";
void markMaterialSymbolsReady();
import "../src/styles/index.css";
const project = { id: "workers", name: "Workers test", channels: [], tasks: [{ externalMetadata: { providerId: "startrek", externalCreator: { id: "uid-42", displayName: "Alice" } } }], autopilotSettings: { enabled: true, includedTags: ["ios"], ignoredTags: ["manual"] } };
createRoot(document.getElementById("root")).render(<ProjectSettingsTab project={project} onUpdateProject={async (patch) => { window.savedPatch = patch; Object.assign(project, patch); return project; }} />);`);
  for (let attempt = 0; ; attempt++) {
    try { if ((await fetch(`http://127.0.0.1:${port}`)).ok) break; } catch {}
    if (attempt === 100) throw new Error("Vite did not start");
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  browser = await chromium.launch({ headless: true, ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage({ viewport: { width: 1280, height: 1000 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.route("**/v1/**", (route) => route.fulfill({ contentType: "application/json", body: "{}" }));
  await page.goto(`http://127.0.0.1:${port}/${path.basename(harness)}/`);
  await page.getByRole("button", { name: "Workers", exact: false }).click();
  const region = page.getByRole("region", { name: "Task pickup rules", exact: true });
  await region.getByRole("button", { name: "Add condition", exact: true }).click();
  assert.equal(await page.getByRole("button", { name: "Save", exact: true }).isDisabled(), true);
  await page.getByRole("button", { name: "Condition 1 known author", exact: true }).click();
  await page.getByRole("option", { name: "Alice (uid-42)", exact: true }).click();
  assert.equal(await page.getByRole("textbox", { name: "Condition 1 values", exact: true }).inputValue(), "uid-42");
  await page.getByRole("textbox", { name: "Condition 1 values", exact: true }).fill("alice.dev, bob");
  await region.getByRole("button", { name: "Add condition", exact: true }).click();
  await page.getByRole("button", { name: "Condition 2 field", exact: true }).click();
  await page.getByRole("option", { name: "Tracker queue", exact: true }).click();
  await page.getByRole("textbox", { name: "Condition 2 values", exact: true }).fill("CORE");
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await page.waitForFunction(() => window.savedPatch?.autopilotSettings?.pickupRules?.conditions?.length === 2);
  let saved = await page.evaluate(() => window.savedPatch.autopilotSettings);
  assert.equal(saved.pickupRules.matchMode, "all");
  assert.deepEqual(saved.pickupRules.conditions[0].values, ["alice.dev", " bob"]);
  assert.deepEqual(saved.pickupRules.conditions[1].values, ["CORE"]);
  assert.deepEqual(saved.includedTags, ["ios"]);
  assert.deepEqual(saved.ignoredTags, ["manual"]);
  await page.getByRole("button", { name: "Any condition (OR)", exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await page.waitForFunction(() => window.savedPatch?.autopilotSettings?.pickupRules?.matchMode === "any");
  await page.getByRole("button", { name: "Condition 2 operator", exact: true }).click();
  await page.getByRole("option", { name: "is missing", exact: true }).click();
  assert.equal(await page.getByRole("textbox", { name: "Condition 2 values", exact: true }).count(), 0);
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  await page.getByRole("textbox", { name: "Condition 2 values", exact: true }).waitFor();
  assert.equal(await page.getByRole("textbox", { name: "Condition 2 values", exact: true }).inputValue(), "CORE");
  await page.waitForFunction(() => document.documentElement.classList.contains("icons-ready"));
  await page.evaluate(() => { document.documentElement.dataset.theme = "modern"; });
  await page.setViewportSize({ width: 1280, height: 2200 });
  await region.screenshot({ path: "/tmp/sloppy-pickup-rules-desktop.png" });
  await page.setViewportSize({ width: 760, height: 2400 });
  assert.equal(await region.evaluate((element) => element.scrollWidth <= element.clientWidth + 1), true);
  await region.screenshot({ path: "/tmp/sloppy-pickup-rules-narrow.png" });
  await page.getByRole("button", { name: "Remove condition 2", exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await page.waitForFunction(() => window.savedPatch?.autopilotSettings?.pickupRules?.conditions?.length === 1);
  assert.deepEqual(errors, []);
  console.log("Pickup rules: add, invalid draft, AND/OR, field/operator selection, save/cancel, preserved tags, removal and responsive layout passed.");

} finally {
  await browser?.close();
  server.kill();
  await rm(harness, { recursive: true, force: true });
}
