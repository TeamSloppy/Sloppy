import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { existsSync } from "node:fs";
import { test } from "node:test";

function loadProjectYAML() {
  return readFileSync(new URL("../../project.yml", import.meta.url), "utf8");
}

test("mesh runtime module is covered by generated Safari web extension resources", () => {
  assert.equal(existsSync(new URL("../Resources/mesh.js", import.meta.url)), true);

  const project = loadProjectYAML();
  for (const target of [
    "SafariExtensionWebExtension-macOS",
    "SafariExtensionWebExtension-iOS",
    "SafariExtensionWebExtension-visionOS"
  ]) {
    const targetBlock = project.match(new RegExp(`  ${target}:\\n[\\s\\S]*?(?=\\n  [A-Za-z0-9-]+:\\n|\\nschemes:)`))?.[0] || "";
    assert.match(targetBlock, /sources:\n\s+- Extension\/Native\n\s+- Extension\/Resources/);
  }
});
