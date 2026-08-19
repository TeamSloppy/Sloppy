import assert from "node:assert/strict";
import test from "node:test";

import { EMPTY_CONFIG, PROVIDER_CATALOG, normalizeConfig } from "../src/features/config/configModel.ts";

test("provider catalog defaults use current routable model ids", () => {
  const defaults = Object.fromEntries(
    PROVIDER_CATALOG.map((provider) => [provider.id, provider.defaultEntry.model])
  );

  assert.equal(defaults["openai-api"], "gpt-5.4-mini");
  assert.equal(defaults["openai-oauth"], "gpt-5.4");
  assert.equal(defaults.openrouter, "openai/gpt-5.4-mini");
  assert.equal(defaults.gemini, "gemini-2.5-flash");
  assert.equal(defaults.anthropic, "claude-sonnet-4-6");
  assert.equal(defaults["anthropic-oauth"], "claude-sonnet-4-6");
  assert.equal(defaults.ollama, "qwen3");
});

test("image generation config defaults are disabled and normalize bounded values", () => {
  assert.equal(EMPTY_CONFIG.imageGeneration.enabled, false);
  assert.equal(EMPTY_CONFIG.imageGeneration.model, "fal-ai/flux-2");

  const normalized = normalizeConfig({
    imageGeneration: {
      enabled: true,
      provider: "unknown",
      model: "",
      fal: { apiKey: "key" },
      timeoutMs: 9999999
    }
  });
  assert.equal(normalized.imageGeneration.enabled, true);
  assert.equal(normalized.imageGeneration.provider, "fal");
  assert.equal(normalized.imageGeneration.model, "fal-ai/flux-2");
  assert.equal(normalized.imageGeneration.fal.apiKey, "key");
  assert.equal(normalized.imageGeneration.timeoutMs, 600000);

  const openAI = normalizeConfig({
    imageGeneration: {
      enabled: true,
      provider: "openai",
      model: "gpt-image-2"
    }
  });
  assert.equal(openAI.imageGeneration.provider, "openai");
  assert.equal(openAI.imageGeneration.model, "gpt-image-2");
});
