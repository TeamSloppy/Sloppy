export const DEEP_RESEARCH_SKILL_ID = "sloppy/deep-research";
export const DEEP_RESEARCH_DEFAULT_MODE = "explore";
export const DEEP_RESEARCH_DEFAULT_ROUNDS = 3;
export const DEEP_RESEARCH_MIN_ROUNDS = 1;
export const DEEP_RESEARCH_MAX_ROUNDS = 8;
export const DEEP_RESEARCH_MODES = [
  { id: "compare", label: "Compare", icon: "compare_arrows" },
  { id: "review", label: "Review", icon: "rate_review" },
  { id: "explore", label: "Explore", icon: "travel_explore" }
];

export function deepResearchShellTokens(text: string) {
  const tokens: string[] = [];
  let current = "";
  let quote = "";
  let escaping = false;
  for (const char of String(text || "")) {
    if (escaping) {
      current += char;
      escaping = false;
      continue;
    }
    if (char === "\\") {
      escaping = true;
      continue;
    }
    if (quote) {
      if (char === quote) {
        quote = "";
      } else {
        current += char;
      }
      continue;
    }
    if (char === "\"" || char === "'") {
      quote = char;
      continue;
    }
    if (/\s/.test(char)) {
      if (current) {
        tokens.push(current);
        current = "";
      }
      continue;
    }
    current += char;
  }
  if (escaping) {
    current += "\\";
  }
  if (quote) {
    return { error: "Unterminated quote in deep research command." };
  }
  if (current) {
    tokens.push(current);
  }
  return { tokens };
}

export function parseDeepResearchArguments(args: string[]) {
  let mode = DEEP_RESEARCH_DEFAULT_MODE;
  let rounds = DEEP_RESEARCH_DEFAULT_ROUNDS;
  let promptParts: string[] = [];
  for (let index = 0; index < args.length; index += 1) {
    const arg = String(args[index] || "");
    if (arg === "--mode") {
      index += 1;
      if (index >= args.length) return { error: "Missing value for --mode." };
      mode = String(args[index] || "").trim().toLowerCase();
    } else if (arg.startsWith("--mode=")) {
      mode = arg.slice("--mode=".length).trim().toLowerCase();
    } else if (arg === "--rounds") {
      index += 1;
      if (index >= args.length) return { error: "Missing value for --rounds." };
      rounds = Number.parseInt(String(args[index] || "").trim(), 10);
    } else if (arg.startsWith("--rounds=")) {
      rounds = Number.parseInt(arg.slice("--rounds=".length).trim(), 10);
    } else if (arg.startsWith("--")) {
      return { error: `Unknown option ${arg}.` };
    } else {
      promptParts = args.slice(index).map((part) => String(part || ""));
      break;
    }
  }
  if (!DEEP_RESEARCH_MODES.some((item) => item.id === mode)) {
    return { error: `Invalid deep research mode "${mode}". Use compare, review, or explore.` };
  }
  if (!Number.isInteger(rounds) || rounds < DEEP_RESEARCH_MIN_ROUNDS || rounds > DEEP_RESEARCH_MAX_ROUNDS) {
    return { error: `Invalid deep research rounds. Use ${DEEP_RESEARCH_MIN_ROUNDS}-${DEEP_RESEARCH_MAX_ROUNDS}.` };
  }
  const prompt = promptParts.join(" ").trim();
  if (!prompt) {
    return { error: "Usage: /deepresearch [--mode compare|review|explore] [--rounds 1...8] <prompt>" };
  }
  return { config: { mode, rounds, prompt } };
}

export function parseDeepResearchCommand(text: string) {
  const trimmed = String(text || "").trim();
  if (!/^\/deepresearch(?:\s|$)/i.test(trimmed)) {
    return null;
  }
  const tokenized = deepResearchShellTokens(trimmed);
  if (tokenized.error) {
    return { error: tokenized.error };
  }
  const tokens = tokenized.tokens || [];
  if (String(tokens[0] || "").toLowerCase() !== "/deepresearch") {
    return null;
  }
  return parseDeepResearchArguments(tokens.slice(1));
}

