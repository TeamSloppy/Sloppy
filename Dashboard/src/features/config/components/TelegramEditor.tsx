import React, { useEffect, useState } from "react";
import { fetchAgents, fetchActorsBoard } from "../../../api";
import { PendingApprovalList } from "./PendingApprovalList";
import { UserIdPicker } from "./UserIdPicker";

function TelegramIcon() {
  return (
    <svg className="tg-icon" viewBox="0 0 40 40" fill="none">
      <circle cx="20" cy="20" r="20" fill="#2AABEE" />
      <path
        d="M9 19.5L28.5 12L24.5 29L17.5 23.5L13.5 27V22.5L24 14L15 22L9 19.5Z"
        fill="white"
      />
    </svg>
  );
}

function ChevronIcon({ up }) {
  return (
    <svg
      className={`tg-chevron${up ? " tg-chevron-up" : ""}`}
      viewBox="0 0 24 24"
      fill="none"
      width="18"
      height="18"
    >
      <path
        d="M6 9L12 15L18 9"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}


interface TelegramBindingModalProps {
  agents: { id: string; displayName: string }[];
  agentChannels: { agentId: string; channelId: string }[];
  initialChannelId?: string;
  initialChatId?: number;
  onClose: () => void;
  onSave: (data: { channelId: string; chatId: number | null; originalChannelId?: string }) => void;
}

function BindingModal({ agents, agentChannels, initialChannelId, initialChatId, onClose, onSave }: TelegramBindingModalProps) {
  const isEditing = Boolean(initialChannelId);

  const initialAgentId = initialChannelId
    ? (agentChannels.find((c) => c.channelId === initialChannelId)?.agentId || agents[0]?.id || "")
    : (agents[0]?.id || "");

  const [selectedAgentId, setSelectedAgentId] = useState(initialAgentId);
  const [chatId, setChatId] = useState(initialChatId ? String(initialChatId) : "");

  const availableChannels = agentChannels.filter((ch) => ch.agentId === selectedAgentId);

  function handleSubmit() {
    if (!selectedAgentId) {
      return;
    }
    const channelId = availableChannels[0]?.channelId || selectedAgentId;
    const chatIdNum = chatId.trim() ? Number(chatId.trim()) : null;
    onSave({ channelId, chatId: chatIdNum, originalChannelId: initialChannelId });
  }

  return (
    <div className="tg-modal-overlay" onClick={onClose}>
      <div className="tg-modal" onClick={(e) => e.stopPropagation()}>
        <div className="tg-modal-header">
          <h3>{isEditing ? "Edit Binding" : "Add Binding"}</h3>
          <button type="button" className="tg-modal-close" onClick={onClose}>
            <span className="material-symbols-rounded">close</span>
          </button>
        </div>

        <div className="tg-modal-body">
          <label className="tg-modal-field">
            <span className="tg-modal-field-label">Agent</span>
            <div className="tg-select-wrap">
              <select value={selectedAgentId} onChange={(e) => setSelectedAgentId(e.target.value)}>
                {agents.map((agent) => (
                  <option key={agent.id} value={agent.id}>
                    {agent.displayName || agent.id}
                  </option>
                ))}
              </select>
              <span className="material-symbols-rounded tg-select-chevron">expand_more</span>
            </div>
          </label>

          <label className="tg-modal-field">
            <span className="tg-modal-field-label">Chat ID</span>
            <input
              value={chatId}
              onChange={(e) => setChatId(e.target.value)}
              placeholder="Optional — leave empty to accept any chat from approved users"
            />
          </label>
        </div>

        <div className="tg-modal-actions">
          <button type="button" className="tg-modal-cancel hover-levitate" onClick={onClose}>
            Cancel
          </button>
          <button type="button" className="tg-modal-submit hover-levitate" onClick={handleSubmit}>
            {isEditing ? "Save Changes" : "Add Binding"}
          </button>
        </div>
      </div>
    </div>
  );
}

export function TelegramEditor({ draftConfig, mutateDraft }) {
  const [collapsed, setCollapsed] = useState(false);
  const [showToken, setShowToken] = useState(false);
  const [editingBinding, setEditingBinding] = useState<{ channelId: string; chatId: number } | null | "new">(null);
  const [agents, setAgents] = useState([]);
  const [agentChannels, setAgentChannels] = useState([]);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      const [agentsRes, boardRes] = await Promise.all([fetchAgents(), fetchActorsBoard()]);
      if (cancelled) {
        return;
      }
      if (Array.isArray(agentsRes)) {
        setAgents(agentsRes.map((a) => ({ id: a.id, displayName: a.displayName || a.id })));
      }
      if (boardRes && Array.isArray(boardRes.nodes)) {
        const channels = boardRes.nodes
          .filter((n) => n.linkedAgentId && n.channelId)
          .map((n) => ({ agentId: n.linkedAgentId, channelId: n.channelId, nodeId: n.id }));
        setAgentChannels(channels);
      }
    }
    load().catch(() => {});
    return () => { cancelled = true; };
  }, []);

  const tg = draftConfig.channels?.telegram;
  const enabled = Boolean(tg);
  const bindings = tg ? Object.entries(tg.channelChatMap || {}) : [];

  function agentForChannel(channelId) {
    const ch = agentChannels.find((c) => c.channelId === channelId);
    if (!ch) {
      return null;
    }
    return agents.find((a) => a.id === ch.agentId) || null;
  }

  function toggleEnabled() {
    mutateDraft((draft) => {
      if (draft.channels.telegram) {
        draft.channels.telegram = null;
      } else {
        draft.channels.telegram = {
          botToken: "",
          channelChatMap: {},
          allowedUserIds: []
        };
      }
    });
  }

  function setField(field, value) {
    mutateDraft((draft) => {
      if (!draft.channels.telegram) {
        return;
      }
      draft.channels.telegram[field] = value;
    });
  }

  function handleSaveBinding({ channelId, chatId, originalChannelId }) {
    mutateDraft((draft) => {
      if (!draft.channels.telegram) {
        return;
      }
      if (originalChannelId && originalChannelId !== channelId) {
        delete draft.channels.telegram.channelChatMap[originalChannelId];
      }
      draft.channels.telegram.channelChatMap[channelId] = chatId ?? 0;
    });
    setEditingBinding(null);
  }

  function removeBinding(channelId) {
    mutateDraft((draft) => {
      if (!draft.channels.telegram) {
        return;
      }
      delete draft.channels.telegram.channelChatMap[channelId];
    });
  }

  function disconnect() {
    mutateDraft((draft) => {
      draft.channels.telegram = null;
    });
  }

  return (
    <div className="tg-card">
      <button
        type="button"
        className="tg-card-header"
        onClick={() => setCollapsed((v) => !v)}
      >
        <div className="tg-card-identity">
          <TelegramIcon />
          <div className="tg-card-meta">
            <div className="tg-card-title-row">
              <span className="tg-card-title">Telegram</span>
              {enabled && (
                <span className="tg-status-badge">
                  <span className="tg-status-dot" />
                  Active
                </span>
              )}
            </div>
            <span className="tg-card-subtitle">Telegram bot integration</span>
          </div>
        </div>
        <ChevronIcon up={!collapsed} />
      </button>

      {!collapsed && (
        <div className="tg-card-body">
          <div className="tg-row">
            <div className="tg-row-copy">
              <span className="tg-row-label">Enabled</span>
              <span className="tg-row-desc">
                {enabled ? "Telegram is receiving messages" : "Enable to start receiving messages"}
              </span>
            </div>
            <label className="agent-tools-switch">
              <input type="checkbox" checked={enabled} onChange={toggleEnabled} />
              <span className="agent-tools-switch-track" />
            </label>
          </div>

          {enabled && (
            <>
              <div className="tg-section">
                <div className="tg-section-title">Update Credentials</div>
                <div className="tg-field">
                  <span className="tg-field-label">Bot Token</span>
                  <div className="tg-token-field">
                    <input
                      type={showToken ? "text" : "password"}
                      autoComplete="off"
                      placeholder="Enter new token to update"
                      value={tg.botToken || ""}
                      onChange={(event) => setField("botToken", event.target.value)}
                    />
                    <button
                      type="button"
                      className="tg-token-reveal"
                      onClick={() => setShowToken((v) => !v)}
                    >
                      {showToken ? "Hide" : "Show"}
                    </button>
                  </div>
                  <a
                    href="https://core.telegram.org/bots#botfather"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="tg-help-link"
                  >
                    Need help? Read the Telegram setup docs →
                  </a>
                </div>
              </div>

              <div className="tg-section">
                <div className="tg-section-head">
                  <span className="tg-section-title">Bindings</span>
                  <button
                    type="button"
                    className="tg-add-btn"
                    onClick={() => setEditingBinding("new")}
                    disabled={agents.length === 0}
                  >
                    Add
                  </button>
                </div>

                {bindings.length === 0 && (
                  <p className="tg-empty">
                    No bindings yet. Add a binding to route Telegram messages to an agent.
                  </p>
                )}

                {bindings.map(([channelId, chatId]) => {
                  const agent = agentForChannel(channelId);
                  return (
                    <div key={channelId} className="tg-binding-row">
                      <div className="tg-binding-info">
                        <span className="tg-binding-name">
                          {agent ? agent.displayName : channelId}
                        </span>
                        <span className="tg-binding-desc">
                          {agent ? `channel: ${channelId}` : "unlinked channel"}
                          {chatId ? ` · chat: ${chatId}` : " · all chats"}
                        </span>
                      </div>
                      <div className="tg-binding-actions">
                        <button
                          type="button"
                          onClick={() => setEditingBinding({ channelId, chatId: chatId as number })}
                        >
                          Edit
                        </button>
                        <button type="button" onClick={() => removeBinding(channelId)}>
                          Remove
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>

              <PendingApprovalList platform="telegram" />

              <div className="tg-section">
                <div className="tg-section-title">Access Control</div>
                <div className="tg-field">
                  <label className="tg-field-label">
                    Allowed User IDs
                    <span className="tg-field-hint">
                      Search approved users or type IDs manually — leave empty to use the approval flow
                    </span>
                  </label>
                  <UserIdPicker
                    platform="telegram"
                    selectedIds={(tg.allowedUserIds || []).map(String)}
                    onChange={(ids) => setField("allowedUserIds", ids.map(Number).filter(Number.isFinite))}
                  />
                </div>
              </div>

              <div className="tg-footer">
                <button type="button" className="tg-disconnect-btn" onClick={disconnect}>
                  Disconnect Telegram
                </button>
              </div>
            </>
          )}
        </div>
      )}

      {editingBinding !== null && (
        <BindingModal
          agents={agents}
          agentChannels={agentChannels}
          initialChannelId={editingBinding !== "new" ? editingBinding.channelId : undefined}
          initialChatId={editingBinding !== "new" ? editingBinding.chatId : undefined}
          onClose={() => setEditingBinding(null)}
          onSave={handleSaveBinding}
        />
      )}
    </div>
  );
}
