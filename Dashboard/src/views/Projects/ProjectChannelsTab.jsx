import React, { useEffect, useMemo, useState } from "react";
import { fetchChannelSessions, fetchChannelSession } from "../../api";

const CHANNEL_MESSAGES_LIMIT = 9;

const USER_COLORS = [
  "#c084fc", "#67e8f9", "#f472b6", "#fbbf24", "#6ee7b7",
  "#fb923c", "#a78bfa", "#38bdf8", "#f87171", "#a3e635"
];

function userColor(name) {
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = name.charCodeAt(i) + ((hash << 5) - hash);
  }
  return USER_COLORS[Math.abs(hash) % USER_COLORS.length];
}

function formatRelativeTime(dateValue) {
  const date = new Date(dateValue);
  if (Number.isNaN(date.getTime())) return "—";
  const diffMs = Date.now() - date.getTime();
  const diffMinutes = Math.round(diffMs / 60000);
  if (Math.abs(diffMinutes) < 1) return "just now";
  if (Math.abs(diffMinutes) < 60) return `${diffMinutes}m ago`;
  const diffHours = Math.round(diffMinutes / 60);
  if (Math.abs(diffHours) < 24) return `${diffHours}h ago`;
  return `${Math.round(diffHours / 24)}d ago`;
}

function formatCompactTime(dateValue) {
  const date = new Date(dateValue);
  if (Number.isNaN(date.getTime())) return "";
  let hours = date.getHours();
  const minutes = String(date.getMinutes()).padStart(2, "0");
  const suffix = hours >= 12 ? "p" : "a";
  hours = hours % 12 || 12;
  return `${hours}:${minutes}${suffix}`;
}

function extractSessionMessages(sessionDetail) {
  const events = Array.isArray(sessionDetail?.events) ? sessionDetail.events : [];
  return events
    .filter((e) => {
      const type = String(e?.type || "");
      return type === "user_message" || type === "assistant_message";
    })
    .map((e) => {
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

export function ProjectChannelsTab({ project, onNavigateToChannelSession }) {
  const [channelSessions, setChannelSessions] = useState([]);
  const [sessionDetails, setSessionDetails] = useState({});
  const [isLoading, setIsLoading] = useState(true);

  const projectChannelIds = useMemo(() => {
    const chats = Array.isArray(project?.chats) ? project.chats : [];
    return new Set(chats.map((ch) => String(ch.channelId || "").trim()).filter(Boolean));
  }, [project]);

  const channelTitleById = useMemo(() => {
    const map = new Map();
    const chats = Array.isArray(project?.chats) ? project.chats : [];
    for (const ch of chats) {
      const channelId = String(ch.channelId || "").trim();
      if (channelId) {
        map.set(channelId, String(ch.title || channelId));
      }
    }
    return map;
  }, [project]);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      setIsLoading(true);
      const allSessions = await fetchChannelSessions({ status: "open" }).catch(() => null);
      if (cancelled) return;

      const sessions = (Array.isArray(allSessions) ? allSessions : []).filter((s) => {
        const channelId = String(s?.channelId || "").trim();
        return projectChannelIds.has(channelId);
      });
      setChannelSessions(sessions);

      if (sessions.length > 0) {
        const details = {};
        const results = await Promise.all(
          sessions.map((s) => {
            const sid = String(s?.sessionId || "").trim();
            return sid ? fetchChannelSession(sid).catch(() => null) : Promise.resolve(null);
          })
        );
        for (let i = 0; i < sessions.length; i++) {
          const sid = String(sessions[i]?.sessionId || "").trim();
          if (sid && results[i]) {
            details[sid] = results[i];
          }
        }
        if (!cancelled) {
          setSessionDetails(details);
        }
      }

      if (!cancelled) setIsLoading(false);
    }

    load();
    return () => { cancelled = true; };
  }, [projectChannelIds]);

  const cards = useMemo(() => {
    return channelSessions.map((session) => {
      const channelId = String(session?.channelId || "").trim();
      const sessionId = String(session?.sessionId || "");
      const detail = sessionDetails[sessionId] || null;
      const messages = extractSessionMessages(detail).slice(-CHANNEL_MESSAGES_LIMIT);

      return {
        key: sessionId || channelId,
        sessionId,
        channelId,
        channelTitle: channelTitleById.get(channelId) || channelId || "Channel",
        updatedAt: session?.updatedAt || session?.createdAt || "",
        messageCount: Number(session?.messageCount || 0),
        lastMessagePreview: String(session?.lastMessagePreview || ""),
        canOpenSession: Boolean(session?.sessionId),
        messages
      };
    });
  }, [channelSessions, sessionDetails, channelTitleById]);

  if (isLoading) {
    return (
      <section className="project-tab-layout">
        <p className="placeholder-text">Loading channels…</p>
      </section>
    );
  }

  return (
    <section className="project-tab-layout">
      <div className="overview-section-header">
        <h2>
          <span className="material-symbols-rounded">forum</span>
          Active Channels
        </h2>
        <span className="overview-section-count">{cards.length}</span>
      </div>

      {cards.length === 0 ? (
        <div className="overview-empty-state">
          <span className="material-symbols-rounded overview-empty-icon">chat_bubble_outline</span>
          <p>No active channel sessions for this project right now.</p>
        </div>
      ) : (
        <div className="active-channels-grid">
          {cards.map((ch) => (
            <button
              key={ch.key}
              type="button"
              className="channel-card hover-levitate"
              disabled={!ch.canOpenSession}
              onClick={() => {
                if (ch.canOpenSession && onNavigateToChannelSession) {
                  onNavigateToChannelSession(ch.sessionId);
                }
              }}
            >
              <div className="channel-card-head">
                <span className="channel-card-dot channel-dot-active" />
                <span className="channel-card-title">{ch.channelTitle}</span>
              </div>
              <div className="channel-card-sub">
                {ch.updatedAt ? formatRelativeTime(ch.updatedAt) : "just now"}
                {ch.messageCount > 0 ? ` · ${ch.messageCount} messages` : ""}
              </div>

              {ch.messages.length > 0 ? (
                <div className="channel-card-messages">
                  {ch.messages.map((msg, i) => (
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
              ) : ch.lastMessagePreview ? (
                <div className="channel-card-preview">{ch.lastMessagePreview}</div>
              ) : null}
            </button>
          ))}
        </div>
      )}
    </section>
  );
}
