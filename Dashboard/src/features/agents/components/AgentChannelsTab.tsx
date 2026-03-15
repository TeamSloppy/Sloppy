import React, { useCallback, useEffect, useMemo, useState } from "react";
import { createActorNode, deleteActorNode, fetchActorsBoard, fetchChannelSessions, fetchChannelSession } from "../../../api";
import { ChannelModelSelector } from "./ChannelModelSelector";

const CHANNEL_MESSAGES_LIMIT = 9;

const USER_COLORS = [
  "#c084fc", "#67e8f9", "#f472b6", "#fbbf24", "#6ee7b7",
  "#fb923c", "#a78bfa", "#38bdf8", "#f87171", "#a3e635"
];

function slugify(value: string) {
  return value
    .toLowerCase()
    .replace(/\s+/g, "-")
    .replace(/[^a-z0-9\-_:]/g, "");
}

function userColor(name: string) {
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = name.charCodeAt(i) + ((hash << 5) - hash);
  }
  return USER_COLORS[Math.abs(hash) % USER_COLORS.length];
}

function formatRelativeTime(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "just now";
  }
  const diffMinutes = Math.max(0, Math.round((Date.now() - date.getTime()) / 60000));
  if (diffMinutes < 1) {
    return "just now";
  }
  if (diffMinutes < 60) {
    return `${diffMinutes}m ago`;
  }
  const diffHours = Math.round(diffMinutes / 60);
  if (diffHours < 24) {
    return `${diffHours}h ago`;
  }
  return `${Math.round(diffHours / 24)}d ago`;
}

function formatCompactTime(dateValue: string) {
  const date = new Date(dateValue);
  if (Number.isNaN(date.getTime())) return "";
  let hours = date.getHours();
  const minutes = String(date.getMinutes()).padStart(2, "0");
  const suffix = hours >= 12 ? "p" : "a";
  hours = hours % 12 || 12;
  return `${hours}:${minutes}${suffix}`;
}

function extractSessionMessages(sessionDetail: any) {
  const events = Array.isArray(sessionDetail?.events) ? sessionDetail.events : [];
  return events
    .filter((e: any) => {
      const type = String(e?.type || "");
      return type === "user_message" || type === "assistant_message";
    })
    .map((e: any) => {
      const type = String(e?.type || "");
      const isBot = type === "assistant_message";
      return {
        id: String(e?.id || ""),
        userId: isBot ? "bot" : String(e?.userId || "user"),
        content: String(e?.content || "").replace(/\s+/g, " ").trim(),
        createdAt: e?.createdAt || "",
        isBot
      };
    });
}

