import React, { useEffect, useRef, useState } from "react";
import { workflowInputNodeReferences } from "./projectWorkflows";

type RecordValue = Record<string, any>;

export function WorkflowSessionControls({ node, workflow, onChange }: {
  node: RecordValue;
  workflow: RecordValue;
  onChange: (config: RecordValue) => void;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    function close(event: PointerEvent) { if (!ref.current?.contains(event.target as Node)) setOpen(false); }
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, []);
  const config = node.config || {};
  const mode = config.sessionMode || "new";
  const sources = workflowInputNodeReferences(workflow, node.id).filter((entry: RecordValue) => {
    const candidate = workflow.nodes.find((candidate: RecordValue) => candidate.id === entry.nodeId);
    return candidate?.id !== node.id && candidate?.type === "agent_step" && config.agentId && candidate.config?.agentId === config.agentId;
  });
  const selected = sources.find((entry: RecordValue) => entry.nodeId === config.sessionSourceNodeId);
  return <>
    <label>Agent session<div className="project-workflow-choice-grid">
      {["new", "shared"].map((choice) => <button key={choice} type="button" aria-label={choice === "new" ? "New session" : "Shared session"}
        className={mode === choice ? "active" : ""} onClick={() => {
          onChange({ ...config, sessionMode: choice, sessionSourceNodeId: choice === "shared" ? config.sessionSourceNodeId : undefined });
          setOpen(false);
        }}>{choice === "new" ? "New session" : "Shared session"}</button>)}
    </div></label>
    {mode === "shared" ? <label>Session source
      <div className="actor-team-search" ref={ref} onKeyDown={(event) => {
        if (event.key === "Escape") { setOpen(false); event.stopPropagation(); }
      }}>
        <button type="button" aria-label={selected?.title ? `Session source: ${selected.title}` : "Session source"} aria-haspopup="listbox" aria-expanded={open} onClick={() => setOpen(!open)}>
          {selected?.title || "Choose an earlier step"}
        </button>
        {open ? <ul className="actor-team-dropdown" role="listbox" aria-label="Session source options">
          {sources.length ? sources.map((source: RecordValue) => <li key={source.nodeId} role="option" tabIndex={0}
            aria-selected={source.nodeId === config.sessionSourceNodeId}
            onClick={() => { onChange({ ...config, sessionSourceNodeId: source.nodeId }); setOpen(false); }}
            onKeyDown={(event) => {
              if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onChange({ ...config, sessionSourceNodeId: source.nodeId }); setOpen(false); }
            }}><span className="actor-team-dropdown-name">{source.title}</span><span className="actor-team-dropdown-id">{source.nodeId}</span></li>)
            : <li>No earlier steps using this agent.</li>}
        </ul> : null}
      </div><small>Continue the completed session of an earlier step in this run using the same agent. Each step keeps its own result.</small>
    </label> : <small>Start a separate session. Pass selected data through input references.</small>}
  </>;
}
