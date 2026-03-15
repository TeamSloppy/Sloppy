import React, { useCallback, useEffect, useState } from "react";
import { fetchAccessUsers, deleteAccessUser } from "../../../api";

interface AccessUser {
  id: string;
  platform: string;
  platformUserId: string;
  displayName: string;
  status: "approved" | "blocked";
  createdAt: string;
}

const PLATFORM_LABELS: Record<string, string> = {
  telegram: "Telegram",
  discord: "Discord",
};

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

export function ApprovalsView() {
  const [users, setUsers] = useState<AccessUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [filter, setFilter] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    const res = await fetchAccessUsers();
    if (Array.isArray(res)) {
      setUsers(res as unknown as AccessUser[]);
    }
    setLoading(false);
  }, []);

  useEffect(() => { load(); }, [load]);

  async function handleDelete(user: AccessUser) {
    setDeletingId(user.id);
    await deleteAccessUser(user.id);
    setUsers((prev) => prev.filter((u) => u.id !== user.id));
    setDeletingId(null);
  }

  const filtered = users.filter((u) => {
    if (!filter) return true;
    const q = filter.toLowerCase();
    return (
      u.displayName.toLowerCase().includes(q) ||
      u.platformUserId.toLowerCase().includes(q) ||
      u.platform.toLowerCase().includes(q)
    );
  });

  const approved = filtered.filter((u) => u.status === "approved");
  const blocked = filtered.filter((u) => u.status === "blocked");

  return (
    <section className="entry-editor-card">
      <div className="approvals-view-header">
        <h3>Channel Access Users</h3>
        <button type="button" className="tg-token-reveal" onClick={load} disabled={loading}>
          {loading ? "Loading…" : "Refresh"}
        </button>
      </div>

      <input
        className="settings-search"
        style={{ marginBottom: 16 }}
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        placeholder="Search by name or ID…"
      />

      {!loading && users.length === 0 && (
        <p className="tg-empty">No access users yet. Approve pending requests from the Channels section.</p>
      )}

      {approved.length > 0 && (
        <div className="approvals-group">
          <div className="approvals-group-title">Approved</div>
          {approved.map((user) => (
            <UserRow
              key={user.id}
              user={user}
              deleting={deletingId === user.id}
              onDelete={handleDelete}
            />
          ))}
        </div>
      )}

      {blocked.length > 0 && (
        <div className="approvals-group">
          <div className="approvals-group-title">Blocked</div>
          {blocked.map((user) => (
            <UserRow
              key={user.id}
              user={user}
              deleting={deletingId === user.id}
              onDelete={handleDelete}
            />
          ))}
        </div>
      )}
    </section>
  );
}

function UserRow({ user, deleting, onDelete }: { user: AccessUser; deleting: boolean; onDelete: (u: AccessUser) => void }) {
  return (
    <div className="approvals-user-row">
      <div className="approvals-user-info">
        <span className="approvals-platform-badge">
          {PLATFORM_LABELS[user.platform] ?? user.platform}
        </span>
        <div className="approvals-user-meta">
          <span className="approvals-user-name">{user.displayName}</span>
          <span className="approvals-user-id">{user.platformUserId}</span>
        </div>
      </div>
      <div className="approvals-user-right">
        <span className={`approvals-status-badge approvals-status-${user.status}`}>
          {user.status}
        </span>
        <span className="approvals-time">{timeAgo(user.createdAt)}</span>
        <button
          type="button"
          className="tg-modal-cancel danger hover-levitate"
          style={{ padding: "4px 10px", fontSize: "0.78rem" }}
          disabled={deleting}
          onClick={() => onDelete(user)}
        >
          Remove
        </button>
      </div>
    </div>
  );
}
