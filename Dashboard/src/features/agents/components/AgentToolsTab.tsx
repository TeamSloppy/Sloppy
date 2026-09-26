import React, { useEffect, useMemo, useState } from "react";
import { fetchAgents, fetchAgentToolsCatalog, fetchAgentToolsPolicy, updateAgentToolsPolicy } from "../../../api";

// MARK: - Presets

const PRESETS = [
  {
    id: "full",
    label: "Full",
    description: "All tools enabled. No restrictions.",
    defaultPolicy: "allow",
    tools: {}
  },
  {
    id: "safe",
    label: "Safe",
    description: "All tools allowed except execution, cron, destructive project/MCP ops, and skills management.",
    defaultPolicy: "allow",
    tools: {
      "runtime.exec": false,
      "runtime.process": false,
      "cron": false,
      "project.delete": false,
      "mcp.save_server": false,
      "mcp.remove_server": false,
      "mcp.install_server": false,
      "mcp.uninstall_server": false,
      "mcp.call_tool": false,
      "skills.install": false,
      "skills.uninstall": false
    }
  },
  {
    id: "read_only",
    label: "Read Only",
    description: "Observation only — no writes, no exec, no side-effects.",
    defaultPolicy: "deny",
    tools: {
      "files.read": true,
      "system.list_tools": true,
      "agents.list": true,
      "sessions.list": true,
      "sessions.history": true,
      "sessions.status": true,
      "channel.history": true,
      "memory.get": true,
      "memory.recall": true,
      "memory.source": true,
      "memory.search": true,
      "project.list": true,
      "project.task_list": true,
      "project.task_get": true,
      "web.search": true,
      "web.fetch": true,
      "mcp.list_servers": true,
      "mcp.list_tools": true,
      "mcp.list_resources": true,
      "mcp.read_resource": true,
      "mcp.list_prompts": true,
      "mcp.get_prompt": true,
      "skills.search": true,
      "skills.list": true
    }
  },
  {
    id: "custom",
    label: "Custom",
    description: "Manually configured tool policy.",
    defaultPolicy: null,
    tools: null
  }
];

function detectPreset(draft) {
  for (const preset of PRESETS) {
    if (preset.id === "custom") continue;
    if (preset.defaultPolicy !== draft.defaultPolicy) continue;
    const presetTools = preset.tools;
    const draftTools = draft.tools || {};
    const presetKeys = Object.keys(presetTools);
    const draftKeys = Object.keys(draftTools);
    if (presetKeys.length !== draftKeys.length) continue;
    const matches = presetKeys.every((key) => presetTools[key] === draftTools[key]);
    if (matches) return preset.id;
  }
  return "custom";
}

// MARK: - Defaults

function defaultDraft() {
  return {
    version: 1,
    defaultPolicy: "allow",
    tools: {},
    approval: {
      policy: "never",
      enabled: false,
      reviewerAgentId: null
    },
    sandbox: {
      mode: "workspace_write"
    },
    preToolsHook: {
      enabled: null,
      command: null,
      arguments: null,
      timeoutMs: null,
      maxOutputBytes: null,
      failurePolicy: null
    },
    guardrails: {
      maxReadBytes: 524288,
      maxWriteBytes: 524288,
      execTimeoutMs: 15000,
      maxExecTimeoutMs: 120000,
      maxExecOutputBytes: 262144,
      maxProcessesPerSession: 2,
      maxToolCallsPerMinute: 60,
      toolLoopWindowSeconds: 60,
      maxConsecutiveIdenticalToolCalls: 3,
      maxIdenticalToolCallsPerWindow: 6,
      maxRepeatedNonRetryableFailures: 2,
      deniedCommandPrefixes: ["rm", "shutdown", "reboot", "mkfs", "dd", "killall", "launchctl"],
      allowedWriteRoots: [],
      allowedExecRoots: [],
      webTimeoutMs: 10000,
      webMaxBytes: 524288,
      webBlockPrivateNetworks: true
    }
  };
}

