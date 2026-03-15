import React from "react";

export function SettingsSidebar({
  rawValid,
  query,
  onQueryChange,
  filteredSettings,
  selectedSettings,
  onSelectSettings
}) {
  return (
    <aside className="settings-side">
      <div className="settings-title-row">
        <h2>Settings</h2>
        {!rawValid && (
          <span className="settings-valid bad">invalid</span>
        )}
      </div>

      <input
        className="settings-search"
        value={query}
        onChange={(event) => onQueryChange(event.target.value)}
        placeholder="Search settings..."
      />

      <div className="settings-nav">
        {filteredSettings.map((item) => (
          <button
            key={item.id}
            type="button"
            className={`settings-nav-item ${selectedSettings === item.id ? "active" : ""}`}
            onClick={() => onSelectSettings(item.id)}
          >
            <span className="material-symbols-rounded settings-nav-icon">{item.icon}</span>
            <span>{item.title}</span>
          </button>
        ))}
      </div>
    </aside>
  );
}
