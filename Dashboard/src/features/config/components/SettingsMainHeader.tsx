import React from "react";

export function SettingsMainHeader({ title, hasChanges, statusText, onReload, onSave }) {
  return (
    <>
      <header className="settings-main-head">
        <div className="settings-main-title">
          <span className="settings-main-eyebrow">Configuration</span>
          <h2>{title}</h2>
        </div>
        <span className="settings-main-status" role="status">{statusText}</span>
      </header>

      <div className={`settings-toast ${hasChanges ? "settings-toast--visible" : ""}`}>
        <span className="settings-toast-label">Unsaved changes</span>
        <div className="settings-toast-actions">
          <button type="button" className="danger hover-levitate" onClick={onReload}>
            Cancel
          </button>
          <button type="button" className="hover-levitate" onClick={onSave}>
            Apply
          </button>
        </div>
      </div>
    </>
  );
}
