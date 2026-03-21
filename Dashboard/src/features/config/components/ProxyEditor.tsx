import React from "react";

const PROXY_TYPES = [
  { id: "socks5", label: "SOCKS5" },
  { id: "http", label: "HTTP" },
  { id: "https", label: "HTTPS" }
];

export function ProxyEditor({ draftConfig, mutateDraft }) {
  const proxy = draftConfig.proxy || {};
  const enabled = Boolean(proxy.enabled);
  const type = String(proxy.type || "socks5");
  const host = String(proxy.host || "");
  const port = proxy.port != null ? proxy.port : 1080;
  const username = String(proxy.username || "");
  const password = String(proxy.password || "");

  return (
    <section className="entry-editor-card">
      <h3>Proxy</h3>
      <p className="placeholder-text">
        Route all AI provider API calls through a proxy. Useful for accessing OpenAI, Google, and other services from restricted regions.
      </p>

      <div className="entry-form-grid">
        <label style={{ gridColumn: "1 / -1" }}>
          Enable Proxy
          <select
            value={enabled ? "enabled" : "disabled"}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.proxy.enabled = event.target.value === "enabled";
              })
            }
          >
            <option value="disabled">Disabled</option>
            <option value="enabled">Enabled</option>
          </select>
        </label>

        <label>
          Proxy Type
          <select
            disabled={!enabled}
            value={type}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.proxy.type = event.target.value;
              })
            }
          >
            {PROXY_TYPES.map((t) => (
              <option key={t.id} value={t.id}>{t.label}</option>
            ))}
          </select>
        </label>

        <label>
          Port
          <input
            type="number"
            disabled={!enabled}
            min={1}
            max={65535}
            placeholder={type === "socks5" ? "1080" : "8080"}
            value={port}
            onChange={(event) =>
              mutateDraft((draft) => {
                const parsed = parseInt(event.target.value, 10);
                draft.proxy.port = Number.isFinite(parsed) ? parsed : 1080;
              })
            }
          />
        </label>

        <label style={{ gridColumn: "1 / -1" }}>
          Host
          <input
            disabled={!enabled}
            placeholder="127.0.0.1"
            value={host}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.proxy.host = event.target.value;
              })
            }
          />
          <span className="entry-form-hint">Hostname or IP address of the proxy server.</span>
        </label>

        <label>
          Username
          <input
            disabled={!enabled}
            placeholder="optional"
            autoComplete="off"
            value={username}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.proxy.username = event.target.value;
              })
            }
          />
        </label>

        <label>
          Password
          <input
            type="password"
            disabled={!enabled}
            placeholder="optional"
            autoComplete="new-password"
            value={password}
            onChange={(event) =>
              mutateDraft((draft) => {
                draft.proxy.password = event.target.value;
              })
            }
          />
        </label>
      </div>
    </section>
  );
}
