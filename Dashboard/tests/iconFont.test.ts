import assert from "node:assert/strict";
import test from "node:test";

import { markMaterialSymbolsReady } from "../src/app/iconFont.ts";

function makeDocument(fonts) {
  const classes = new Set();
  return {
    classes,
    documentElement: {
      classList: {
        add(className) {
          classes.add(className);
        }
      }
    },
    fonts
  };
}

test("material symbols readiness loads the local icon font before marking icons ready", async () => {
  const calls = [];
  const doc = makeDocument({
    async load(font, text) {
      calls.push(["load", font, text]);
    },
    check(font, text) {
      calls.push(["check", font, text]);
      return true;
    }
  });

  const loaded = await markMaterialSymbolsReady(doc);

  assert.equal(loaded, true);
  assert.deepEqual(calls, [
    ["load", "20px 'Material Symbols Rounded'", "home"],
    ["check", "20px 'Material Symbols Rounded'", "home"]
  ]);
  assert.equal(doc.classes.has("icons-ready"), true);
});

test("material symbols readiness releases icon placeholders when the font API is unavailable", async () => {
  const doc = makeDocument(undefined);

  const loaded = await markMaterialSymbolsReady(doc);

  assert.equal(loaded, false);
  assert.equal(doc.classes.has("icons-ready"), true);
});
