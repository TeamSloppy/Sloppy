import React from "react";
import { WorkflowChoice } from "./WorkflowChoice";

type RecordValue = Record<string, any>;
export function WorkflowParallelControls({ node, workflow, onChange }: { node: RecordValue; workflow: RecordValue; onChange: (key: string, value: any) => void }) {
  const isJoin = (candidate: RecordValue) => candidate.type === "join" || String(candidate.config?.blockKind || candidate.config?.block_kind || "").trim() === "merge";
  if (isJoin(node)) return <>
    <WorkflowChoice label="Join strategy" value={node.config?.strategy || "all"} onChange={(strategy) => onChange("strategy", strategy)} options={[
      { value: "all", label: "Wait for all branches" }, { value: "first_completed", label: "First completed branch" }
    ]} />
    <small>{node.config?.strategy === "first_completed" ? "The first successful branch wins and cancels the others. Completed external effects are retained." : "Continue after every branch of the owning Parallel block succeeds."}</small>
  </>;
  return <>
    <WorkflowChoice label="Join block" value={node.config?.joinNodeId || ""} options={[
      { value: "", label: "Choose a Join block" }, ...(workflow.nodes || []).filter(isJoin).map((join: RecordValue) => ({ value: join.id, label: join.title }))
    ]} onChange={(id) => onChange("joinNodeId", id)} />
    <small>Connect 2–16 disjoint branches with unconditional edges. Every branch must reach the selected Join. Nested groups are not supported.</small>
  </>;
}
