import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

function loadManifest() {
  return JSON.parse(readFileSync(new URL("../Resources/manifest.json", import.meta.url), "utf8"));
}

test("host permissions use valid WebExtension match patterns", () => {
  const manifest = loadManifest();
  assert.equal(manifest.host_permissions.includes("http://192.168.0.0/16"), false);
  assert.equal(manifest.host_permissions.includes("<all_urls>"), true);
});
