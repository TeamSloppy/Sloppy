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

  return (
    <section className="entry-editor-card">
      <h3>Workspace Git Sync</h3>
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
