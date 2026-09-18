import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const dashboardRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const source = readFileSync(
  join(dashboardRoot, "src", "features", "agents", "components", "AgentChatTab.tsx"),
  "utf8"
);

test("chat transcript resets its bottom-follow state when the opened session changes", () => {
  assert.match(source, /function AgentChatEvents\(\{[\s\S]*scrollKey,/);
  assert.match(source, /useLayoutEffect\(\(\) => \{[\s\S]*wasNearBottomRef\.current = true;[\s\S]*scrollTop = [\s\S]*scrollHeight;[\s\S]*\}, \[scrollKey\]\);/);
  assert.match(source, /<AgentChatEvents[\s\S]*scrollKey=\{activeSessionId\}/);
  assert.match(source, /<AgentChatEvents[\s\S]*scrollKey=\{subagentPanel\.sessionId\}/);
});

test("manual scrolling still disables bottom following until the user returns near the end", () => {
  assert.match(source, /wasNearBottomRef\.current = el\.scrollHeight - el\.scrollTop - el\.clientHeight < 80;/);
  assert.match(source, /if \(!scrollRef\.current \|\| !wasNearBottomRef\.current\)/);
});
