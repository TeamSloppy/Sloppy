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
  return "openai-api";
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

export async function collectAggregatedProviderModels(
  config: Record<string, unknown> | null | undefined
): Promise<AggregatedModelOption[]> {
  if (!config || !Array.isArray(config.models) || config.models.length === 0) {
    return [];
  }

  const allModels: AggregatedModelOption[] = [];

  for (const entry of config.models as Record<string, unknown>[]) {
    const providerId = inferProviderId(entry);
    const result = await probeProvider({
      providerId,
      apiKey: String(entry.apiKey || ""),
      apiUrl: String(entry.apiUrl || "")
    });

    if (result?.ok && Array.isArray(result.models)) {
      for (const model of result.models as Record<string, unknown>[]) {
        const id = String(model.id || "");
        const title = String(model.title || id);
        if (!id || allModels.some((m) => m.id === id)) {
          continue;
        }
        const next: AggregatedModelOption = { id, title };
        if (model.contextWindow != null) {
          next.contextWindow = String(model.contextWindow);
        }
        if (Array.isArray(model.capabilities) && model.capabilities.length > 0) {
          next.capabilities = (model.capabilities as unknown[]).map((c) => String(c));
        }
        allModels.push(next);
      }
    }
  }

  return allModels;
}
