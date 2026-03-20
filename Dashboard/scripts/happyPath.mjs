import fs from "node:fs/promises";
import { chromium } from "playwright";
import {
  CONSOLE_LOG_PATH,
  DASHBOARD_BASE_URL,
  FAILURE_SCREENSHOT_PATH,
  OUTPUT_DIR,
  SEED_STATE_PATH
} from "./happyPathConfig.mjs";

async function ensureOutputDir() {
  await fs.mkdir(OUTPUT_DIR, { recursive: true });
}

async function readSeedState() {
  const text = await fs.readFile(SEED_STATE_PATH, "utf8");
  return JSON.parse(text);
}

async function waitForText(page, selector, text, timeout = 30_000) {
  await page.waitForFunction(
    ({ targetSelector, expectedText }) => {
      const node = document.querySelector(targetSelector);
      return Boolean(node && node.textContent && node.textContent.includes(expectedText));
    },
    { targetSelector: selector, expectedText: text },
    { timeout }
  );
}

async function appendConsoleLog(lines) {
  await fs.writeFile(CONSOLE_LOG_PATH, `${lines.join("\n")}\n`, "utf8");
}

async function main() {
  await ensureOutputDir();
  const seed = await readSeedState();
  const consoleLines = [];
  const browser = await chromium.launch({ headless: process.env.PLAYWRIGHT_HEADLESS !== "0" });
  const page = await browser.newPage({
    viewport: { width: 1440, height: 1024 }
  });

  page.on("console", (message) => {
    consoleLines.push(`[console:${message.type()}] ${message.text()}`);
  });
  page.on("pageerror", (error) => {
    consoleLines.push(`[pageerror] ${error instanceof Error ? error.stack || error.message : String(error)}`);
  });

  try {
    await page.goto(DASHBOARD_BASE_URL, { waitUntil: "domcontentloaded" });
    await page.waitForSelector('[data-testid="sidebar-nav-overview"]', {
      state: "visible",
      timeout: 30_000
    });

    if (await page.getByText("First start bootstrap").count()) {
      throw new Error("Dashboard opened onboarding instead of seeded workspace.");
    }

    await page.click('[data-testid="sidebar-nav-agents"]');
    await page.waitForSelector(`[data-testid="agent-list-item-${seed.agentId}"]`, {
      state: "visible",
      timeout: 30_000
    });
    await page.click(`[data-testid="agent-list-item-${seed.agentId}"]`);
    await page.waitForSelector('[data-testid="agent-tab-chat"]', {
      state: "visible",
      timeout: 30_000
    });
    await page.click('[data-testid="agent-tab-chat"]');
    await page.waitForSelector(`[data-testid="agent-chat-session-${seed.sessionId}"]`, {
      state: "visible",
      timeout: 30_000
    });
    await page.click(`[data-testid="agent-chat-session-${seed.sessionId}"]`);
    await page.waitForSelector('[data-testid="agent-chat-compose-input"]', {
      state: "visible",
      timeout: 30_000
    });

    await page.click('[data-testid="agent-chat-compose-input"]');
    await page.keyboard.type(seed.messageText);
    await page.click('[data-testid="agent-chat-send"]');

    await waitForText(page, '[data-testid="agent-chat-events"]', seed.messageText);
    await page.waitForFunction(
      () => document.querySelectorAll('[data-testid^="agent-chat-message-assistant-"]').length > 0,
      undefined,
      { timeout: 30_000 }
    );

    await page.click('[data-testid="sidebar-nav-projects"]');
    await page.waitForSelector(`[data-testid="project-list-item-${seed.projectId}"]`, {
      state: "visible",
      timeout: 30_000
    });
    await page.click(`[data-testid="project-list-item-${seed.projectId}"]`);
    await page.waitForSelector(`[data-testid="project-workspace-${seed.projectId}"]`, {
      state: "visible",
      timeout: 30_000
    });

    await appendConsoleLog(consoleLines);
  } catch (error) {
    await page.screenshot({ path: FAILURE_SCREENSHOT_PATH, fullPage: true });
    await appendConsoleLog(consoleLines);
    throw error;
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.stack || error.message : String(error)}\n`);
  process.exitCode = 1;
});
