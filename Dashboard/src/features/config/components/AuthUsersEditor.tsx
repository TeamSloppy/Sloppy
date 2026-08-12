import React, { useCallback, useEffect, useState } from "react";
import { setDashboardAuthToken } from "../../../shared/api/dashboardAuth";
import { requestJson } from "../../../shared/api/httpClient";

export function AuthUsersEditor() {
  const [identityAuthChallenge, setIdentityAuthChallenge] = useState<Record<string, any> | null>(null);
  const [identityAuthStatus, setIdentityAuthStatus] = useState("");
  const [identityUsers, setIdentityUsers] = useState<Record<string, any>[]>([]);
  const [identityUsersStatus, setIdentityUsersStatus] = useState("");
  const [inviteRole, setInviteRole] = useState("user");
  const [inviteToken, setInviteToken] = useState("");
  const [bootstrapName, setBootstrapName] = useState("Admin");
  const [bootstrapLogin, setBootstrapLogin] = useState("admin");
  const [bootstrapPassword, setBootstrapPassword] = useState("");
  const [recoveryCodes, setRecoveryCodes] = useState<string[]>([]);
  const [passwordResetToken, setPasswordResetToken] = useState("");
  const [applicationTokens, setApplicationTokens] = useState<Record<string, any>[]>([]);
  const [applicationTokenName, setApplicationTokenName] = useState("Sloppy Safari");
  const [createdApplicationToken, setCreatedApplicationToken] = useState("");
  const [applicationTokenStatus, setApplicationTokenStatus] = useState("");

  const loadAuthChallenge = useCallback(async () => {
    const response = await requestJson<Record<string, any>>({ path: "/v1/auth/challenge" });
    if (response.ok) {
      setIdentityAuthChallenge(response.data);
      return response.data;
    }
    return null;
  }, []);

  const loadIdentityUsers = useCallback(async () => {
    setIdentityUsersStatus("Loading users...");
    const response = await requestJson<Record<string, any>[]>({ path: "/v1/auth/users" });
    if (!response.ok || !response.data) {
      setIdentityUsers([]);
      setIdentityUsersStatus("Login as Admin to manage accounts.");
      return;
    }
    setIdentityUsers(response.data);
    setIdentityUsersStatus("");
  }, []);

  const loadApplicationTokens = useCallback(async () => {
    const response = await requestJson<Record<string, any>[]>({ path: "/v1/auth/application-tokens" });
    if (!response.ok || !Array.isArray(response.data)) {
      setApplicationTokens([]);
      setApplicationTokenStatus("Unable to load application tokens.");
      return;
    }
    setApplicationTokens(response.data);
    setApplicationTokenStatus("");
  }, []);

  useEffect(() => {
    let cancelled = false;
    loadAuthChallenge().then((challenge) => {
      if (cancelled) return;
      if (challenge?.mode === "login_password" && !Boolean(challenge?.bootstrapRequired)) {
        void loadIdentityUsers();
        void loadApplicationTokens();
      }
    });
    return () => {
      cancelled = true;
    };
  }, [loadApplicationTokens, loadAuthChallenge, loadIdentityUsers]);

  const enableLoginPasswordAuth = useCallback(async () => {
    const confirmed = window.confirm(
      "Switch Sloppy to login/password authentication? This action cannot be reverted to token auth."
    );
    if (!confirmed) return;
    setIdentityAuthStatus("Enabling login/password auth...");
    const response = await requestJson<Record<string, any>, Record<string, any>>({
      path: "/v1/auth/mode",
      method: "POST",
      body: {
        mode: "login_password",
        confirmIrreversible: true
      }
    });
    if (!response.ok || !response.data) {
      setIdentityAuthStatus("Failed to enable login/password auth.");
      return;
    }
    setIdentityAuthChallenge(response.data);
    setIdentityAuthStatus("Login/password auth enabled. Create the first Admin account next.");
  }, []);

  const bootstrapFirstAdmin = useCallback(async () => {
    if (!bootstrapLogin.trim() || !bootstrapPassword) {
      setIdentityAuthStatus("Enter admin login and password.");
      return;
    }
    setIdentityAuthStatus("Creating the first Admin account...");
    const response = await requestJson<Record<string, any>, Record<string, any>>({
      path: "/v1/auth/bootstrap",
      method: "POST",
      body: {
        login: bootstrapLogin.trim(),
        name: bootstrapName.trim() || bootstrapLogin.trim(),
        password: bootstrapPassword
      }
    });
    const accessToken = typeof response.data?.accessToken === "string" ? response.data.accessToken.trim() : "";
    if (!response.ok || !accessToken) {
      setIdentityAuthStatus("Failed to create the first Admin account.");
      return;
    }
    setDashboardAuthToken(accessToken, { persist: true });
    setBootstrapPassword("");
    setIdentityAuthStatus("Admin account created and session saved in this browser.");
    await loadAuthChallenge();
    await loadIdentityUsers();
  }, [bootstrapLogin, bootstrapName, bootstrapPassword, loadAuthChallenge, loadIdentityUsers]);

  const createInvite = useCallback(async () => {
    setIdentityAuthStatus("Creating invite...");
    const response = await requestJson<Record<string, any>, Record<string, any>>({
      path: "/v1/auth/invites",
      method: "POST",
      body: {
        role: inviteRole,
        ttlSeconds: 604800
      }
    });
    const token = typeof response.data?.token === "string" ? response.data.token : "";
    if (!response.ok || !token) {
      setIdentityAuthStatus("Failed to create invite.");
      return;
    }
    setInviteToken(token);
    setIdentityAuthStatus("Invite created.");
  }, [inviteRole]);

  const updateIdentityUser = useCallback(async (login: string, patch: Record<string, any>) => {
    setIdentityUsersStatus("Updating user...");
    const response = await requestJson<Record<string, any>, Record<string, any>>({
      path: `/v1/auth/users/${encodeURIComponent(login)}`,
      method: "PATCH",
      body: patch
    });
    if (!response.ok) {
      setIdentityUsersStatus("Failed to update user. The last active Admin cannot be disabled or demoted.");
      return;
    }
    await loadIdentityUsers();
  }, [loadIdentityUsers]);

  const generateRecoveryCodes = useCallback(async () => {
    setIdentityAuthStatus("Generating recovery codes...");
    const response = await requestJson<Record<string, any>>({
      path: "/v1/auth/recovery-codes",
      method: "POST"
    });
    const codes = Array.isArray(response.data?.codes) ? response.data.codes.map((code) => String(code)) : [];
    if (!response.ok || codes.length === 0) {
      setIdentityAuthStatus("Failed to generate recovery codes.");
      return;
    }
    setRecoveryCodes(codes);
    setIdentityAuthStatus("Recovery codes generated. Store them now; they are one-time codes.");
  }, []);

  const createPasswordResetToken = useCallback(async (login: string) => {
    setIdentityAuthStatus("Creating password reset token...");
    const response = await requestJson<Record<string, any>>({
      path: `/v1/auth/users/${encodeURIComponent(login)}/password-reset-token`,
      method: "POST"
    });
    const token = typeof response.data?.resetToken === "string" ? response.data.resetToken : "";
    if (!response.ok || !token) {
      setIdentityAuthStatus("Failed to create password reset token.");
      return;
    }
    setPasswordResetToken(token);
    setIdentityAuthStatus(`Password reset token created for ${login}.`);
  }, []);

  const createApplicationToken = useCallback(async () => {
    const name = applicationTokenName.trim();
    if (!name) {
      setApplicationTokenStatus("Enter a token name.");
      return;
    }
    setApplicationTokenStatus("Creating application token...");
    setCreatedApplicationToken("");
    const response = await requestJson<Record<string, any>, Record<string, any>>({
      path: "/v1/auth/application-tokens",
      method: "POST",
      body: {
        name,
        expiresInSeconds: 31_536_000
      }
    });
    const token = typeof response.data?.token === "string" ? response.data.token.trim() : "";
    if (!response.ok || !token) {
      setApplicationTokenStatus("Failed to create application token.");
      return;
    }
    setCreatedApplicationToken(token);
    await loadApplicationTokens();
    setApplicationTokenStatus("Token created. Copy it now; it will not be shown again.");
  }, [applicationTokenName, loadApplicationTokens]);

  const revokeApplicationToken = useCallback(async (id: string, name: string) => {
    if (!window.confirm(`Revoke application token “${name}”?`)) return;
    setApplicationTokenStatus("Revoking application token...");
    const response = await requestJson({
      path: `/v1/auth/application-tokens/${encodeURIComponent(id)}`,
      method: "DELETE"
    });
    if (!response.ok) {
      setApplicationTokenStatus("Failed to revoke application token.");
      return;
    }
    setCreatedApplicationToken("");
    await loadApplicationTokens();
  }, [loadApplicationTokens]);

  const copyCreatedApplicationToken = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(createdApplicationToken);
      setApplicationTokenStatus("Token copied. It will not be shown again after you leave this page.");
    } catch {
      setApplicationTokenStatus("Unable to copy automatically. Select the token and copy it manually.");
    }
  }, [createdApplicationToken]);

  return (
    <section className="entry-editor-card">
      <h3>Users & Auth</h3>
      <p className="placeholder-text">
        Manage login/password authentication, Admin/User roles, invites, recovery codes, and password reset tokens.
      </p>

      <div className="entry-form-grid">
        <div style={{ gridColumn: "1 / -1" }}>
          <div className="settings-toggle-row">
            <div className="agent-tools-guardrail" style={{ width: "100%" }}>
              <span className="agent-tools-guardrail-copy">
                <span className="agent-tools-guardrail-title">Login/password authentication</span>
                <span className="entry-form-hint">
                  Current challenge: <code>{String(identityAuthChallenge?.mode || "token")}</code>
                  {identityAuthChallenge?.passkeySupported ? " · PassKey supported" : ""}. Switching to login/password cannot be undone.
                </span>
                {identityAuthStatus ? <span className="entry-form-hint">{identityAuthStatus}</span> : null}
              </span>
              <button
                type="button"
                className="secondary-button"
                disabled={identityAuthChallenge?.mode === "login_password"}
                onClick={enableLoginPasswordAuth}
              >
                Enable
              </button>
            </div>
          </div>
        </div>

        {identityAuthChallenge?.mode === "login_password" ? (
          <div style={{ gridColumn: "1 / -1" }}>
            <div className="agent-tools-guardrail" style={{ width: "100%", display: "grid", gap: "12px" }}>
              {identityAuthChallenge?.bootstrapRequired ? (
                <>
                  <span className="agent-tools-guardrail-copy">
                    <span className="agent-tools-guardrail-title">Create first Admin</span>
                    <span className="entry-form-hint">The first account gets full Admin permissions.</span>
                  </span>
                  <label>
                    Admin name
                    <input value={bootstrapName} onChange={(event) => setBootstrapName(event.target.value)} />
                  </label>
                  <label>
                    Admin login
                    <input
                      value={bootstrapLogin}
                      autoCapitalize="off"
                      autoCorrect="off"
                      spellCheck={false}
                      onChange={(event) => setBootstrapLogin(event.target.value)}
                    />
                  </label>
                  <label>
                    Admin password
                    <input
                      type="password"
                      value={bootstrapPassword}
                      onChange={(event) => setBootstrapPassword(event.target.value)}
                    />
                  </label>
                  <button type="button" className="secondary-button" onClick={() => void bootstrapFirstAdmin()}>
                    Create Admin
                  </button>
                </>
              ) : (
                <>
                  <span className="agent-tools-guardrail-copy">
                    <span className="agent-tools-guardrail-title">Accounts</span>
                    <span className="entry-form-hint">Admins can change roles, disable users, issue invites, and create reset tokens.</span>
                  </span>
                  <div className="settings-toggle-row">
                    <button type="button" className="secondary-button" onClick={() => void loadIdentityUsers()}>
                      Refresh users
                    </button>
                    <button type="button" className="secondary-button" onClick={() => void generateRecoveryCodes()}>
                      Generate my recovery codes
                    </button>
                  </div>
                  {identityUsersStatus ? <span className="entry-form-hint">{identityUsersStatus}</span> : null}
                  {recoveryCodes.length > 0 ? (
                    <textarea
                      readOnly
                      rows={Math.min(8, recoveryCodes.length + 1)}
                      value={recoveryCodes.join("\n")}
                    />
                  ) : null}
                  <div style={{ display: "grid", gap: "10px" }}>
                    {identityUsers.map((user) => {
                      const login = String(user.login || "");
                      const role = String(user.role || "user");
                      const status = String(user.status || "active");
                      return (
                        <div key={login} className="agent-tools-guardrail" style={{ display: "grid", gap: "8px" }}>
                          <span className="agent-tools-guardrail-copy">
                            <span className="agent-tools-guardrail-title">{String(user.name || login)}</span>
                            <span className="entry-form-hint">
                              @{login} · {role} · {status}
                            </span>
                          </span>
                          <div className="settings-toggle-row">
                            <button
                              type="button"
                              className={`secondary-button ${role === "admin" ? "active" : ""}`}
                              onClick={() => void updateIdentityUser(login, { role: "admin" })}
                            >
                              Admin
                            </button>
                            <button
                              type="button"
                              className={`secondary-button ${role === "user" ? "active" : ""}`}
                              onClick={() => void updateIdentityUser(login, { role: "user" })}
                            >
                              User
                            </button>
                            <button
                              type="button"
                              className={`secondary-button ${status === "active" ? "active" : ""}`}
                              onClick={() => void updateIdentityUser(login, { status: status === "active" ? "disabled" : "active" })}
                            >
                              {status === "active" ? "Disable" : "Enable"}
                            </button>
                            <button
                              type="button"
                              className="secondary-button"
                              onClick={() => void createPasswordResetToken(login)}
                            >
                              Reset token
                            </button>
                          </div>
                        </div>
                      );
                    })}
                  </div>

                  <span className="agent-tools-guardrail-copy">
                    <span className="agent-tools-guardrail-title">Application tokens</span>
                    <span className="entry-form-hint">
                      Long-lived bearer tokens for Sloppy Safari and other clients. Tokens inherit your current role and expire after one year.
                    </span>
                  </span>
                  <div className="settings-toggle-row">
                    <input
                      value={applicationTokenName}
                      placeholder="Sloppy Safari"
                      onChange={(event) => setApplicationTokenName(event.target.value)}
                    />
                    <button type="button" className="secondary-button" onClick={() => void createApplicationToken()}>
                      Generate token
                    </button>
                  </div>
                  {applicationTokenStatus ? <span className="entry-form-hint">{applicationTokenStatus}</span> : null}
                  {createdApplicationToken ? (
                    <div className="settings-toggle-row">
                      <label>
                        New application token
                        <input
                          readOnly
                          value={createdApplicationToken}
                          onFocus={(event) => event.currentTarget.select()}
                        />
                      </label>
                      <button type="button" className="secondary-button" onClick={() => void copyCreatedApplicationToken()}>
                        Copy token
                      </button>
                    </div>
                  ) : null}
                  <div style={{ display: "grid", gap: "10px" }}>
                    {applicationTokens.map((token) => {
                      const id = String(token.id || "");
                      const name = String(token.name || "Application token");
                      const prefix = String(token.tokenPrefix || "");
                      const expiresAt = String(token.expiresAt || "");
                      const expiry = expiresAt ? new Date(expiresAt).toLocaleDateString() : "unknown";
                      return (
                        <div key={id} className="agent-tools-guardrail">
                          <span className="agent-tools-guardrail-copy">
                            <span className="agent-tools-guardrail-title">{name}</span>
                            <span className="entry-form-hint">
                              <code>{prefix}</code> · expires {expiry}
                            </span>
                          </span>
                          <button
                            type="button"
                            className="secondary-button"
                            onClick={() => void revokeApplicationToken(id, name)}
                          >
                            Revoke
                          </button>
                        </div>
                      );
                    })}
                  </div>

                  <span className="agent-tools-guardrail-copy">
                    <span className="agent-tools-guardrail-title">Invite user</span>
                    <span className="entry-form-hint">Invite tokens are single-use registration secrets.</span>
                  </span>
                  <div className="settings-toggle-row">
                    <button
                      type="button"
                      className={`secondary-button ${inviteRole === "admin" ? "active" : ""}`}
                      onClick={() => setInviteRole("admin")}
                    >
                      Admin
                    </button>
                    <button
                      type="button"
                      className={`secondary-button ${inviteRole === "user" ? "active" : ""}`}
                      onClick={() => setInviteRole("user")}
                    >
                      User
                    </button>
                    <button type="button" className="secondary-button" onClick={() => void createInvite()}>
                      Create invite
                    </button>
                  </div>
                  {inviteToken ? (
                    <input readOnly value={inviteToken} onFocus={(event) => event.currentTarget.select()} />
                  ) : null}
                  {passwordResetToken ? (
                    <label>
                      Password reset token
                      <input readOnly value={passwordResetToken} onFocus={(event) => event.currentTarget.select()} />
                    </label>
                  ) : null}
                </>
              )}
            </div>
          </div>
        ) : null}
      </div>
    </section>
  );
}
