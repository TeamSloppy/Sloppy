import React, { useCallback, useEffect, useMemo, useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { formatHttpError, requestJson } from "../../../shared/api/httpClient";

interface ClientConnectViewProps {
  listenPort: number;
}

interface PairingUser {
  id: string;
  login: string;
  name: string;
}

interface DevicePairingRecord {
  id: string;
  token: string;
  clientName: string;
  createdAt: string;
  expiresAt: string;
  user: PairingUser;
}

function deriveServerHost(): string {
  return window.location.hostname;
}

export function ClientConnectView({ listenPort }: ClientConnectViewProps) {
  const [customHost, setCustomHost] = useState("");
  const [pairing, setPairing] = useState<DevicePairingRecord | null>(null);
  const [pairingError, setPairingError] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [copied, setCopied] = useState(false);

  const defaultHost = deriveServerHost();
  const host = customHost.trim() || defaultHost;
  const port = listenPort || 25101;
  const transportScheme = window.location.protocol === "https:" ? "https" : "http";

  const issuePairing = useCallback(async (signal?: AbortSignal) => {
    setIsLoading(true);
    setPairingError("");
    setPairing(null);
    const response = await requestJson<DevicePairingRecord, { clientName: string; ttlSeconds: number }>({
      path: "/v1/auth/device-pairing",
      method: "POST",
      body: { clientName: "Sloppy Rokid", ttlSeconds: 120 },
      signal
    });
    if (signal?.aborted) return;
    setIsLoading(false);
    if (!response.ok || !response.data) {
      setPairingError(formatHttpError(response.status, response.data));
      return;
    }
    setPairing(response.data);
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    void issuePairing(controller.signal);
    return () => controller.abort();
  }, [issuePairing]);

  useEffect(() => {
    if (!pairing) return;
    const remainingMilliseconds = new Date(pairing.expiresAt).getTime() - Date.now();
    if (remainingMilliseconds <= 0) {
      setPairing(null);
      return;
    }
    const expiryTimer = window.setTimeout(() => setPairing(null), remainingMilliseconds);
    return () => window.clearTimeout(expiryTimer);
  }, [pairing]);

  const deepLink = useMemo(() => {
    if (!pairing) return "";
    const query = new URLSearchParams({
      host,
      port: String(port),
      scheme: transportScheme,
      label: `Sloppy @ ${host}`,
      pairingToken: pairing.token
    });
    return `sloppy://connect?${query.toString()}`;
  }, [host, pairing, port, transportScheme]);

  function handleCopy() {
    if (!deepLink) return;
    navigator.clipboard.writeText(deepLink).catch(() => {});
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <section className="entry-editor-card">
      <h3>Connect Sloppy Client</h3>
      <p className="placeholder-text">
        Scan this short-lived QR code with Sloppy Rokid. The glasses will connect as the
        Dashboard user shown below; no password is placed in the QR code.
      </p>

      <div style={{ display: "flex", gap: 32, flexWrap: "wrap", alignItems: "flex-start", marginTop: 20 }}>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 12, width: 234 }}>
          <div style={{
            width: 234,
            height: 234,
            boxSizing: "border-box",
            background: pairing ? "#fff" : "var(--surface-raised, var(--surface))",
            padding: 16,
            border: "1px solid var(--line)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            textAlign: "center"
          }}>
            {pairing && deepLink ? (
              <QRCodeSVG value={deepLink} size={200} bgColor="#ffffff" fgColor="#000000" level="M" />
            ) : (
              <span className="placeholder-text" style={{ fontSize: "0.8rem" }}>
                {isLoading ? "Creating secure pairing code…" : "Pairing code unavailable"}
              </span>
            )}
          </div>
          <span className="placeholder-text" style={{ fontSize: "0.75rem", textAlign: "center" }}>
            {pairing
              ? `Connect as ${pairing.user.name} (@${pairing.user.login})`
              : "Sign in to Dashboard to create a code"}
          </span>
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => void issuePairing()} disabled={isLoading}>
            {isLoading ? "Generating…" : "Generate new QR"}
          </button>
        </div>

        <div style={{ flex: 1, minWidth: 260, display: "flex", flexDirection: "column", gap: 16 }}>
          {pairingError ? (
            <div className="entry-form-hint" role="alert" style={{ color: "var(--danger, #ef5350)" }}>
              {pairingError}
            </div>
          ) : null}

          <div className="entry-form-grid">
            <label style={{ gridColumn: "1 / -1" }}>
              Server Host
              <input
                type="text"
                value={customHost}
                onChange={(event) => setCustomHost(event.target.value)}
                placeholder={defaultHost}
                autoComplete="off"
              />
              <span className="entry-form-hint">
                Use a LAN address or Tailscale hostname reachable from the glasses. Never use localhost for a physical device.
              </span>
            </label>

            <label style={{ gridColumn: "1 / -1" }}>
              Port
              <input type="text" value={port} readOnly style={{ color: "var(--text-muted)", cursor: "default" }} />
            </label>
          </div>

          {pairing ? (
            <div>
              <p className="placeholder-text" style={{ marginBottom: 6, fontSize: "0.78rem" }}>Temporary pairing link</p>
              <div style={{
                display: "flex",
                alignItems: "center",
                gap: 8,
                background: "var(--surface-raised, var(--surface))",
                border: "1px solid var(--line)",
                padding: "6px 10px",
                fontSize: "0.75rem",
                color: "var(--text-muted)"
              }}>
                <code style={{ flex: 1 }}>One-time secret hidden · expires {new Date(pairing.expiresAt).toLocaleTimeString()}</code>
                <button type="button" className="btn btn-secondary btn-sm" onClick={handleCopy} style={{ whiteSpace: "nowrap" }}>
                  {copied ? "Copied!" : "Copy link"}
                </button>
              </div>
            </div>
          ) : null}

          <div style={{
            background: "color-mix(in srgb, var(--warn, #e8a000) 10%, transparent)",
            border: "1px solid color-mix(in srgb, var(--warn, #e8a000) 30%, transparent)",
            padding: "10px 14px",
            fontSize: "0.8rem",
            color: "var(--text-secondary, var(--text-muted))",
            lineHeight: 1.5
          }}>
            <strong>One scan, two minutes.</strong> The code is bound to the currently authenticated user and becomes invalid after its first successful use. Generate a new code if it expires.
            {transportScheme === "http" ? " HTTP is intended only for trusted local development networks." : ""}
          </div>
        </div>
      </div>
    </section>
  );
}
