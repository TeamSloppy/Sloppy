import React from "react";
import { workflowInputNodeReferences } from "./projectWorkflows";
import { WorkflowChoice } from "./WorkflowChoice";

type RecordValue = Record<string, any>;
export function WorkflowSessionControls({ node, workflow, onChange }: { node: RecordValue; workflow: RecordValue; onChange: (config: RecordValue) => void }) {
  const config = node.config || {};
  const mode = config.sessionMode || "new";
  const sources = workflowInputNodeReferences(workflow, node.id).filter((entry: RecordValue) => {
    const candidate = workflow.nodes.find((candidate: RecordValue) => candidate.id === entry.nodeId);
    return candidate?.id !== node.id && candidate?.type === "agent_step" && (mode === "compact" || (config.agentId && candidate.config?.agentId === config.agentId));
  });
  return <>
    <WorkflowChoice label="Agent session" value={mode} options={[
      { value: "new", label: "New session" }, { value: "shared", label: "Continue session" }, { value: "compact", label: "Compact and start new" }
    ]} onChange={(choice) => onChange({ ...config, sessionMode: choice, sessionSourceNodeId: choice === "new" ? undefined : config.sessionSourceNodeId })} />
    {mode !== "new" ? <>
      <WorkflowChoice label="Session source" value={config.sessionSourceNodeId || ""} options={[
        { value: "", label: "Choose an earlier step" }, ...sources.map((source: RecordValue) => ({ value: source.nodeId, label: source.title }))
      ]} onChange={(source) => onChange({ ...config, sessionSourceNodeId: source })} />
      <small>{mode === "compact" ? "Summarize the selected completed phase and start a fresh session. The target agent may differ; the summary and session bindings survive restart." : "Continue an earlier completed step using the same agent. Each attempt keeps its own output."}</small>
    </> : <small>Start a separate session using the prompt and workflow input.</small>}
  </>;
}
