import assert from "node:assert/strict";
import { test } from "node:test";
import {
  buildBrowserContextPayload,
  extractPromptReferences
} from "../Resources/panel.js";

test("extractPromptReferences strips @project and #task markers from composer text", () => {
  const parsed = extractPromptReferences("@PROMOZAVR #123 надо добавить это сюда");

  assert.deepEqual(parsed, {
    prompt: "надо добавить это сюда",
    projectReference: "PROMOZAVR",
    taskReference: "123"
  });
});

test("buildBrowserContextPayload includes parsed project and task references", () => {
  const payload = buildBrowserContextPayload(
    { defaultAgentID: "sloppy" },
    { url: "https://example.com/a", title: "Article" },
    "Selected text",
    "Надо добавить это сюда",
    {
      projectReference: "PROMOZAVR",
      taskReference: "123"
    }
  );

  assert.deepEqual(payload.context, {
    projectReference: "PROMOZAVR",
    taskReference: "123"
  });
});
