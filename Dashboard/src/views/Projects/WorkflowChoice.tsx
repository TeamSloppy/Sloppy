import React, { useEffect, useId, useRef, useState } from "react";

type Option = { value: string; label: string };
export function WorkflowChoice({ label, value, options, onChange }: {
  label: string; value: string; options: Option[]; onChange: (value: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const id = useId();
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const close = (event: PointerEvent) => { if (!ref.current?.contains(event.target as Node)) setOpen(false); };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, []);
  return <div className="project-workflow-field">
    <label htmlFor={id}>{label}</label>
    <div ref={ref} className="actor-team-search" onKeyDown={(event) => {
      if (event.key === "Escape") { setOpen(false); event.stopPropagation(); }
    }}>
      <button id={id} type="button" aria-label={`${label}: ${options.find((option) => option.value === value)?.label || "Choose"}`} aria-haspopup="listbox" aria-expanded={open} onClick={() => setOpen(!open)}>
        {options.find((option) => option.value === value)?.label || "Choose"}
      </button>
      {open ? <ul role="listbox" aria-label={`${label} options`} className="actor-team-dropdown">
        {options.map((option) => <li key={option.value} role="option" aria-selected={option.value === value} tabIndex={0}
          onClick={() => { onChange(option.value); setOpen(false); }} onKeyDown={(event) => {
            if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onChange(option.value); setOpen(false); }
          }}>{option.label}</li>)}
      </ul> : null}
    </div>
  </div>;
}
