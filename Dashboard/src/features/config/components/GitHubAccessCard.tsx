import React from "react";

export function GitHubAccessCard({
  gitHubAuthStatus,
  gitHubToken,
  gitHubStatusText,
  gitHubConnecting,
  onGitHubTokenChange,
  onConnect,
  onDisconnect
}) {
  return (
    <section className="entry-editor-card providers-intro-card" style={{ marginTop: 0 }}>
      <h3>GitHub Access</h3>
      <p className="placeholder-text">
        Connect a GitHub Personal Access Token to clone private repositories and download private skills.
        The token is stored locally in the workspace.{" "}
        <a href="https://github.com/settings/tokens/new?scopes=repo&description=Sloppy" target="_blank" rel="noreferrer">
          Create a token
        </a>
        .
      </p>
      {gitHubAuthStatus.connected ? (
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <div className="onboarding-provider-badge" style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <span className="material-symbols-rounded" aria-hidden="true" style={{ color: "var(--color-success, #22c55e)" }}>check_circle</span>
            <span>
              Connected{gitHubAuthStatus.username ? ` as @${gitHubAuthStatus.username}` : ""}
            </span>
          </div>
          <div>
            <button type="button" className="btn btn-secondary btn-sm" onClick={onDisconnect}>
              Disconnect
            </button>
          </div>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <label style={{ marginBottom: 0 }}>
            Personal Access Token
            <input
              type="password"
              value={gitHubToken}
              onChange={(e) => onGitHubTokenChange(e.target.value)}
              placeholder="ghp_..."
              autoComplete="off"
              onKeyDown={(e) => { if (e.key === "Enter") onConnect(); }}
            />
          </label>
          <div>
            <button
              type="button"
              className="btn btn-primary btn-sm"
              onClick={onConnect}
              disabled={gitHubConnecting || !gitHubToken.trim()}
            >
              {gitHubConnecting ? "Connecting..." : "Connect"}
            </button>
          </div>
        </div>
      )}
      {gitHubStatusText ? (
        <p className="placeholder-text" style={{ marginTop: 8, marginBottom: 0 }}>{gitHubStatusText}</p>
      ) : null}
    </section>
  );
}
