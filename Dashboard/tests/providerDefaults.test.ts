import assert from "node:assert/strict";
import test from "node:test";

import { PROVIDER_CATALOG } from "../src/features/config/configModel.ts";

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
