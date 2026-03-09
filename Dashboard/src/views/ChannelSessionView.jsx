import React, { useEffect, useMemo, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { oneDark } from "react-syntax-highlighter/dist/esm/styles/prism";
import { fetchActorsBoard, fetchAgents, fetchChannelEvents, fetchChannelSession, fetchProjects } from "../api";
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

function normalizeRuntimeEvents(payload) {
  if (!payload || typeof payload !== "object") {
    return [];
  }

  const items = payload.items;
  if (!Array.isArray(items)) {
    return [];
  }

  const result = [];
  for (const entry of items) {
    if (!entry || typeof entry !== "object") {
      continue;
    }
    const id = String(entry.messageId || "").trim();
    const messageType = String(entry.messageType || "").trim();
    const ts = String(entry.ts || "").trim();
    if (!id || !messageType || !ts) {
      continue;
    }

    result.push({
      id,
      messageType,
      ts,
      taskId: typeof entry.taskId === "string" ? entry.taskId : "",
      branchId: typeof entry.branchId === "string" ? entry.branchId : "",
      workerId: typeof entry.workerId === "string" ? entry.workerId : "",
      payload: entry.payload,
      extensions: entry.extensions && typeof entry.extensions === "object" ? entry.extensions : null
    });
  }

  return result;
}

function normalizeEventTypeLabel(type) {
  const normalized = String(type || "").replace(/_/g, " ").trim();
  if (!normalized) {
    return "event";
  }
  return normalized;
}

function normalizeMessageTypeLabel(type) {
  return String(type || "")
    .split(".")
    .join(" ")
    .replace(/_/g, " ")
    .trim();
}

function buildTechnicalEventSummary(event) {
  const payload = event?.payload && typeof event.payload === "object" ? event.payload : {};
  const extensions = event?.extensions && typeof event.extensions === "object" ? event.extensions : {};
  const type = String(event?.messageType || "");

  if (type === "channel.route.decided") {
    const action = String(payload.action || "").trim();
    const reason = String(payload.reason || "").trim();
    const confidence = payload.confidence != null ? `Confidence: ${payload.confidence}` : "";
    return {
      title: action ? `Route: ${action}` : "Route decided",
      summary: previewText(reason || action, "Route decided"),
      detail: [reason ? `Reason: ${reason}` : "", confidence].filter(Boolean).join("\n")
    };
  }

  if (type === "branch.spawned") {
    const prompt = String(payload.prompt || "").trim();
    const todos = Array.isArray(extensions.todos) ? extensions.todos.join("\n") : "";
    return {
      title: "Branch spawned",
      summary: previewText(prompt, "Branch created"),
      detail: [prompt ? `Prompt:\n${prompt}` : "", todos ? `Todos:\n${todos}` : ""].filter(Boolean).join("\n\n")
    };
  }

  if (type === "branch.conclusion") {
    const summary = String(payload.summary || "").trim();
    const tokenUsage = payload.tokenUsage ? `Token usage:\n${formatStructuredData(payload.tokenUsage)}` : "";
    const artifactRefs = Array.isArray(payload.artifactRefs) ? `Artifacts:\n${formatStructuredData(payload.artifactRefs)}` : "";
    const memoryRefs = Array.isArray(payload.memoryRefs) ? `Memories:\n${formatStructuredData(payload.memoryRefs)}` : "";
    return {
      title: "Branch conclusion",
      summary: previewText(summary, "Conclusion stored"),
      detail: [summary ? `Summary:\n${summary}` : "", tokenUsage, artifactRefs, memoryRefs].filter(Boolean).join("\n\n")
    };
  }

  if (type === "worker.spawned") {
    const title = String(payload.title || "").trim();
    const mode = String(payload.mode || "").trim();
    return {
      title: "Worker spawned",
      summary: previewText(title || mode, "Worker queued"),
      detail: [
        title ? `Title: ${title}` : "",
        mode ? `Mode: ${mode}` : "",
        event.taskId ? `Task: ${event.taskId}` : "",
        event.workerId ? `Worker: ${event.workerId}` : ""
      ]
        .filter(Boolean)
        .join("\n")
    };
  }

  if (type === "worker.progress") {
    const progress = String(payload.progress || "").trim();
    return {
      title: "Worker progress",
      summary: previewText(progress, "Worker updated"),
      detail: [
        progress ? `Progress: ${progress}` : "",
        event.taskId ? `Task: ${event.taskId}` : "",
        event.workerId ? `Worker: ${event.workerId}` : ""
      ]
        .filter(Boolean)
        .join("\n")
    };
  }

  if (type === "worker.completed") {
    const summary = String(payload.summary || "").trim();
    const artifactId = String(payload.artifactId || "").trim();
    return {
      title: "Worker completed",
      summary: previewText(summary || artifactId, "Worker completed"),
      detail: [summary ? `Summary:\n${summary}` : "", artifactId ? `Artifact: ${artifactId}` : ""].filter(Boolean).join("\n\n")
    };
  }

  if (type === "worker.failed") {
    const error = String(payload.error || "").trim();
    const reason = String(payload.reason || "").trim();
    return {
      title: "Worker failed",
      summary: previewText(error || reason, "Worker failed"),
      detail: [error ? `Error:\n${error}` : "", reason ? `Reason: ${reason}` : ""].filter(Boolean).join("\n\n")
    };
  }

  if (type === "actor.discussion.started") {
    const targetActorId = String(payload.targetActorId || "").trim();
    const topic = String(payload.topic || "").trim();
    const message = String(payload.message || "").trim();
    return {
      title: "Actor discussion",
      summary: previewText(topic || message, "Discussion started"),
      detail: [
        targetActorId ? `Target actor: ${targetActorId}` : "",
        topic ? `Topic: ${topic}` : "",
        message ? `Message:\n${message}` : ""
      ]
        .filter(Boolean)
        .join("\n\n")
    };
  }

  return {
    title: normalizeMessageTypeLabel(type) || "Technical event",
    summary: previewText(formatStructuredData(payload), "Technical event"),
    detail: [
      event.taskId ? `Task: ${event.taskId}` : "",
      event.branchId ? `Branch: ${event.branchId}` : "",
      event.workerId ? `Worker: ${event.workerId}` : "",
      `Payload:\n${formatStructuredData(payload)}`,
      extensions && Object.keys(extensions).length > 0 ? `Extensions:\n${formatStructuredData(extensions)}` : ""
    ]
      .filter(Boolean)
      .join("\n\n")
  };
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
  const [runtimeEvents, setRuntimeEvents] = useState([]);
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

  useEffect(() => {
    const channelId = String(sessionDetail?.summary?.channelId || "").trim();
    const createdAt = sessionDetail?.summary?.createdAt || "";
    const closedAt = sessionDetail?.summary?.closedAt || "";
    if (!sessionId || !channelId) {
      return undefined;
    }

    let cancelled = false;

    async function refreshLive(silent = false) {
      const [detail, channelEventsResponse] = await Promise.all([
        fetchChannelSession(sessionId).catch(() => null),
        fetchChannelEvents(channelId, { limit: 200 }).catch(() => null)
      ]);

      if (cancelled) {
        return;
      }

      if (detail) {
        setSessionDetail(detail);
      } else if (!silent) {
        setErrorText("Failed to refresh channel session.");
      }

      const allRuntimeEvents = normalizeRuntimeEvents(channelEventsResponse);
      const windowStart = createdAt ? new Date(createdAt).getTime() : Number.NEGATIVE_INFINITY;
      const windowEnd = closedAt ? new Date(closedAt).getTime() : Number.POSITIVE_INFINITY;
      const filteredRuntimeEvents = allRuntimeEvents.filter((event) => {
        const eventTs = new Date(event.ts).getTime();
        if (Number.isNaN(eventTs)) {
          return false;
        }
        return eventTs >= windowStart && eventTs <= windowEnd;
      });
      setRuntimeEvents(filteredRuntimeEvents);
    }

    refreshLive(true).catch(() => { });
    const timerId = window.setInterval(() => {
      refreshLive(true).catch(() => { });
    }, 2000);

    return () => {
      cancelled = true;
      window.clearInterval(timerId);
    };
  }, [sessionDetail?.summary?.channelId, sessionDetail?.summary?.closedAt, sessionDetail?.summary?.createdAt, sessionId]);

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

  const technicalTimeline = useMemo(() => {
    return runtimeEvents
      .filter((event) => event.messageType !== "channel.message.received")
      .map((event) => ({
        ...event,
        ...buildTechnicalEventSummary(event)
      }));
  }, [runtimeEvents]);

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
              <span className="material-symbols-rounded">memory</span>
              Technical Timeline
            </h2>
            <span className="overview-section-count">{technicalTimeline.length}</span>
          </div>

          <div className="channel-session-transcript-panel channel-session-technical-panel">
            <div className="agent-chat-events channel-session-events">
              {technicalTimeline.length === 0 ? (
                <div className="overview-empty-state channel-session-inline-empty">
                  <span className="material-symbols-rounded overview-empty-icon">manufacturing</span>
                  <p>No runtime events captured for this channel session yet.</p>
                </div>
              ) : (
                technicalTimeline.map((event) => (
                  <article key={event.id} className="agent-chat-technical">
                    <div className="agent-chat-technical-body">
                      <div className="channel-session-technical-copy">
                        <strong>{event.title}</strong>
                        <small>{formatEventTime(event.ts)}</small>
                      </div>
                      <p className="channel-session-technical-summary">{event.summary}</p>
                      <pre className="agent-chat-expandable-pre">{event.detail || "No details."}</pre>
                    </div>
                  </article>
                ))
              )}
            </div>
          </div>

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
                        <div className="markdown-body">
                          <ReactMarkdown
                            remarkPlugins={[remarkGfm]}
                            components={{
                              code({ node, inline, className, children, ...props }) {
                                const match = /language-(\w+)/.exec(className || "");
                                return !inline && match ? (
                                  <SyntaxHighlighter
                                    style={oneDark}
                                    language={match[1]}
                                    PreTag="div"
                                    {...props}
                                  >
                                    {String(children).replace(/\n$/, "")}
                                  </SyntaxHighlighter>
                                ) : (
                                  <code className={className} {...props}>
                                    {children}
                                  </code>
                                );
                              }
                            }}
                          >
                            {item.content || "No message content."}
                          </ReactMarkdown>
                        </div>
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
