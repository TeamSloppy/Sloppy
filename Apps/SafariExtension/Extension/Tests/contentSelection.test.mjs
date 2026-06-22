import assert from "node:assert/strict";
import { test } from "node:test";
import { extractPageContext } from "../Resources/contentScript.js";

test("extractPageContext trims selected text and reads page metadata", () => {
  const context = extractPageContext(
    {
      location: { href: "https://example.com/page" },
      title: "Example Page"
    },
    "  Selected text  "
  );

  assert.deepEqual(context, {
    page: {
      url: "https://example.com/page",
      title: "Example Page"
    },
    selection: "Selected text"
  });
});