function parseList(value) {
  if (Array.isArray(value)) {
    return value.map((item) => String(item || "").trim()).filter(Boolean);
  }
  return String(value || "")
    .split("\n")
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseNullableList(value) {
  const items = parseList(value);
  return items.length > 0 ? items : null;
}

function nullableText(value) {
  const text = String(value || "").trim();
  return text ? text : null;
}

const NUMERIC_GUARDRAILS = [
  {
    key: "maxReadBytes",
    label: "Max Read Bytes",
    hint: "Maximum bytes a single read operation can return.",
    unit: "bytes"
  },
  {
    key: "maxWriteBytes",
    label: "Max Write Bytes",
    hint: "Maximum bytes allowed per write operation.",
    unit: "bytes"
  },
  {
    key: "execTimeoutMs",
    label: "Exec Timeout",
    hint: "Default run time for one command execution.",
    unit: "ms"
  },
  {
    key: "maxExecTimeoutMs",
    label: "Max Exec Timeout",
    hint: "Upper bound for model-requested command timeouts.",
    unit: "ms"
  },
  {
    key: "maxExecOutputBytes",
    label: "Max Exec Output",
    hint: "Cap for captured stdout and stderr output.",
    unit: "bytes"
  },
  {
    key: "maxProcessesPerSession",
    label: "Max Processes / Session",
    hint: "Maximum concurrently tracked child processes.",
    unit: ""
  },
  {
    key: "maxToolCallsPerMinute",
    label: "Max Tool Calls / Minute",
    hint: "Rate limit across all tool invocations.",
    unit: ""
  },
  {
    key: "toolLoopWindowSeconds",
    label: "Loop Window",
    hint: "Sliding window used for repeated-call loop detection.",
    unit: "s"
  },
  {
    key: "maxConsecutiveIdenticalToolCalls",
    label: "Max Consecutive Identical Calls",
    hint: "Block repeated identical exec/process calls after this many same-shape attempts.",
    unit: ""
  },
  {
    key: "maxIdenticalToolCallsPerWindow",
    label: "Max Identical Calls / Window",
    hint: "Block a repeated shell/process signature when it appears too many times inside the loop window.",
    unit: ""
  },
  {
    key: "maxRepeatedNonRetryableFailures",
    label: "Max Repeated Hard Failures",
    hint: "Block a retried tool signature after repeated non-retryable failures.",
    unit: ""
  },
  {
    key: "webTimeoutMs",
    label: "Web Timeout",
    hint: "Timeout for each web request from tools.",
    unit: "ms"
  },
  {
    key: "webMaxBytes",
    label: "Web Max Bytes",
    hint: "Maximum bytes accepted from a web response.",
    unit: "bytes"
  }
] as const;

// MARK: - Component

export function AgentToolsTab({ agentId }) {
  const [catalog, setCatalog] = useState([]);
  const [agents, setAgents] = useState([]);
  const [reviewerSearch, setReviewerSearch] = useState("");
  const [reviewerDropdownOpen, setReviewerDropdownOpen] = useState(false);
  const [presetDropdownOpen, setPresetDropdownOpen] = useState(false);
  const [draft, setDraft] = useState(defaultDraft);
  const [savedPolicy, setSavedPolicy] = useState(defaultDraft);
  const [statusText, setStatusText] = useState("Loading tools policy...");
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      setIsLoading(true);
      setStatusText("Loading tools policy...");
      const [catalogResponse, policyResponse, agentsResponse] = await Promise.all([
        fetchAgentToolsCatalog(agentId),
        fetchAgentToolsPolicy(agentId),
        fetchAgents({ includeSystem: true })
      ]);
      if (cancelled) {
        return;
      }

      if (!catalogResponse || !policyResponse) {
        setCatalog([]);
        const empty = defaultDraft();
        setDraft(empty);
        setSavedPolicy(empty);
        setStatusText("Failed to load tools policy.");
        setIsLoading(false);
        return;
      }

      const policy = policyResponse as any;
      const loaded = {
        version: Number(policy.version || 1),
        defaultPolicy: String(policy.defaultPolicy || "allow"),
        tools: typeof policy.tools === "object" && policy.tools ? policy.tools : {},
        approval: {
          ...defaultDraft().approval,
          ...(policy.approval || {}),
          policy: String(policy.approval?.policy || (policy.approval?.enabled ? "on_request" : "never"))
        },
        sandbox: {
          ...defaultDraft().sandbox,
          ...(policy.sandbox || {})
        },
        preToolsHook: {
          ...defaultDraft().preToolsHook,
          ...(policy.preToolsHook || {})
        },
        guardrails: {
          ...defaultDraft().guardrails,
          ...(policy.guardrails || {})
        }
      };
      setCatalog(Array.isArray(catalogResponse) ? catalogResponse : []);
      const loadedAgents = Array.isArray(agentsResponse) ? agentsResponse : [];
      setAgents(loadedAgents);
      const selectedReviewer = loadedAgents.find((agent) => agent.id === loaded.approval.reviewerAgentId);
      setReviewerSearch(selectedReviewer ? String(selectedReviewer.displayName || selectedReviewer.id || "") : "");
      setDraft(loaded);
      setSavedPolicy(loaded);
      setStatusText("Tools policy loaded.");
      setIsLoading(false);
    }

    load().catch(() => {
      if (!cancelled) {
        setStatusText("Failed to load tools policy.");
        setIsLoading(false);
      }
    });

    return () => {
      cancelled = true;
    };
  }, [agentId]);

  const groupedCatalog = useMemo(() => {
    const groups = new Map();
    for (const item of catalog) {
      const domain = String(item?.domain || "other");
      if (!groups.has(domain)) {
        groups.set(domain, []);
      }
      groups.get(domain).push(item);
    }
    return Array.from(groups.entries()).sort((left, right) => left[0].localeCompare(right[0]));
  }, [catalog]);

  const hasChanges = useMemo(() => {
    return JSON.stringify(draft) !== JSON.stringify(savedPolicy);
  }, [draft, savedPolicy]);

  const activePreset = useMemo(() => detectPreset(draft), [draft]);

  function applyPreset(presetId) {
    const preset = PRESETS.find((p) => p.id === presetId);
    if (!preset || preset.id === "custom") return;
    setDraft((previous) => ({
      ...previous,
      defaultPolicy: preset.defaultPolicy,
      tools: { ...preset.tools }
    }));
  }

  function updateGuardrail(field, value) {
    setDraft((previous) => ({
      ...previous,
      guardrails: {
        ...previous.guardrails,
        [field]: value
      }
    }));
  }

  function updateApproval(field, value) {
    setDraft((previous) => ({
      ...previous,
      approval: {
        ...previous.approval,
        [field]: value,
        ...(field === "policy" ? { enabled: value !== "never" } : {})
      }
    }));
  }

  function updateSandbox(field, value) {
    setDraft((previous) => ({
      ...previous,
      sandbox: {
        ...previous.sandbox,
        [field]: value
      }
    }));
  }

  function updatePreToolsHook(field, value) {
    setDraft((previous) => ({
      ...previous,
      preToolsHook: {
        ...previous.preToolsHook,
        [field]: value
      }
    }));
  }

  function isToolEnabled(toolId, state = draft) {
    const explicitlyEnabled = state.tools?.[toolId];
    if (typeof explicitlyEnabled === "boolean") {
      return explicitlyEnabled;
    }
    return state.defaultPolicy === "allow";
  }

  function toggleTool(toolId) {
    setDraft((previous) => ({
      ...previous,
      tools: (() => {
        const effective = isToolEnabled(toolId, previous);
        const nextValue = !effective;
        const defaultEnabled = previous.defaultPolicy === "allow";
        const nextTools = {
          ...previous.tools
        };

        if (nextValue === defaultEnabled) {
          delete nextTools[toolId];
        } else {
          nextTools[toolId] = nextValue;
        }
        return nextTools;
      })()
    }));
  }

  function cancelChanges() {
    setDraft(savedPolicy);
    setStatusText("Changes cancelled.");
  }

  async function savePolicy() {
    if (isSaving) return;
    if (draft.approval?.policy === "approve_for_me" && !draft.approval?.reviewerAgentId) {
      setStatusText("Choose a reviewer agent before saving.");
      return;
    }

    setIsSaving(true);
    const payload = {
      version: 1,
      defaultPolicy: draft.defaultPolicy === "deny" ? "deny" : "allow",
      tools: draft.tools,
      approval: {
        policy: ["on_request", "approve_for_me"].includes(draft.approval?.policy)
          ? draft.approval.policy
          : "never",
        enabled: draft.approval?.policy !== "never",
        reviewerAgentId: draft.approval?.policy === "approve_for_me"
          ? draft.approval?.reviewerAgentId || null
          : null
      },
      sandbox: {
        mode: draft.sandbox?.mode === "full_access" ? "full_access" : "workspace_write"
      },
      preToolsHook: {
        enabled: typeof draft.preToolsHook?.enabled === "boolean" ? draft.preToolsHook.enabled : null,
        command: nullableText(draft.preToolsHook?.command),
        arguments: parseNullableList(draft.preToolsHook?.arguments),
        timeoutMs: draft.preToolsHook?.timeoutMs === null || draft.preToolsHook?.timeoutMs === ""
          ? null
          : Number(draft.preToolsHook?.timeoutMs),
        maxOutputBytes: draft.preToolsHook?.maxOutputBytes === null || draft.preToolsHook?.maxOutputBytes === ""
          ? null
          : Number(draft.preToolsHook?.maxOutputBytes),
        failurePolicy: draft.preToolsHook?.failurePolicy === "allow" || draft.preToolsHook?.failurePolicy === "block"
          ? draft.preToolsHook.failurePolicy
          : null
      },
      guardrails: {
        maxReadBytes: Number(draft.guardrails.maxReadBytes),
        maxWriteBytes: Number(draft.guardrails.maxWriteBytes),
        execTimeoutMs: Number(draft.guardrails.execTimeoutMs),
        maxExecTimeoutMs: Number(draft.guardrails.maxExecTimeoutMs),
        maxExecOutputBytes: Number(draft.guardrails.maxExecOutputBytes),
        maxProcessesPerSession: Number(draft.guardrails.maxProcessesPerSession),
        maxToolCallsPerMinute: Number(draft.guardrails.maxToolCallsPerMinute),
        toolLoopWindowSeconds: Number(draft.guardrails.toolLoopWindowSeconds),
        maxConsecutiveIdenticalToolCalls: Number(draft.guardrails.maxConsecutiveIdenticalToolCalls),
        maxIdenticalToolCallsPerWindow: Number(draft.guardrails.maxIdenticalToolCallsPerWindow),
        maxRepeatedNonRetryableFailures: Number(draft.guardrails.maxRepeatedNonRetryableFailures),
        deniedCommandPrefixes: parseList(draft.guardrails.deniedCommandPrefixes),
        allowedWriteRoots: parseList(draft.guardrails.allowedWriteRoots),
        allowedExecRoots: parseList(draft.guardrails.allowedExecRoots),
        webTimeoutMs: Number(draft.guardrails.webTimeoutMs),
        webMaxBytes: Number(draft.guardrails.webMaxBytes),
        webBlockPrivateNetworks: Boolean(draft.guardrails.webBlockPrivateNetworks)
      }
    };

    const response = await updateAgentToolsPolicy(agentId, payload);
    if (!response) {
      setStatusText("Failed to save tools policy.");
      setIsSaving(false);
      return;
    }

    setSavedPolicy(draft);
    setStatusText("Tools policy saved.");
    setIsSaving(false);
  }

  const activePresetMeta = PRESETS.find((p) => p.id === activePreset);

  return (
    <section className="agent-config-shell agent-tools-shell">
      <div className="agent-config-head agent-tools-head">
        <div className="agent-tools-head-copy">
          <h3>Tools Policy</h3>
          <p className="placeholder-text">Control catalog overrides and runtime guardrails for tool execution.</p>
        </div>
        <span className="agent-tools-status">{statusText}</span>
      </div>

      {isLoading ? (
        <p className="placeholder-text">Loading...</p>
      ) : (
        <>
          <section className="agent-tools-panel">
            <div className="agent-tools-panel-head">
              <h4>Policy Preset</h4>
              <p>Quick configuration template. Selecting a preset rewrites the default policy and tool overrides.</p>
            </div>
            <div className="agent-tools-field">
              <span id="agent-tools-preset-label">Preset</span>
              <div className="actor-team-search-wrap">
                <button
                  type="button"
                  className="actor-team-search agent-tools-preset-button"
                  aria-labelledby="agent-tools-preset-label"
                  aria-haspopup="listbox"
                  aria-controls="agent-tools-preset-options"
                  aria-expanded={presetDropdownOpen}
                  onClick={() => setPresetDropdownOpen((open) => !open)}
                  onBlur={() => setTimeout(() => setPresetDropdownOpen(false), 150)}
                  onKeyDown={(event) => {
                    if (event.key === "Escape") setPresetDropdownOpen(false);
                  }}
                >
                  {activePresetMeta?.label || "Custom"}
                  <span className="material-symbols-rounded" aria-hidden="true">expand_more</span>
                </button>
                {presetDropdownOpen ? (
                  <ul className="actor-team-dropdown" id="agent-tools-preset-options" role="listbox" aria-labelledby="agent-tools-preset-label">
                    {PRESETS.filter((preset) => preset.id !== "custom").map((preset) => (
                      <li key={preset.id} role="presentation">
                        <button
                          type="button"
                          className="agent-tools-preset-option"
                          role="option"
                          aria-selected={activePreset === preset.id}
                          onClick={() => {
                            applyPreset(preset.id);
                            setPresetDropdownOpen(false);
                          }}
                        >
                          {preset.label}
                        </button>
                      </li>
                    ))}
                  </ul>
                ) : null}
              </div>
            </div>
            {activePresetMeta && (
              <p className="placeholder-text" style={{ marginTop: 6 }}>{activePresetMeta.description}</p>
            )}
          </section>

          <section className="agent-tools-panel">
            <div className="agent-tools-panel-head">
              <h4>Agent Permissions</h4>
              <p>Configure approval prompts and filesystem sandbox access for this agent.</p>
            </div>

            <div>
              <span className="agent-tools-guardrail-title">Approval Policy</span>
              <div className="review-approval-options" style={{ marginTop: 8 }}>
                {[
                  { id: "never", label: "Never", icon: "lock_open" },
                  { id: "on_request", label: "On Request", icon: "fact_check" },
                  { id: "approve_for_me", label: "Approve for me", icon: "smart_toy" }
                ].map((option) => (
                  <button
                    key={option.id}
                    type="button"
                    className={`review-approval-option ${draft.approval?.policy === option.id ? "active" : ""}`}
                    onClick={() => updateApproval("policy", option.id)}
                  >
                    <span className="material-symbols-rounded review-approval-icon">{option.icon}</span>
                    <strong className="review-approval-name">{option.label}</strong>
                  </button>
                ))}
              </div>
              <p className="placeholder-text" style={{ marginTop: 8 }}>
                On Request waits for a human. Approve for me asks the selected agent for a one-call decision and rejects if review fails.
              </p>
              {draft.approval?.policy === "approve_for_me" ? (
                <div style={{ marginTop: 12 }}>
                  <span className="agent-tools-guardrail-title">Reviewer Agent</span>
                  <div className="actor-team-search-wrap" style={{ marginTop: 8 }}>
                    <input
                      className="actor-team-search"
                      value={reviewerSearch}
                      onChange={(event) => {
                        setReviewerSearch(event.target.value);
                        setReviewerDropdownOpen(true);
                      }}
                      onFocus={(event) => {
                        event.currentTarget.select();
                        setReviewerDropdownOpen(true);
                      }}
                      onBlur={() => setTimeout(() => setReviewerDropdownOpen(false), 150)}
                      placeholder="Search agents…"
                      autoComplete="off"
                      role="combobox"
                      aria-expanded={reviewerDropdownOpen}
                    />
                    {reviewerDropdownOpen ? (
                      <ul className="actor-team-dropdown" role="listbox" aria-label="Reviewer agent">
                        {agents
                          .filter((agent) => agent.id !== agentId && String(agent.runtime?.type || "native") === "native")
                          .filter((agent) => {
                            const query = reviewerSearch.toLowerCase();
                            return !query || String(agent.displayName || "").toLowerCase().includes(query) || String(agent.id || "").toLowerCase().includes(query);
                          })
                          .map((agent) => (
                            <li
                              key={agent.id}
                              className={`actor-team-dropdown-item ${draft.approval?.reviewerAgentId === agent.id ? "selected" : ""}`}
                              onMouseDown={(event) => {
                                event.preventDefault();
                                updateApproval("reviewerAgentId", String(agent.id || ""));
                                setReviewerSearch(String(agent.displayName || agent.id || ""));
                                setReviewerDropdownOpen(false);
                              }}
                              role="option"
                              aria-selected={draft.approval?.reviewerAgentId === agent.id}
                            >
                              <span className="actor-team-dropdown-name">{agent.displayName || agent.id}</span>
                              <span className="actor-team-dropdown-id">{agent.id}</span>
                            </li>
                          ))}
                      </ul>
                    ) : null}
                  </div>
                </div>
              ) : null}
            </div>

            <div style={{ marginTop: 18 }}>
              <span className="agent-tools-guardrail-title">Sandbox Settings</span>
              <div className="review-approval-options" style={{ marginTop: 8 }}>
                {[
                  { id: "workspace_write", label: "Workspace Access", icon: "folder_managed" },
                  { id: "full_access", label: "Full Access", icon: "admin_panel_settings" }
                ].map((option) => (
                  <button
                    key={option.id}
                    type="button"
                    className={`review-approval-option ${draft.sandbox?.mode === option.id ? "active" : ""}`}
                    onClick={() => updateSandbox("mode", option.id)}
                  >
                    <span className="material-symbols-rounded review-approval-icon">{option.icon}</span>
                    <strong className="review-approval-name">{option.label}</strong>
                  </button>
                ))}
              </div>
              <p className="placeholder-text" style={{ marginTop: 8 }}>
                Full Access allows filesystem reads, writes, and command working directories outside the workspace while preserving command denylist and limits.
              </p>
            </div>
          </section>

          <section className="agent-tools-panel">
            <div className="agent-tools-panel-head">
              <h4>Pre-Tools Hook Override</h4>
              <p>Override the global local hook for this agent before tool calls are logged, approved, or executed.</p>
            </div>

            <div className="review-approval-options">
              {[
                { id: "inherit", label: "Inherit", icon: "settings_backup_restore" },
                { id: "enabled", label: "Enabled", icon: "lock" },
                { id: "disabled", label: "Disabled", icon: "lock_open" }
              ].map((option) => {
                const mode = draft.preToolsHook?.enabled === true
                  ? "enabled"
                  : draft.preToolsHook?.enabled === false
                    ? "disabled"
                    : "inherit";
                return (
                  <button
                    key={option.id}
                    type="button"
                    className={`review-approval-option ${mode === option.id ? "active" : ""}`}
                    onClick={() => {
                      updatePreToolsHook(
                        "enabled",
                        option.id === "inherit" ? null : option.id === "enabled"
                      );
                    }}
                  >
                    <span className="material-symbols-rounded review-approval-icon">{option.icon}</span>
                    <strong className="review-approval-name">{option.label}</strong>
                  </button>
                );
              })}
            </div>

            <div className="agent-tools-textarea-grid" style={{ marginTop: 12 }}>
              <label className="agent-tools-field">
                <span>Command Override</span>
                <small>Blank inherits the global command.</small>
                <input
                  type="text"
                  value={draft.preToolsHook?.command ?? ""}
                  placeholder="/absolute/path/to/hook"
                  onChange={(event) => updatePreToolsHook("command", event.target.value)}
                />
              </label>
              <label className="agent-tools-field">
                <span>Arguments Override</span>
                <small>Blank inherits global arguments. One argument per line.</small>
                <textarea
                  rows={4}
                  value={Array.isArray(draft.preToolsHook?.arguments)
                    ? draft.preToolsHook.arguments.join("\n")
                    : String(draft.preToolsHook?.arguments || "")}
                  onChange={(event) => updatePreToolsHook("arguments", event.target.value)}
                />
              </label>
            </div>

            <div className="agent-tools-guardrail-grid" style={{ marginTop: 12 }}>
              <label className="agent-tools-guardrail">
                <span className="agent-tools-guardrail-title">Timeout Override</span>
                <span className="agent-tools-guardrail-note">Blank inherits global timeout.</span>
                <div className="agent-tools-number">
                  <input
                    type="number"
                    value={draft.preToolsHook?.timeoutMs ?? ""}
                    placeholder="inherit"
                    onChange={(event) => updatePreToolsHook("timeoutMs", event.target.value)}
                  />
                  <span className="agent-tools-unit">ms</span>
                </div>
              </label>
              <label className="agent-tools-guardrail">
                <span className="agent-tools-guardrail-title">Max Output Override</span>
                <span className="agent-tools-guardrail-note">Blank inherits global output cap.</span>
                <div className="agent-tools-number">
                  <input
                    type="number"
                    value={draft.preToolsHook?.maxOutputBytes ?? ""}
                    placeholder="inherit"
                    onChange={(event) => updatePreToolsHook("maxOutputBytes", event.target.value)}
                  />
                  <span className="agent-tools-unit">bytes</span>
                </div>
              </label>
            </div>

            <div style={{ marginTop: 12 }}>
              <span className="agent-tools-guardrail-title">Failure Policy Override</span>
              <div className="review-approval-options" style={{ marginTop: 8 }}>
                {[
                  { id: "inherit", label: "Inherit", icon: "settings_backup_restore" },
                  { id: "block", label: "Block", icon: "lock" },
                  { id: "allow", label: "Allow", icon: "lock_open" }
                ].map((option) => {
                  const mode = draft.preToolsHook?.failurePolicy || "inherit";
                  return (
                    <button
                      key={option.id}
                      type="button"
                      className={`review-approval-option ${mode === option.id ? "active" : ""}`}
                      onClick={() => updatePreToolsHook("failurePolicy", option.id === "inherit" ? null : option.id)}
                    >
                      <span className="material-symbols-rounded review-approval-icon">{option.icon}</span>
                      <strong className="review-approval-name">{option.label}</strong>
                    </button>
                  );
                })}
              </div>
            </div>
          </section>

          <section className="agent-tools-panel">
            <div className="agent-tools-panel-head">
              <h4>Catalog Overrides</h4>
              <p>Enable or disable specific tools per catalog domain.</p>
            </div>
            {groupedCatalog.length === 0 ? (
              <p className="placeholder-text">No tools available in the catalog.</p>
            ) : (
              <div className="agent-tools-domain-grid">
                {groupedCatalog.map(([domain, items]) => (
                  <fieldset key={domain} className="agent-tools-domain">
                    <legend>{domain}</legend>
                    {items.map((item) => {
                      const id = String(item?.id || "");
                      const checked = isToolEnabled(id);
                      return (
                        <label key={id} className="agent-tools-tool-row">
                          <span className="agent-tools-tool-copy">
                            <strong>{item.title || id}</strong>
                            <small>
                              {id} · {item.status || "unknown"}
                            </small>
                          </span>
                          <span className="agent-tools-switch">
                            <input type="checkbox" checked={checked} onChange={() => toggleTool(id)} />
                            <span className="agent-tools-switch-track" />
                          </span>
                        </label>
                      );
                    })}
                  </fieldset>
                ))}
              </div>
            )}
          </section>

          <section className="agent-tools-panel">
            <div className="agent-tools-panel-head">
              <h4>Guardrails</h4>
              <p>Execution, process, filesystem, and network boundaries for tools.</p>
            </div>

            <div className="agent-tools-guardrail-grid">
              {NUMERIC_GUARDRAILS.map((field) => (
                <label key={field.key} className="agent-tools-guardrail">
                  <span className="agent-tools-guardrail-title">{field.label}</span>
                  <span className="agent-tools-guardrail-note">{field.hint}</span>
                  <div className="agent-tools-number">
                    <input
                      type="number"
                      value={draft.guardrails[field.key]}
                      onChange={(event) => updateGuardrail(field.key, event.target.value)}
                    />
                    {field.unit ? <span className="agent-tools-unit">{field.unit}</span> : null}
                  </div>
                </label>
              ))}

              <label className="agent-tools-guardrail agent-tools-guardrail-toggle">
                <span className="agent-tools-guardrail-copy">
                  <span className="agent-tools-guardrail-title">Block Private Networks</span>
                  <span className="agent-tools-guardrail-note">Reject loopback and private web addresses.</span>
                </span>
                <span className="agent-tools-switch">
                  <input
                    type="checkbox"
                    checked={Boolean(draft.guardrails.webBlockPrivateNetworks)}
                    onChange={(event) => updateGuardrail("webBlockPrivateNetworks", event.target.checked)}
                  />
                  <span className="agent-tools-switch-track" />
                </span>
              </label>
            </div>

            <div className="agent-tools-textarea-grid">
              <label className="agent-tools-field">
                <span>Denied Command Prefixes</span>
                <small>One prefix per line.</small>
                <textarea
                  rows={5}
                  value={Array.isArray(draft.guardrails.deniedCommandPrefixes)
                    ? draft.guardrails.deniedCommandPrefixes.join("\n")
                    : String(draft.guardrails.deniedCommandPrefixes || "")}
                  onChange={(event) => updateGuardrail("deniedCommandPrefixes", event.target.value)}
                />
              </label>
              <label className="agent-tools-field">
                <span>Allowed Write Roots</span>
                <small>Absolute paths, one root per line.</small>
                <textarea
                  rows={5}
                  value={Array.isArray(draft.guardrails.allowedWriteRoots)
                    ? draft.guardrails.allowedWriteRoots.join("\n")
                    : String(draft.guardrails.allowedWriteRoots || "")}
                  onChange={(event) => updateGuardrail("allowedWriteRoots", event.target.value)}
                />
              </label>
              <label className="agent-tools-field">
                <span>Allowed Exec Roots</span>
                <small>Absolute paths, one root per line.</small>
                <textarea
                  rows={5}
                  value={Array.isArray(draft.guardrails.allowedExecRoots)
                    ? draft.guardrails.allowedExecRoots.join("\n")
                    : String(draft.guardrails.allowedExecRoots || "")}
                  onChange={(event) => updateGuardrail("allowedExecRoots", event.target.value)}
                />
              </label>
            </div>
          </section>

          <div className={`settings-toast ${hasChanges ? "settings-toast--visible" : ""}`}>
            <span className="settings-toast-label">Unsaved changes</span>
            <div className="settings-toast-actions">
              <button type="button" className="danger hover-levitate" onClick={cancelChanges}>
                Cancel
              </button>
              <button type="button" className="hover-levitate" onClick={savePolicy} disabled={isSaving}>
                {isSaving ? "Saving..." : "Apply"}
              </button>
            </div>
          </div>
        </>
      )}
    </section>
  );
}
