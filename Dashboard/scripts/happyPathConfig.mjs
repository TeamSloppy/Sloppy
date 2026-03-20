import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptsDir = path.dirname(fileURLToPath(import.meta.url));

export const CORE_API_BASE = (process.env.CORE_API_BASE || "http://127.0.0.1:25101").replace(/\/+$/, "");
export const DASHBOARD_BASE_URL = (process.env.DASHBOARD_BASE_URL || "http://127.0.0.1:25102").replace(/\/+$/, "");
export const OUTPUT_DIR = path.join(scriptsDir, "..", "output", "playwright", "happy-path");
export const SEED_STATE_PATH = path.join(OUTPUT_DIR, "seed-state.json");
export const CONSOLE_LOG_PATH = path.join(OUTPUT_DIR, "browser-console.log");
export const FAILURE_SCREENSHOT_PATH = path.join(OUTPUT_DIR, "failure.png");

export const HAPPY_PATH_FIXTURE = {
  projectId: "happy-path-project",
  projectName: "Happy Path Project",
  projectDescription: "Seeded project used by dashboard happy path verification.",
  agentId: "happy-path-agent",
  agentDisplayName: "Happy Path Agent",
  agentRole: "QA Driver",
  sessionTitle: "Happy Path Session",
  messageText: "Please summarize the current session state."
};
