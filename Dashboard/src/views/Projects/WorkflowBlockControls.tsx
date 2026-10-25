import React, { useEffect, useState } from "react";
import { WorkflowChoice } from "./WorkflowChoice";

type RecordValue = Record<string, any>;
export function WorkflowBlockControls({ node, project, workflows, currentWorkflowId, onChange, onError }: {
  node: RecordValue; project: RecordValue; workflows: RecordValue[]; currentWorkflowId: string;
  onChange: (key: string, value: any) => void; onError: (error: string) => void;
}) {
  const config = node.config || {};
  const kind = config.blockKind || config.block_kind;
  const serializedArguments = typeof config.arguments === "string" ? config.arguments : JSON.stringify(config.arguments || {}, null, 2);
  const [argumentsText, setArgumentsText] = useState(serializedArguments);
  useEffect(() => { setArgumentsText(serializedArguments); onError(""); }, [node.id, serializedArguments]);
  if (node.type === "notify" || kind === "channel") return <WorkflowChoice label="Notification channel" value={config.channelId || ""} options={[
    { value: "", label: "Choose a project channel" }, ...(project.channels || []).map((channel: RecordValue) => ({ value: channel.channelId, label: channel.title || channel.channelId }))
  ]} onChange={(channel) => onChange("channelId", channel)} />;
  if (kind === "sub_workflow") return <>
    <WorkflowChoice label="Child workflow" value={config.workflowId || ""} options={[
      { value: "", label: "Choose a workflow" }, ...workflows.filter((workflow) => workflow.id !== currentWorkflowId).map((workflow) => ({ value: workflow.id, label: workflow.name }))
    ]} onChange={(workflowId) => onChange("workflowId", workflowId)} />
    <small>The parent waits for completion. Inspect the child run to answer questions or reconcile failures. The task and execution directory are inherited.</small>
  </>;
  if (kind === "tool") return <>
    <label>Tool name<input value={config.toolName || ""} onChange={(event) => onChange("toolName", event.target.value)} /></label>
    <label>Arguments JSON<textarea rows={5} value={argumentsText} onChange={(event) => {
      const text = event.target.value; setArgumentsText(text);
      try {
        const value = JSON.parse(text);
        if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
        onError(""); onChange("arguments", value);
      } catch { onError("Tool arguments must be a JSON object."); }
    }} /></label>
  </>;
  return null;
}
