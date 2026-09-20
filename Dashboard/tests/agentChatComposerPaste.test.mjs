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

test("chat composer inserts pasted plain text through controlled editor state", () => {
  assert.match(source, /function getEditorSelectionOffsets\(root\)/);
  assert.match(
    source,
    /onPaste=\{\(event\) => \{[\s\S]*const text = event\.clipboardData\?\.getData\("text\/plain"\)[\s\S]*getEditorSelectionOffsets\(event\.currentTarget\)[\s\S]*applyInputValue\(nextValue, start \+ text\.length\)/
  );
  assert.doesNotMatch(source, /document\.execCommand\("insertText"/);
});

test("chat composer does not cancel a paste when the clipboard has no plain text", () => {
  assert.match(
    source,
    /const text = event\.clipboardData\?\.getData\("text\/plain"\) \|\| "";[\s\S]*if \(!text\) \{[\s\S]*return;[\s\S]*\}[\s\S]*event\.preventDefault\(\)/
  );
});
