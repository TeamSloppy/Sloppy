import React, { useState } from "react";
import { probeACPTarget } from "../../../api";

function emptyTarget() {
  return {
    id: "",
    title: "",
    transport: "stdio",
    command: "",
    arguments: [],
    cwd: "",
    environment: {},
    timeoutMs: 30000,
    enabled: true
  };
}

function normalizeTargets(raw) {
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw.map((t) => ({
    id: String(t.id || ""),
    title: String(t.title || t.id || ""),
    transport: String(t.transport || "stdio"),
    command: String(t.command || ""),
    arguments: Array.isArray(t.arguments) ? t.arguments : [],
    cwd: String(t.cwd || ""),
    environment: t.environment && typeof t.environment === "object" ? t.environment : {},
    timeoutMs: Number.parseInt(String(t.timeoutMs ?? 30000), 10) || 30000,
    enabled: t.enabled !== false
  }));
}

function envToText(env) {
  if (!env || typeof env !== "object") {
    return "";
  }
  return Object.entries(env)
    .map(([k, v]) => `${k}=${v}`)
    .join("\n");
}

function textToEnv(text) {
  const env = {};
  String(text || "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .forEach((line) => {
      const idx = line.indexOf("=");
      if (idx > 0) {
        env[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
      }
    });
  return env;
}

