import React, { useEffect, useRef, useState } from "react";
import { FILTER_FIELDS, FILTER_OPERATORS, filterError, filterValueOptions, hasTaskFilter, newFilterRule, normalizeTaskFilter, taskMatchesFilter } from "./taskFilters";
import "../../styles/kanban-filters.css";

function FilterPicker({ label, value, options, onChange, multiple = false, placeholder = "Choose", allowCustom = false, displayValue }) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const root = useRef(null);
  const trigger = useRef(null);
  const selected = multiple ? value : [value];
  const matches = (id) => selected.some((item) => item.toLowerCase() === id.toLowerCase());
  useEffect(() => {
    if (!open) return;
    const close = (event) => { if (!root.current?.contains(event.target)) setOpen(false); };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [open]);
  const choose = (id) => {
    onChange(multiple ? matches(id) ? value.filter((item) => item.toLowerCase() !== id.toLowerCase()) : [...value, id] : id);
    setSearch("");
    if (!multiple) { setOpen(false); trigger.current?.focus(); }
  };
  const visible = options.filter((option) => `${option.label} ${option.id}`.toLowerCase().includes(search.toLowerCase()));
  const custom = allowCustom && search.trim() && !options.some((option) => option.id.toLowerCase() === search.trim().toLowerCase());
  return <div className="actor-team-search-wrap kf-picker" ref={root} onKeyDown={(event) => {
    if (event.key === "Escape") { event.stopPropagation(); setOpen(false); trigger.current?.focus(); }
  }}>
    {multiple && value.length > 0 && <div className="kf-values">{value.map((id) => <span key={id}>
      {options.find((option) => option.id === id)?.label || id}
      <button type="button" aria-label={`Remove value ${id}`} onClick={() => choose(id)}>×</button>
    </span>)}</div>}
    <button type="button" ref={trigger} className="actor-team-search" aria-label={label} aria-haspopup="listbox" aria-expanded={open}
      onClick={() => { setOpen(!open); setSearch(""); }}>
      <span>{multiple ? "Choose values…" : displayValue || options.find((option) => option.id === value)?.label || value || placeholder}</span>
      <span className="material-symbols-rounded" aria-hidden="true">expand_more</span>
    </button>
    {open && <div className="actor-team-dropdown kf-menu">
      <input aria-label={`Search ${label}`} placeholder={allowCustom ? "Search or enter a value…" : "Search…"} value={search} autoFocus
        onChange={(event) => setSearch(event.target.value)} onKeyDown={(event) => {
          if (event.key === "Enter" && custom) { event.preventDefault(); choose(search.trim()); }
        }} />
      <div role="listbox" aria-label={label} aria-multiselectable={multiple || undefined}>
        {visible.map((option) => <button type="button" role="option" aria-selected={matches(option.id)} key={option.id}
          className={`actor-team-dropdown-item ${matches(option.id) ? "selected" : ""}`} onClick={() => choose(option.id)}>
          <span>{option.label}</span><span aria-hidden="true">{matches(option.id) ? "✓" : ""}</span>
        </button>)}
      </div>
      {custom && <button type="button" className="actor-team-dropdown-item" onClick={() => choose(search.trim())}>Use “{search.trim()}”</button>}
      {!visible.length && !custom && <p className="kf-hint">No matching values</p>}
    </div>}
  </div>;
}

