import React, { useEffect, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { oneDark } from "react-syntax-highlighter/dist/esm/styles/prism";
import {
  createAgentSession,
  fetchAgentSessions,
  fetchAgentSession,
  postAgentSessionMessage,
  postAgentSessionControl,
  subscribeAgentSessionStream
} from "../../api";

function formatEventTime(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function extractTextFromSegments(segments) {
  return (segments || [])
    .filter((s) => s.kind === "text")
    .map((s) => String(s.text || "").trim())
    .filter(Boolean)
    .join("\n")
    .trim();
}

function MarkdownContent({ text }) {
  return (
    <div className="markdown-body">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          code(props) {
            const { inline, className, children, ...rest } = props;
            const match = /language-(\w+)/.exec(className || "");
            return !inline && match ? (
              <SyntaxHighlighter style={oneDark} language={match[1]} PreTag="div" {...rest}>
                {String(children).replace(/\n$/, "")}
              </SyntaxHighlighter>
            ) : (
              <code className={className} {...rest}>{children}</code>
            );
          }
        }}
      >
        {text || ""}
      </ReactMarkdown>
    </div>
  );
}

export function ReviewChatPanel({ agentId, taskTitle, diff }) {
  const [sessionId, setSessionId] = useState(null);
  const [events, setEvents] = useState([]);
  const [inputText, setInputText] = useState("");
  const [isSending, setIsSending] = useState(false);
  const [statusText, setStatusText] = useState("");
  const [optimisticUserText, setOptimisticUserText] = useState(null);
  const [streamText, setStreamText] = useState("");
  const scrollRef = useRef(null);
  const streamCleanupRef = useRef(() => {});
  const sessionIdRef = useRef(null);

  useEffect(() => {
    sessionIdRef.current = sessionId;
  }, [sessionId]);

  useEffect(() => {
    if (!scrollRef.current) return;
    scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [events, optimisticUserText, streamText]);

  useEffect(() => {
    if (!agentId) return;

    let cancelled = false;

    async function init() {
      setStatusText("Loading...");
      const sessions = await fetchAgentSessions(agentId);
      if (cancelled) return;

      const existing = Array.isArray(sessions) && sessions.length > 0 ? sessions[0] : null;
      if (existing) {
        setSessionId(existing.id);
        const detail = await fetchAgentSession(agentId, existing.id);
        if (!cancelled && detail) {
          setEvents(Array.isArray(detail.events) ? detail.events : []);
          setStatusText("");
        }
      } else {
        setStatusText("");
      }
    }

    init().catch(() => setStatusText("Failed to load chat."));

    return () => {
      cancelled = true;
    };
  }, [agentId]);

  useEffect(() => {
    streamCleanupRef.current?.();
    streamCleanupRef.current = () => {};
    if (!agentId || !sessionId) return;

    const disconnect = subscribeAgentSessionStream(agentId, sessionId, {
      onUpdate: (update) => {
        if (!update) return;
        const kind = String(update.kind || "");
        const streamEvent = update.event && typeof update.event === "object" ? update.event : null;

        if (kind === "session_delta") {
          const text = String(update.message || "");
          if (text.trim()) setStreamText(text);
          return;
        }

        if (streamEvent) {
          if (
            streamEvent.type === "run_status" &&
            streamEvent.runStatus?.stage === "done"
          ) {
            setStreamText("");
          }
          if (streamEvent.type === "message") {
            setEvents((prev) => {
              const exists = prev.some((e) => e?.id === streamEvent.id);
              if (exists) return prev;
              return [...prev, streamEvent];
            });
            if (streamEvent.message?.role === "user") {
              setOptimisticUserText(null);
            }
          }
        }
      }
    });
    streamCleanupRef.current = disconnect;

    return () => {
      disconnect();
    };
  }, [agentId, sessionId]);

  async function ensureSession() {
    if (sessionId) return sessionId;

    const context = [
      `You are a code reviewer for this task: ${taskTitle}`,
      diff ? `\nThe git diff for review:\n\`\`\`diff\n${diff.slice(0, 8000)}\n\`\`\`` : ""
    ].filter(Boolean).join("\n");

    const session = await createAgentSession(agentId, {});
    if (!session) return null;
    setSessionId(session.id);

    await postAgentSessionMessage(agentId, session.id, {
      userId: "dashboard",
      content: context,
      spawnSubSession: false
    });
    return session.id;
  }

  async function handleSend(event) {
    event?.preventDefault?.();
    const text = inputText.trim();
    if (!text || isSending || !agentId) return;

    setOptimisticUserText(text);
    setInputText("");
    setIsSending(true);
    setStreamText("");

    const sid = await ensureSession();
    if (!sid) {
      setStatusText("Failed to start session.");
      setIsSending(false);
      setOptimisticUserText(null);
      return;
    }

    await postAgentSessionMessage(agentId, sid, {
      userId: "dashboard",
      content: text,
      spawnSubSession: false
    });

    const detail = await fetchAgentSession(agentId, sid);
    if (detail) {
      setEvents(Array.isArray(detail.events) ? detail.events : []);
    }

    setIsSending(false);
    setStreamText("");
    setStatusText("");
  }

  async function handleStop() {
    if (!sessionId || !isSending) return;
    await postAgentSessionControl(agentId, sessionId, {
      action: "interrupt",
      requestedBy: "dashboard",
      reason: "Stopped by user"
    });
    setIsSending(false);
    setStreamText("");
  }

  const messageEvents = events.filter(
    (e) => e?.type === "message" && (e.message?.role === "user" || e.message?.role === "assistant")
  );

  return (
    <div className="review-chat-panel">
      <div className="review-chat-head">
        <span className="material-symbols-rounded" aria-hidden="true">smart_toy</span>
        <span>Review Chat</span>
        {agentId && <span className="review-chat-agent-id">{agentId}</span>}
      </div>

      <div className="review-chat-messages" ref={scrollRef}>
        {!agentId && (
          <p className="placeholder-text">No agent configured for this project.</p>
        )}

        {agentId && messageEvents.length === 0 && !optimisticUserText && (
          <p className="placeholder-text">Ask the agent about the code changes...</p>
        )}

        {messageEvents.map((eventItem, index) => {
          const role = eventItem.message?.role || "system";
          const segments = Array.isArray(eventItem.message?.segments) ? eventItem.message.segments : [];
          const text = extractTextFromSegments(segments);
          return (
            <article key={eventItem.id || `msg-${index}`} className={`review-chat-message ${role}`}>
              <div className="review-chat-message-role">
                <span className="material-symbols-rounded" aria-hidden="true">
                  {role === "assistant" ? "smart_toy" : "person"}
                </span>
                <strong>{role}</strong>
                <span className="review-chat-time">
                  {formatEventTime(eventItem.message?.createdAt || eventItem.createdAt)}
                </span>
              </div>
              <MarkdownContent text={text} />
            </article>
          );
        })}

        {optimisticUserText && (
          <article className="review-chat-message user">
            <div className="review-chat-message-role">
              <span className="material-symbols-rounded" aria-hidden="true">person</span>
              <strong>user</strong>
            </div>
            <p>{optimisticUserText}</p>
          </article>
        )}

        {streamText && (
          <article className="review-chat-message assistant">
            <div className="review-chat-message-role">
              <span className="material-symbols-rounded" aria-hidden="true">smart_toy</span>
              <strong>assistant</strong>
            </div>
            <MarkdownContent text={streamText} />
          </article>
        )}
      </div>

      {statusText && (
        <p className="review-chat-status placeholder-text">{statusText}</p>
      )}

      <form className="review-chat-compose" onSubmit={handleSend}>
        <textarea
          className="review-chat-input"
          value={inputText}
          onChange={(e) => setInputText(e.target.value)}
          placeholder={agentId ? "Ask about these changes..." : "No agent available"}
          rows={2}
          disabled={isSending || !agentId}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent?.isComposing) {
              e.preventDefault();
              handleSend(e);
            }
          }}
        />
        <div className="review-chat-compose-actions">
          {isSending ? (
            <button type="button" className="review-chat-send-btn danger" onClick={handleStop}>
              <span className="material-symbols-rounded" aria-hidden="true">stop</span>
            </button>
          ) : (
            <button
              type="submit"
              className="review-chat-send-btn"
              disabled={!inputText.trim() || !agentId}
            >
              <span className="material-symbols-rounded" aria-hidden="true">arrow_upward</span>
            </button>
          )}
        </div>
      </form>
    </div>
  );
}
