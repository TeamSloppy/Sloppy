import { useEffect, useRef, useState } from "react";
import { fetchAgentSessionApprovalPolicy, fetchDefaultChatApprovalPolicy, setAgentSessionApprovalPolicy } from "../../../api";
import type { SessionApprovalMode } from "../../../shared/api/coreApi";

export const CHAT_APPROVAL_MODES: { mode: SessionApprovalMode; title: string; detail: string }[] = [
  { mode: "ask_for_approval", title: "Ask for approval", detail: "Ask you before actions that require approval." },
  { mode: "approve_for_me", title: "Approve for me", detail: "JEV reviews actions, with Visor as backup. Human decisions still come to you." }
];

export function useChatApprovalPolicy(agentId: string, sessionId: string | null, projectId: string | null) {
  const key = JSON.stringify([agentId, sessionId, projectId]);
  const currentKey = useRef(key);
  currentKey.current = key;
  const revision = useRef(0);
  const pendingSaves = useRef(new Map<string, Promise<unknown>>());
  const [state, setState] = useState({ key, mode: "ask_for_approval" as SessionApprovalMode, overridden: false, known: false, loading: true, saving: false, error: "" });
  const [reload, setReload] = useState(0);

  useEffect(() => {
    let disposed = false;
    const version = ++revision.current;
    setState({ key, mode: "ask_for_approval", overridden: false, known: false, loading: true, saving: false, error: "" });
    void (async () => {
      try {
        // Returning to a chat must observe any save still in flight for it.
        await pendingSaves.current.get(key)?.catch(() => {});
        const policy = sessionId ? await fetchAgentSessionApprovalPolicy(agentId, sessionId) : await fetchDefaultChatApprovalPolicy();
        if (!disposed && revision.current === version) {
          setState({ key, mode: policy.mode, overridden: false, known: true, loading: false, saving: false, error: "" });
        }
      } catch (error) {
        if (!disposed && revision.current === version) {
          setState((previous) => ({ ...previous, loading: false, error: String(error) }));
        }
      }
    })();
    return () => { disposed = true; };
  }, [agentId, sessionId, projectId, key, reload]);

  const current = state.key === key ? state : { key, mode: "ask_for_approval" as SessionApprovalMode, overridden: false, known: false, loading: true, saving: false, error: "" };

  async function select(mode: SessionApprovalMode) {
    if (current.loading || current.saving || pendingSaves.current.has(key)) return;
    if (!sessionId) {
      setState({ key, mode, overridden: true, known: true, loading: false, saving: false, error: "" });
      return;
    }
    const version = ++revision.current;
    setState((previous) => ({ ...previous, saving: true, error: "" }));
    const save = setAgentSessionApprovalPolicy(agentId, sessionId, mode);
    pendingSaves.current.set(key, save);
    try {
      const policy = await save;
      if (currentKey.current === key && revision.current === version) {
        setState({ key, mode: policy.mode, overridden: false, known: true, loading: false, saving: false, error: "" });
      }
    } catch (error) {
      if (currentKey.current === key && revision.current === version) {
        setState((previous) => ({ ...previous, saving: false, error: String(error) }));
      }
    } finally {
      if (pendingSaves.current.get(key) === save) pendingSaves.current.delete(key);
    }
  }

  function reportError(error: string) {
    if (currentKey.current === key) setState((previous) => ({ ...previous, error }));
  }

  function retry() {
    if (sessionId || !current.known) setReload((value) => value + 1);
    else setState((previous) => ({ ...previous, error: "" }));
  }

  return { ...current, busy: current.loading || current.saving || pendingSaves.current.has(key), select, reportError, retry };
}
