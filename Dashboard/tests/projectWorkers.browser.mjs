import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { chromium } from "playwright";
const root = fileURLToPath(new URL("../", import.meta.url));
const harness = await mkdtemp(path.join(root, ".project-workers-test-"));
const port = 25118;
const server = spawn(process.execPath, ["node_modules/vite/bin/vite.js", "--host", "127.0.0.1", "--port", String(port), "--strictPort"], { cwd: root, stdio: "pipe" });
let browser;
try {
  await writeFile(path.join(harness, "index.html"), '<html><div id="root"></div><script type="module" src="./main.jsx"></script></html>');
  await writeFile(path.join(harness, "main.jsx"), `import React from "react";
import { createRoot } from "react-dom/client";
import { ProjectSettingsTab } from "../src/views/Projects/ProjectSettingsTab";
import "../src/styles/index.css";
const project = { id: "workers", name: "Workers test", channels: [], tasks: [], autopilotSettings: { enabled: true } };
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
  const toggle = page.getByRole("checkbox", { name: "Automatic task pickup", exact: true });
  assert.equal(await toggle.isChecked(), true);
  await toggle.locator("..").click();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await page.waitForFunction(() => window.savedPatch?.automaticTaskPickupEnabled === false);
  assert.equal(await toggle.isChecked(), false);
  assert.equal(await page.evaluate(() => window.savedPatch.autopilotSettings.enabled), true);
  await toggle.locator("..").click();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await page.waitForFunction(() => window.savedPatch?.automaticTaskPickupEnabled === true);
  let stopRequests = 0;
  await page.route("**/v1/projects/workers/emergency-stop", (route) => {
    stopRequests += 1;
    assert.equal(route.request().method(), "POST");
    return route.fulfill({ contentType: "application/json", body: JSON.stringify({
      project: { id: "workers", automaticTaskPickupEnabled: false },
      stoppedWorkerCount: 2, interruptedSessionCount: 2, warnings: []
    }) });
  });
  await page.getByRole("button", { name: "Stop all task executions" }).click();
  await page.getByRole("status").filter({ hasText: "Executions stopped" }).waitFor();
  assert.equal(await toggle.isChecked(), false);
  assert.equal(stopRequests, 1);
  await page.route("**/v1/projects/workers/emergency-stop", (route) => route.fulfill({ status: 500, body: "{}" }));
  await page.getByRole("button", { name: "Stop all task executions" }).click();
  await page.getByRole("status").filter({ hasText: "Emergency stop failed" }).waitFor();
  assert.deepEqual(errors, []);
  console.log("Workers settings: defaults, disable/save, preserved autopilot, re-enable, emergency stop, and failure reporting passed.");
} finally {
  await browser?.close();
  server.kill();
  await rm(harness, { recursive: true, force: true });
}
