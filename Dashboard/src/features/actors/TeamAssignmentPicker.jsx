import React, { useEffect, useRef, useState } from "react";
import "../../styles/team-roles.css";

export function TeamAssignmentPicker({ label, value, options, onChange, emptyLabel = "Unassigned", disabled = false }) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const ref = useRef(null);
  useEffect(() => {
    function close(event) { if (!ref.current?.contains(event.target)) setOpen(false); }
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, []);
  return <div className="actor-team-search-wrap team-assignment-picker" ref={ref}
    onKeyDown={(event) => { if (event.key === "Escape") setOpen(false); }}>
    <button type="button" className="actor-team-search" aria-label={label} aria-expanded={open} disabled={disabled}
      onClick={() => { setOpen(!open); setSearch(""); }}>
      {options.find((item) => item.id === value)?.name || value || emptyLabel}
      <span aria-hidden="true"> ▾</span>
    </button>
    {open && <div className="actor-team-dropdown team-assignment-menu">
      <input aria-label={`Search ${label}`} value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search…" autoFocus />
      {[{ id: "", name: emptyLabel }, ...options].filter((item) => item.name.toLowerCase().includes(search.toLowerCase())).map((item) =>
        <button type="button" key={item.id} className={`actor-team-dropdown-item ${value === item.id ? "selected" : ""}`}
          onClick={() => { onChange(item.id); setOpen(false); }}>{item.name}{value === item.id ? " ✓" : ""}</button>)}
    </div>}
  </div>;
}
