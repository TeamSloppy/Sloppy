export type ModelPickerOptionLike = {
  id?: string;
  title?: string;
  contextWindow?: string;
  capabilities?: string[];
};

export type ModelPickerGroup<T extends ModelPickerOptionLike> = {
  title: string;
  models: T[];
};

export function modelPickerProviderTitle(provider: string): string {
  switch (String(provider || "").trim().toLowerCase()) {
    case "anthropic":
      return "Anthropic";
    case "gemini":
      return "Gemini";
    case "ollama":
      return "Ollama";
    case "openai-api":
      return "OpenAI API";
    case "openai-oauth":
      return "OpenAI Codex";
    case "opencode":
      return "OpenCode";
    case "openrouter":
      return "OpenRouter";
    case "configured":
      return "Configured";
    default:
      return String(provider || "").trim()
        .split("-")
        .filter(Boolean)
        .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
        .join(" ") || "Configured";
  }
}

export function modelPickerGroup(modelId: string): string {
  const raw = String(modelId || "").trim();
  if (!raw) {
    return "Configured";
  }

  const separator = raw.indexOf(":");
  const provider = separator >= 0 ? raw.slice(0, separator) : "configured";
  const remainder = separator >= 0 ? raw.slice(separator + 1) : raw;
  const groupParts = [modelPickerProviderTitle(provider)];
  const scopedParts = remainder.split(":").filter(Boolean);

  if (scopedParts.length > 1) {
    groupParts.push(scopedParts[0]);
    const namespace = modelPickerNamespace(scopedParts.slice(1).join(":"));
    if (namespace) {
      groupParts.push(namespace);
    }
  } else {
    const namespace = modelPickerNamespace(remainder);
    if (namespace) {
      groupParts.push(namespace);
    }
  }

  return groupParts.join(" / ");
}

export function groupModelsForPicker<T extends ModelPickerOptionLike>(
  models: T[],
  selectedModelId = "",
  forcedGroupTitle = ""
): ModelPickerGroup<T>[] {
  const selectedGroup = selectedModelId ? modelPickerGroup(selectedModelId) : "";
  const groups = new Map<string, { title: string; firstIndex: number; models: T[] }>();

  models.forEach((model, index) => {
    const title = forcedGroupTitle || modelPickerGroup(String(model?.id || ""));
    const group = groups.get(title) ?? { title, firstIndex: index, models: [] };
    group.models.push(model);
    groups.set(title, group);
  });

  return Array.from(groups.values())
    .sort((left, right) => {
      if (selectedGroup) {
        if (left.title === selectedGroup && right.title !== selectedGroup) return -1;
        if (right.title === selectedGroup && left.title !== selectedGroup) return 1;
      }
      const titleOrder = left.title.localeCompare(right.title, undefined, { sensitivity: "accent" });
      if (titleOrder !== 0) {
        return titleOrder;
      }
      return left.firstIndex - right.firstIndex;
    })
    .map(({ title, models }) => ({ title, models }));
}

function modelPickerNamespace(modelId: string): string {
  const trimmed = String(modelId || "").trim();
  if (!trimmed) {
    return "";
  }
  const slash = trimmed.indexOf("/");
  if (slash >= 0) {
    return trimmed.slice(0, slash);
  }

  const separatorIndex = trimmed.search(/[-_.]/);
  if (separatorIndex < 0) {
    return "";
  }
  const prefix = trimmed.slice(0, separatorIndex);
  return prefix.length >= 2 && prefix.length < trimmed.length ? prefix : "";
}