export function AgentChannelsTab({ agentId, agentDisplayName, onNavigateToChannelSession = null }) {
  const [nodes, setNodes] = useState([]);
  const [activeSessions, setActiveSessions] = useState([]);
  const [sessionDetails, setSessionDetails] = useState<Record<string, any>>({});
  const [statusText, setStatusText] = useState("Loading channels...");
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [newChannelId, setNewChannelId] = useState("");
  const [formError, setFormError] = useState("");

  async function loadSessionDetails(sessions: any[]) {
    if (sessions.length === 0) {
      setSessionDetails({});
      return;
    }
    const results = await Promise.all(
      sessions.map((s) => {
        const sid = String(s?.sessionId || "").trim();
        return sid ? fetchChannelSession(sid).catch(() => null) : Promise.resolve(null);
      })
    );
    const details: Record<string, any> = {};
    for (let i = 0; i < sessions.length; i++) {
      const sid = String(sessions[i]?.sessionId || "").trim();
      if (sid && results[i]) {
        details[sid] = results[i];
      }
    }
    setSessionDetails(details);
  }

  function updateStatusText(nodeCount: number, sessionCount: number) {
    setStatusText(
      `${nodeCount} channel${nodeCount !== 1 ? "s" : ""} · ` +
      `${sessionCount} active session${sessionCount !== 1 ? "s" : ""}`
    );
  }

  useEffect(() => {
    let cancelled = false;

    async function load() {
      setIsLoading(true);
      const [board, sessions] = await Promise.all([
        fetchActorsBoard(),
        fetchChannelSessions({ status: "open", agentId })
      ]);
      if (cancelled) {
        return;
      }
      if (!board || !Array.isArray(board.nodes)) {
        setNodes([]);
        setActiveSessions([]);
        setSessionDetails({});
        setStatusText("Failed to load channels.");
        setIsLoading(false);
        return;
      }
      const agentNodes = board.nodes.filter((n) => n.linkedAgentId === agentId);
      setNodes(agentNodes);
      const nextSessions = Array.isArray(sessions) ? sessions : [];
      setActiveSessions(nextSessions);
      updateStatusText(agentNodes.length, nextSessions.length);
      await loadSessionDetails(nextSessions);
      if (!cancelled) setIsLoading(false);
    }

    load().catch(() => {
      if (!cancelled) {
        setNodes([]);
        setActiveSessions([]);
        setSessionDetails({});
        setStatusText("Failed to load channels.");
        setIsLoading(false);
      }
    });

    return () => {
      cancelled = true;
    };
  }, [agentId]);

  async function refreshData() {
    const [board, sessions] = await Promise.all([
      fetchActorsBoard(),
      fetchChannelSessions({ status: "open", agentId })
    ]);
    if (!board || !Array.isArray(board.nodes)) {
      return;
    }
    const agentNodes = board.nodes.filter((n) => n.linkedAgentId === agentId);
    setNodes(agentNodes);
    const nextSessions = Array.isArray(sessions) ? sessions : [];
    setActiveSessions(nextSessions);
    updateStatusText(agentNodes.length, nextSessions.length);
    await loadSessionDetails(nextSessions);
  }

  async function addChannel() {
    const channelId = slugify(newChannelId);
    if (!channelId) {
      setFormError("Channel ID is required.");
      return;
    }
    const alreadyExists = nodes.some((n) => n.channelId === channelId);
    if (alreadyExists) {
      setFormError("A channel with this ID is already linked to this agent.");
      return;
    }

    setIsSaving(true);
    setFormError("");

    const nodeId = `actor:${agentId}:${channelId}`;
    const payload = {
      id: nodeId,
      displayName: agentDisplayName || agentId,
      kind: "agent",
      linkedAgentId: agentId,
      channelId,
      positionX: 120 + nodes.length * 220,
      positionY: 120,
      createdAt: new Date().toISOString()
    };

    const result = await createActorNode(payload);
    setIsSaving(false);

    if (!result) {
      setFormError("Failed to create channel. The ID may already be taken.");
      return;
    }

    await refreshData();
    setNewChannelId("");
    setShowForm(false);
  }

  async function removeChannel(nodeId) {
    const ok = await deleteActorNode(nodeId);
    if (!ok) {
      return;
    }
    setNodes((previous) => {
      const next = previous.filter((n) => n.id !== nodeId);
      setStatusText(
        `${next.length} channel${next.length !== 1 ? "s" : ""} · ` +
        `${activeSessions.length} active session${activeSessions.length !== 1 ? "s" : ""}`
      );
      return next;
    });
    await refreshData();
  }

  function handleFormKeyDown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      void addChannel();
    }
    if (event.key === "Escape") {
      setShowForm(false);
      setNewChannelId("");
      setFormError("");
    }
  }

  return (
    <section className="agent-config-shell agent-channels-shell">
      <div className="agent-config-head">
        <div className="agent-tools-head-copy">
          <h3>Channels</h3>
          <p className="placeholder-text">Channel IDs this agent is available in for receiving messages.</p>
        </div>
        <span className="agent-tools-status">{statusText}</span>
      </div>

      {isLoading ? (
        <p className="placeholder-text">Loading...</p>
      ) : (
        <>
          {nodes.length === 0 && !showForm ? (
            <div className="agent-channels-empty">
              <p className="placeholder-text">No channels configured. Add a channel ID to connect this agent to incoming messages.</p>
            </div>
          ) : (
            <div className="agent-channels-list">
              {nodes.map((node) => {
                const channelId = node.channelId || node.id;
                return (
                  <div key={node.id} className="agent-channel-row">
                    <div className="agent-channel-info">
                      <span className="agent-channel-id">
                        <span className="material-symbols-rounded agent-channel-icon">forum</span>
                        {channelId}
                      </span>
                      <span className="agent-channel-node-id">actor node · {node.id}</span>
                    </div>
                    <div className="agent-channel-actions">
                      <ChannelModelSelector channelId={channelId} />
                      <button
                        type="button"
                        className="agent-channel-remove"
                        onClick={() => void removeChannel(node.id)}
                        title="Remove channel"
                      >
                        <span className="material-symbols-rounded">delete</span>
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          <section className="agent-channel-sessions-panel">
            <div className="agent-config-head">
              <div className="agent-tools-head-copy">
                <h4>Active Sessions</h4>
                <p className="placeholder-text">Open incoming channel sessions that have not been auto-closed yet.</p>
              </div>
              <span className="agent-tools-status">
                {activeSessions.length} active
              </span>
            </div>

            {activeSessions.length === 0 ? (
              <div className="agent-channels-empty">
                <p className="placeholder-text">No active channel sessions right now.</p>
              </div>
            ) : (
              <div className="active-channels-grid">
                {activeSessions.map((session) => {
                  const sessionId = String(session.sessionId || "");
                  const detail = sessionDetails[sessionId] || null;
                  const messages = extractSessionMessages(detail).slice(-CHANNEL_MESSAGES_LIMIT);
                  const messageCount = Number(session.messageCount || 0);

                  const canOpen = Boolean(sessionId && onNavigateToChannelSession);

                  return (
                    <button
                      key={session.sessionId || session.channelId}
                      type="button"
                      className="channel-card hover-levitate"
                      disabled={!canOpen}
                      onClick={() => {
                        if (canOpen) {
                          onNavigateToChannelSession(sessionId);
                        }
                      }}
                    >
                      <div className="channel-card-head">
                        <span className="channel-card-dot channel-dot-active" />
                        <span className="channel-card-title">{session.channelId}</span>
                      </div>
                      <div className="channel-card-sub">
                        {formatRelativeTime(String(session.updatedAt || session.createdAt || ""))}
                        {messageCount > 0 ? ` · ${messageCount} messages` : ""}
                      </div>

                      {messages.length > 0 ? (
                        <div className="channel-card-messages">
                          {messages.map((msg, i) => (
                            <div key={msg.id || i} className="channel-msg-row">
                              <span className="channel-msg-time">{formatCompactTime(msg.createdAt)}</span>
                              <span
                                className={`channel-msg-user ${msg.isBot ? "channel-msg-bot" : ""}`}
                                style={msg.isBot ? undefined : { color: userColor(msg.userId) }}
                              >
                                {msg.userId}
                              </span>
                              <span className="channel-msg-text">{msg.content || "..."}</span>
                            </div>
                          ))}
                        </div>
                      ) : session.lastMessagePreview ? (
                        <div className="channel-card-preview">{session.lastMessagePreview}</div>
                      ) : null}
                    </button>
                  );
                })}
              </div>
            )}
          </section>

          {showForm ? (
            <div className="agent-channel-form">
              <label className="agent-channel-form-label">
                Channel ID
                <span className="agent-channel-form-hint">Lowercase letters, numbers, hyphens, underscores, and colons only.</span>
                <input
                  value={newChannelId}
                  onChange={(event) => setNewChannelId(event.target.value)}
                  onKeyDown={handleFormKeyDown}
                  placeholder="e.g. support, general, tg:my-group"
                  autoFocus
                />
              </label>
              {formError ? <p className="agent-create-error">{formError}</p> : null}
              <div className="agent-channel-form-actions">
                <button
                  type="button"
                  onClick={() => {
                    setShowForm(false);
                    setNewChannelId("");
                    setFormError("");
                  }}
                >
                  Cancel
                </button>
                <button type="button" className="agent-create-confirm hover-levitate" disabled={isSaving} onClick={() => void addChannel()}>
                  {isSaving ? "Adding..." : "Add Channel"}
                </button>
              </div>
            </div>
          ) : (
            <button type="button" className="agent-channels-add-btn" onClick={() => setShowForm(true)}>
              <span className="material-symbols-rounded">add</span>
              Add Channel
            </button>
          )}
        </>
      )}
    </section>
  );
}
