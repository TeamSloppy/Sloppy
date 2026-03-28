import React, { useEffect, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { oneDark } from "react-syntax-highlighter/dist/esm/styles/prism";
import { buildApiURL } from "../../shared/api/httpClient";
import { fetchVisorReady, postVisorChat } from "../../api";

interface Message {
  id: string;
  role: "user" | "visor";
  text: string;
  streaming?: boolean;
}

const STORAGE_KEY = "visor-chat-history";
const MAX_STORED_MESSAGES = 200;

function loadStoredMessages(): Message[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (m) => m && typeof m.id === "string" && typeof m.role === "string" && typeof m.text === "string"
    );
  } catch {
    return [];
  }
}

function saveMessages(messages: Message[]) {
  try {
    const toSave = messages
      .filter((m) => !m.streaming)
      .slice(-MAX_STORED_MESSAGES);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(toSave));
  } catch {
    // ignore quota errors
  }
}

function parseSSEChunks(
  buffer: string,
  flush = false
): { events: Array<{ event: string; data: string }>; remaining: string } {
  const events: Array<{ event: string; data: string }> = [];
  const normalized = buffer.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  const lines = normalized.split("\n");

  let event = "message";
  const dataLines: string[] = [];
  let lineIndex = 0;

  while (lineIndex < lines.length) {
    const line = lines[lineIndex];
    lineIndex += 1;

    if (line === "") {
      if (dataLines.length > 0) {
        events.push({ event, data: dataLines.join("\n") });
      }
      event = "message";
      dataLines.length = 0;
      continue;
    }

    if (line.startsWith("event:")) {
      event = line.slice(6).trim();
    } else if (line.startsWith("data:")) {
      const value = line.length > 5 && line[5] === " " ? line.slice(6) : line.slice(5);
      dataLines.push(value);
    }
  }

  if (flush && dataLines.length > 0) {
    events.push({ event, data: dataLines.join("\n") });
    return { events, remaining: "" };
  }

  const lastNewline = normalized.lastIndexOf("\n");
  const remaining = lastNewline >= 0 ? buffer.slice(lastNewline + 1) : buffer;
  return { events, remaining };
}

