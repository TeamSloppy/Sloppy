import { useEffect, useState } from "react";
import { fetchSessionPromptSuggestion } from "../../../shared/api/coreApi";

export function usePromptSuggestion(agentId: string, sessionId: string, runId: string | null, enabled: boolean) {
  const [suggestion, setSuggestion] = useState<{ key: string; text: string } | null>(null);
  const key = enabled && runId && sessionId ? JSON.stringify([agentId, sessionId, runId]) : null;

  useEffect(() => {
    if (!key || !runId) return;
    const controller = new AbortController();
    fetchSessionPromptSuggestion(agentId, sessionId, runId, controller.signal).then((result) => {
      if (!controller.signal.aborted && result?.sourceRunId === runId && result.text) {
        setSuggestion({ key, text: result.text });
      }
    }).catch(() => { /* Older backends and unavailable predictions leave the composer empty. */ });
    return () => controller.abort();
  }, [key, agentId, sessionId, runId]);

  return suggestion?.key === key ? suggestion.text : null;
}
