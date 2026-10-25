import React, { useEffect, useId, useRef, useState } from "react";

type RecordValue = Record<string, any>;

export function WorkflowParallelControls({ node, workflow, onChange }: {
  node: RecordValue;
  workflow: RecordValue;
  onChange: (key: string, value: any) => void;
}) {
  const [open, setOpen] = useState(false);
  const buttonId = useId();
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    function close(event: PointerEvent) { if (!ref.current?.contains(event.target as Node)) setOpen(false); }
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, []);
  if (node.type === "join") return <small>Wait for every branch of the owning Parallel block to succeed, then pass all branch results downstream.</small>;
  const joins = (workflow.nodes || []).filter((candidate: RecordValue) => candidate.type === "join");
  const selected = joins.find((candidate: RecordValue) => candidate.id === node.config?.joinNodeId);
  function choose(id: string) { onChange("joinNodeId", id); setOpen(false); }
  return <div>
    <label htmlFor={buttonId}>Join block</label>
    <div className="actor-team-search" ref={ref} onKeyDown={(event) => {
      if (event.key === "Escape") { setOpen(false); event.stopPropagation(); }
    }}>
      <button id={buttonId} type="button" aria-label={selected ? `Join block: ${selected.title}` : "Join block"} aria-haspopup="listbox" aria-expanded={open} onClick={() => setOpen(!open)}>
        {selected?.title || "Choose a Join block"}
      </button>
      {open ? <ul className="actor-team-dropdown" role="listbox" aria-label="Join block options">
        {joins.length ? joins.map((join: RecordValue) => <li key={join.id} role="option" tabIndex={0}
          aria-selected={join.id === node.config?.joinNodeId} onClick={() => choose(join.id)}
          onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); choose(join.id); } }}>
          <span className="actor-team-dropdown-name">{join.title}</span><span className="actor-team-dropdown-id">{join.id}</span>
        </li>) : <li>Add a Join block to this graph first.</li>}
      </ul> : null}
    </div>
    <small>Connect 2–16 separate branches with unconditional edges. Every branch must reach this Join. Nested parallel groups are not supported.</small>
  </div>;
}