export function ACPEditor({ draftConfig, mutateDraft }) {
  const acp = draftConfig.acp || { enabled: false, targets: [] };
  const enabled = Boolean(acp.enabled);
  const targets = normalizeTargets(acp.targets);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [editTarget, setEditTarget] = useState(null);
  const [probeStatus, setProbeStatus] = useState(null);
  const [isProbing, setIsProbing] = useState(false);

  const current = selectedIndex >= 0 && selectedIndex < targets.length ? targets[selectedIndex] : null;

  function startAdd() {
    setEditTarget(emptyTarget());
    setProbeStatus(null);
  }

  function startEdit(target) {
    setEditTarget({ ...target, arguments: [...target.arguments] });
    setProbeStatus(null);
  }

  function cancelEdit() {
    setEditTarget(null);
    setProbeStatus(null);
  }

  function saveEdit() {
    if (!editTarget) {
      return;
    }

    const id = String(editTarget.id || "").trim();
    const title = String(editTarget.title || "").trim();
    const command = String(editTarget.command || "").trim();
    if (!id || !title || !command) {
      return;
    }

    mutateDraft((draft) => {
      if (!draft.acp) {
        draft.acp = { enabled: false, targets: [] };
      }
      const list = normalizeTargets(draft.acp.targets);
      const existingIdx = list.findIndex((t) => t.id === id);
      const entry = {
        id,
        title,
        transport: "stdio",
        command,
        arguments: (editTarget.arguments || []).filter(Boolean),
        cwd: String(editTarget.cwd || "").trim() || undefined,
        environment: editTarget.environment || {},
        timeoutMs: editTarget.timeoutMs || 30000,
        enabled: editTarget.enabled !== false
      };
      if (existingIdx >= 0) {
        list[existingIdx] = entry;
      } else {
        list.push(entry);
      }
      draft.acp.targets = list;
    });
    setEditTarget(null);
    setProbeStatus(null);
  }

  function deleteTarget(id) {
    mutateDraft((draft) => {
      if (!draft.acp) {
        return;
      }
      draft.acp.targets = normalizeTargets(draft.acp.targets).filter((t) => t.id !== id);
    });
    if (selectedIndex >= targets.length - 1) {
      setSelectedIndex(Math.max(0, targets.length - 2));
    }
  }

  async function probeTarget() {
    const target = editTarget || current;
    if (!target) {
      return;
    }
    setIsProbing(true);
    setProbeStatus("Probing...");

    const response = await probeACPTarget({
      target: {
        id: target.id,
        title: target.title,
        transport: target.transport || "stdio",
        command: target.command,
        arguments: target.arguments || [],
        cwd: target.cwd || undefined,
        environment: target.environment || {},
        timeoutMs: target.timeoutMs || 30000,
        enabled: target.enabled !== false
      }
    });

    setIsProbing(false);
    if (!response) {
      setProbeStatus("Probe request failed.");
      return;
    }

    const r = response as any;
    if (r.ok) {
      const parts = [`Connected to ${r.agentName || "agent"}`];
      if (r.agentVersion) {
        parts[0] += ` v${r.agentVersion}`;
      }
      if (r.supportsSessionList) {
        parts.push("session/list");
      }
      setProbeStatus(parts.join(" | "));
    } else {
      setProbeStatus(String(r.message || "Probe failed."));
    }
  }

  if (editTarget) {
    return (
      <section className="entry-editor-card">
        <h3>{editTarget.id ? "Edit ACP Target" : "New ACP Target"}</h3>
        <div className="entry-form-grid">
          <label>
            ID
            <input
              placeholder="claude-code"
              value={editTarget.id}
              disabled={Boolean(current && targets.some((t) => t.id === editTarget.id))}
              onChange={(e) => setEditTarget({ ...editTarget, id: e.target.value })}
            />
          </label>
          <label>
            Title
            <input
              placeholder="Claude Code"
              value={editTarget.title}
              onChange={(e) => setEditTarget({ ...editTarget, title: e.target.value })}
            />
          </label>
          <label style={{ gridColumn: "1 / -1" }}>
            Command
            <input
              placeholder="/usr/local/bin/claude"
              value={editTarget.command}
              onChange={(e) => setEditTarget({ ...editTarget, command: e.target.value })}
            />
          </label>
          <label style={{ gridColumn: "1 / -1" }}>
            Arguments
            <input
              placeholder="--flag1 --flag2 (space-separated)"
              value={(editTarget.arguments || []).join(" ")}
              onChange={(e) =>
                setEditTarget({
                  ...editTarget,
                  arguments: e.target.value.split(/\s+/).filter(Boolean)
                })
              }
            />
          </label>
          <label>
            Working Directory
            <input
              placeholder="(defaults to workspace root)"
              value={editTarget.cwd || ""}
              onChange={(e) => setEditTarget({ ...editTarget, cwd: e.target.value })}
            />
          </label>
          <label>
            Timeout (ms)
            <input
              type="number"
              min={1000}
              step={1000}
              value={editTarget.timeoutMs}
              onChange={(e) =>
                setEditTarget({
                  ...editTarget,
                  timeoutMs: parseInt(e.target.value, 10) || 30000
                })
              }
            />
          </label>
          <label style={{ gridColumn: "1 / -1" }}>
            Environment Variables
            <textarea
              rows={3}
              placeholder="KEY=value (one per line)"
              value={envToText(editTarget.environment)}
              onChange={(e) => setEditTarget({ ...editTarget, environment: textToEnv(e.target.value) })}
            />
          </label>
          <label className="cron-form-toggle" style={{ gridColumn: "1 / -1" }}>
            <span>Enabled</span>
            <span className="agent-tools-switch">
              <input
                type="checkbox"
                checked={editTarget.enabled !== false}
                onChange={(e) => setEditTarget({ ...editTarget, enabled: e.target.checked })}
              />
              <span className="agent-tools-switch-track" />
            </span>
          </label>
        </div>

        {probeStatus && (
          <p className="placeholder-text" style={{ marginTop: 8 }}>{probeStatus}</p>
        )}

        <div className="settings-toast-actions" style={{ marginTop: 12 }}>
          <button type="button" className="hover-levitate" onClick={probeTarget} disabled={isProbing || !editTarget.command}>
            {isProbing ? "Probing..." : "Probe"}
          </button>
          <button type="button" className="danger hover-levitate" onClick={cancelEdit}>Cancel</button>
          <button
            type="button"
            className="hover-levitate"
            onClick={saveEdit}
            disabled={!editTarget.id?.trim() || !editTarget.title?.trim() || !editTarget.command?.trim()}
          >
            Save
          </button>
        </div>
      </section>
    );
  }

  return (
    <div className="tg-settings-shell">
      <section className="entry-editor-card providers-intro-card">
        <h3>ACP (Agent Client Protocol)</h3>
        <p className="placeholder-text">
          Manage ACP targets to use external coding agents (like Claude Code) through the Agent Client Protocol.
          ACP targets are launched via stdio and communicate using JSON-RPC.
        </p>
        <div className="entry-form-grid">
          <label style={{ gridColumn: "1 / -1" }}>
            ACP Gateway
            <select
              value={enabled ? "enabled" : "disabled"}
              onChange={(e) =>
                mutateDraft((draft) => {
                  if (!draft.acp) {
                    draft.acp = { enabled: false, targets: [] };
                  }
                  draft.acp.enabled = e.target.value === "enabled";
                })
              }
            >
              <option value="disabled">Disabled</option>
              <option value="enabled">Enabled</option>
            </select>
          </label>
        </div>
      </section>

      <section className="entry-editor-card">
        <div className="agent-config-head">
          <div className="agent-tools-head-copy">
            <h4>Targets ({targets.length})</h4>
          </div>
          <button type="button" className="hover-levitate" onClick={startAdd}>
            <span className="material-symbols-rounded" style={{ fontSize: 18 }}>add</span>
            Add Target
          </button>
        </div>

        {targets.length === 0 ? (
          <p className="placeholder-text">No ACP targets configured. Add one to get started.</p>
        ) : (
          <div className="agent-channels-list">
            {targets.map((target, idx) => (
              <div key={target.id} className="agent-channel-row">
                <div className="agent-channel-info">
                  <span className="agent-channel-id">
                    <span className="material-symbols-rounded agent-channel-icon">terminal</span>
                    {target.title}
                    <span style={{ opacity: 0.5, marginLeft: 8, fontSize: 12 }}>{target.id}</span>
                  </span>
                  <span style={{ fontSize: 12, opacity: 0.6 }}>
                    {target.command}
                    {!target.enabled && " (disabled)"}
                  </span>
                </div>
                <div className="agent-channel-actions" style={{ gap: 4 }}>
                  <button type="button" className="hover-levitate" onClick={() => startEdit(target)} title="Edit">
                    <span className="material-symbols-rounded" style={{ fontSize: 16 }}>edit</span>
                  </button>
                  <button type="button" className="danger hover-levitate" onClick={() => deleteTarget(target.id)} title="Delete">
                    <span className="material-symbols-rounded" style={{ fontSize: 16 }}>delete</span>
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}

        {probeStatus && (
          <p className="placeholder-text" style={{ marginTop: 8 }}>{probeStatus}</p>
        )}
      </section>
    </div>
  );
}
