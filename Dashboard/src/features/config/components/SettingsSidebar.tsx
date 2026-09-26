import React from "react";

const SETTINGS_GROUPS = [
  { title: "AI & tools", ids: ["providers", "model-routing", "semantic-decisions", "search-tools", "image-generation", "mcp", "plugins"] },
  { title: "Connections", ids: ["channels", "browser", "voice-mode", "acp", "proxy", "git-sync", "connect-client", "nodehost"] },
  { title: "Runtime", ids: ["sessions", "approvals", "visor", "compactor"] },
  { title: "Application", ids: ["users", "ui", "tui", "updates", "config"] }
];

export function SettingsSidebar({
  rawValid,
  query,
  onQueryChange,
  filteredSettings,
  selectedSettings,
  onSelectSettings
}) {
  const groups = SETTINGS_GROUPS.map((group) => ({
    title: group.title,
    items: group.ids.map((id) => filteredSettings.find((item) => item.id === id)).filter(Boolean)
  })).filter((group) => group.items.length > 0);

  return (
    <>
      <header className="settings-page-header">
        <div className="settings-title-row">
          <h1>Settings</h1>
          {!rawValid ? <span className="settings-valid bad">Invalid JSON</span> : null}
        </div>
        <label className="settings-page-search">
          <span className="material-symbols-rounded" aria-hidden="true">search</span>
          <span className="visually-hidden">Search settings</span>
          <input
            className="settings-search"
            type="search"
            value={query}
            onChange={(event) => onQueryChange(event.target.value)}
            placeholder="Search settings"
            aria-label="Search settings"
          />
        </label>
      </header>

      <aside className="settings-side">
        <nav className="settings-nav" aria-label="Settings sections">
          {groups.length === 0 ? <p className="settings-nav-empty">No matching settings</p> : null}
          {groups.map((group) => (
            <details
              className="settings-nav-group"
              key={group.title}
              open={Boolean(query.trim()) || group.items.some((item) => item.id === selectedSettings)}
            >
              <summary>
                <span>{group.title}</span>
                <span className="material-symbols-rounded" aria-hidden="true">expand_more</span>
              </summary>
              <div className="settings-nav-group-items">
                {group.items.map((item) => (
                  <button
                    key={item.id}
                    type="button"
                    className={`settings-nav-item ${selectedSettings === item.id ? "active" : ""}`}
                    aria-current={selectedSettings === item.id ? "page" : undefined}
                    onClick={() => onSelectSettings(item.id)}
                  >
                    <span className="material-symbols-rounded settings-nav-icon" aria-hidden="true">{item.icon}</span>
                    <span>{item.title}</span>
                  </button>
                ))}
              </div>
            </details>
          ))}
        </nav>
      </aside>
    </>
  );
}
