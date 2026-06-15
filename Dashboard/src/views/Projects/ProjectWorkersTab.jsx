import React, { useMemo, useState } from "react";
import { cancelWorker } from "../../api";
import { parseAgentWorkerChannelId, workersForProject } from "./utils";

const STATUS_DOT_CLASS = {
  running: "channel-dot-active",
  queued: "worker-dot-queued",
  waitinginput: "worker-dot-waiting",
  waiting_input: "worker-dot-waiting",
  completed: "worker-dot-done",
  failed: "worker-dot-failed"
};

const STATUS_LABEL = {
  running: "Running",
  queued: "Queued",
  waitinginput: "Waiting input",
  waiting_input: "Waiting input",
  completed: "Completed",
  failed: "Failed"
};

const ACTIVE_STATUSES = new Set(["running", "waitinginput", "waiting_input"]);
const QUEUED_STATUSES = new Set(["queued"]);
const HISTORICAL_STATUSES = new Set(["completed", "failed"]);

function normalizeStatus(worker) {
  return String(worker?.status || "unknown").trim().toLowerCase();
}

function statusLabel(status) {
  return STATUS_LABEL[status] || status || "Unknown";
}

function formatRelativeTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }
  const diffMs = Date.now() - date.getTime();
  const diffMinutes = Math.round(diffMs / 60000);
  if (Math.abs(diffMinutes) < 1) return "just now";
  if (Math.abs(diffMinutes) < 60) return `${diffMinutes}m ago`;
  const diffHours = Math.round(diffMinutes / 60);
  if (Math.abs(diffHours) < 24) return `${diffHours}h ago`;
  return `${Math.round(diffHours / 24)}d ago`;
}

function previewText(value, limit = 160) {
  const normalized = String(value || "").replace(/\s+/g, " ").trim();
  if (!normalized) {
    return "";
  }
  return normalized.length > limit ? `${normalized.slice(0, limit)}...` : normalized;
}

function workerTitle(worker, index) {
  return String(worker?.title || worker?.taskId || worker?.workerId || `worker-${index}`);
}

function workerUpdatedAt(worker) {
  return String(worker?.updatedAt || worker?.startedAt || worker?.createdAt || "");
}

function sortWorkers(left, right) {
  const leftStatus = normalizeStatus(left);
  const rightStatus = normalizeStatus(right);
  const rank = (status) => {
    if (ACTIVE_STATUSES.has(status)) return 0;
    if (QUEUED_STATUSES.has(status)) return 1;
    if (HISTORICAL_STATUSES.has(status)) return 2;
    return 3;
  };
  const statusRank = rank(leftStatus) - rank(rightStatus);
  if (statusRank !== 0) {
    return statusRank;
  }
  return new Date(workerUpdatedAt(right) || 0).getTime() - new Date(workerUpdatedAt(left) || 0).getTime();
}

function StatusDot({ status }) {
  const cls = STATUS_DOT_CLASS[status] || "worker-dot-done";
  return <span className={`channel-card-dot ${cls}`} aria-hidden="true" />;
}

