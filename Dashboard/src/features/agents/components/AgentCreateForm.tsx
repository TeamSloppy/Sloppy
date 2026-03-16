import React from "react";

export const SYSTEM_ROLES = [
  { value: "manager", label: "Manager" },
  { value: "developer", label: "Developer" },
  { value: "qa", label: "QA" },
  { value: "reviewer", label: "Reviewer" }
];

const SYSTEM_ROLE_VALUES = new Set(SYSTEM_ROLES.map((r) => r.value));

export function resolveSystemRole(role: string): string {
  const normalized = role.trim().toLowerCase();
  return SYSTEM_ROLE_VALUES.has(normalized) ? normalized : (role.trim() ? "custom" : "");
}

export interface AgentFormValues {
  id: string;
  displayName: string;
  role: string;
  systemRole: string;
}

export function emptyAgentFormValues(): AgentFormValues {
  return { id: "", displayName: "", role: "", systemRole: "" };
}

interface AgentCreateFormProps {
  form: AgentFormValues;
  error: string;
  onFormChange: (field: keyof AgentFormValues, value: string) => void;
  onSubmit: (event: React.FormEvent) => void;
  onCancel: () => void;
  submitLabel?: string;
  cancelLabel?: string;
}

export function AgentCreateForm({
  form,
  error,
  onFormChange,
  onSubmit,
  onCancel,
  submitLabel = "Create",
  cancelLabel = "Cancel"
}: AgentCreateFormProps) {
  const [roleDropdownOpen, setRoleDropdownOpen] = React.useState(false);

  const filteredRoles = SYSTEM_ROLES.filter((r) =>
    r.label.toLowerCase().includes(form.role.toLowerCase())
  );

  return (
    <form className="agent-form" onSubmit={onSubmit}>
      <label>
        Agent ID
        <input
          value={form.id}
          onChange={(event) => onFormChange("id", event.target.value)}
          placeholder="e.g. research_support_dev"
          autoFocus
        />
        <span className="agent-field-note">Lowercase letters, numbers, hyphens, and underscores only.</span>
      </label>
      <label>
        Display Name <span className="agent-field-optional">optional</span>
        <input
          value={form.displayName}
          onChange={(event) => onFormChange("displayName", event.target.value)}
          placeholder="e.g. Research Agent"
        />
      </label>
      <label>
        Role <span className="agent-field-optional">optional</span>
        <div className="actor-team-search-wrap">
          <input
            className="actor-team-search"
            value={form.role}
            onChange={(event) => {
              onFormChange("role", event.target.value);
              onFormChange("systemRole", resolveSystemRole(event.target.value));
              setRoleDropdownOpen(true);
            }}
            onFocus={() => setRoleDropdownOpen(true)}
            onBlur={() => setTimeout(() => setRoleDropdownOpen(false), 150)}
            placeholder="Select or type a role…"
            autoComplete="off"
          />
          {roleDropdownOpen && (
            <ul className="actor-team-dropdown">
              {filteredRoles.map((r) => {
                const isSelected = resolveSystemRole(form.role) === r.value;
                return (
                  <li
                    key={r.value}
                    className={`actor-team-dropdown-item ${isSelected ? "selected" : ""}`}
                    onMouseDown={(event) => {
                      event.preventDefault();
                      onFormChange("role", r.label);
                      onFormChange("systemRole", r.value);
                      setRoleDropdownOpen(false);
                    }}
                  >
                    <span className="actor-team-dropdown-name">{r.label}</span>
                    {isSelected && <span className="actor-team-dropdown-check material-symbols-rounded">check</span>}
                  </li>
                );
              })}
              {filteredRoles.length === 0 && (
                <li className="actor-team-dropdown-empty">Custom role</li>
              )}
            </ul>
          )}
        </div>
      </label>
      {error ? <p className="agent-create-error">{error}</p> : null}
      <div className="agent-modal-actions">
        <button type="button" onClick={onCancel}>
          {cancelLabel}
        </button>
        <button type="submit" className="agent-create-confirm hover-levitate">
          {submitLabel}
        </button>
      </div>
    </form>
  );
}
