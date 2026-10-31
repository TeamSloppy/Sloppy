import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

// Exercise the real App, routing, theme and reused tools with an isolated Core.
const server = await createServer({
  root: fileURLToPath(new URL("..", import.meta.url)),
  server: { host: "127.0.0.1", port: 0 }
});
const output = new URL("../../.build/work-ui/", import.meta.url);
const now = new Date().toISOString();
const projects = [
  { id: "sloppy", name: "Sloppy", repoPath: "D:/Development/Sloppy", tasks: [
    { id: "task-1", title: "Build the Work workspace", status: "in_progress", priority: "high", createdAt: now, updatedAt: now },
    { id: "task-2", title: "Review the file browser", status: "needs_review", priority: "medium", createdAt: now, updatedAt: now }
  ], channels: [], actors: [], teams: [], description: "Agent runtime and dashboard" },
  { id: "other", name: "Other project", repoPath: "D:/Development/Other", tasks: [], channels: [], actors: [], teams: [] }
];
const agents = [{ id: "sloppy-agent", displayName: "Sloppy" }, { id: "reviewer", displayName: "Reviewer" }];
let sessions = [
  { id: "chat-1", agentId: "sloppy-agent", projectId: "sloppy", title: "Build the Work workspace", kind: "chat", messageCount: 2, createdAt: now, updatedAt: now },
  { id: "chat-2", agentId: "reviewer", projectId: "sloppy", title: "Review dashboard navigation", kind: "chat", messageCount: 0, createdAt: now, updatedAt: now },
  { id: "chat-other", agentId: "sloppy-agent", projectId: "other", title: "A chat in another project", kind: "chat", messageCount: 0, createdAt: now, updatedAt: now },
  { id: "worker-1", agentId: "sloppy-agent", projectId: "sloppy", title: "Internal worker", kind: "long_chat_worker", createdAt: now, updatedAt: now }
];
let failSessions = false;
let failCreate = false;
let terminalEnabled = true;
const writes = [];
const terminalMessages = [];
const errors = [];
let browser;
try {
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  browser = await chromium.launch(process.platform === "win32" ? { channel: "msedge" } : {});
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
  page.setDefaultTimeout(30000);
  page.on("pageerror", error => errors.push(error.message));
  await page.addInitScript(() => {
    localStorage.setItem("sloppy_dashboard_theme_v2", "minimal");
    // Exercise the actual recording hook without microphone access or real audio.
    Object.defineProperty(navigator, "mediaDevices", { configurable: true, value: {
      getUserMedia: async () => ({ getTracks: () => [{ stop() {} }] })
    } });
    window.MediaRecorder = class {
      static isTypeSupported() { return true; }
      state = "inactive";
      mimeType = "audio/webm";
      start() { this.state = "recording"; }
      stop() {
        this.state = "inactive";
        this.ondataavailable?.({ data: new Blob(["fixture audio"], { type: "audio/webm" }) });
        this.onstop?.();
      }
    };
  });
  await page.route("**/config.json", route => route.fulfill({ json: { apiBase: base } }));
  await page.route("**/health", route => route.fulfill({ json: { status: "ok", pid: 1234 } }));
  await page.routeWebSocket(/\/v1\//, socket => {
    socket.onMessage(message => {
      let value;
      try { value = JSON.parse(String(message)); } catch { return; }
      if (value.type === "auth") socket.send(JSON.stringify({ type: "authenticated" }));
      if (value.type === "start") {
        terminalMessages.push(value);
        socket.send(JSON.stringify({ type: "ready", sessionId: `terminal-${terminalMessages.length}`, cwd: "D:/Development/Sloppy", shell: "pwsh" }));
        socket.send(JSON.stringify({ type: "output", data: "Work terminal ready\r\nPS D:\\Development\\Sloppy> " }));
      }
      if (value.type === "input") terminalMessages.push(value);
    });
  });
  await page.route("**/v1/**", async route => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname;
    const method = request.method();
    if (!["GET", "OPTIONS"].includes(method)) writes.push({ path, method, body: request.postDataJSON() });
    let data = [];
    let status = 200;
    if (path === "/v1/config") data = { onboarding: { completed: true }, ui: { dashboardTerminal: { enabled: terminalEnabled } } };
    else if (path === "/v1/voice/config") data = { enabled: true, effectiveTranscriptionProvider: "openai", local: { enabled: false } };
    else if (path === "/v1/voice/transcriptions") data = { text: "A dictated message" };
    else if (path === "/v1/agent-sessions") { data = sessions; if (failSessions) status = 503; }
    else if (path === "/v1/agents") data = agents;
    else if (path === "/v1/projects") data = projects;
    else if (path.match(/^\/v1\/projects\/[^/]+$/)) data = projects.find(project => path.endsWith(`/${project.id}`));
    else if (path.endsWith("/source-control/working-tree")) data = { isRepository: true, branch: "main", linesAdded: 1, linesDeleted: 1,
      diff: "diff --git a/README.md b/README.md\n--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-Old workspace\n+Work workspace\n" };
    else if (path.endsWith("/files/content")) data = { path: "README.md", content: "# Sloppy\n\nA workspace for your agents.\n", language: "markdown" };
    else if (path.endsWith("/files")) data = [{ name: "README.md", path: "README.md", type: "file" }];
    else if (path.endsWith("/config")) data = { selectedModel: "test/model", availableModels: [{ id: "test/model", title: "Test model" }] };
    else if (path.endsWith("/approval-policy")) data = { mode: "ask_for_approval" };
    else if (path.endsWith("/sessions") && method === "POST") {
      if (failCreate) { status = 503; data = { error: "Core unavailable" }; }
      else {
        const body = request.postDataJSON();
        data = { id: `new-${sessions.length}`, agentId: path.split("/")[3], projectId: body.projectId || null, title: "New separate chat", kind: "chat", createdAt: now, updatedAt: now };
        sessions = [data, ...sessions];
      }
    }
    else if (path.endsWith("/sessions")) data = sessions.filter(session => session.agentId === path.split("/")[3] && (!url.searchParams.get("projectId") || session.projectId === url.searchParams.get("projectId")));
    else if (path.match(/\/sessions\/[^/]+$/)) {
      const summary = sessions.find(session => path.endsWith(`/${session.id}`));
      data = summary ? { summary, events: [] } : null;
    }
    else if (path === "/v1/actors/board") data = { nodes: [], teams: [], links: [] };
    else if (path.endsWith("/changes/stream")) return route.fulfill({ contentType: "text/event-stream", body: "" });
    else if (path.includes("/updates")) data = { available: false };
    else if (path.includes("/token-usage")) data = { totalTokens: 0 };
    await route.fulfill({ status, json: data });
  });
  await mkdir(output, { recursive: true });
  await page.goto(`${base}/work`, { waitUntil: "domcontentloaded", timeout: 60000 });
  const work = page.getByTestId("work-view");
  await work.getByRole("button", { name: "Build the Work workspace", exact: true }).waitFor();
  assert.equal(await page.getByTestId("sidebar-nav-work").getAttribute("aria-current"), "page");
  assert.equal(await work.getByText("Internal worker", { exact: true }).count(), 0);
  await work.getByRole("button", { name: "Select project Sloppy", exact: true }).click();
  assert.equal(await work.getByRole("button", { name: "A chat in another project", exact: true }).count(), 1);
  await work.getByRole("button", { name: "Collapse project Other project", exact: true }).click();
  assert.equal(await work.getByRole("button", { name: "A chat in another project", exact: true }).isVisible(), false);
  await work.getByRole("button", { name: "Expand project Other project", exact: true }).click();
  await work.getByRole("button", { name: "Build the Work workspace", exact: true }).click();
  const firstChat = work.getByRole("tabpanel", { name: "Build the Work workspace", exact: true });
  const firstInput = firstChat.getByTestId("agent-chat-compose-input");
  await firstInput.fill("");
  const primaryAction = firstChat.getByTestId("work-composer-action");
  await firstChat.getByRole("button", { name: "Dictate message", exact: true }).click();
  await firstChat.getByRole("button", { name: "Stop recording", exact: true }).click();
  await firstInput.getByText("A dictated message", { exact: true }).waitFor();
  assert.equal(await primaryAction.getAttribute("aria-label"), "Send message");
  assert.equal(await firstChat.locator(".work-composer-action").count(), 1);
  await firstInput.fill("Keep this draft in the first chat");
  assert.equal(await firstChat.locator(".agent-chat-main-head").count(), 0);
  assert.equal(await firstChat.locator(".agent-chat-compose").getByLabel("Select chat model").count(), 1);
  assert.equal(await firstChat.getByTestId("work-composer-action").getAttribute("aria-label"), "Send message");
  assert.equal(await firstChat.getByText(/pets|in the TUI|auto-pins/i).count(), 0);
  await firstChat.getByRole("button", { name: "Composer options", exact: true }).click();
  const options = firstChat.getByRole("menu", { name: "Composer options", exact: true });
  await page.screenshot({ path: fileURLToPath(new URL("work-composer-options-desktop.png", output)) });
  await options.getByRole("combobox", { name: "Agent for new chats", exact: true }).click();
  await options.getByRole("option", { name: "Reviewer", exact: true }).click();
  await options.getByRole("combobox", { name: "Agent for new chats", exact: true }).click();
  await options.getByRole("option", { name: "Sloppy", exact: true }).click();
  await options.getByRole("menuitemradio", { name: "Plan", exact: true }).click();
  await firstChat.getByRole("button", { name: "Composer options", exact: true }).click();
  assert.equal(await options.getByRole("menuitemradio", { name: "Plan", exact: true }).getAttribute("aria-checked"), "true");
  await options.getByRole("menuitem", { name: "Deep Research", exact: true }).click();
  await firstChat.getByRole("button", { name: "Close deep research configuration", exact: true }).click();
  const chrome = await firstChat.evaluate(element => {
    const tag = element.querySelector(".chat-approval-mode-trigger");
    return { approvalBorder: getComputedStyle(tag).borderTopWidth, composerRadius: getComputedStyle(element.querySelector(".agent-chat-compose")).borderRadius };
  });
  assert.equal(chrome.approvalBorder, "0px");
  assert.ok(parseFloat(chrome.composerRadius) >= 10);
  await work.getByRole("button", { name: "Review dashboard navigation", exact: true }).click();
  const secondChat = work.getByRole("tabpanel", { name: "Review dashboard navigation", exact: true });
  await secondChat.getByTestId("agent-chat-compose-input").fill("A different draft");
  await work.getByRole("tab", { name: "Build the Work workspace", exact: true }).click();
  assert.equal(await firstInput.innerText(), "Keep this draft in the first chat");
  assert.equal(await work.locator(".agent-chat-sidebar").count(), 0);
  await work.getByRole("tab", { name: "Build the Work workspace", exact: true }).focus();
  await page.keyboard.press("ArrowRight");
  assert.equal(await work.getByRole("tab", { name: "Review dashboard navigation", exact: true }).getAttribute("aria-selected"), "true");
  await page.keyboard.press("ArrowLeft");
  await work.getByRole("navigation", { name: "Work panels" }).getByRole("button", { name: "Files", exact: true }).click();
  await work.getByRole("button", { name: "README.md" }).click();
  await work.locator(".pft-viewer-body").getByText("A workspace for your agents.", { exact: false }).waitFor();
  await page.screenshot({ path: fileURLToPath(new URL("work-files-desktop.png", output)) });
  await work.getByRole("navigation", { name: "Work panels" }).getByRole("button", { name: "Review", exact: true }).click();
  const review = work.getByTestId("project-source-control-diff-panel");
  await review.locator("textarea").fill("Please simplify this change.");
  await review.getByRole("button", { name: "Add selection as tag" }).click();
  await firstChat.locator(".agent-chat-source-control-compose-tag").waitFor();
  await firstChat.getByRole("button", { name: "Remove diff reference", exact: true }).click();
  await firstInput.fill("Keep this draft in the first chat (saved)");
  await work.getByRole("button", { name: "Close chat Build the Work workspace", exact: true }).click();
  await work.getByRole("button", { name: "Build the Work workspace", exact: true }).click();
  await firstInput.waitFor();
  assert.equal(await firstInput.innerText(), "Keep this draft in the first chat (saved)");
  assert.equal(await firstChat.locator(".agent-chat-source-control-compose-tag").count(), 0);
  // A fresh review note still reaches the reopened chat once.
  await review.locator("textarea").fill("Keep this review note.");
  await review.getByRole("button", { name: "Add selection as tag" }).click();
  await firstChat.locator(".agent-chat-source-control-compose-tag").waitFor();
  await work.getByRole("button", { name: "Terminal", exact: true }).click();
  await work.locator(".work-terminal-context").getByText("Connected to D:/Development/Sloppy", { exact: false }).waitFor();
  assert.equal(terminalMessages[0].projectId, "sloppy");
  const surfaces = await work.locator(".work-terminal").evaluate(element => [element, element.querySelector(".terminal-drawer-screen"), element.querySelector(".xterm-viewport")].map(node => getComputedStyle(node).backgroundColor));
  assert.ok(surfaces.every(color => color === surfaces[0]), JSON.stringify(surfaces));
  const decoration = await work.evaluate(element => ({
    closeBackground: getComputedStyle(element.querySelector(".work-tab > button:last-child")).backgroundColor,
    reviewButtonBorder: getComputedStyle(element.querySelector(".agent-chat-source-control-panel__head-actions button")).borderTopWidth,
    tagRadius: getComputedStyle(element.querySelector(".agent-chat-source-control-compose-tag")).borderRadius
  }));
  assert.equal(decoration.closeBackground, "rgba(0, 0, 0, 0)");
  assert.equal(decoration.reviewButtonBorder, "0px");
  assert.ok(parseFloat(decoration.tagRadius) >= 6);
  await page.screenshot({ path: fileURLToPath(new URL("work-review-terminal-desktop.png", output)) });
  await work.getByRole("button", { name: "New Work terminal", exact: true }).click();
  assert.equal(await work.getByRole("tablist", { name: "Work terminal tabs" }).getByRole("tab").count(), 2);
  await work.getByRole("button", { name: "Hide Work terminal", exact: true }).click();
  await work.getByRole("navigation", { name: "Work panels" }).getByRole("button", { name: "Kanban", exact: true }).click();
  await work.locator(".project-kanban-pane").waitFor();
  await work.locator(".project-kanban-pane").getByText("Build the Work workspace", { exact: true }).waitFor();
  assert.equal(new URL(page.url()).pathname, "/work");
  await work.getByRole("button", { name: "Expand Work panel", exact: true }).click();
  await page.screenshot({ path: fileURLToPath(new URL("work-kanban-desktop.png", output)) });
  await work.locator(".project-kanban-pane").getByText("Build the Work workspace", { exact: true }).click();
  await work.getByRole("button", { name: "Close task details", exact: true }).waitFor();
  await work.getByRole("button", { name: "Close task details", exact: true }).click();
  assert.equal(new URL(page.url()).pathname, "/work");
  await work.getByRole("button", { name: "Restore Work panel", exact: true }).click();
  await work.getByRole("button", { name: "Close Work panel", exact: true }).click();
  // Closing a tab must retain the chat in history and select a neighboring tab.
  await work.getByRole("button", { name: "Close chat Review dashboard navigation", exact: true }).click();
  assert.equal(await work.getByRole("tablist", { name: "Open chats" }).getByRole("tab").count(), 1);
  assert.equal(await work.getByRole("button", { name: "Review dashboard navigation", exact: true }).count(), 1);
  failCreate = true;
  await work.locator(".work-header-new").click();
  await work.getByRole("alert").filter({ hasText: "Could not create chat" }).waitFor();
  failCreate = false;
  await work.locator(".work-header-new").click();
  await work.getByRole("tab", { name: "New separate chat", exact: true }).waitFor();
  const create = writes.findLast(write => write.path.endsWith("/sessions"));
  assert.equal(create.body.separateChat, true);
  assert.equal(create.body.projectId, "sloppy");
  assert.equal(writes.filter(write => write.path.includes("long-chat")).length, 0);
  await page.getByTestId("sidebar-nav-projects").click();
  assert.equal(await work.isVisible(), false);
  await page.getByRole("button", { name: "Open terminal", exact: true }).click();
  await page.locator(".terminal-drawer-status-text").getByText("Connected to D:/Development/Sloppy", { exact: false }).waitFor();
  const terminalCount = terminalMessages.filter(message => message.type === "start").length;
  await page.getByTestId("sidebar-nav-work").click();
  assert.equal(await page.locator(".terminal-drawer").isVisible(), false);
  await page.getByTestId("sidebar-nav-projects").click();
  await page.locator(".terminal-drawer.open").waitFor();
  assert.equal(terminalMessages.filter(message => message.type === "start").length, terminalCount);
  await page.getByTestId("sidebar-nav-work").click();
  await work.getByRole("tab", { name: "Build the Work workspace", exact: true }).click();
  assert.equal(await firstInput.innerText(), "Keep this draft in the first chat (saved)");
  // Persist the layout and tab selection across a full reload.
  await page.reload();
  await work.getByRole("tab", { name: "Build the Work workspace", exact: true }).waitFor();
  assert.equal(await work.getByRole("tab", { name: "Build the Work workspace", exact: true }).getAttribute("aria-selected"), "true");
  await work.getByRole("tabpanel", { name: "Build the Work workspace", exact: true }).getByTestId("agent-chat-compose-input").getByText("Keep this draft in the first chat (saved)").waitFor();
  failSessions = true;
  await work.getByRole("button", { name: "Refresh Work chats", exact: true }).click();
  await work.getByRole("alert").filter({ hasText: "Could not load chats" }).waitFor();
  failSessions = false;
  await work.getByRole("button", { name: "Retry", exact: true }).click();
  await work.getByRole("alert").filter({ hasText: "Could not load chats" }).waitFor({ state: "hidden" });
  for (const width of [1440, 1024, 768, 390]) {
    await page.setViewportSize({ width, height: 900 });
    if (width <= 1000 && await work.getByRole("button", { name: "Hide chats", exact: true }).count()) await work.getByRole("button", { name: "Hide chats", exact: true }).click();
    await work.getByRole("navigation", { name: "Work panels" }).getByRole("button", { name: "Files", exact: true }).click();
    await page.screenshot({ path: fileURLToPath(new URL(`work-files-${width}.png`, output)) });
    if (width <= 1000) {
      await work.getByRole("button", { name: "README.md" }).click();
      await work.getByRole("dialog").waitFor();
      await page.keyboard.press("Escape");
    }
    const layout = await work.evaluate(element => ({
      overflow: document.documentElement.scrollWidth > innerWidth + 1,
      bottom: element.getBoundingClientRect().bottom,
      rail: element.querySelector(".work-tool-rail").getBoundingClientRect().right
    }));
    assert.equal(layout.overflow, false, `${width}: ${JSON.stringify(layout)}`);
    assert.ok(layout.bottom <= 901, `${width}: ${JSON.stringify(layout)}`);
    assert.ok(layout.rail <= width + 1, `${width}: ${JSON.stringify(layout)}`);
    await work.getByRole("button", { name: "Close Work panel", exact: true }).click();
    if (width === 390) {
      await page.screenshot({ path: fileURLToPath(new URL("work-composer-mobile.png", output)) });
      const bounds = await work.getByRole("tabpanel", { name: "Build the Work workspace", exact: true }).locator(".agent-chat-compose").boundingBox();
      assert.ok(bounds && bounds.x >= 0 && bounds.x + bounds.width <= width, JSON.stringify(bounds));
      const active = work.getByRole("tabpanel", { name: "Build the Work workspace", exact: true });
      await active.getByRole("button", { name: "Composer options", exact: true }).click();
      const menuBounds = await active.getByRole("menu", { name: "Composer options", exact: true }).boundingBox();
      assert.ok(menuBounds && menuBounds.x >= 0 && menuBounds.x + menuBounds.width <= width && menuBounds.y >= 0, JSON.stringify(menuBounds));
      await page.keyboard.press("Escape");
    }
  }
  // Selecting a project without an open chat must survive reload too.
  await work.getByRole("button", { name: "Show chats", exact: true }).click();
  await work.getByRole("button", { name: "Select project Other project", exact: true }).click();
  await page.reload();
  await work.getByRole("button", { name: "Show chats", exact: true }).click();
  assert.equal(await work.locator(".work-header-project").innerText(), "Other project");
  await work.getByRole("heading", { name: "Room to work." }).waitFor();
  // Corrupt browser storage falls back to a usable empty workspace.
  terminalEnabled = false;
  await page.evaluate(() => localStorage.setItem("sloppy.work.v1", "{broken"));
  await page.reload();
  await work.getByRole("heading", { name: "Room to work." }).waitFor();
  await work.getByRole("button", { name: "Terminal", exact: true }).click();
  await work.getByRole("button", { name: "Terminal settings", exact: true }).waitFor();
  assert.deepEqual(errors, []);
  console.log("Work: project tree, composer options/model/approvals, combined dictation/send, independent drafts, files, review, terminal surfaces/tabs, Kanban, persistence, API failures and responsive layout passed.");
} catch (error) {
  const page = browser?.contexts()[0]?.pages()[0];
  if (page) {
    await page.screenshot({ path: fileURLToPath(new URL("failure.png", output)) }).catch(() => {});
    console.log("Page:", await page.locator("body").innerText().catch(() => "unavailable"));
    console.log("Browser errors:", errors);
    console.log("Layout:", await page.evaluate(() => [".page", ".work-route-container", ".work-shell", ".work-center", ".agent-chat-main", ".work-chat-stage", ".work-chat-pane", ".work-context"].map(selector => {
      const element = document.querySelector(selector);
      if (!element) return { selector, missing: true };
      const style = getComputedStyle(element);
      return { selector, height: element.getBoundingClientRect().height, top: element.getBoundingClientRect().top, minHeight: style.minHeight, flex: style.flex, position: style.position, display: style.display };
    })));
  }
  throw error;
} finally {
  await browser?.close();
  await server.close();
}
