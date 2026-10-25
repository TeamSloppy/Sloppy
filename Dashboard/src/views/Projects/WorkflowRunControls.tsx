import React, { useState } from "react";
import { retryProjectWorkflowRun, cancelProjectWorkflowRun } from "../../api";
import { WorkflowChoice } from "./WorkflowChoice";

type RecordValue = Record<string, any>;
export function WorkflowRunControls({ projectId, detail, onChange }: { projectId: string; detail: RecordValue; onChange: (detail: RecordValue) => void }) {
  const [decision, setDecision] = useState("retry");
  const [stepId, setStepId] = useState("");
  const [evidence, setEvidence] = useState("");
  const [output, setOutput] = useState("{}");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const terminal = ["failed", "blocked", "cancelled"].includes(detail.run.status);
  const latest = new Map<string, RecordValue>();
  for (const step of detail.steps || []) latest.set(step.nodeId, step);
  const candidates = [...latest.values()].filter((step) => ["failed", "waiting", "skipped"].includes(step.status));
  async function submit(cancel: boolean) {
    setBusy(true); setError("");
    try {
      const parsed = !cancel && decision === "accept_result" ? JSON.parse(output) : undefined;
      if (parsed && (Array.isArray(parsed) || typeof parsed !== "object")) throw new Error("Recorded output must be an object.");
      const result = cancel ? await cancelProjectWorkflowRun(projectId, detail.run.id, { userId: "dashboard" })
        : await retryProjectWorkflowRun(projectId, detail.run.id, { stepId, decision, evidence: evidence.trim(), output: parsed, userId: "dashboard" });
      if (!result?.run) throw new Error("Operation not accepted. Refresh and inspect the run state.");
      onChange(result); setStepId("");
    } catch (problem) { setError(problem instanceof Error ? problem.message : "Workflow operation failed."); }
    finally { setBusy(false); }
  }
  return <div className="project-workflow-launch">
    {(detail.run.status === "blocked" || (!terminal && detail.run.status !== "completed")) ? <button type="button" disabled={busy} onClick={() => void submit(true)}>Cancel run</button> : null}
    {terminal && candidates.length ? <>
      <WorkflowChoice label="Attempt to reconcile" value={stepId} options={[{ value: "", label: "Choose an attempt" }, ...candidates.map((step: RecordValue) => ({ value: step.id, label: `${step.nodeId} · ${step.status} · ${step.id.slice(-6)}` }))]} onChange={setStepId} />
      <WorkflowChoice label="Reconciliation decision" value={decision} onChange={setDecision} options={[{ value: "retry", label: "Retry this operation" }, { value: "accept_result", label: "Use a verified result" }]} />
      <label>Evidence<textarea rows={3} value={evidence} onChange={(event) => setEvidence(event.target.value)} /><small>Inspect external effects first. Retry runs this operation again and retains completed earlier steps.</small></label>
      {decision === "accept_result" ? <label>Verified output JSON<textarea rows={4} value={output} onChange={(event) => setOutput(event.target.value)} /></label> : null}
      <button type="button" disabled={busy || !stepId || !evidence.trim()} onClick={() => void submit(false)}>Apply and continue</button>
    </> : null}
    {error ? <p role="alert">{error}</p> : null}
  </div>;
}
