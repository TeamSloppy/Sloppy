import { useState } from "react";

export interface MemoryScopeOption { type: string; id: string | null; label: string; group: string }

export function MemoryScopePicker({ options, selected, onChange }: {
  options: MemoryScopeOption[];
  selected: MemoryScopeOption;
  onChange: (option: MemoryScopeOption) => void;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const matches = options.filter((option) => `${option.label} ${option.group}`.toLowerCase().includes(query.toLowerCase()));
  return <div className="actor-team-search-wrap memory-scope-picker" onBlur={(event) => {
    if (!event.currentTarget.contains(event.relatedTarget as Node)) setOpen(false);
  }}>
    <label htmlFor="memory-scope">Memory scope</label>
    <input id="memory-scope" className="actor-team-search" role="combobox" aria-expanded={open} aria-controls="memory-scope-options"
      value={open ? query : `${selected.group} · ${selected.label}`} placeholder="Find an agent or project…"
      onFocus={() => { setQuery(""); setOpen(true); }} onClick={() => setOpen(true)}
      onChange={(event) => { setQuery(event.target.value); setOpen(true); }} onKeyDown={(event) => {
        if (event.key === "Escape") setOpen(false);
        if (event.key === "ArrowDown") { event.preventDefault(); event.currentTarget.parentElement?.querySelector<HTMLButtonElement>("button")?.focus(); }
      }} />
    {open && <ul id="memory-scope-options" className="actor-team-dropdown" role="listbox">
      {matches.map((option) => <li key={`${option.type}:${option.id}`}>
        <button type="button" className="actor-team-dropdown-item" role="option" aria-selected={selected.type === option.type && selected.id === option.id}
          onClick={() => { onChange(option); setOpen(false); }}>
          <span className="actor-team-dropdown-name">{option.label}</span><span className="actor-team-dropdown-id">{option.group}</span>
        </button>
      </li>)}
      {!matches.length && <li className="actor-team-dropdown-item">No matching scopes</li>}
    </ul>}
  </div>;
}
