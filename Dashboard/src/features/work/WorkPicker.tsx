import React, { useId, useState } from "react";

export function WorkPicker({ label, value, options, onChange }: {
  label: string;
  value: string;
  options: { id: string; label: string }[];
  onChange: (id: string) => void;
}) {
  const id = useId();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [index, setIndex] = useState(0);
  const filtered = options.filter((option) => option.label.toLowerCase().includes(query.toLowerCase()));
  const selected = options.find((option) => option.id === value);
  function choose(next: string) {
    onChange(next);
    setOpen(false);
    setQuery("");
  }
  return (
    <div className="work-picker actor-team-search-wrap">
      <label htmlFor={id}>{label}</label>
      <div className="work-picker-field">
        <input id={id} className="actor-team-search" role="combobox" aria-expanded={open}
          aria-controls={`${id}-list`} aria-autocomplete="list"
          aria-activedescendant={open && filtered.length ? `${id}-option-${Math.min(index, filtered.length - 1)}` : undefined}
          value={open ? query : selected?.label || ""} placeholder={selected?.label || `Choose ${label.toLowerCase()}…`}
          autoComplete="off" onFocus={() => { setOpen(true); setQuery(""); setIndex(0); }}
          onClick={() => { if (!open) { setOpen(true); setQuery(""); setIndex(0); } }}
          onChange={(event) => { setQuery(event.target.value); setOpen(true); setIndex(0); }}
          onBlur={() => { setOpen(false); setQuery(""); }}
          onKeyDown={(event) => {
            if (event.key === "Escape") { setOpen(false); setQuery(""); }
            if (event.key === "ArrowDown" || event.key === "ArrowUp") {
              event.preventDefault();
              setOpen(true);
              setIndex((previous) => Math.max(0, Math.min(filtered.length - 1, previous + (event.key === "ArrowDown" ? 1 : -1))));
            }
            if (event.key === "Enter" && open && filtered[index]) { event.preventDefault(); choose(filtered[index].id); }
          }} />
        <span className="material-symbols-rounded" aria-hidden="true">unfold_more</span>
      </div>
      {open ? <ul id={`${id}-list`} role="listbox" aria-label={label} className="actor-team-dropdown">
        {filtered.map((option, optionIndex) => <li key={option.id} role="option" id={`${id}-option-${optionIndex}`}
          aria-selected={value === option.id} className={`actor-team-dropdown-item ${optionIndex === index ? "selected" : ""}`}
          onMouseDown={(event) => { event.preventDefault(); choose(option.id); }}>
          <span className="actor-team-dropdown-name">{option.label}</span>
          {value === option.id ? <span className="material-symbols-rounded" aria-hidden="true">check</span> : null}
        </li>)}
        {!filtered.length ? <li className="actor-team-dropdown-empty">No matches</li> : null}
      </ul> : null}
    </div>
  );
}
