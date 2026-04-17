import { probeProvider } from "../../../api";

export type AggregatedModelOption = {
  id: string;
  title: string;
  contextWindow?: string;
  capabilities?: string[];
};

export function inferProviderId(entry: Record<string, unknown>): string {
  const title = String(entry.title || "").toLowerCase();
  const apiUrl = String(entry.apiUrl || "").toLowerCase();
  if (title.includes("oauth")) return "openai-oauth";
  if (title.includes("ollama") || apiUrl.includes("11434") || apiUrl.includes("ollama")) return "ollama";
  if (title.includes("gemini") || apiUrl.includes("generativelanguage.googleapis.com")) return "gemini";
  if (title.includes("anthropic") || apiUrl.includes("anthropic")) return "anthropic";
  if (title.includes("openrouter") || apiUrl.includes("openrouter")) return "openrouter";
  return "openai-api";
}

/**
 * Core expects routed ids like `openrouter:google/gemma-…:free`. Probe APIs return bare slugs;
 * without the prefix, the first `:` in `:free` breaks parsing on the server.
 */
export function prefixedRuntimeModelId(providerCatalogId: string, rawId: string): string {
  const trimmed = String(rawId || "").trim();
  if (!trimmed) {
    return trimmed;
  }
  if (
    trimmed.startsWith("openai:") ||
    trimmed.startsWith("openrouter:") ||
    trimmed.startsWith("ollama:") ||
    trimmed.startsWith("gemini:") ||
    trimmed.startsWith("anthropic:")
  ) {
    return trimmed;
  }

  let route: string;
  if (providerCatalogId === "openai-api" || providerCatalogId === "openai-oauth") {
    route = "openai";
  } else if (providerCatalogId === "openrouter") {
    route = "openrouter";
  } else if (providerCatalogId === "ollama") {
    route = "ollama";
  } else if (providerCatalogId === "gemini") {
    route = "gemini";
  } else if (providerCatalogId === "anthropic") {
    route = "anthropic";
  } else {
    route = "openai";
  }
  return `${route}:${trimmed}`;
}

/**
 * Older agent configs stored OpenRouter slugs without `openrouter:`; those strings contain `:` (`:free`)
 * and break server parsing. Slugs almost always include `/` (`google/gemma-…`).
 */
export function coerceLegacySloppyModelId(modelId: string): string {
  const t = String(modelId || "").trim();
  if (!t) {
    return t;
  }
  if (
    t.startsWith("openai:") ||
    t.startsWith("openrouter:") ||
    t.startsWith("ollama:") ||
    t.startsWith("gemini:") ||
    t.startsWith("anthropic:")
  ) {
    return t;
  }
  if (t.includes("/")) {
    return `openrouter:${t}`;
  }
  return t;
}

function normalizeSearch(value: unknown): string {
  return String(value || "").trim().toLowerCase();
}

/**
 * Same ranking as legacy filterProviderModels in ConfigView: substring match on id/title, then sort.
 */
export function filterModelsByQuery<T extends { id?: string; title?: string }>(
  models: T[],
  query: string
): T[] {
  const needle = normalizeSearch(query);
  if (!needle) {
    return models;
  }

  return [...models]
    .map((model) => {
      const id = normalizeSearch(model?.id);
      const title = normalizeSearch(model?.title);
      const idIndex = id.indexOf(needle);
      const titleIndex = title.indexOf(needle);
      const rank = Math.min(
        idIndex >= 0 ? idIndex : Number.MAX_SAFE_INTEGER,
        titleIndex >= 0 ? titleIndex : Number.MAX_SAFE_INTEGER
      );
      return { model, rank };
    })
    .filter((item) => item.rank !== Number.MAX_SAFE_INTEGER)
    .sort((left, right) => {
      if (left.rank !== right.rank) {
        return left.rank - right.rank;
      }
      return String(left.model?.id || "").localeCompare(String(right.model?.id || ""));
    })
    .map((item) => item.model);
}

export type ProviderProbeOutcome = {
  providerId: string;
  title: string;
  ok: boolean;
  message: string;
  modelCount: number;
};

export type AggregatedProviderCatalog = {
  models: AggregatedModelOption[];
  probes: ProviderProbeOutcome[];
};

export async function collectAggregatedProviderModels(
  config: Record<string, unknown> | null | undefined
): Promise<AggregatedProviderCatalog> {
  if (!config || !Array.isArray(config.models) || config.models.length === 0) {
    return { models: [], probes: [] };
  }

  const allModels: AggregatedModelOption[] = [];
  const probes: ProviderProbeOutcome[] = [];

  for (const entry of config.models as Record<string, unknown>[]) {
    const providerId = inferProviderId(entry);
    const title = String(entry.title || providerId);
    const result = await probeProvider({
      providerId,
      apiKey: String(entry.apiKey || ""),
      apiUrl: String(entry.apiUrl || "")
    });

    const ok = Boolean(result?.ok);
    const rawModels = Array.isArray(result?.models) ? (result!.models as Record<string, unknown>[]) : [];
    if (ok) {
      for (const model of rawModels) {
        const rawId = String(model.id || "");
        const id = prefixedRuntimeModelId(providerId, rawId);
        const modelTitle = String(model.title || rawId);
        if (!id || allModels.some((m) => m.id === id)) {
          continue;
        }
        const next: AggregatedModelOption = { id, title: modelTitle };
        if (model.contextWindow != null) {
          next.contextWindow = String(model.contextWindow);
        }
        if (Array.isArray(model.capabilities) && model.capabilities.length > 0) {
          next.capabilities = (model.capabilities as unknown[]).map((c) => String(c));
        }
        allModels.push(next);
      }
    }

    probes.push({
      providerId,
      title,
      ok,
      message: String(result?.message || (ok ? "" : "Probe failed.")),
      modelCount: rawModels.length
    });
  }

  return { models: allModels, probes };
}
