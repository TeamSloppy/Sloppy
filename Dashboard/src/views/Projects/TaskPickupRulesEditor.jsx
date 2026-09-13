import React, { useEffect, useRef, useState } from "react";
import { PICKUP_FIELDS, PICKUP_OPERATORS, pickupRulesError, pickupIdentityOptions } from "./taskPickupRules";
import "../../styles/task-pickup-rules.css";

function RuleDropdown({ label, value, options, onChange, placeholder = "Choose" }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);
  useEffect(() => {
    if (!open) return;
    const close = (event) => { if (!ref.current?.contains(event.target)) setOpen(false); };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [open]);
  return <div className="actor-team-search-wrap pickup-rules-dropdown" ref={ref} onKeyDown={(event) => {
    if (event.key === "Escape") setOpen(false);
  }}>
    <button type="button" className="actor-team-search" aria-label={label} aria-expanded={open}
      aria-haspopup="listbox" onClick={() => setOpen(!open)}>
      <span>{options.find((option) => option.id === value)?.label || value || placeholder}</span>
      <span className="material-symbols-rounded" aria-hidden="true">expand_more</span>
    </button>
    {open && <ul className="actor-team-dropdown" role="listbox" aria-label={label}>
      {options.map((option) => <li key={option.id}>
        <button type="button" className={`actor-team-dropdown-item ${option.id === value ? "selected" : ""}`}
          role="option" aria-selected={option.id === value} onClick={() => { onChange(option.id); setOpen(false); }}>
          {option.label}
        </button>
      </li>)}
    </ul>}
  </div>;
}

export function TaskPickupRulesEditor({ rules, onChange, tasks = [] }) {
  const error = pickupRulesError(rules);
  const update = (index, patch) => onChange({ ...rules, conditions: rules.conditions.map((condition, i) => i === index ? { ...condition, ...patch } : condition) });
  return <section className="pickup-rules" aria-label="Task pickup rules">
    <h4>Task pickup rules</h4>
    <p className="project-settings-field-hint">Restrict which tasks workers can start automatically. These rules apply even when Autopilot is off. Imported tasks remain visible on the board.</p>
    <div className="pickup-rules-mode" role="group" aria-label="Combine conditions">
      {[{ id: "all", label: "All conditions (AND)" }, { id: "any", label: "Any condition (OR)" }].map((mode) =>
        <button type="button" key={mode.id} aria-pressed={rules.matchMode === mode.id}
          className={`task-sync-token-option ${rules.matchMode === mode.id ? "active" : ""}`}
          onClick={() => onChange({ ...rules, matchMode: mode.id })}>{mode.label}</button>)}
    </div>
    {rules.conditions.length === 0 && <p className="project-settings-field-hint">No additional restrictions. Add a condition to limit pickup.</p>}
    {rules.conditions.map((condition, index) => {
      const field = PICKUP_FIELDS.find((item) => item.id === condition.field);
      const operators = PICKUP_OPERATORS.filter((item) => item.id !== "contains" || ["title", "description"].includes(condition.field));
      const needsValues = !["is_set", "is_not_set"].includes(condition.operation);
      const identities = pickupIdentityOptions(tasks, condition.field);
      return <div key={condition.id} className="pickup-rules-row">
        <RuleDropdown label={`Condition ${index + 1} field`} value={condition.field} options={PICKUP_FIELDS}
          onChange={(value) => update(index, { field: value, operation: "one_of", values: [] })} />
        <RuleDropdown label={`Condition ${index + 1} operator`} value={condition.operation} options={operators}
          onChange={(value) => update(index, { operation: value })} />
        <div className="pickup-rules-value">
          {needsValues ? <><input aria-label={`Condition ${index + 1} values`} placeholder={field?.hint}
            value={condition.values.join(",")} onChange={(event) => update(index, { values: event.target.value.split(",") })} />
            <small className="project-settings-field-hint">{field?.hint}. Separate alternatives with commas.</small>
            {identities.length > 0 && <RuleDropdown label={`Condition ${index + 1} known ${condition.field}`} value=""
              placeholder={`Add known ${condition.field}`} options={identities} onChange={(value) => {
                const values = condition.values.filter((item) => item.trim());
                if (!values.some((item) => item.trim().toLowerCase() === value.toLowerCase())) values.push(value);
                update(index, { values });
              }} />}</> :
            <small className="project-settings-field-hint">No value needed.</small>}
        </div>
        <button type="button" className="pickup-rules-remove" aria-label={`Remove condition ${index + 1}`}
          onClick={() => onChange({ ...rules, conditions: rules.conditions.filter((_, i) => i !== index) })}>
          <span className="material-symbols-rounded" aria-hidden="true">close</span>
        </button>
      </div>;
    })}
    <button type="button" disabled={rules.conditions.length >= 50} onClick={() => onChange({ ...rules, conditions: [
      ...rules.conditions, { id: globalThis.crypto?.randomUUID?.() || `rule-${Date.now()}-${Math.random().toString(36).slice(2)}`, field: "author", operation: "one_of", values: [] }
    ] })}>Add condition</button>
    {error && <p className="pickup-rules-error" role="alert">{error}</p>}
    <p className="project-settings-field-hint">Matches ignore letter case. Authors and assignees use logins or IDs, not display names. Missing source metadata does not match value conditions; synchronize Tracker tasks after updating the plugin. Autopilot subtasks inherit their root task's rules.</p>
  </section>;
}
