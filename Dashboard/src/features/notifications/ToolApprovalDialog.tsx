import React, { useEffect, useState } from "react";
import {
  approveToolApproval,
  fetchPendingToolApprovals,
  rejectToolApproval
} from "../../api";

interface ToolApprovalRecord {
  id: string;
  status: "pending" | "approved" | "rejected" | "timed_out";
  agentId: string;
  sessionId?: string;
  channelId?: string;
  topicId?: string;
  tool: string;
  arguments?: Record<string, unknown>;
  reason?: string;
  requestedBy?: string;
  createdAt: string;
  expiresAt: string;
}

interface ToolApprovalDialogProps {
  approvalId: string;
  onClose: () => void;
  onResolved?: () => void;
  onNavigateToAgent?: (agentId: string, sessionId?: string) => void;
}

function formatDateTime(value?: string): string {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString();
}

function formatArguments(value?: Record<string, unknown>): string {
  if (!value || Object.keys(value).length === 0) {
    return "{}";
  }
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

export function ToolApprovalDialog({
  approvalId,
  onClose,
  onResolved,
  onNavigateToAgent
}: ToolApprovalDialogProps) {
  const [entry, setEntry] = useState<ToolApprovalRecord | null>(null);
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState("");
  const [working, setWorking] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      const list = await fetchPendingToolApprovals();
      if (cancelled) return;
      if (Array.isArray(list)) {
        const found = (list as unknown as ToolApprovalRecord[]).find((approval) => approval.id === approvalId);
        setEntry(found ?? null);
      }
      setLoading(false);
    }
    load().catch(() => setLoading(false));
    return () => { cancelled = true; };
  }, [approvalId]);

  async function resolve(approved: boolean) {
    setWorking(true);
    setStatus("");
    const record = approved
      ? await approveToolApproval(approvalId)
      : await rejectToolApproval(approvalId);
    setWorking(false);

    if (record) {
      setStatus(approved ? "Approved." : "Rejected.");
      onResolved?.();
      setTimeout(onClose, 700);
    } else {
      setStatus("Request not found or already resolved.");
      setEntry(null);
    }
  }

  function openSession() {
    if (!entry || !onNavigateToAgent) return;
    onClose();
    onNavigateToAgent(entry.agentId, entry.sessionId);
  }

  return (
    <div className="tg-modal-overlay" onClick={onClose}>
      <div className="tg-modal" onClick={(e) => e.stopPropagation()}>
        <div className="tg-modal-header">
          <h3>Tool Approval</h3>
          <button type="button" className="tg-modal-close" onClick={onClose}>
            <span className="material-symbols-rounded">close</span>
          </button>
        </div>

        <div className="tg-modal-body">
          {loading && <p style={{ margin: 0, color: "var(--text-muted)" }}>Loading...</p>}

          {!loading && !entry && (
            <p style={{ margin: 0, color: "var(--text-muted)" }}>
              Request not found or already resolved.
            </p>
          )}

          {!loading && entry && (
            <>
              <div className="tg-modal-field">
                <span className="tg-modal-field-label">Tool</span>
                <span style={{ fontSize: "0.9rem" }}>{entry.tool}</span>
              </div>

              <div className="tg-modal-field">
                <span className="tg-modal-field-label">Reason</span>
                <span style={{ fontSize: "0.9rem", color: "var(--text-muted)" }}>
                  {entry.reason?.trim() || "No reason provided."}
                </span>
              </div>

              <div className="tg-modal-field">
                <span className="tg-modal-field-label">Agent</span>
                <span style={{ fontSize: "0.9rem", color: "var(--text-muted)" }}>
                  {entry.agentId}
                  {entry.sessionId ? ` / ${entry.sessionId}` : ""}
                </span>
              </div>

              <div className="tg-modal-field">
                <span className="tg-modal-field-label">Expires</span>
                <span style={{ fontSize: "0.9rem", color: "var(--text-muted)" }}>
                  {formatDateTime(entry.expiresAt)}
                </span>
              </div>

              <div className="tg-modal-field">
                <span className="tg-modal-field-label">Arguments</span>
                <pre className="agent-chat-expandable-pre" style={{ maxHeight: 220 }}>
                  {formatArguments(entry.arguments)}
                </pre>
                {status && (
                  <span style={{ fontSize: "0.82rem", color: status.endsWith(".") ? "var(--accent)" : "var(--danger)", marginTop: 4 }}>
                    {status}
                  </span>
                )}
              </div>
            </>
          )}
        </div>

        {!loading && entry && (
          <div className="tg-modal-actions">
            {onNavigateToAgent && (
              <button type="button" className="tg-modal-cancel hover-levitate" onClick={openSession} disabled={working}>
                View Session
              </button>
            )}
            <button
              type="button"
              className="tg-modal-cancel hover-levitate"
              onClick={() => void resolve(false)}
              disabled={working}
              style={{ color: "var(--text-muted)" }}
            >
              Reject
            </button>
            <button
              type="button"
              className="tg-modal-submit hover-levitate"
              onClick={() => void resolve(true)}
              disabled={working}
            >
              Approve
            </button>
          </div>
        )}

        {!loading && !entry && (
          <div className="tg-modal-actions">
            <button type="button" className="tg-modal-cancel" onClick={onClose}>
              Close
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