function WorkerDetailsModal({ worker, onClose, onOpenSession, canOpenSession, onCancel, isCancelling }) {
  if (!worker) {
    return null;
  }

  const status = normalizeStatus(worker);
  const parsed = parseAgentWorkerChannelId(worker.channelId);
  const workerId = String(worker.workerId || "");
  const latestReport = String(worker.latestReport || "");
  const updatedAt = workerUpdatedAt(worker);
  const createdAt = String(worker.createdAt || "");
  const startedAt = String(worker.startedAt || "");
  const tools = Array.isArray(worker.tools) ? worker.tools : [];
  const canCancel = ACTIVE_STATUSES.has(status) || QUEUED_STATUSES.has(status);

  return (
    <div className="project-worker-modal-backdrop" role="presentation" onClick={onClose}>
      <section
        className="project-worker-modal"
        role="dialog"
        aria-modal="true"
        aria-label="Worker details"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="project-worker-modal-header">
          <div>
            <div className="project-worker-status-line">
              <StatusDot status={status} />
              <span>{statusLabel(status)}</span>
            </div>
            <h3>{String(worker.title || worker.taskId || workerId || "Worker")}</h3>
          </div>
          <button type="button" className="project-worker-icon-btn" onClick={onClose} aria-label="Close worker details">
            <span className="material-symbols-rounded">close</span>
          </button>
        </div>

        <dl className="project-worker-detail-grid">
          <div>
            <dt>Worker</dt>
            <dd>{workerId || "unknown"}</dd>
          </div>
          <div>
            <dt>Task</dt>
            <dd>{String(worker.taskId || "unknown")}</dd>
          </div>
          <div>
            <dt>Channel</dt>
            <dd>{String(worker.channelId || "unknown")}</dd>
          </div>
          <div>
            <dt>Agent</dt>
            <dd>{parsed?.agentId || "unknown"}</dd>
          </div>
          <div>
            <dt>Session</dt>
            <dd>{parsed?.sessionId || "unknown"}</dd>
          </div>
          <div>
            <dt>Mode</dt>
            <dd>{String(worker.mode || "unknown")}</dd>
          </div>
          <div>
            <dt>Created</dt>
            <dd>{createdAt ? `${formatRelativeTime(createdAt)} · ${createdAt}` : "unknown"}</dd>
          </div>
          <div>
            <dt>Updated</dt>
            <dd>{updatedAt ? `${formatRelativeTime(updatedAt)} · ${updatedAt}` : "unknown"}</dd>
          </div>
          <div>
            <dt>Started</dt>
            <dd>{startedAt ? `${formatRelativeTime(startedAt)} · ${startedAt}` : "not started"}</dd>
          </div>
          <div>
            <dt>Tools</dt>
            <dd>{tools.length > 0 ? tools.join(", ") : "none"}</dd>
          </div>
        </dl>

        {latestReport ? (
          <div className="project-worker-report">
            <h4>Latest report</h4>
            <p>{latestReport}</p>
          </div>
        ) : null}

        <div className="project-worker-modal-actions">
          <button type="button" className="secondary-action" disabled={!canOpenSession} onClick={() => onOpenSession(worker)}>
            <span className="material-symbols-rounded">open_in_new</span>
            Open Chat
          </button>
          <button
            type="button"
            className="danger-action"
            disabled={!canCancel || isCancelling}
            onClick={() => onCancel(worker)}
          >
            <span className="material-symbols-rounded">cancel</span>
            {isCancelling ? "Cancelling..." : "Cancel Worker"}
          </button>
        </div>
      </section>
    </div>
  );
}

