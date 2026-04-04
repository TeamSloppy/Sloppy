import React, { useMemo, useState } from "react";
import { QRCodeSVG } from "qrcode.react";

interface ClientConnectViewProps {
  listenPort: number;
}

function deriveServerHost(): string {
  const hostname = window.location.hostname;
  if (hostname === "localhost" || hostname === "127.0.0.1") {
    return hostname;
  }
  return hostname;
}

export function ClientConnectView({ listenPort }: ClientConnectViewProps) {
  const [customHost, setCustomHost] = useState("");
  const [copied, setCopied] = useState(false);

  const defaultHost = deriveServerHost();
  const host = customHost.trim() || defaultHost;
  const port = listenPort || 25101;

  const deepLink = useMemo(() => {
    const label = encodeURIComponent(`Sloppy @ ${host}`);
    return `sloppy://connect?host=${encodeURIComponent(host)}&port=${port}&label=${label}`;
  }, [host, port]);

  function handleCopy() {
    navigator.clipboard.writeText(deepLink).catch(() => {});
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <section className="entry-editor-card">
      <h3>Connect Sloppy Client</h3>
      <p className="placeholder-text">
        Scan the QR code with the Sloppy iOS/macOS app to connect instantly.
        The QR encodes your server address — no manual input required.
      </p>

      <div style={{ display: "flex", gap: 32, flexWrap: "wrap", alignItems: "flex-start", marginTop: 20 }}>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 12 }}>
          <div style={{
            background: "#fff",
            padding: 16,
            borderRadius: 0,
            border: "1px solid var(--line)",
            display: "inline-flex"
          }}>
            <QRCodeSVG
              value={deepLink}
              size={200}
              bgColor="#ffffff"
              fgColor="#000000"
              level="M"
            />
          </div>
          <span className="placeholder-text" style={{ fontSize: "0.75rem", textAlign: "center" }}>
            Scan with Sloppy Client app
          </span>
        </div>

        <div style={{ flex: 1, minWidth: 260, display: "flex", flexDirection: "column", gap: 16 }}>
          <div className="entry-form-grid">
            <label style={{ gridColumn: "1 / -1" }}>
              Server Host
              <input
                type="text"
                value={customHost}
                onChange={(e) => setCustomHost(e.target.value)}
                placeholder={defaultHost}
                autoComplete="off"
              />
              <span className="entry-form-hint">
                Leave blank to use the current browser hostname (<code>{defaultHost}</code>).
                Enter a Tailscale hostname or IP for remote access.
              </span>
            </label>

            <label style={{ gridColumn: "1 / -1" }}>
              Port
              <input
                type="text"
                value={port}
                readOnly
                style={{ color: "var(--text-muted)", cursor: "default" }}
              />
              <span className="entry-form-hint">
                Matches the Sloppy server listen port from config.
              </span>
            </label>
          </div>

          <div>
            <p className="placeholder-text" style={{ marginBottom: 6, fontSize: "0.78rem" }}>Deep link URL</p>
            <div style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              background: "var(--surface-raised, var(--surface))",
              border: "1px solid var(--line)",
              padding: "6px 10px",
              fontSize: "0.75rem",
              wordBreak: "break-all",
              color: "var(--text-muted)"
            }}>
              <code style={{ flex: 1 }}>{deepLink}</code>
              <button
                type="button"
                className="btn btn-secondary btn-sm"
                onClick={handleCopy}
                style={{ whiteSpace: "nowrap", flexShrink: 0 }}
              >
                {copied ? "Copied!" : "Copy"}
              </button>
            </div>
          </div>

          <div style={{
            background: "color-mix(in srgb, var(--warn, #e8a000) 10%, transparent)",
            border: "1px solid color-mix(in srgb, var(--warn, #e8a000) 30%, transparent)",
            padding: "10px 14px",
            fontSize: "0.8rem",
            color: "var(--text-secondary, var(--text-muted))",
            lineHeight: 1.5
          }}>
            <strong>Local network only.</strong> The QR code works when your phone is on the same Wi-Fi as this server.
            For remote access, enter a <strong>Tailscale hostname</strong> above — the client will save it for use anywhere.
          </div>
        </div>
      </div>
    </section>
  );
}
