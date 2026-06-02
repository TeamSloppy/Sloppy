import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const dashboardRoot = join(__dirname, "..");

test("agent pet icons do not use generated raster sprite parts", () => {
  assert.equal(existsSync(join(dashboardRoot, "public", "sprites", "manifest.json")), false);
  assert.equal(existsSync(join(dashboardRoot, "scripts", "slice-sloppies-sheet.mjs")), false);
  assert.equal(existsSync(join(dashboardRoot, "scripts", "generate-placeholder-sprites.mjs")), false);
});
