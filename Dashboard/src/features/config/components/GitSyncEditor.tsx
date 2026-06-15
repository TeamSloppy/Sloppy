import React from "react";

export function GitSyncEditor({
  draftConfig,
  mutateDraft,
  normalizeGitSyncFrequency,
  normalizeGitSyncConflictStrategy,
  normalizeTimeValue,
  gitSyncRunning,
  gitSyncStatusText,
  onRunGitSyncNow
}) {
  const gitSyncEnabled = Boolean(draftConfig.gitSync?.enabled);
  const syncFrequency = normalizeGitSyncFrequency(draftConfig.gitSync?.schedule?.frequency);
  const conflictStrategy = normalizeGitSyncConflictStrategy(draftConfig.gitSync?.conflictStrategy);
  const status = draftConfig.gitSync?.status || {};
  const failedAttempts = Number.parseInt(String(status.failedAttempts || 0), 10) || 0;
  const hasActiveFailure = failedAttempts > 0 || Boolean(status.lastError);
  const statusTone = hasActiveFailure ? "is-warning" : status.lastSuccessAt ? "is-ok" : "";
  const lastCommit = String(status.lastCommit || "");
  const lastFilesChanged = Number.parseInt(String(status.lastFilesChanged || 0), 10) || 0;

  return (
    <section className="entry-editor-card">
      <h3>Workspace Git Sync</h3>
      <div className={`git-sync-status ${statusTone}`}>
        <div className="git-sync-status-item">
          <span>Last sync</span>
          <strong>{formatGitSyncDate(status.lastSuccessAt, "Never synced")}</strong>
        </div>
        <div className="git-sync-status-item">
          <span>Last attempt</span>
          <strong>{formatGitSyncDate(status.lastAttemptAt, "Never run")}</strong>
        </div>
        <div className="git-sync-status-item">
          <span>Failed attempts</span>
          <strong>{failedAttempts}</strong>
        </div>
        <div className="git-sync-status-item">
          <span>Last commit</span>
          <strong>{lastCommit || "No commit yet"}</strong>
        </div>
        <div className="git-sync-status-item">
          <span>Changed files</span>
          <strong>{lastFilesChanged}</strong>
        </div>
        {hasActiveFailure ? (
          <div className="git-sync-status-error">
            <span>{formatGitSyncDate(status.lastFailureAt, "Last failure")}</span>
            <strong>{String(status.lastError || "Workspace Git Sync failed.")}</strong>
          </div>
        ) : null}
      </div>
      <div className="entry-form-grid">
        <label style={{ gridColumn: "1 / -1" }}>
          Enable Sync
          <select
            value={gitSyncEnabled ? "enabled" : "disabled"}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.gitSync.enabled = event.target.value === "enabled";
              })
            }
          >
            <option value="disabled">Disabled</option>
            <option value="enabled">Enabled</option>
          </select>
        </label>
        <label style={{ gridColumn: "1 / -1" }}>
          Git Auth Token
          <input
            type="password"
            autoComplete="new-password"
            placeholder="ghp_xxx"
            value={draftConfig.gitSync.authToken}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.gitSync.authToken = event.target.value;
              })
            }
          />
          <span className="entry-form-hint">Stored in runtime config and used for authenticated sync against the target repo.</span>
        </label>
        <label>
          Repository
          <input
            placeholder="owner/repo or https://github.com/owner/repo.git"
            value={draftConfig.gitSync.repository}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.gitSync.repository = event.target.value;
              })
            }
          />
        </label>
        <label>
          Push Branch
          <input
            placeholder="main"
            value={draftConfig.gitSync.branch}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.gitSync.branch = event.target.value;
              })
            }
          />
        </label>
        <label>
          Sync Schedule
          <select
            value={syncFrequency}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.gitSync.schedule.frequency = normalizeGitSyncFrequency(event.target.value);
              })
            }
          >
            <option value="manual">Manual only</option>
            <option value="daily">Every day</option>
            <option value="weekdays">Weekdays</option>
          </select>
        </label>
        <label>
          Sync Time
          <input
            type="time"
            disabled={syncFrequency === "manual"}
            value={normalizeTimeValue(draftConfig.gitSync.schedule.time)}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.gitSync.schedule.time = normalizeTimeValue(event.target.value, "18:00");
              })
            }
          />
        </label>
        <label style={{ gridColumn: "1 / -1" }}>
          Conflict Strategy
          <select
            value={conflictStrategy}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.gitSync.conflictStrategy = normalizeGitSyncConflictStrategy(event.target.value);
              })
            }
          >
            <option value="remote_wins">Remote wins (overwrite local workspace)</option>
            <option value="local_wins">Keep local changes</option>
            <option value="manual">Stop and resolve manually</option>
          </select>
          <span className="entry-form-hint">
            Default policy keeps remote as the source of truth and rewrites local workspace state on conflict.
          </span>
        </label>
        <div style={{ gridColumn: "1 / -1", display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={onRunGitSyncNow}
            disabled={gitSyncRunning || !gitSyncEnabled}
          >
            {gitSyncRunning ? "Syncing..." : "Sync now"}
          </button>
          {gitSyncStatusText ? <span className="entry-form-hint">{gitSyncStatusText}</span> : null}
        </div>
      </div>
    </section>
  );
}

function formatGitSyncDate(value, fallback) {
  const raw = String(value || "").trim();
  if (!raw) {
    return fallback;
  }
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) {
    return raw;
  }
  return date.toLocaleString();
}
