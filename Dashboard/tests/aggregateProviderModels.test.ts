import assert from "node:assert/strict";
import test from "node:test";

import { filterProviderRoutedModelOptions } from "../src/features/agents/utils/modelRoutingIds.ts";

test("model pickers hide bare models and keep provider-routed ids", () => {
  const models = filterProviderRoutedModelOptions([
      { id: "gpt-5.5", title: "GPT 5.5" },
      { id: "claude-sonnet-4-6", title: "Claude Sonnet 4.6" },
      { id: "mock:test-model", title: "Mock test model" },
      { id: "openai-oauth:gpt-5.5", title: "GPT 5.5" },
      { id: "openrouter:google/gemini-2.5-pro", title: "Gemini 2.5 Pro" }
    ]);

  assert.deepEqual(
    models.map((model) => model.id),
    [
      "mock:test-model",
      "openai-oauth:gpt-5.5",
      "openrouter:google/gemini-2.5-pro"
    ]
  );
});
