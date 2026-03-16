import React, { useState } from "react";

function formatCommentTime(dateValue) {
  const date = new Date(dateValue);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

export function ReviewCommentWidget({ filePath, lineNumber, side, comments, onAdd, onResolve, onDelete, onClose }) {
  const [draft, setDraft] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const lineComments = comments.filter(
    (c) => c.filePath === filePath && c.lineNumber === lineNumber && (side ? c.side === side : true)
  );

  async function handleSubmit(event) {
    event.preventDefault();
    const trimmed = draft.trim();
    if (!trimmed) return;
    setSubmitting(true);
    await onAdd({ filePath, lineNumber, side, content: trimmed, author: "user" });
    setDraft("");
    setSubmitting(false);
  }

  return (
    <div className="review-comment-widget">
      {lineComments.length > 0 && (
        <div className="review-comment-list">
          {lineComments.map((comment) => (
            <div key={comment.id} className={`review-comment ${comment.resolved ? "resolved" : ""}`}>
              <div className="review-comment-head">
                <span className="review-comment-author">
                  <span className="material-symbols-rounded" aria-hidden="true">
                    {comment.author === "assistant" ? "smart_toy" : "person"}
                  </span>
                  {comment.author}
                </span>
                <span className="review-comment-time">{formatCommentTime(comment.createdAt)}</span>
                <div className="review-comment-actions">
                  <button
                    type="button"
                    className="review-comment-action-btn"
                    title={comment.resolved ? "Unresolve" : "Resolve"}
                    onClick={() => onResolve(comment.id, !comment.resolved)}
                  >
                    <span className="material-symbols-rounded" aria-hidden="true">
                      {comment.resolved ? "check_circle" : "radio_button_unchecked"}
                    </span>
                  </button>
                  <button
                    type="button"
                    className="review-comment-action-btn danger"
                    title="Delete"
                    onClick={() => onDelete(comment.id)}
                  >
                    <span className="material-symbols-rounded" aria-hidden="true">delete</span>
                  </button>
                </div>
              </div>
              <p className="review-comment-body">{comment.content}</p>
            </div>
          ))}
        </div>
      )}

      <form className="review-comment-form" onSubmit={handleSubmit}>
        <textarea
          className="review-comment-input"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Add a comment..."
          rows={2}
          disabled={submitting}
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
              e.preventDefault();
              handleSubmit(e);
            }
          }}
        />
        <div className="review-comment-form-actions">
          <button type="button" className="review-comment-cancel-btn" onClick={onClose}>Cancel</button>
          <button type="submit" className="review-comment-submit-btn" disabled={!draft.trim() || submitting}>
            Comment
          </button>
        </div>
      </form>
    </div>
  );
}

export function ReviewCommentBadge({ count }) {
  if (!count) return null;
  return (
    <span className="review-comment-badge" title={`${count} comment${count === 1 ? "" : "s"}`}>
      <span className="material-symbols-rounded" aria-hidden="true">comment</span>
      {count}
    </span>
  );
}
