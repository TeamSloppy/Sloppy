import React, { useEffect, useRef, useState } from "react";
import { fetchAccessUsers } from "../../../api";

interface AccessUser {
  id: string;
  platform: string;
  platformUserId: string;
  displayName: string;
  status: string;
}

interface UserIdPickerProps {
  platform: string;
  selectedIds: string[];
  onChange: (ids: string[]) => void;
}

export function UserIdPicker({ platform, selectedIds, onChange }: UserIdPickerProps) {
  const [users, setUsers] = useState<AccessUser[]>([]);
  const [search, setSearch] = useState("");
  const [open, setOpen] = useState(false);
  const searchRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let cancelled = false;
    fetchAccessUsers(platform).then((res) => {
      if (!cancelled && Array.isArray(res)) {
        setUsers(res as unknown as AccessUser[]);
      }
    });
    return () => { cancelled = true; };
  }, [platform]);

  const selectedSet = new Set(selectedIds);

  const filtered = users.filter((u) => {
    if (u.status !== "approved") return false;
    if (selectedSet.has(u.platformUserId)) return false;
    const q = search.toLowerCase();
    return (
      u.displayName.toLowerCase().includes(q) ||
      u.platformUserId.toLowerCase().includes(q)
    );
  });

  function addUser(user: AccessUser) {
    if (selectedSet.has(user.platformUserId)) return;
    onChange([...selectedIds, user.platformUserId]);
    setSearch("");
  }

  function removeId(id: string) {
    onChange(selectedIds.filter((x) => x !== id));
  }

  function labelForId(id: string) {
    const user = users.find((u) => u.platformUserId === id);
    return user ? user.displayName : id;
  }

  return (
    <div className="user-id-picker">
      {selectedIds.length > 0 && (
        <div className="actor-team-tags" style={{ marginBottom: 6 }}>
          {selectedIds.map((id) => (
            <span key={id} className="actor-team-tag">
              {labelForId(id)}
              <button
                type="button"
                className="actor-team-tag-remove"
                onClick={() => removeId(id)}
                title="Remove"
              >
                ×
              </button>
            </span>
          ))}
        </div>
      )}

      <div className="actor-team-search-wrap">
        <input
          ref={searchRef}
          className="actor-team-search"
          value={search}
          onChange={(e) => { setSearch(e.target.value); setOpen(true); }}
          onFocus={() => setOpen(true)}
          onBlur={() => setTimeout(() => setOpen(false), 150)}
          placeholder="Search approved users…"
          autoComplete="off"
        />
        {open && (
          <ul className="actor-team-dropdown">
            {filtered.map((user) => (
              <li
                key={user.id}
                className="actor-team-dropdown-item"
                onMouseDown={(e) => { e.preventDefault(); addUser(user); }}
              >
                <span className="actor-team-dropdown-name">{user.displayName}</span>
                <span className="actor-team-dropdown-id">{user.platformUserId}</span>
              </li>
            ))}
            {filtered.length === 0 && (
              <li className="actor-team-dropdown-empty">
                {users.filter((u) => u.status === "approved").length === 0
                  ? "No approved users yet"
                  : "No matching users"}
              </li>
            )}
          </ul>
        )}
      </div>
    </div>
  );
}
