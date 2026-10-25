import React, { useEffect, useState } from "react";
import { fetchAgentSession, answerAgentSessionInputRequest } from "../../api";
import { PlanInputPanel } from "../../components/PlanInputPanel/PlanInputPanel";

type RecordValue = Record<string, any>;
export function WorkflowAgentQuestions({ steps }: { steps: RecordValue[] }) {
  const [questions, setQuestions] = useState<RecordValue[]>([]);
  const [error, setError] = useState("");
  const bindings = JSON.stringify(steps.filter((step) => step.status === "waiting" && step.output?.agentId && step.output?.sessionId)
    .map((step) => ({ agentId: step.output.agentId, sessionId: step.output.sessionId })));
  useEffect(() => {
    if (bindings === "[]") { setQuestions([]); setError(""); return; }
    let stopped = false;
    let timer: number | undefined;
    async function refresh() {
      try {
        const pending: RecordValue[] = [];
        for (const binding of JSON.parse(bindings)) {
          const detail = await fetchAgentSession(binding.agentId, binding.sessionId);
          if (!detail) throw new Error("Could not load the agent question.");
          const events: RecordValue[] = Array.isArray(detail.events) ? detail.events : [];
          const resolved = new Set(events.map((event: RecordValue) => event.inputResponse?.requestId).filter(Boolean));
          for (const event of events) if (event.inputRequest?.id && !resolved.has(event.inputRequest.id)) pending.push({ ...binding, request: event.inputRequest });
        }
        if (!stopped) { setQuestions(pending); setError(""); }
      } catch { if (!stopped) setError("Could not refresh agent questions. Retrying…"); }
      if (!stopped) timer = window.setTimeout(refresh, 2000);
    }
    void refresh();
    return () => { stopped = true; window.clearTimeout(timer); };
  }, [bindings]);
  return <>
    {error ? <small role="status">{error}</small> : null}
    {questions.map((question) => <PlanInputPanel key={`${question.sessionId}-${question.request.id}`} request={question.request} onSubmit={async (payload) => {
      const result = await answerAgentSessionInputRequest(question.agentId, question.sessionId, question.request.id, payload);
      if (!result) throw new Error("Could not answer the question.");
      setQuestions((previous) => previous.filter((entry) => entry.request.id !== question.request.id));
    }} />)}
  </>;
}
