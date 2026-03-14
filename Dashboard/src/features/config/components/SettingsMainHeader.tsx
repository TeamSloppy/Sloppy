import React from "react";

export function SettingsMainHeader({ hasChanges, statusText, onReload, onSave }) {
  return (
    <>
      <header className="settings-main-head">
        <div className="settings-main-status">
          <span>{statusText}</span>
        </div>
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