export function KanbanFilters({ filters, tasks, actors, teams, visibleCount }) {
  const { state, active, modified } = filters;
  const [editing, setEditing] = useState(null);
  const [saving, setSaving] = useState(null);
  const [name, setName] = useState("");
  const [nameError, setNameError] = useState("");
  const invalid = editing ? filterError(editing) : "";
  const activeError = filterError(state.filter);
  const previewCount = editing && !invalid ? tasks.filter((task) => taskMatchesFilter(task, { ...editing, query: state.filter.query })).length : null;
  const apply = () => { filters.setFilter({ ...editing, query: state.filter.query }); setEditing(null); };
  const updateRule = (index, patch) => setEditing({ ...editing, rules: editing.rules.map((rule, i) => i === index ? { ...rule, ...patch } : rule) });
  const openSave = (mode) => { if (editing) { if (invalid) return; filters.setFilter({ ...editing, query: state.filter.query }); } setSaving(mode); setName(mode === "update" ? active?.name || "" : ""); setNameError(""); setEditing(null); };
  return <section className="kanban-filters" aria-label="Kanban filters">
    <div className="kf-toolbar">
      <FilterPicker label="Saved task filter" value={state.activeId || (hasTaskFilter(state.filter) ? "__custom__" : "")} displayValue={!state.activeId && hasTaskFilter(state.filter) ? "Custom filter" : undefined} options={[{ id: "", label: "All tasks" }, ...state.saved.map((entry) => ({ id: entry.id, label: entry.name }))]}
        onChange={(id) => { filters.select(id); setEditing(null); setSaving(null); }} />
      <label className="kf-search"><span className="material-symbols-rounded" aria-hidden="true">search</span>
        <input aria-label="Search tasks" placeholder="Search title, ID or description…" value={state.filter.query}
          onChange={(event) => filters.setFilter({ ...state.filter, query: event.target.value })} />
      </label>
      <button type="button" aria-expanded={Boolean(editing)} aria-controls="kanban-filter-editor" className={hasTaskFilter(state.filter) ? "kf-active" : ""}
        onClick={() => { setEditing(editing ? null : normalizeTaskFilter(state.filter)); setSaving(null); }}>
        <span className="material-symbols-rounded" aria-hidden="true">filter_list</span>Filters{state.filter.rules.length ? ` (${state.filter.rules.length})` : ""}
      </button>
      <button type="button" disabled={Boolean(invalid)} onClick={() => openSave("create")}>Save as…</button>
      {active && <><button type="button" disabled={Boolean(invalid)} onClick={() => openSave("update")}>{modified ? "Save changes…" : "Rename…"}</button>
        <button type="button" className="kf-icon-button" aria-label={`Delete saved filter ${active.name}`} onClick={() => { filters.remove(); setEditing(null); setSaving(null); }}>
          <span className="material-symbols-rounded" aria-hidden="true">delete</span>
        </button></>}
      {hasTaskFilter(state.filter) && <button type="button" onClick={() => { filters.clear(); setEditing(null); setSaving(null); }}>Clear filters</button>}
    </div>
    <div className="kf-summary" aria-live="polite"><span>{visibleCount} of {tasks.length} tasks shown{modified ? " · Unsaved changes" : ""}</span><span>Saved for this project in this browser</span></div>
    {activeError && <p className="kf-error" role="alert">{activeError}</p>}
    {filters.storageError && <p className="kf-error" role="alert">{filters.storageError}</p>}
    {saving && <form className="kf-save" aria-label="Save task filter" onSubmit={(event) => {
      event.preventDefault(); const error = filters.save(name, saving === "update"); setNameError(error); if (!error) setSaving(null);
    }}>
      <label>Filter name<input aria-label="Filter name" placeholder="e.g. My active tasks" value={name} maxLength={80} autoFocus onChange={(event) => setName(event.target.value)} /></label>
      <button type="submit">{saving === "update" ? "Save changes" : "Save filter"}</button>
      <button type="button" onClick={() => setSaving(null)}>Cancel</button>
      {nameError && <p className="kf-error" role="alert">{nameError}</p>}
    </form>}
    {editing && <div className="kf-editor" id="kanban-filter-editor">
      <div className="kf-editor-head"><strong>Show tasks matching</strong><div className="kf-modes" role="group" aria-label="Combine filter conditions">
        {[{ id: "all", label: "All conditions" }, { id: "any", label: "Any condition" }].map((mode) => <button type="button" key={mode.id}
          aria-pressed={editing.match === mode.id} onClick={() => setEditing({ ...editing, match: mode.id })}>{mode.label}</button>)}
      </div></div>
      {!editing.rules.length && <p className="kf-hint">Add conditions to narrow down the board. Multiple values within one condition are alternatives.</p>}
      {editing.rules.map((rule, index) => {
        const field = FILTER_FIELDS.find((item) => item.id === rule.field);
        const needsValues = !["is_empty", "is_not_empty"].includes(rule.operation);
        return <div className="kf-rule" key={rule.id}>
          <FilterPicker label={`Filter condition ${index + 1} field`} value={rule.field} options={FILTER_FIELDS} onChange={(value) => updateRule(index, { field: value, operation: FILTER_FIELDS.find((item) => item.id === value)?.text ? "contains" : "is", values: [] })} />
          <FilterPicker label={`Filter condition ${index + 1} operator`} value={rule.operation} options={FILTER_OPERATORS} onChange={(value) => updateRule(index, { operation: value })} />
          <div className="kf-rule-value">{needsValues ? field?.text
            ? <input aria-label={`Filter condition ${index + 1} text`} placeholder="Enter text…" value={rule.values[0] || ""} onChange={(event) => updateRule(index, { values: [event.target.value] })} />
            : <FilterPicker label={`Filter condition ${index + 1} values`} value={rule.values} multiple allowCustom options={filterValueOptions(rule.field, tasks, actors, teams)} onChange={(values) => updateRule(index, { values })} />
            : <span className="kf-hint">No value needed</span>}
          {field?.hint && <small className="kf-hint">{field.hint}</small>}</div>
          <button type="button" className="kf-icon-button" aria-label={`Remove filter condition ${index + 1}`} onClick={() => setEditing({ ...editing, rules: editing.rules.filter((_, i) => i !== index) })}>×</button>
        </div>;
      })}
      <button type="button" onClick={() => setEditing({ ...editing, rules: [...editing.rules, newFilterRule()] })}>Add condition</button>
      <div className="kf-editor-footer"><span aria-live="polite">{invalid || `${previewCount} ${previewCount === 1 ? "task matches" : "tasks match"}`}</span><div>
        <button type="button" onClick={() => setEditing(null)}>Cancel</button>
        <button type="button" className="kf-primary" disabled={Boolean(invalid)} onClick={apply}>Apply filters</button>
      </div></div>
    </div>}
  </section>;
}
