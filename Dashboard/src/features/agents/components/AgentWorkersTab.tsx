import React, { useEffect, useRef, useState } from "react";
import { fetchWorkers } from "../../../api";

const POLL_INTERVAL_MS = 5000;

function extractAgentIdAndSessionId(channelId: string): { agentId: string; sessionId: string } | null {
  const agentMarker = "agent:";
  const sessionMarker = ":session:";
  if (!channelId.startsWith(agentMarker)) return null;
  const sessionIdx = channelId.indexOf(sessionMarker);
  if (sessionIdx < 0) return null;
  const agentId = channelId.slice(agentMarker.length, sessionIdx);
  const sessionId = channelId.slice(sessionIdx + sessionMarker.length);
  if (!agentId || !sessionId) return null;
  return { agentId, sessionId };
}

function workerBelongsToAgent(worker: Record<string, unknown>, agentId: string): boolean {
  const channelId = String(worker.channelId ?? "");
  if (channelId.includes(`agent:${agentId}:`)) return true;
  if (String(worker.agentId ?? "") === agentId) return true;
  return false;
}

function formatRelativeTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const diffMs = Date.now() - date.getTime();
  const diffMinutes = Math.round(diffMs / 60000);
  if (Math.abs(diffMinutes) < 1) return "just now";
  if (Math.abs(diffMinutes) < 60) return `${diffMinutes}m ago`;
  const diffHours = Math.round(diffMinutes / 60);
  if (Math.abs(diffHours) < 24) return `${diffHours}h ago`;
  return `${Math.round(diffHours / 24)}d ago`;
}

function previewText(value: string, limit = 120): string {
  const normalized = String(value ?? "").replace(/\s+/g, " ").trim();
  if (!normalized) return "";
  return normalized.length > limit ? `${normalized.slice(0, limit)}...` : normalized;
}

type WorkerStatus = "running" | "queued" | "waitinginput" | "waiting_input" | "completed" | "failed" | string;

const STATUS_DOT_CLASS: Record<string, string> = {
  running: "channel-dot-active",
  queued: "worker-dot-queued",
  waitinginput: "worker-dot-waiting",
  waiting_input: "worker-dot-waiting",
  completed: "worker-dot-done",
  failed: "worker-dot-failed"
};

const STATUS_LABEL: Record<string, string> = {
  running: "Running",
  queued: "Queued",
  waitinginput: "Waiting input",
  waiting_input: "Waiting input",
  completed: "Completed",
  failed: "Failed"
};

function StatusDot({ status }: { status: WorkerStatus }) {
  const cls = STATUS_DOT_CLASS[status] ?? "worker-dot-done";
  return <span className={`channel-card-dot ${cls}`} aria-hidden="true" />;
}

interface AgentWorkersTabProps {
  agentId: string;
  onOpenWorkerSession: ((agentId: string, sessionId: string) => void) | null;
}

export function AgentWorkersTab({ agentId, onOpenWorkerSession }: AgentWorkersTabProps) {
  const [workers, setWorkers] = useState<Record<string, unknown>[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const pollTimerRef = useRef<number | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      const all = await fetchWorkers();
      if (cancelled) return;
      const filtered = all.filter((w) =>
        workerBelongsToAgent(w as Record<string, unknown>, agentId)
      ) as Record<string, unknown>[];
      setWorkers(filtered);
      setIsLoading(false);
    }

    function schedule() {
      if (cancelled) return;
      load()
        .catch(() => { if (!cancelled) setIsLoading(false); })
        .finally(() => {
          if (!cancelled) {
            pollTimerRef.current = window.setTimeout(schedule, POLL_INTERVAL_MS);
          }
        });
    }

    setIsLoading(true);
    schedule();

    return () => {
      cancelled = true;
      if (pollTimerRef.current != null) {
        window.clearTimeout(pollTimerRef.current);
        pollTimerRef.current = null;
      }
    };
  }, [agentId]);

  function handleOpen(worker: Record<string, unknown>) {
    if (typeof onOpenWorkerSession !== "function") return;
    const channelId = String(worker.channelId ?? "");
    const parsed = extractAgentIdAndSessionId(channelId);
    if (!parsed) return;
    onOpenWorkerSession(parsed.agentId, parsed.sessionId);
  }

  return (
    <section className="entry-editor-card agent-content-card">
      <div className="overview-section-header">
        <h3>
          <span className="material-symbols-rounded">deployed_code</span>
          Workers
        </h3>
        {workers.length > 0 && (
          <span className="overview-section-count">{workers.length}</span>
        )}
      </div>

      {isLoading ? (
        <div className="overview-empty-state">
          <span className="material-symbols-rounded overview-empty-icon">hourglass_empty</span>
          <p>Loading workers...</p>
        </div>
      ) : workers.length === 0 ? (
        <div className="overview-empty-state">
          <span className="material-symbols-rounded overview-empty-icon">deployed_code</span>
          <p>No workers spawned by this agent yet.</p>
        </div>
      ) : (
        <div className="active-channels-grid">
          {workers.map((worker, index) => {
            const workerId = String(worker.workerId ?? `worker-${index}`);
            const title = String(worker.title ?? worker.taskId ?? workerId);
            const status = String(worker.status ?? "unknown") as WorkerStatus;
            const mode = String(worker.mode ?? "");
            const taskId = String(worker.taskId ?? "");
            const updatedAt = String(worker.updatedAt ?? worker.createdAt ?? "");
            const latestReport = String(worker.latestReport ?? "");
            const canOpen = typeof onOpenWorkerSession === "function" &&
              !!extractAgentIdAndSessionId(String(worker.channelId ?? ""));

            return (
              <button
                key={workerId}
                type="button"
                className="channel-card hover-levitate"
                disabled={!canOpen}
                onClick={() => handleOpen(worker)}
              >
                <div className="channel-card-head">
                  <StatusDot status={status} />
                  <span className="channel-card-title">{title}</span>
                  {mode ? (
                    <span className="channel-card-members">{mode}</span>
                  ) : null}
                </div>

                <div className="channel-card-sub">
                  {STATUS_LABEL[status] ?? status}
                  {updatedAt ? ` · ${formatRelativeTime(updatedAt)}` : ""}
                </div>

                {(latestReport || taskId) ? (
                  <div className="channel-card-messages">
                    {latestReport ? (
                      <div className="channel-card-preview" style={{ minHeight: "unset" }}>
                        {previewText(latestReport)}
                      </div>
                    ) : taskId ? (
                      <div className="channel-card-preview" style={{ minHeight: "unset", opacity: 0.55 }}>
                        Task: {taskId}
                      </div>
                    ) : null}
                  </div>
                ) : null}

                <div className="channel-card-footer">
                  <span />
                  {canOpen && (
                    <span className="material-symbols-rounded channel-card-arrow">
                      arrow_forward
                    </span>
                  )}
                </div>
              </button>
            );
          })}
        </div>
      )}
    </section>
  );
}
