import React, { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { LoadingSkeleton } from "../components/LoadingSkeleton";

type AnyRecord = Record<string, unknown>;
type Level = "trace" | "debug" | "info" | "warning" | "error" | "fatal";

interface LogEntry {
  timestamp: string;
  level: Level;
  label: string;
  source: string;
  message: string;
  metadata: Record<string, string>;
}

interface LogsViewProps {
  coreApi: {
    fetchSystemLogs: () => Promise<AnyRecord | null>;
  };
}

const LOG_LEVELS: Level[] = ["trace", "debug", "info", "warning", "error", "fatal"];

const LEVEL_LABELS: Record<Level, string> = {
  trace: "trace",
  debug: "debug",
  info: "info",
  warning: "warn",
  error: "error",
  fatal: "fatal"
};

function normalizeLevel(value: unknown): Level {
  const raw = String(value || "").toLowerCase();
  if (raw === "warn") {
    return "warning";
  }
  if (raw === "critical") {
    return "fatal";
  }
  if (LOG_LEVELS.includes(raw as Level)) {
    return raw as Level;
  }
  return "info";
}

function normalizeMetadata(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }

  const metadata: Record<string, string> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    metadata[key] = String(item ?? "");
  }
  return metadata;
}

function normalizeEntry(value: unknown, index: number): LogEntry {
  const record = (value && typeof value === "object" ? value : {}) as AnyRecord;
  return {
    timestamp: String(record.timestamp || new Date().toISOString()),
    level: normalizeLevel(record.level),
    label: String(record.label || `system-${index + 1}`),
    source: String(record.source || ""),
    message: String(record.message || ""),
    metadata: normalizeMetadata(record.metadata)
  };
}

function toSearchText(entry: LogEntry) {
  const metadata = Object.entries(entry.metadata)
    .map(([key, value]) => `${key}:${value}`)
    .join(" ");
  return `${entry.message} ${entry.label} ${entry.source} ${metadata}`.toLowerCase();
}

function formatTimestamp(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleTimeString();
}

function hasMetadata(entry: LogEntry) {
  return Object.keys(entry.metadata).length > 0;
}

function formatMetadata(entry: LogEntry) {
  if (!hasMetadata(entry)) {
    return "";
  }
  return JSON.stringify(entry.metadata, null, 2);
}

