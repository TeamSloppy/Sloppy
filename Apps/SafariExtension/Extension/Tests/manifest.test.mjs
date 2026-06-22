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

test("extension declares tab access for browser context", () => {
  const manifest = loadManifest();
  assert.equal(manifest.permissions.includes("tabs"), true);
});

test("logo is web accessible for injected sidebar images", () => {
  const manifest = loadManifest();
  const resources = manifest.web_accessible_resources || [];
  assert.equal(
    resources.some((entry) => entry.resources?.includes("so_logo.svg") && entry.matches?.includes("<all_urls>")),
    true
  );
});

test("toolbar action uses the green Sloppy logo", () => {
  const manifest = loadManifest();
  assert.equal(manifest.action?.default_icon?.["128"], "so_logo.svg");
});