export function VisorChatView() {
  const [messages, setMessages] = useState<Message[]>(() => loadStoredMessages());
  const [inputText, setInputText] = useState("");
  const [isSending, setIsSending] = useState(false);
  const [isReady, setIsReady] = useState<boolean | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    fetchVisorReady().then((data) => {
      if (data && typeof data.ready === "boolean") {
        setIsReady(data.ready);
      } else {
        setIsReady(false);
      }
    });
  }, []);

  useEffect(() => {
    saveMessages(messages);
  }, [messages]);

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    el.scrollTop = el.scrollHeight;
  }, [messages]);

  function autoResizeTextarea() {
    const el = inputRef.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 160)}px`;
  }

  function handleInputChange(e: React.ChangeEvent<HTMLTextAreaElement>) {
    setInputText(e.target.value);
    autoResizeTextarea();
  }

  async function handleSend() {
    const question = inputText.trim();
    if (!question || isSending) return;

    const userMessageId = `user-${Date.now()}`;
    const visorMessageId = `visor-${Date.now()}`;

    setMessages((prev) => [
      ...prev,
      { id: userMessageId, role: "user", text: question }
    ]);
    setInputText("");

    // Reset textarea height
    if (inputRef.current) {
      inputRef.current.style.height = "auto";
    }

    setIsSending(true);

    const abort = new AbortController();
    abortRef.current = abort;

    try {
      const url = buildApiURL(`/v1/visor/chat/stream?question=${encodeURIComponent(question)}`);
      const response = await fetch(url, {
        signal: abort.signal,
        headers: { Accept: "text/event-stream" }
      });

      if (!response.ok || !response.body) {
        throw new Error("Stream unavailable");
      }

      setMessages((prev) => [
        ...prev,
        { id: visorMessageId, role: "visor", text: "", streaming: true }
      ]);

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let sseBuffer = "";
      let accumulated = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          const { events: finalEvents } = parseSSEChunks(sseBuffer, true);
          for (const { event, data } of finalEvents) {
            if (event === "delta" && data) {
              accumulated += data;
            }
          }
          break;
        }
        sseBuffer += decoder.decode(value, { stream: true });
        const { events, remaining } = parseSSEChunks(sseBuffer);
        sseBuffer = remaining;

        for (const { event, data } of events) {
          if (event === "delta" && data) {
            accumulated += data;
            const next = accumulated;
            setMessages((prev) =>
              prev.map((m) => (m.id === visorMessageId ? { ...m, text: next } : m))
            );
          }
        }
      }

      if (accumulated) {
        setMessages((prev) =>
          prev.map((m) => (m.id === visorMessageId ? { ...m, text: accumulated, streaming: false } : m))
        );
      } else {
        setMessages((prev) =>
          prev.map((m) => (m.id === visorMessageId ? { ...m, streaming: false } : m))
        );
      }
    } catch (err: unknown) {
      if (err instanceof Error && err.name === "AbortError") {
        setMessages((prev) =>
          prev.map((m) => (m.id === visorMessageId ? { ...m, streaming: false } : m))
        );
        return;
      }

      setMessages((prev) => prev.filter((m) => m.id !== visorMessageId));

      try {
        const data = await postVisorChat(question);
        const answer = typeof data?.answer === "string" ? data.answer : "No response.";
        setMessages((prev) => [
          ...prev,
          { id: visorMessageId, role: "visor", text: answer }
        ]);
      } catch {
        setMessages((prev) => [
          ...prev,
          { id: visorMessageId, role: "visor", text: "Visor is not available." }
        ]);
      }
    } finally {
      abortRef.current = null;
      setIsSending(false);
      inputRef.current?.focus();
    }
  }

  function handleKeyDown(event: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      handleSend();
    }
  }

  function handleStop() {
    abortRef.current?.abort();
  }

  function handleClear() {
    if (!window.confirm("Clear Visor chat history?")) return;
    setMessages([]);
    localStorage.removeItem(STORAGE_KEY);
  }

  return (
    <section className="visor-chat-shell">
      <div className="visor-chat-header">
        <h2 className="visor-chat-title">Visor</h2>
        {isReady === null ? (
          <span className="visor-ready-badge checking">Checking...</span>
        ) : isReady ? (
          <span className="visor-ready-badge ready">Ready</span>
        ) : (
          <span className="visor-ready-badge not-ready">Not ready</span>
        )}
        <div style={{ flex: 1 }} />
        {messages.length > 0 && (
          <button
            type="button"
            className="agent-chat-icon-button"
            onClick={handleClear}
            title="Clear history"
          >
            <span className="material-symbols-rounded" aria-hidden="true">delete_sweep</span>
          </button>
        )}
      </div>

      <div className="visor-chat-messages" ref={scrollRef}>
        {messages.length === 0 ? (
          <p className="placeholder-text">Ask Visor anything about the runtime state.</p>
        ) : (
          messages.map((msg) => (
            <article
              key={msg.id}
              className={`agent-chat-message ${msg.role === "user" ? "user" : "assistant"}${msg.streaming ? " streaming" : ""}`}
            >
              <div className="agent-chat-message-head">
                <strong>{msg.role === "user" ? "you" : "visor"}</strong>
              </div>
              <div className="agent-chat-message-body">
                {msg.streaming && msg.text.length === 0 ? (
                  <div className="agent-chat-stream-indicator">
                    <span className="agent-chat-stream-dot" />
                    <span className="agent-chat-stream-dot" />
                    <span className="agent-chat-stream-dot" />
                  </div>
                ) : (
                  <div className="markdown-body">
                    <ReactMarkdown
                      remarkPlugins={[remarkGfm]}
                      components={{
                        code(props: any) {
                          const { inline, className, children, ...rest } = props;
                          const match = /language-(\w+)/.exec(className || "");
                          return !inline && match ? (
                            <SyntaxHighlighter
                              style={oneDark as any}
                              language={match[1]}
                              PreTag="div"
                              {...rest}
                            >
                              {String(children).replace(/\n$/, "")}
                            </SyntaxHighlighter>
                          ) : (
                            <code className={className} {...rest}>
                              {children}
                            </code>
                          );
                        }
                      }}
                    >
                      {msg.text}
                    </ReactMarkdown>
                  </div>
                )}
              </div>
            </article>
          ))
        )}
      </div>

      <div className="visor-chat-compose-wrap">
        <form
          className="agent-chat-compose"
          onSubmit={(e) => {
            e.preventDefault();
            handleSend();
          }}
        >
          <div className="agent-chat-compose-row">
            <textarea
              ref={inputRef}
              className="visor-chat-textarea"
              placeholder="Ask Visor..."
              value={inputText}
              onChange={handleInputChange}
              onKeyDown={handleKeyDown}
              disabled={isSending}
              rows={1}
            />
            <div className="agent-chat-compose-right">
              {isSending ? (
                <button
                  type="button"
                  className="agent-chat-icon-button agent-chat-send-button danger"
                  onClick={handleStop}
                >
                  <span className="material-symbols-rounded" aria-hidden="true">stop</span>
                </button>
              ) : (
                <button
                  type="submit"
                  className="agent-chat-icon-button agent-chat-send-button"
                  disabled={!inputText.trim()}
                >
                  <span className="material-symbols-rounded" aria-hidden="true">arrow_upward</span>
                </button>
              )}
            </div>
          </div>
        </form>
      </div>
    </section>
  );
}