export function quoteDeepResearchPrompt(prompt: string) {
  const value = String(prompt || "").trim();
  if (!value) return "";
  if (!/[\s"'\\]/.test(value)) return value;
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
}

export function buildDeepResearchCommand({ mode = DEEP_RESEARCH_DEFAULT_MODE, rounds = DEEP_RESEARCH_DEFAULT_ROUNDS, prompt = "" }) {
  return `/deepresearch --mode ${mode} --rounds ${rounds} ${quoteDeepResearchPrompt(prompt)}`.trim();
}

export function deepResearchSkillInvocation(config: { mode: string; rounds: number; prompt: string }) {
  return `Use installed skill \`${DEEP_RESEARCH_SKILL_ID}\` for this request.

Deep research configuration:
mode: ${config.mode}
rounds: ${config.rounds}

User request:
${config.prompt}`;
}

export function parseDeepResearchSkillInvocation(text: string) {
  const raw = String(text || "");
  if (!raw.includes(`Use installed skill \`${DEEP_RESEARCH_SKILL_ID}\``)) {
    return null;
  }
  const mode = raw.match(/^\s*mode:\s*(compare|review|explore)\s*$/im)?.[1] || DEEP_RESEARCH_DEFAULT_MODE;
  const parsedRounds = Number.parseInt(raw.match(/^\s*rounds:\s*(\d+)\s*$/im)?.[1] || "", 10);
  const rounds = Number.isInteger(parsedRounds)
    ? Math.min(DEEP_RESEARCH_MAX_ROUNDS, Math.max(DEEP_RESEARCH_MIN_ROUNDS, parsedRounds))
    : DEEP_RESEARCH_DEFAULT_ROUNDS;
  const prompt = raw.split(/User request:\s*/i).slice(1).join("User request:").trim();
  if (!prompt) return null;
  return { mode, rounds, prompt };
}

export function collectDeepResearchUrls(value: unknown, urls: string[] = []) {
  if (!value || urls.length >= 12) {
    return urls;
  }
  if (typeof value === "string") {
    if (/^https?:\/\//i.test(value) && !urls.includes(value)) {
      urls.push(value);
    }
    return urls;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      collectDeepResearchUrls(item, urls);
      if (urls.length >= 12) break;
    }
    return urls;
  }
  if (typeof value === "object") {
    for (const [key, nested] of Object.entries(value)) {
      if (/^(url|link|href)$/i.test(key) && typeof nested === "string" && /^https?:\/\//i.test(nested) && !urls.includes(nested)) {
        urls.push(nested);
      } else {
        collectDeepResearchUrls(nested, urls);
      }
      if (urls.length >= 12) break;
    }
  }
  return urls;
}

export function buildDeepResearchProcess(
  events: unknown[],
  latestRunStatus: Record<string, unknown> | null | undefined,
  getMessageText: (eventItem: any) => string = (eventItem) => String(eventItem?.message?.text || eventItem?.message?.content || "")
) {
  const safe = Array.isArray(events) ? events : [];
  let startIndex = -1;
  let config = null;
  for (let index = safe.length - 1; index >= 0; index -= 1) {
    const eventItem: any = safe[index];
    if (eventItem?.type !== "message" || eventItem?.message?.role !== "user") {
      continue;
    }
    const text = getMessageText(eventItem);
    const slash = parseDeepResearchCommand(text);
    const parsed = slash && "config" in slash ? slash.config : parseDeepResearchSkillInvocation(text);
    if (parsed) {
      startIndex = index;
      config = parsed;
      break;
    }
  }
  if (!config || startIndex < 0) {
    return null;
  }

  const queries: string[] = [];
  const urls: string[] = [];
  let latestProgress: unknown = null;
  let searchCallCount = 0;
  let activeTool = "";
  for (let index = startIndex + 1; index < safe.length; index += 1) {
    const eventItem: any = safe[index];
    if (eventItem?.type === "tool_call" && eventItem.toolCall) {
      const tool = String(eventItem.toolCall.tool || "");
      activeTool = tool;
      if (tool === "web.search") {
        searchCallCount += 1;
        const args = eventItem.toolCall.arguments || {};
        const query = String(args.query || args.q || args.search || "").trim();
        if (query && !queries.includes(query)) {
          queries.push(query);
        }
      }
    } else if (eventItem?.type === "tool_result" && eventItem.toolResult) {
      collectDeepResearchUrls(eventItem.toolResult.data, urls);
      if (String(eventItem.toolResult.tool || "") === activeTool) {
        activeTool = "";
      }
    } else if (eventItem?.type === "build_progress" && eventItem.buildProgress) {
      latestProgress = eventItem.buildProgress;
    }
  }

  const stage = String(latestRunStatus?.stage || "").toLowerCase();
  const rounds = Number(config.rounds) || DEEP_RESEARCH_DEFAULT_ROUNDS;
  const currentRound = Math.max(1, Math.min(rounds, searchCallCount || 1));
  return {
    config,
    startEventId: (safe[startIndex] as any)?.id || "",
    stage: stage || (activeTool ? "searching" : "thinking"),
    currentRound,
    queries: queries.slice(-5),
    urls: urls.slice(0, 8),
    progress: latestProgress,
    activeTool
  };
}
