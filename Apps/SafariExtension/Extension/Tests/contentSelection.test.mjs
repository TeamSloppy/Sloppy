import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

function loadContentScriptSandbox() {
  const source = readFileSync(new URL("../Resources/contentScript.js", import.meta.url), "utf8");
  assert.equal(/\bexport\s+function\b/.test(source), false);

  const sandbox = {
    chrome: undefined,
    document: undefined,
    globalThis: {}
  };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(source, sandbox);
  return sandbox;
}

test("extractPageContext trims selected text and reads page metadata", () => {
  const { extractPageContext } = loadContentScriptSandbox();
  const context = extractPageContext(
    {
      location: { href: "https://example.com/page" },
      title: "Example Page"
    },
    "  Selected text  "
  );

  assert.equal(context.page.url, "https://example.com/page");
  assert.equal(context.page.title, "Example Page");
  assert.equal(context.selection, "Selected text");
});