export function ProjectWorkersTab({
  project,
  workers,
  onOpenWorkerSession = null,
  onWorkersChanged = null
}) {
  const [selectedWorker, setSelectedWorker] = useState(null);
  const [cancellingWorkerId, setCancellingWorkerId] = useState("");

  const projectWorkers = useMemo(
    () => workersForProject(project, workers).slice().sort(sortWorkers),
    [project, workers]
  );

  const counts = useMemo(() => {
    const next = { active: 0, queued: 0, historical: 0 };
    for (const worker of projectWorkers) {
      const status = normalizeStatus(worker);
      if (ACTIVE_STATUSES.has(status)) {
        next.active += 1;
      } else if (QUEUED_STATUSES.has(status)) {
        next.queued += 1;
      } else {
        next.historical += 1;
      }
    }
    return next;
  }, [projectWorkers]);

  function canOpenSession(worker) {
    const parsed = parseAgentWorkerChannelId(worker?.channelId);
    return Boolean(parsed?.agentId && parsed?.sessionId && typeof onOpenWorkerSession === "function");
  }

  function handleOpenSession(worker) {
    const parsed = parseAgentWorkerChannelId(worker?.channelId);
    if (!parsed?.agentId || !parsed?.sessionId || typeof onOpenWorkerSession !== "function") {
      return;
    }
    onOpenWorkerSession(parsed.agentId, parsed.sessionId);
  }

  async function handleCancel(worker) {
    const workerId = String(worker?.workerId || "");
    if (!workerId || cancellingWorkerId) {
      return;
    }
    if (!window.confirm(`Cancel worker ${workerId}?`)) {
      return;
    }

    setCancellingWorkerId(workerId);
    const response = await cancelWorker(workerId, { reason: "Cancelled from project workers dashboard" });
    setCancellingWorkerId("");
    if (!response) {
      window.alert("Failed to cancel worker.");
      return;
    }
    if (typeof onWorkersChanged === "function") {
      await onWorkersChanged();
    }
  }

  if (projectWorkers.length === 0) {
    return (
      <div className="project-tab-placeholder">
        <h3>Workers</h3>
        <p>No workers are linked to this project yet.</p>
      </div>
    );
  }

  return (
    <section className="project-tab-layout">
      <section className="project-pane">
        <div className="project-workers-header">
          <h4>Workers</h4>
          <div className="project-workers-counts">
            <span>{counts.active} active</span>
            <span>{counts.queued} queued</span>
            <span>{counts.historical} historical</span>
          </div>
        </div>

        <div className="active-channels-grid project-workers-grid">
          {projectWorkers.map((worker, index) => {
            const workerId = String(worker?.workerId || `worker-${index}`);
            const status = normalizeStatus(worker);
            const title = workerTitle(worker, index);
            const mode = String(worker?.mode || "");
            const taskId = String(worker?.taskId || "");
            const updatedAt = workerUpdatedAt(worker);
            const latestReport = previewText(worker?.latestReport || worker?.objective || "");
            const canOpen = canOpenSession(worker);
            const canCancel = ACTIVE_STATUSES.has(status) || QUEUED_STATUSES.has(status);
            const isCancelling = cancellingWorkerId === workerId;

            return (
              <article
                key={workerId}
                className="channel-card project-worker-card"
                tabIndex={0}
                onClick={() => setSelectedWorker(worker)}
                onKeyDown={(event) => {
                  if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    setSelectedWorker(worker);
                  }
                }}
              >
                <div className="channel-card-head">
                  <StatusDot status={status} />
                  <span className="channel-card-title">{title}</span>
                  {mode ? <span className="channel-card-members">{mode}</span> : null}
                </div>

                <div className="channel-card-sub">
                  {statusLabel(status)}
                  {updatedAt ? ` · ${formatRelativeTime(updatedAt)}` : ""}
                </div>

                <div className="channel-card-messages">
                  <div className="channel-card-preview" style={{ minHeight: "unset" }}>
                    {latestReport || `Task: ${taskId || "unknown"}`}
                  </div>
                </div>

                <div className="project-worker-meta-row">
                  <span>{taskId || "unknown task"}</span>
                  <span>{String(worker?.channelId || "unknown channel")}</span>
                </div>

                <div className="project-worker-actions">
                  <button
                    type="button"
                    className="secondary-action"
                    disabled={!canOpen}
                    onClick={(event) => {
                      event.stopPropagation();
                      handleOpenSession(worker);
                    }}
                  >
                    <span className="material-symbols-rounded">open_in_new</span>
                    Open
                  </button>
                  <button
                    type="button"
                    className="danger-action"
                    disabled={!canCancel || isCancelling}
                    onClick={(event) => {
                      event.stopPropagation();
                      handleCancel(worker);
                    }}
                  >
                    <span className="material-symbols-rounded">cancel</span>
                    {isCancelling ? "Cancelling" : "Cancel"}
                  </button>
                </div>
              </article>
            );
          })}
        </div>
      </section>

      <WorkerDetailsModal
        worker={selectedWorker}
        onClose={() => setSelectedWorker(null)}
        onOpenSession={handleOpenSession}
        canOpenSession={canOpenSession(selectedWorker)}
        onCancel={handleCancel}
        isCancelling={Boolean(cancellingWorkerId)}
      />
    </section>
  );
}
