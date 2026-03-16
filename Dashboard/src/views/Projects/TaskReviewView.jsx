import React, { useCallback, useEffect, useState } from "react";
import {
  fetchTaskDiff,
  approveProjectTask,
  rejectProjectTask,
  fetchReviewComments,
  addReviewComment,
  updateReviewComment,
  deleteReviewComment
} from "../../api";
import { ReviewDiffPanel } from "./ReviewDiffPanel";
import { ReviewChatPanel } from "./ReviewChatPanel";

export function TaskReviewView({ project, task, onClose, onProjectRefresh }) {
  const [diffData, setDiffData] = useState(null);
  const [comments, setComments] = useState([]);
  const [loadingDiff, setLoadingDiff] = useState(true);
  const [statusText, setStatusText] = useState("");
  const [rejectReason, setRejectReason] = useState("");
  const [showRejectDialog, setShowRejectDialog] = useState(false);
  const [working, setWorking] = useState(false);

  const projectId = project?.id || "";
  const taskId = task?.id || "";
  const agentId = task?.claimedAgentId || null;

  useEffect(() => {
    if (!projectId || !taskId) return;
    let cancelled = false;

    async function load() {
      setLoadingDiff(true);
      const [diff, commentList] = await Promise.all([
        fetchTaskDiff(projectId, taskId),
        fetchReviewComments(projectId, taskId)
      ]);
      if (cancelled) return;
      setDiffData(diff);
      setComments(Array.isArray(commentList) ? commentList : []);
      setLoadingDiff(false);
    }

    load().catch(() => {
      if (!cancelled) setLoadingDiff(false);
    });

    return () => { cancelled = true; };
  }, [projectId, taskId]);

  const handleAddComment = useCallback(async (payload) => {
    const comment = await addReviewComment(projectId, taskId, payload);
    if (comment) {
      setComments((prev) => [...prev, comment]);
    }
  }, [projectId, taskId]);

  const handleResolveComment = useCallback(async (commentId, resolved) => {
    const updated = await updateReviewComment(projectId, taskId, commentId, { resolved });
    if (updated) {
      setComments((prev) => prev.map((c) => c.id === commentId ? updated : c));
    }
  }, [projectId, taskId]);

  const handleDeleteComment = useCallback(async (commentId) => {
    const ok = await deleteReviewComment(projectId, taskId, commentId);
    if (ok) {
      setComments((prev) => prev.filter((c) => c.id !== commentId));
    }
  }, [projectId, taskId]);

  async function handleApprove() {
    if (working) return;
    if (!window.confirm("Approve this task? The worktree branch will be merged.")) return;
    setWorking(true);
    setStatusText("Approving...");
    const ok = await approveProjectTask(projectId, taskId);
    if (ok) {
      setStatusText("Task approved.");
      onProjectRefresh?.();
      onClose?.();
    } else {
      setStatusText("Failed to approve task.");
    }
    setWorking(false);
  }

  async function handleReject() {
    if (working) return;
    setWorking(true);
    setStatusText("Rejecting...");
    const ok = await rejectProjectTask(projectId, taskId, rejectReason.trim() || undefined);
    if (ok) {
      setStatusText("Task rejected.");
      setShowRejectDialog(false);
      setRejectReason("");
      onProjectRefresh?.();
      onClose?.();
    } else {
      setStatusText("Failed to reject task.");
    }
    setWorking(false);
  }

  const rawDiff = diffData?.diff || "";
  const branchName = diffData?.branchName || task?.worktreeBranch || "";
  const baseBranch = diffData?.baseBranch || "main";
  const unresolvedCount = comments.filter((c) => !c.resolved).length;

  return (
    <div className="task-review-view">
      <header className="task-review-header">
        <div className="task-review-header-left">
          <button type="button" className="task-review-back-btn" onClick={onClose} title="Back to tasks">
            <span className="material-symbols-rounded" aria-hidden="true">arrow_back</span>
          </button>
          <div className="task-review-title-block">
            <span className="task-review-badge">Review</span>
            <h2 className="task-review-title">{task?.title || "Task Review"}</h2>
            {branchName && (
              <span className="task-review-branch">
                <span className="material-symbols-rounded" aria-hidden="true">account_tree</span>
                {branchName}
                {baseBranch && <span className="task-review-branch-arrow">← {baseBranch}</span>}
              </span>
            )}
          </div>
        </div>

        <div className="task-review-header-right">
          {unresolvedCount > 0 && (
            <span className="task-review-unresolved-badge" title={`${unresolvedCount} unresolved comment${unresolvedCount !== 1 ? "s" : ""}`}>
              <span className="material-symbols-rounded" aria-hidden="true">comment</span>
              {unresolvedCount}
            </span>
          )}

          {statusText && (
            <span className="task-review-status placeholder-text">{statusText}</span>
          )}

          <button
            type="button"
            className="task-review-action-btn danger"
            onClick={() => setShowRejectDialog(true)}
            disabled={working}
            title="Reject task"
          >
            <span className="material-symbols-rounded" aria-hidden="true">close</span>
            Reject
          </button>

          <button
            type="button"
            className="task-review-action-btn approve"
            onClick={handleApprove}
            disabled={working}
            title="Approve and merge"
          >
            <span className="material-symbols-rounded" aria-hidden="true">check</span>
            Approve
          </button>
        </div>
      </header>

      <div className="task-review-body">
        <div className="task-review-diff-area">
          {loadingDiff ? (
            <div className="review-diff-empty">
              <p className="placeholder-text">Loading diff...</p>
            </div>
          ) : (
            <ReviewDiffPanel
              rawDiff={rawDiff}
              comments={comments}
              onAddComment={handleAddComment}
              onResolveComment={handleResolveComment}
              onDeleteComment={handleDeleteComment}
            />
          )}
        </div>

        <ReviewChatPanel
          agentId={agentId}
          taskTitle={task?.title || ""}
          diff={rawDiff}
        />
      </div>

      {showRejectDialog && (
        <div className="task-review-dialog-overlay" onClick={() => setShowRejectDialog(false)}>
          <div className="task-review-dialog" onClick={(e) => e.stopPropagation()}>
            <div className="task-review-dialog-head">
              <h3>Reject Task</h3>
              <button type="button" onClick={() => setShowRejectDialog(false)}>
                <span className="material-symbols-rounded" aria-hidden="true">close</span>
              </button>
            </div>
            <div className="task-review-dialog-body">
              <label>
                Reason <span className="task-review-optional">(optional)</span>
                <textarea
                  value={rejectReason}
                  onChange={(e) => setRejectReason(e.target.value)}
                  placeholder="Describe what needs to be changed..."
                  rows={4}
                  autoFocus
                />
              </label>
            </div>
            <div className="task-review-dialog-actions">
              <button
                type="button"
                className="task-review-dialog-cancel"
                onClick={() => setShowRejectDialog(false)}
              >
                Cancel
              </button>
              <button
                type="button"
                className="task-review-dialog-reject danger"
                onClick={handleReject}
                disabled={working}
              >
                Reject
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
