import React, { useEffect, useMemo, useState } from "react";
import { fetchActorsBoard, fetchAgents, fetchChannelSession, fetchProjects } from "../api";
import { Breadcrumbs } from "../components/Breadcrumbs/Breadcrumbs";

function formatRelativeTime(value) {
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

function formatDateTime(value) {
  if (!value) {
    return "—";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "—";
  }
  return date.toLocaleString([], {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  });
}

function formatEventTime(value) {
  if (!value) {
    return "";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }
  return date.toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  });
}

function agentInitials(name) {
  const parts = String(name || "?")
    .trim()
    .split(/[\s_-]+/)
    .filter(Boolean);
  if (parts.length === 0) {
    return "??";
  }
  if (parts.length === 1) {
    return parts[0].slice(0, 2).toUpperCase();
  }
  return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
}

function previewText(value, fallback = "No details") {
  const normalized = String(value || "").replace(/\s+/g, " ").trim();
  if (!normalized) {
    return fallback;
  }
  if (normalized.length > 140) {
    return `${normalized.slice(0, 140)}...`;
  }
  return normalized;
}

function formatStructuredData(value) {
  if (value == null) {
    return "";
  }
  if (typeof value === "string") {
    return value;
  }
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function normalizeEventTypeLabel(type) {
  const normalized = String(type || "").replace(/_/g, " ").trim();
  if (!normalized) {
    return "event";
  }
  return normalized;
}

function isMessageEvent(type) {
  return type === "user_message" || type === "assistant_message" || type === "system_message";
}

function eventRole(type, userId) {
  if (type === "assistant_message") {
    return "assistant";
  }
  if (type === "user_message") {
    return "user";
  }
  if (type === "system_message") {
    return "system";
  }
  const normalizedUserId = String(userId || "").trim().toLowerCase();
  if (normalizedUserId === "assistant") {
    return "assistant";
  }
  if (normalizedUserId === "system") {
    return "system";
  }
  return "system";
}

function buildProjectByChannel(projects) {
  const projectByChannel = new Map();
  for (const project of Array.isArray(projects) ? projects : []) {
    const channels = Array.isArray(project?.channels)
      ? project.channels
      : Array.isArray(project?.chats)
        ? project.chats
        : [];
    for (const channel of channels) {
      const channelId = String(channel?.channelId || "").trim();
      if (!channelId || projectByChannel.has(channelId)) {
        continue;
      }
      projectByChannel.set(channelId, {
        projectId: String(project?.id || ""),
        projectName: String(project?.name || project?.id || "Project"),
        channelTitle: String(channel?.title || channelId)
      });
    }
  }
  return projectByChannel;
}

export function ChannelSessionView({ sessionId, onNavigateBack }) {
  const [sessionDetail, setSessionDetail] = useState(null);
  const [projects, setProjects] = useState([]);
  const [agents, setAgents] = useState([]);
  const [actorBoard, setActorBoard] = useState({ nodes: [], links: [], teams: [] });
  const [isLoading, setIsLoading] = useState(true);
  const [errorText, setErrorText] = useState("");

  useEffect(() => {
    let cancelled = false;

    async function load() {
      if (!sessionId) {
        setErrorText("Session route is incomplete.");
        setIsLoading(false);
        return;
      }

      setIsLoading(true);
      setErrorText("");

      const [detail, projectsResponse, agentsResponse, boardResponse] = await Promise.all([
        fetchChannelSession(sessionId).catch(() => null),
        fetchProjects().catch(() => null),
        fetchAgents().catch(() => null),
        fetchActorsBoard().catch(() => null)
      ]);

      if (cancelled) {
        return;
      }

      if (!detail) {
        setSessionDetail(null);
        setErrorText("Failed to load channel session.");
        setIsLoading(false);
        return;
      }

      setSessionDetail(detail);
      setProjects(Array.isArray(projectsResponse) ? projectsResponse : []);
      setAgents(Array.isArray(agentsResponse) ? agentsResponse : []);
      setActorBoard(boardResponse && Array.isArray(boardResponse.nodes) ? boardResponse : { nodes: [], links: [], teams: [] });
      setIsLoading(false);
    }

    load().catch(() => {
      if (!cancelled) {
        setSessionDetail(null);
        setErrorText("Failed to load channel session.");
        setIsLoading(false);
      }
    });

    return () => {
      cancelled = true;
    };
  }, [sessionId]);

  const summary = sessionDetail?.summary || null;
  const events = Array.isArray(sessionDetail?.events) ? sessionDetail.events : [];

  const channelMeta = useMemo(() => {
    const channelId = String(summary?.channelId || "").trim();
    const projectByChannel = buildProjectByChannel(projects);
    const projectMeta = projectByChannel.get(channelId);

    const agentNameById = new Map(
      (Array.isArray(agents) ? agents : []).map((agent) => [
        String(agent?.id || ""),
        String(agent?.displayName || agent?.id || "")
      ])
    );

    const nodes = Array.isArray(actorBoard?.nodes) ? actorBoard.nodes : [];
    const linkedAgents = nodes
      .filter((node) => String(node?.channelId || "").trim() === channelId && String(node?.linkedAgentId || "").trim())
      .map((node) => {
        const agentId = String(node?.linkedAgentId || "").trim();
        return {
          id: agentId,
          name: agentNameById.get(agentId) || agentId
        };
      })
      .filter((value, index, array) => array.findIndex((item) => item.id === value.id) === index);

    return {
      channelId,
      channelTitle: projectMeta?.channelTitle || channelId || "Channel",
      projectName: projectMeta?.projectName || "",
      linkedAgents
    };
  }, [actorBoard, agents, projects, summary?.channelId]);

  const transcriptItems = useMemo(() => {
    return events.map((eventItem, index) => ({
      id: String(eventItem?.id || `event-${index}`),
      index,
      type: String(eventItem?.type || ""),
      role: eventRole(eventItem?.type, eventItem?.userId),
      userId: String(eventItem?.userId || ""),
      content: String(eventItem?.content || ""),
      createdAt: eventItem?.createdAt || "",
      metadata: eventItem?.metadata || null,
      isMessage: isMessageEvent(String(eventItem?.type || ""))
    }));
  }, [events]);

  const breadcrumbItems = [
    { id: "overview", label: "Overview", onClick: onNavigateBack },
    { id: "session", label: channelMeta.channelTitle || "Channel Session" }
  ];

  if (isLoading) {
    return (
      <main className="channel-session-shell">
        <Breadcrumbs items={breadcrumbItems} style={{ marginBottom: "20px" }} />
        <div className="overview-empty-state">
          <span className="material-symbols-rounded overview-empty-icon">hourglass_empty</span>
          <p>Loading channel session...</p>
        </div>
      </main>
    );
  }

  if (errorText || !summary) {
    return (
      <main className="channel-session-shell">
        <Breadcrumbs items={breadcrumbItems} style={{ marginBottom: "20px" }} />
        <div className="overview-empty-state">
          <span className="material-symbols-rounded overview-empty-icon">error</span>
          <p>{errorText || "Session not found."}</p>
        </div>
      </main>
    );
  }

  return (
    <main className="channel-session-shell">
      <Breadcrumbs items={breadcrumbItems} style={{ marginBottom: "20px" }} />

      <section className="channel-session-hero">
        <div className="channel-session-titlebar">
          <div className="channel-session-avatar">
            {agentInitials(channelMeta.linkedAgents[0]?.name || channelMeta.channelTitle)}
          </div>
          <div className="channel-session-copy">
            <h1>{channelMeta.channelTitle || "Channel Session"}</h1>
            <p>
              {channelMeta.channelId}
              {channelMeta.projectName ? ` · ${channelMeta.projectName}` : ""}
            </p>
          </div>
        </div>
        <div className="channel-session-badges">
          <span className="channel-session-badge">{summary.status || "open"}</span>
          <span className="channel-session-badge">{summary.messageCount || 0} messages</span>
          <span className="channel-session-badge">Updated {formatRelativeTime(summary.updatedAt)}</span>
        </div>
      </section>

      <div className="channel-session-layout">
        <aside className="channel-session-sidebar">
          <section className="channel-session-panel">
            <div className="overview-section-header">
              <h2>
                <span className="material-symbols-rounded">info</span>
                Session
              </h2>
            </div>
            <dl className="channel-session-meta-list">
              <div>
                <dt>Session ID</dt>
                <dd>{summary.sessionId}</dd>
              </div>
              <div>
                <dt>Channel</dt>
                <dd>{channelMeta.channelId}</dd>
              </div>
              <div>
                <dt>Status</dt>
                <dd>{summary.status || "open"}</dd>
              </div>
              <div>
                <dt>Messages</dt>
                <dd>{summary.messageCount || 0}</dd>
              </div>
              <div>
                <dt>Created</dt>
                <dd>{formatDateTime(summary.createdAt)}</dd>
              </div>
              <div>
                <dt>Updated</dt>
                <dd>{formatDateTime(summary.updatedAt)}</dd>
              </div>
              {summary.closedAt ? (
                <div>
                  <dt>Closed</dt>
                  <dd>{formatDateTime(summary.closedAt)}</dd>
                </div>
              ) : null}
              {channelMeta.projectName ? (
                <div>
                  <dt>Project</dt>
                  <dd>{channelMeta.projectName}</dd>
                </div>
              ) : null}
              {channelMeta.linkedAgents.length > 0 ? (
                <div>
                  <dt>Agents</dt>
                  <dd>{channelMeta.linkedAgents.map((agent) => agent.name).join(", ")}</dd>
                </div>
              ) : null}
            </dl>
          </section>

          {summary.lastMessagePreview ? (
            <section className="channel-session-panel">
              <div className="overview-section-header">
                <h2>
                  <span className="material-symbols-rounded">notes</span>
                  Preview
                </h2>
              </div>
              <p className="channel-session-preview">{summary.lastMessagePreview}</p>
            </section>
          ) : null}
        </aside>

        <section className="channel-session-main">
          <div className="overview-section-header">
            <h2>
              <span className="material-symbols-rounded">article</span>
              Full Session
            </h2>
            <span className="overview-section-count">{transcriptItems.length}</span>
          </div>

          <div className="channel-session-transcript-panel">
            <div className="agent-chat-events channel-session-events">
              {transcriptItems.length === 0 ? (
                <p className="placeholder-text">No transcript available yet.</p>
              ) : (
                transcriptItems.map((item) => {
                  if (!item.isMessage) {
                    return (
                      <article key={item.id} className="agent-chat-technical">
                        <div className="agent-chat-technical-body">
                          <div className="channel-session-technical-copy">
                            <strong>{normalizeEventTypeLabel(item.type)}</strong>
                            <small>{formatEventTime(item.createdAt)}</small>
                          </div>
                          <pre className="agent-chat-expandable-pre">
                            {[
                              item.content ? `Content:\n${item.content}` : "",
                              item.userId ? `User: ${item.userId}` : "",
                              item.metadata ? `Metadata:\n${formatStructuredData(item.metadata)}` : ""
                            ]
                              .filter(Boolean)
                              .join("\n\n") || "No details."}
                          </pre>
                        </div>
                      </article>
                    );
                  }

                  return (
                    <article key={item.id} className={`agent-chat-message ${item.role} channel-session-message`}>
                      <div className="agent-chat-message-head">
                        <strong>{item.userId || item.role}</strong>
                        <span>{formatEventTime(item.createdAt)}</span>
                      </div>
                      <div className="agent-chat-message-body">
                        <p>{item.content || "No message content."}</p>
                        {item.metadata ? (
                          <pre className="agent-chat-expandable-pre">
                            {previewText(formatStructuredData(item.metadata), "No metadata")}
                          </pre>
                        ) : null}
                      </div>
                    </article>
                  );
                })
              )}
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}
