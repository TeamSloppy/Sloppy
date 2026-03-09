import React from "react";

export function SettingsMainHeader({ hasChanges, statusText, onReload, onSave }) {
  return (
    <header className="settings-main-head">
      <div className="settings-main-status">
        <strong>{hasChanges ? "Unsaved changes" : "No changes"}</strong>
        <span>{statusText}</span>
      </div>

      <div className="settings-main-actions">
        <button type="button" className="danger hover-levitate" disabled={!hasChanges} onClick={onReload}>
          Cancel
        </button>
        <button type="button" className="hover-levitate" disabled={!hasChanges} onClick={onSave}>
          Apply
        </button>
      </div>
    </header>
  );
}
