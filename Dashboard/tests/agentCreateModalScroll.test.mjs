import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const dashboardRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const agentsCss = readFileSync(join(dashboardRoot, "src", "styles", "agents.css"), "utf8");

function ruleBody(selector) {
  const escapedSelector = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = agentsCss.match(new RegExp(`${escapedSelector}\\s*\\{([^}]+)\\}`));
  return match?.[1] || "";
}

test("agent create modal scrolls when the form is taller than a mobile viewport", () => {
  const cardRule = ruleBody(".agent-modal-card");

  assert.match(cardRule, /max-height:\s*calc\(100dvh - 40px\)/);
  assert.match(cardRule, /overflow-y:\s*auto/);
  assert.match(cardRule, /-webkit-overflow-scrolling:\s*touch/);
  assert.match(
    agentsCss,
    /@media\s*\(max-width:\s*700px\)[\s\S]*?\.agent-modal-overlay\s*\{[\s\S]*?align-items:\s*flex-start/
  );
});

test("agent pet controls stay readable in the create modal", () => {
  const petHeadCopyRule = ruleBody(".agent-pet-create-head > div");
  const petModeRule = ruleBody(".agent-pet-mode-row");

  assert.match(petHeadCopyRule, /display:\s*grid/);
  assert.match(petHeadCopyRule, /gap:\s*3px/);
  assert.match(petModeRule, /grid-template-columns:\s*repeat\(3,\s*minmax\(0,\s*1fr\)\)/);
});