export function LogsView({ coreApi }: LogsViewProps) {
  const [entries, setEntries] = useState<LogEntry[]>([]);
  const [filePath, setFilePath] = useState("");
  const [searchTerm, setSearchTerm] = useState("");
  const [autoFollow, setAutoFollow] = useState(true);
  const [isAtBottom, setIsAtBottom] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const [statusText, setStatusText] = useState("Loading logs...");
  const [levelState, setLevelState] = useState<Record<Level, boolean>>({
    trace: true,
    debug: true,
    info: true,
    warning: true,
    error: true,
    fatal: true
  });
  const feedRef = useRef<HTMLDivElement | null>(null);
  const autoFollowRef = useRef(autoFollow);
  const pendingScrollTopRef = useRef<number | null>(null);

  useEffect(() => {
    autoFollowRef.current = autoFollow;
  }, [autoFollow]);

  const updateIsAtBottom = useCallback(() => {
    const feed = feedRef.current;
    if (!feed) {
      setIsAtBottom(true);
      return;
    }

    const remainingScroll = feed.scrollHeight - feed.clientHeight - feed.scrollTop;
    setIsAtBottom(remainingScroll <= 8);
  }, []);

  const loadLogs = useCallback(
    async (silent = false) => {
      if (!autoFollowRef.current && feedRef.current) {
        pendingScrollTopRef.current = feedRef.current.scrollTop;
      }

      if (!silent) {
        setIsLoading(true);
      }

      const response = await coreApi.fetchSystemLogs();
      if (!response) {
        setStatusText("Failed to load logs from Sloppy.");
        setIsLoading(false);
        return;
      }

      const logEntries = Array.isArray(response.entries)
        ? response.entries.map((entry, index) => normalizeEntry(entry, index))
        : [];
      setEntries(logEntries);
      setFilePath(String(response.filePath || ""));
      setStatusText(`Loaded ${logEntries.length} log entries.`);
      setIsLoading(false);
    },
    [coreApi]
  );

  useEffect(() => {
    loadLogs().catch(() => {
      setStatusText("Failed to load logs from Sloppy.");
      setIsLoading(false);
    });
  }, [loadLogs]);

  useEffect(() => {
    const timerId = window.setInterval(() => {
      loadLogs(true).catch(() => {
        setStatusText("Failed to refresh logs.");
      });
    }, 2000);
    return () => window.clearInterval(timerId);
  }, [loadLogs]);

  const visibleEntries = useMemo(() => {
    const query = searchTerm.trim().toLowerCase();
    return entries.filter((entry) => {
      if (!levelState[entry.level]) {
        return false;
      }
      if (!query) {
        return true;
      }
      return toSearchText(entry).includes(query);
    });
  }, [entries, levelState, searchTerm]);

  useLayoutEffect(() => {
    const feed = feedRef.current;
    if (!feed) {
      return;
    }

    if (autoFollow) {
      feed.scrollTop = feed.scrollHeight;
    } else if (pendingScrollTopRef.current !== null) {
      feed.scrollTop = pendingScrollTopRef.current;
      pendingScrollTopRef.current = null;
    }

    updateIsAtBottom();
  }, [autoFollow, updateIsAtBottom, visibleEntries]);

  useEffect(() => {
    const feed = feedRef.current;
    if (!feed) {
      return;
    }

    updateIsAtBottom();
    feed.addEventListener("scroll", updateIsAtBottom, { passive: true });
    return () => feed.removeEventListener("scroll", updateIsAtBottom);
  }, [updateIsAtBottom]);

  function scrollToBottom() {
    const feed = feedRef.current;
    if (!feed) {
      return;
    }

    feed.scrollTo({ top: feed.scrollHeight, behavior: "smooth" });
    setIsAtBottom(true);
  }

  function toggleLevel(level: Level) {
    setLevelState((previous) => ({
      ...previous,
      [level]: !previous[level]
    }));
  }

  function exportVisible() {
    if (visibleEntries.length === 0) {
      return;
    }

    const payload = visibleEntries
      .map((entry) =>
        JSON.stringify({
          timestamp: entry.timestamp,
          level: entry.level,
          label: entry.label,
          source: entry.source,
          message: entry.message,
          metadata: entry.metadata
        })
      )
      .join("\n");

    const blob = new Blob([payload], { type: "application/jsonl;charset=utf-8" });
    const objectURL = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = objectURL;
    anchor.download = `logs-visible-${Date.now()}.log`;
    anchor.click();
    URL.revokeObjectURL(objectURL);
  }

  return (
    <main className="grid">
      <section className="panel logs-panel">
        <header className="logs-header">
          <div>
            <h2>Logs</h2>
            <p className="placeholder-text">System file logs (JSONL).</p>
          </div>
          <div className="logs-actions">
            <button type="button" className="hover-levitate" onClick={() => loadLogs()} disabled={isLoading}>
              Refresh
            </button>
            <button type="button" className="hover-levitate" onClick={exportVisible} disabled={visibleEntries.length === 0}>
              Export visible
            </button>
          </div>
        </header>

        <div className="logs-toolbar">
          <label className="logs-search">
            <span>Filter</span>
            <input
              value={searchTerm}
              onChange={(event) => setSearchTerm(event.target.value)}
              placeholder="Search logs"
            />
          </label>
          <label className="logs-autofollow">
            <span>Auto-follow</span>
            <span className="agent-tools-switch logs-switch">
              <input type="checkbox" checked={autoFollow} onChange={(event) => setAutoFollow(event.target.checked)} />
              <span className="agent-tools-switch-track" />
            </span>
          </label>
        </div>

        <div className="logs-levels">
          {LOG_LEVELS.map((level) => (
            <label key={level} className={`logs-level-pill ${level}`}>
              <input type="checkbox" checked={levelState[level]} onChange={() => toggleLevel(level)} />
              <span className="logs-level-check" aria-hidden="true" />
              <span>{LEVEL_LABELS[level]}</span>
            </label>
          ))}
        </div>

        <p className="placeholder-text logs-file">File: {filePath || "unavailable"}</p>
        <p className="placeholder-text logs-status">{statusText}</p>

        <div className="logs-feed" ref={feedRef}>
          {visibleEntries.length === 0 ? (
            isLoading ? (
              <LoadingSkeleton label="Loading logs…" variant="list" rows={6} />
            ) : (
              <div className="logs-empty placeholder-text">No log entries match current filters.</div>
            )
          ) : (
            visibleEntries.map((entry, index) => (
              <article key={`${entry.timestamp}-${index}`} className="logs-row">
                <span className="logs-time">{formatTimestamp(entry.timestamp)}</span>
                <span className={`logs-level-tag ${entry.level}`}>{LEVEL_LABELS[entry.level]}</span>
                <span className="logs-source">{entry.label}</span>
                <div className="logs-message-block">
                  <p className="logs-message">{entry.message}</p>
                  {hasMetadata(entry) ? <pre className="logs-metadata">{formatMetadata(entry)}</pre> : null}
                </div>
              </article>
            ))
          )}
        </div>
        {!autoFollow && !isAtBottom ? (
          <button type="button" className="logs-scroll-bottom" onClick={scrollToBottom} aria-label="Scroll logs to bottom" title="Scroll to bottom">
            <span className="material-symbols-rounded" aria-hidden="true">arrow_downward</span>
          </button>
        ) : null}
      </section>
    </main>
  );
}
