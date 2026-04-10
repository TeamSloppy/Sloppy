import React, { useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { fetchActorsBoard, fetchAgentConfig, fetchRuntimeConfig, updateAgentConfig, deleteAgent } from "../../../api";
import {
  coerceLegacySloppyModelId,
  collectAggregatedProviderModels,
  filterModelsByQuery
} from "../utils/aggregateProviderModels";
import { ChannelModelSelector } from "./ChannelModelSelector";

const AGENT_CONFIG_SECTIONS = [
  { id: "runtime", title: "Runtime", icon: "smart_toy" },
  { id: "models", title: "Models", icon: "hub" },
  { id: "files", title: "Agent Files", icon: "description" },
  { id: "channel", title: "Channel", icon: "forum" },
  { id: "heartbeat", title: "Heartbeat", icon: "monitor_heart" },
  { id: "danger", title: "Danger Zone", icon: "warning", danger: true }
];

function emptyAgentConfigDraft(agentId) {
  return {
    agentId,
    selectedModel: "",
    availableModels: [],
    documents: {
      userMarkdown: "",
      agentsMarkdown: "",
      soulMarkdown: "",
      identityMarkdown: "",
      heartbeatMarkdown: "",
      memoryMarkdown: ""
    },
    heartbeat: {
      enabled: false,
      intervalMinutes: 5
    },
    channelSessions: {
      autoCloseEnabled: false,
      autoCloseAfterMinutes: 30
    },
    heartbeatStatus: {
      lastRunAt: null,
      lastSuccessAt: null,
      lastFailureAt: null,
      lastResult: "",
      lastErrorMessage: "",
      lastSessionId: ""
    },
    runtime: {
      type: "native",
      acp: null
    }
  };
}

function normalizeConfigDraft(agentId, config) {
  return {
    agentId: config.agentId || agentId,
    selectedModel: coerceLegacySloppyModelId(String(config.selectedModel || "")),
    availableModels: Array.isArray(config.availableModels) ? config.availableModels : [],
    documents: {
      userMarkdown: String(config.documents?.userMarkdown || ""),
      agentsMarkdown: String(config.documents?.agentsMarkdown || ""),
      soulMarkdown: String(config.documents?.soulMarkdown || ""),
      identityMarkdown: String(config.documents?.identityMarkdown || ""),
      heartbeatMarkdown: String(config.documents?.heartbeatMarkdown || ""),
      memoryMarkdown: String(config.documents?.memoryMarkdown || "")
    },
    heartbeat: {
      enabled: Boolean(config.heartbeat?.enabled),
      intervalMinutes: Number.parseInt(String(config.heartbeat?.intervalMinutes ?? 5), 10) || 5
    },
    channelSessions: {
      autoCloseEnabled: Boolean(config.channelSessions?.autoCloseEnabled),
      autoCloseAfterMinutes: Number.parseInt(String(config.channelSessions?.autoCloseAfterMinutes ?? 30), 10) || 30
    },
    heartbeatStatus: {
      lastRunAt: config.heartbeatStatus?.lastRunAt || null,
      lastSuccessAt: config.heartbeatStatus?.lastSuccessAt || null,
      lastFailureAt: config.heartbeatStatus?.lastFailureAt || null,
      lastResult: String(config.heartbeatStatus?.lastResult || ""),
      lastErrorMessage: String(config.heartbeatStatus?.lastErrorMessage || ""),
      lastSessionId: String(config.heartbeatStatus?.lastSessionId || "")
    },
    runtime: {
      type: String(config.runtime?.type || "native"),
      acp: config.runtime?.acp
        ? {
            targetId: String(config.runtime.acp.targetId || ""),
            cwd: config.runtime.acp.cwd || null
          }
        : null
    }
  };
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function formatDateTime(value) {
  if (!value) {
    return "Never";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "Never";
  }

  return date.toLocaleString([], {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  });
}

function statusValue(value, fallback = "None") {
  const normalized = String(value || "").trim();
  return normalized || fallback;
}

const AGENT_DOC_FILES = [
  { id: "userMarkdown", name: "USER.md", icon: "person" },
  { id: "agentsMarkdown", name: "AGENTS.md", icon: "smart_toy" },
  { id: "soulMarkdown", name: "SOUL.md", icon: "psychology" },
  { id: "identityMarkdown", name: "IDENTITY.md", icon: "badge" },
  { id: "memoryMarkdown", name: "MEMORY.md", icon: "neurology", readOnly: true }
];

export function AgentConfigTab({ agentId, agentDisplayName = "", onDeleteAgent = null }) {
  const [draft, setDraft] = useState(() => emptyAgentConfigDraft(agentId));
  const [savedDraft, setSavedDraft] = useState(() => emptyAgentConfigDraft(agentId));
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [statusText, setStatusText] = useState("Loading agent config...");
  const [channelNodes, setChannelNodes] = useState([]);
  const [selectedSection, setSelectedSection] = useState("runtime");
  const [acpTargets, setAcpTargets] = useState([]);
  const [selectedDocFile, setSelectedDocFile] = useState("userMarkdown");
  const [deleteConfirmOpen, setDeleteConfirmOpen] = useState(false);
  const [deleteConfirmText, setDeleteConfirmText] = useState("");
  const [isDeleting, setIsDeleting] = useState(false);
  const [aggregatedModels, setAggregatedModels] = useState([]);
  const [modelCatalogStatus, setModelCatalogStatus] = useState("");
  const [defaultModelMenuOpen, setDefaultModelMenuOpen] = useState(false);
  const [defaultModelMenuRect, setDefaultModelMenuRect] = useState(null);
  const [modelPickerQuery, setModelPickerQuery] = useState("");
  const defaultModelPickerRef = useRef(null);
  const defaultModelMenuRef = useRef(null);

  useEffect(() => {
    let isCancelled = false;

    async function load() {
      setIsLoading(true);
      setStatusText("Loading agent config...");
      setAggregatedModels([]);
      setModelCatalogStatus("Loading model catalog...");
      const [response, board, runtimeCfg] = await Promise.all([
        fetchAgentConfig(agentId),
        fetchActorsBoard(),
        fetchRuntimeConfig()
      ]);
      if (isCancelled) {
        return;
      }

      if (board && Array.isArray(board.nodes)) {
        setChannelNodes(board.nodes.filter((n) => n.linkedAgentId === agentId));
      }

      if (runtimeCfg && Array.isArray((runtimeCfg as any).acp?.targets)) {
        setAcpTargets((runtimeCfg as any).acp.targets.filter((t) => t.enabled !== false));
      }

      let catalog = [];
      let catalogLoadError = false;
      if (runtimeCfg) {
        try {
          catalog = await collectAggregatedProviderModels(runtimeCfg as Record<string, unknown>);
        } catch {
          catalogLoadError = true;
        }
      }
      if (isCancelled) {
        return;
      }

      setAggregatedModels(catalog);
      if (catalogLoadError) {
        setModelCatalogStatus("Failed to load provider model catalogs.");
      } else if (catalog.length === 0) {
        const modelsField = runtimeCfg ? (runtimeCfg as Record<string, unknown>).models : undefined;
        const hasModelEntries =
          runtimeCfg && Array.isArray(modelsField) && modelsField.length > 0;
        setModelCatalogStatus(
          hasModelEntries
            ? "Could not list models from configured providers. Check API keys in Settings."
            : "No models found. Configure providers in Settings."
        );
      } else {
        setModelCatalogStatus("");
      }

      if (!response) {
        const empty = emptyAgentConfigDraft(agentId);
        setDraft(empty);
        setSavedDraft(clone(empty));
        setStatusText("Failed to load config.");
        setIsLoading(false);
        return;
      }

      const normalized = normalizeConfigDraft(agentId, response);
      setDraft(normalized);
      setSavedDraft(clone(normalized));
      setStatusText("Config loaded.");
      setIsLoading(false);
    }

    load().catch(() => {
      if (!isCancelled) {
        setStatusText("Failed to load config.");
        setModelCatalogStatus("Failed to load provider model catalogs.");
        setIsLoading(false);
      }
    });

    return () => {
      isCancelled = true;
    };
  }, [agentId]);

  useEffect(() => {
    if (!defaultModelMenuOpen) {
      setModelPickerQuery(String(draft.selectedModel || ""));
    }
  }, [defaultModelMenuOpen, draft.selectedModel]);

  useEffect(() => {
    if (!defaultModelMenuOpen) {
      return;
    }

    function syncDefaultModelMenuRect() {
      const picker = defaultModelPickerRef.current;
      if (!picker) {
        return;
      }
      const rect = picker.getBoundingClientRect();
      const viewportHeight = window.innerHeight || document.documentElement.clientHeight;
      const viewportPadding = 10;
      const menuGap = 6;
      const defaultMaxHeight = 260;
      const minMaxHeight = 140;
      const spaceBelow = viewportHeight - rect.bottom - viewportPadding;
      const spaceAbove = rect.top - viewportPadding;

      let maxHeight = Math.max(minMaxHeight, Math.min(defaultMaxHeight, spaceBelow));
      let top = rect.bottom + menuGap;
      if (spaceBelow < minMaxHeight && spaceAbove > spaceBelow) {
        maxHeight = Math.max(minMaxHeight, Math.min(defaultMaxHeight, spaceAbove - menuGap));
        top = rect.top - menuGap - maxHeight;
      }
      top = Math.max(viewportPadding, Math.round(top));

      setDefaultModelMenuRect({
        top,
        left: Math.round(rect.left),
        width: Math.round(rect.width),
        maxHeight: Math.round(maxHeight)
      });
    }

    function handlePointerDown(event) {
      const target = event.target;
      const pickerContainsTarget = defaultModelPickerRef.current?.contains(target);
      const menuContainsTarget = defaultModelMenuRef.current?.contains(target);
      if (!pickerContainsTarget && !menuContainsTarget) {
        setDefaultModelMenuOpen(false);
        setDefaultModelMenuRect(null);
      }
    }

    syncDefaultModelMenuRect();
    window.addEventListener("resize", syncDefaultModelMenuRect);
    window.addEventListener("scroll", syncDefaultModelMenuRect, true);
    window.addEventListener("pointerdown", handlePointerDown);
    return () => {
      window.removeEventListener("resize", syncDefaultModelMenuRect);
      window.removeEventListener("scroll", syncDefaultModelMenuRect, true);
      window.removeEventListener("pointerdown", handlePointerDown);
    };
  }, [defaultModelMenuOpen]);

  const hasChanges = useMemo(() => {
    return JSON.stringify(draft) !== JSON.stringify(savedDraft);
  }, [draft, savedDraft]);

  const defaultModelOptions = useMemo(() => {
    const selected = String(draft.selectedModel || "").trim();
    const base = aggregatedModels.slice();
    if (selected && !base.some((m) => m.id === selected)) {
      base.unshift({ id: selected, title: selected });
    }
    return base;
  }, [aggregatedModels, draft.selectedModel]);

  const filteredDefaultModels = useMemo(
    () => filterModelsByQuery(defaultModelOptions, modelPickerQuery),
    [defaultModelOptions, modelPickerQuery]
  );

  function updateField(field, value) {
    setDraft((previous) => ({
      ...previous,
      [field]: value
    }));
  }

  function updateDocumentField(field, value) {
    setDraft((previous) => ({
      ...previous,
      documents: {
        ...previous.documents,
        [field]: value
      }
    }));
  }

  function updateHeartbeatField(field, value) {
    setDraft((previous) => ({
      ...previous,
      heartbeat: {
        ...previous.heartbeat,
        [field]: value
      }
    }));
  }

  function updateChannelSessionField(field, value) {
    setDraft((previous) => ({
      ...previous,
      channelSessions: {
        ...previous.channelSessions,
        [field]: value
      }
    }));
  }

  function updateRuntimeType(type) {
    setDraft((previous) => ({
      ...previous,
      runtime: {
        type,
        acp: type === "acp" ? (previous.runtime.acp || { targetId: "", cwd: null }) : null
      }
    }));
  }

  function updateRuntimeACPField(field, value) {
    setDraft((previous) => ({
      ...previous,
      runtime: {
        ...previous.runtime,
        acp: {
          ...(previous.runtime.acp || { targetId: "", cwd: null }),
          [field]: value
        }
      }
    }));
  }

  function cancelChanges() {
    setDraft(clone(savedDraft));
    setStatusText("Changes cancelled.");
  }

  async function saveConfig() {
    if (isSaving) {
      return;
    }

    const runtimeType = draft.runtime?.type || "native";
    const selectedModel = coerceLegacySloppyModelId(String(draft.selectedModel || "").trim());
    if (runtimeType === "native" && !selectedModel) {
      setStatusText("Model is required for native runtime.");
      return;
    }
    if (runtimeType === "acp" && !draft.runtime?.acp?.targetId?.trim()) {
      setStatusText("ACP target is required.");
      return;
    }

    const intervalMinutes = Number.parseInt(String(draft.heartbeat.intervalMinutes || 0), 10);
    if (draft.heartbeat.enabled && (!Number.isFinite(intervalMinutes) || intervalMinutes < 1)) {
      setStatusText("Heartbeat interval must be at least 1 minute.");
      return;
    }
    const autoCloseAfterMinutes = Number.parseInt(String(draft.channelSessions.autoCloseAfterMinutes || 0), 10);
    if (draft.channelSessions.autoCloseEnabled && (!Number.isFinite(autoCloseAfterMinutes) || autoCloseAfterMinutes < 1)) {
      setStatusText("Channel session timeout must be at least 1 minute.");
      return;
    }

    const runtime = { type: runtimeType };
    if (runtimeType === "acp" && draft.runtime?.acp) {
      (runtime as any).acp = {
        targetId: draft.runtime.acp.targetId,
        cwd: draft.runtime.acp.cwd || undefined
      };
    }

    const payload = {
      selectedModel: runtimeType === "native" ? selectedModel : null,
      documents: {
        userMarkdown: String(draft.documents.userMarkdown || ""),
        agentsMarkdown: String(draft.documents.agentsMarkdown || ""),
        soulMarkdown: String(draft.documents.soulMarkdown || ""),
        identityMarkdown: String(draft.documents.identityMarkdown || ""),
        heartbeatMarkdown: String(draft.documents.heartbeatMarkdown || ""),
        memoryMarkdown: String(draft.documents.memoryMarkdown || "")
      },
      heartbeat: {
        enabled: Boolean(draft.heartbeat.enabled),
        intervalMinutes: intervalMinutes || 5
      },
      channelSessions: {
        autoCloseEnabled: Boolean(draft.channelSessions.autoCloseEnabled),
        autoCloseAfterMinutes: autoCloseAfterMinutes || 30
      },
      runtime
    };

    setIsSaving(true);
    try {
      const response = await updateAgentConfig(agentId, payload);
      const normalized = normalizeConfigDraft(agentId, response);
      setDraft(normalized);
      setSavedDraft(clone(normalized));
      setStatusText("Config saved.");
    } catch (err) {
      setStatusText(err instanceof Error ? err.message : "Failed to save config.");
    }
    setIsSaving(false);
  }

  const isACP = draft.runtime?.type === "acp";

  async function handleDeleteAgent() {
    if (isDeleting) return;
    setIsDeleting(true);
    const ok = await deleteAgent(agentId);
    if (ok) {
      onDeleteAgent?.();
    } else {
      setStatusText("Failed to delete agent.");
      setIsDeleting(false);
      setDeleteConfirmOpen(false);
      setDeleteConfirmText("");
    }
  }

  function renderDangerSection() {
    const confirmName = agentDisplayName || agentId;
    return (
      <section className="entry-editor-card settings-danger-zone">
        <h3 style={{ color: "var(--danger, #ef4444)" }}>Danger Zone</h3>
        <div className="settings-danger-block">
          <div className="settings-danger-info">
            <strong>Delete this agent</strong>
            <p>
              Once you delete an agent, there is no going back. All sessions, memories, and configuration will be permanently removed.
            </p>
          </div>
          {!deleteConfirmOpen ? (
            <button
              type="button"
              className="danger hover-levitate"
              onClick={() => {
                setDeleteConfirmOpen(true);
                setDeleteConfirmText("");
              }}
            >
              Delete Agent
            </button>
          ) : (
            <div className="settings-danger-confirm">
              <p className="settings-danger-warning">
                <span className="material-symbols-rounded" style={{ fontSize: "1rem", verticalAlign: "middle" }}>warning</span>
                {" "}This action is irreversible. All agent data will be permanently deleted.
              </p>
              <label>
                Type <strong>{confirmName}</strong> to confirm
                <input
                  type="text"
                  value={deleteConfirmText}
                  onChange={(e) => setDeleteConfirmText(e.target.value)}
                  placeholder={confirmName}
                  autoFocus
                />
              </label>
              <div className="settings-danger-confirm-actions">
                <button
                  type="button"
                  onClick={() => {
                    setDeleteConfirmOpen(false);
                    setDeleteConfirmText("");
                  }}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  className="danger hover-levitate"
                  disabled={deleteConfirmText.trim() !== confirmName || isDeleting}
                  onClick={handleDeleteAgent}
                >
                  {isDeleting ? "Deleting..." : "I understand, delete this agent"}
                </button>
              </div>
            </div>
          )}
        </div>
      </section>
    );
  }

  function renderSectionContent() {
    if (selectedSection === "runtime") {
      return (
        <section className="entry-editor-card">
          <h3>Agent Runtime</h3>
          <p className="placeholder-text">
            Choose how this agent processes messages. <strong>Native</strong> uses the built-in Sloppy runtime with a selected model.{" "}
            <strong>ACP</strong> delegates to an external agent (e.g. Claude Code) via the Agent Client Protocol.
          </p>
          <div className="entry-form-grid">
            <label style={{ gridColumn: "1 / -1" }}>
              Runtime Type
              <select
                value={draft.runtime?.type || "native"}
                onChange={(e) => updateRuntimeType(e.target.value)}
              >
                <option value="native">Native</option>
                <option value="acp">ACP (Agent Client Protocol)</option>
              </select>
            </label>

            {isACP && (
              <>
                <label style={{ gridColumn: "1 / -1" }}>
                  ACP Target
                  <select
                    value={draft.runtime?.acp?.targetId || ""}
                    onChange={(e) => updateRuntimeACPField("targetId", e.target.value)}
                  >
                    <option value="">Select a target...</option>
                    {acpTargets.map((t) => (
                      <option key={t.id} value={t.id}>
                        {t.title} ({t.id})
                      </option>
                    ))}
                  </select>
                  {acpTargets.length === 0 && (
                    <span className="entry-form-hint">No ACP targets configured. Add targets in Settings &gt; ACP.</span>
                  )}
                </label>
                <label style={{ gridColumn: "1 / -1" }}>
                  Working Directory Override
                  <input
                    placeholder="(defaults to target cwd or workspace root)"
                    value={draft.runtime?.acp?.cwd || ""}
                    onChange={(e) => updateRuntimeACPField("cwd", e.target.value || null)}
                  />
                </label>
              </>
            )}
          </div>
        </section>
      );
    }

    if (selectedSection === "models") {
      return (
        <section className="entry-editor-card">
          <h3>Models</h3>
          <div className="entry-form-grid">
            <label style={{ gridColumn: "1 / -1" }}>
              Default Model
              <div ref={defaultModelPickerRef} className="provider-model-picker">
                <input
                  value={modelPickerQuery}
                  onFocus={() => setDefaultModelMenuOpen(true)}
                  onClick={() => setDefaultModelMenuOpen(true)}
                  onChange={(event) => setModelPickerQuery(event.target.value)}
                  placeholder="Select model id..."
                  disabled={isSaving}
                  autoComplete="off"
                />
              </div>
              {modelCatalogStatus ? (
                <span className="entry-form-hint" style={{ gridColumn: "1 / -1" }}>
                  {modelCatalogStatus}
                </span>
              ) : null}
            </label>
          </div>

          {channelNodes.length > 0 && (
            <>
              <div className="agent-config-head" style={{ marginTop: 16 }}>
                <div className="agent-tools-head-copy">
                  <h4>Channel Models</h4>
                  <p className="placeholder-text">
                    Override the model used for specific channels. Channels without an override use the agent default above.
                  </p>
                </div>
              </div>
              <div className="agent-channels-list">
                {channelNodes.map((node) => {
                  const channelId = node.channelId || node.id;
                  return (
                    <div key={node.id} className="agent-channel-row">
                      <div className="agent-channel-info">
                        <span className="agent-channel-id">
                          <span className="material-symbols-rounded agent-channel-icon">forum</span>
                          {channelId}
                        </span>
                      </div>
                      <div className="agent-channel-actions">
                        <ChannelModelSelector channelId={channelId} />
                      </div>
                    </div>
                  );
                })}
              </div>
            </>
          )}
        </section>
      );
    }

    if (selectedSection === "files") {
      const activeFile = AGENT_DOC_FILES.find((f) => f.id === selectedDocFile) || AGENT_DOC_FILES[0];
      return (
        <section className="entry-editor-card">
          <h3>Agent Files</h3>
          <div className="agent-doc-files">
            <nav className="agent-doc-files-nav">
              {AGENT_DOC_FILES.map((file) => {
                const isActive = file.id === activeFile.id;
                const hasContent = Boolean(draft.documents[file.id]?.trim());
                return (
                  <button
                    key={file.id}
                    type="button"
                    className={`agent-doc-files-item ${isActive ? "active" : ""}`}
                    onClick={() => setSelectedDocFile(file.id)}
                  >
                    <span className="material-symbols-rounded agent-doc-files-icon">{file.icon}</span>
                    <span className="agent-doc-files-name">{file.name}</span>
                    {!hasContent && <span className="agent-doc-files-empty">empty</span>}
                  </button>
                );
              })}
            </nav>
            <div className="agent-doc-files-editor">
              <label>
                {activeFile.name}
                {activeFile.readOnly && (
                  <span className="agent-doc-files-readonly-badge"> [Read-Only]</span>
                )}
                <textarea
                  rows={18}
                  value={draft.documents[activeFile.id]}
                  onChange={(event) => updateDocumentField(activeFile.id, event.target.value)}
                  readOnly={activeFile.readOnly}
                  className={activeFile.readOnly ? "readonly-textarea" : ""}
                />
              </label>
            </div>
          </div>
        </section>
      );
    }

    if (selectedSection === "channel") {
      return (
        <section className="entry-editor-card">
          <h3>Channel Sessions</h3>
          <p className="placeholder-text">
            Automatically close inactive incoming channel sessions and start a new one on the next message.
          </p>
          <div className="entry-form-grid">
            <label className="cron-form-toggle" style={{ gridColumn: "1 / -1" }}>
              <span>Close session after</span>
              <span className="agent-tools-switch">
                <input
                  type="checkbox"
                  checked={draft.channelSessions.autoCloseEnabled}
                  onChange={(event) => updateChannelSessionField("autoCloseEnabled", event.target.checked)}
                />
                <span className="agent-tools-switch-track" />
              </span>
            </label>
            <label>
              Timeout (minutes)
              <input
                type="number"
                min="1"
                step="1"
                value={draft.channelSessions.autoCloseAfterMinutes}
                onChange={(event) => updateChannelSessionField("autoCloseAfterMinutes", event.target.value)}
              />
            </label>
          </div>
        </section>
      );
    }

    if (selectedSection === "danger") {
      return renderDangerSection();
    }

    if (selectedSection === "heartbeat") {
      return (
        <section className="entry-editor-card">
          <h3>Heartbeat</h3>
          <p className="placeholder-text">
            Runs `HEARTBEAT.md` on a timer and expects exactly `SLOPPY_ACTION_OK` on success.
          </p>
          <div className="entry-form-grid">
            <label className="cron-form-toggle" style={{ gridColumn: "1 / -1" }}>
              <span>Enabled</span>
              <span className="agent-tools-switch">
                <input
                  type="checkbox"
                  checked={draft.heartbeat.enabled}
                  onChange={(event) => updateHeartbeatField("enabled", event.target.checked)}
                />
                <span className="agent-tools-switch-track" />
              </span>
            </label>
            <label>
              Interval (minutes)
              <input
                type="number"
                min="1"
                step="1"
                value={draft.heartbeat.intervalMinutes}
                onChange={(event) => updateHeartbeatField("intervalMinutes", event.target.value)}
              />
            </label>
            <label style={{ gridColumn: "1 / -1" }}>
              HEARTBEAT.md
              <textarea
                rows={10}
                value={draft.documents.heartbeatMarkdown}
                onChange={(event) => updateDocumentField("heartbeatMarkdown", event.target.value)}
                placeholder="Describe what the automated heartbeat should verify."
              />
            </label>
          </div>

          <div className="agent-config-heartbeat-status" style={{ marginTop: 12 }}>
            <div>
              <strong>Last run:</strong> {formatDateTime(draft.heartbeatStatus.lastRunAt)}
            </div>
            <div>
              <strong>Last success:</strong> {formatDateTime(draft.heartbeatStatus.lastSuccessAt)}
            </div>
            <div>
              <strong>Last failure:</strong> {formatDateTime(draft.heartbeatStatus.lastFailureAt)}
            </div>
            <div>
              <strong>Last result:</strong> {statusValue(draft.heartbeatStatus.lastResult)}
            </div>
            <div>
              <strong>Last session:</strong> {statusValue(draft.heartbeatStatus.lastSessionId)}
            </div>
            <div>
              <strong>Last error:</strong> {statusValue(draft.heartbeatStatus.lastErrorMessage)}
            </div>
          </div>
        </section>
      );
    }

    return null;
  }

  return (
    <>
    <main className="settings-shell">
      <aside className="settings-side">
        <div className="settings-title-row">
          <h2>Agent Config</h2>
        </div>

        <div className="settings-nav">
          {AGENT_CONFIG_SECTIONS.map((item) => (
            <button
              key={item.id}
              type="button"
              className={`settings-nav-item ${selectedSection === item.id ? "active" : ""}${(item as any).danger ? " settings-nav-item--danger" : ""}`}
              onClick={() => setSelectedSection(item.id)}
            >
              <span className="material-symbols-rounded settings-nav-icon">{item.icon}</span>
              <span>{item.title}</span>
            </button>
          ))}
        </div>
      </aside>

      <section className="settings-main">
        <header className="settings-main-head">
          <div className="settings-main-status">
            <span>{statusText}</span>
          </div>
        </header>

        <div className={`settings-toast ${hasChanges ? "settings-toast--visible" : ""}`}>
          <span className="settings-toast-label">Unsaved changes</span>
          <div className="settings-toast-actions">
            <button type="button" className="danger hover-levitate" onClick={cancelChanges}>
              Cancel
            </button>
            <button type="button" className="hover-levitate" onClick={saveConfig} disabled={isSaving}>
              {isSaving ? "Saving..." : "Apply"}
            </button>
          </div>
        </div>

        {isLoading ? (
          <p className="placeholder-text">Loading...</p>
        ) : (
          renderSectionContent()
        )}
      </section>
    </main>
    {defaultModelMenuOpen && defaultModelMenuRect
      ? createPortal(
          <div
            ref={defaultModelMenuRef}
            className="provider-model-picker-menu provider-model-picker-menu-floating"
            style={{
              top: `${defaultModelMenuRect.top}px`,
              left: `${defaultModelMenuRect.left}px`,
              width: `${defaultModelMenuRect.width}px`
            }}
          >
            <div className="provider-model-picker-group">Available models</div>
            <div
              className="provider-model-options"
              style={{ maxHeight: `${defaultModelMenuRect.maxHeight}px` }}
            >
              {filteredDefaultModels.length === 0 ? (
                <div className="placeholder-text" style={{ padding: "10px 12px" }}>
                  No matching models
                </div>
              ) : (
                filteredDefaultModels.map((model) => (
                  <button
                    key={model.id}
                    type="button"
                    className={`provider-model-option ${draft.selectedModel === model.id ? "active" : ""}`}
                    onMouseDown={(event) => event.preventDefault()}
                    onClick={() => {
                      updateField("selectedModel", model.id);
                      setModelPickerQuery(model.id);
                      setDefaultModelMenuOpen(false);
                      setDefaultModelMenuRect(null);
                    }}
                  >
                    <div className="provider-model-option-main">
                      <strong>{model.title || model.id}</strong>
                      {model.contextWindow ? (
                        <span className="provider-model-context">{model.contextWindow}</span>
                      ) : null}
                    </div>
                    <span>{model.id}</span>
                    {Array.isArray(model.capabilities) && model.capabilities.length > 0 ? (
                      <div className="provider-model-capabilities">
                        {model.capabilities.map((capability) => (
                          <span key={`${model.id}-${capability}`}>{capability}</span>
                        ))}
                      </div>
                    ) : null}
                  </button>
                ))
              )}
            </div>
          </div>,
          document.body
        )
      : null}
    </>
  );
}
