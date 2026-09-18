const ROUTED_MODEL_PREFIXES = [
  "sloppy:",
  "openai-api:",
  "openai-oauth:",
  "openrouter:",
  "ollama:",
  "gemini:",
  "anthropic:",
  "opencode:",
  "mock:"
];

export function isProviderRoutedModelId(modelId: string): boolean {
  const trimmed = String(modelId || "").trim();
  return ROUTED_MODEL_PREFIXES.some((prefix) => trimmed.startsWith(prefix));
}

export function filterProviderRoutedModelOptions<T extends { id?: unknown }>(models: T[]): T[] {
  return models.filter((model) => isProviderRoutedModelId(String(model?.id || "")));
}
