import assert from "node:assert/strict";
import test from "node:test";

import {
  groupModelsForPicker,
  modelPickerGroup,
  modelPickerProviderTitle
} from "../src/features/agents/utils/modelPickerSections.ts";
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

test("model picker groups match the TUI provider and namespace sections", () => {
  assert.equal(modelPickerProviderTitle("openai-oauth"), "OpenAI Codex");
  assert.equal(modelPickerProviderTitle("openai-api"), "OpenAI API");
  assert.equal(modelPickerProviderTitle("openrouter"), "OpenRouter");
  assert.equal(modelPickerProviderTitle("configured"), "Configured");

  assert.equal(modelPickerGroup("openai-oauth:gpt-5.4"), "OpenAI Codex / gpt");
  assert.equal(modelPickerGroup("openrouter:google/gemini-2.5-pro"), "OpenRouter / google");
  assert.equal(modelPickerGroup("openrouter:anthropic/claude-sonnet-4.6"), "OpenRouter / anthropic");
  assert.equal(modelPickerGroup("ollama:qwen3"), "Ollama");
  assert.equal(modelPickerGroup("mock:test-model"), "Mock / test");
});

test("model picker ordering keeps the selected TUI section first", () => {
  const grouped = groupModelsForPicker(
    [
      { id: "openrouter:google/gemini-2.5-pro", title: "Gemini" },
      { id: "anthropic:claude-sonnet-4.6", title: "Claude" },
      { id: "openrouter:openai/gpt-5.4", title: "GPT" },
      { id: "ollama:qwen3", title: "Qwen" }
    ],
    "openrouter:google/gemini-2.5-pro"
  );

  assert.deepEqual(
    grouped.map((group) => group.title),
    ["OpenRouter / google", "Anthropic / claude", "Ollama", "OpenRouter / openai"]
  );
  assert.deepEqual(grouped[0].models.map((model) => model.id), ["openrouter:google/gemini-2.5-pro"]);
});
