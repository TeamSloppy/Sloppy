import React, { useCallback, useEffect, useMemo, useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { clientPairingLink } from "./clientPairingLink";
import { RelayClientConnectView } from "./RelayClientConnectView";
import {
  detectClientTLSFingerprint,
  prepareClientConnection,
  type DevicePairingRecord
} from "../../../shared/api/coreApi";

interface ClientConnectViewProps {
  listenPort: number;
  clientPublicURL: string;
  clientAlternateURLs: string[];
  clientTLSFingerprint: string;
  onConfigChange: (patch: {
    clientPublicURL: string;
    clientAlternateURLs: string[];
    clientTLSFingerprint: string;
  }) => void;
  onSave: () => Promise<boolean>;
  onFingerprintDetected: (fingerprint: string) => Promise<boolean>;
}

export function ClientConnectView({
  clientPublicURL,
  clientAlternateURLs,
  clientTLSFingerprint,
  onConfigChange,
  onSave,
  onFingerprintDetected
}: ClientConnectViewProps) {
  const [showLan, setShowLan] = useState(false);
  const [pairing, setPairing] = useState<DevicePairingRecord | null>(null);
  const [pairingError, setPairingError] = useState("");
  const [isTokenMode, setIsTokenMode] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [copied, setCopied] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [isDetectingFingerprint, setIsDetectingFingerprint] = useState(false);
  const [fingerprintStatus, setFingerprintStatus] = useState("");

  const issuePairing = useCallback(async (signal?: AbortSignal) => {
    setIsLoading(true);
    setPairingError("");
    setPairing(null);
    setIsTokenMode(false);
    try {
      const connection = await prepareClientConnection(signal);
      if (signal?.aborted) return;
      if (connection.mode === "token") {
        setIsTokenMode(true);
        setPairingError("QR pairing requires login/password authentication and is unavailable with an operator token. Your Dashboard session is still active. Connect manually in Sloppy Client using the server address and operator token.");
        return;
      }
      setPairing(connection.pairing);
    } catch (error) {
      if (signal?.aborted) return;
      setPairingError(error instanceof Error ? error.message : "Failed to prepare the client connection.");
    } finally {
      if (!signal?.aborted) setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!showLan) return;
    const controller = new AbortController();
    void issuePairing(controller.signal);
    return () => controller.abort();
  }, [issuePairing, showLan]);

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

  const connectionLink = useMemo(() => {
    if (!pairing) return { link: "", serverURL: "", error: "" };
    try {
      return { ...clientPairingLink(pairing), error: "" };
    } catch (error) {
      return { link: "", serverURL: "", error: error instanceof Error ? error.message : "Invalid client address." };
    }
  }, [pairing]);
  const deepLink = connectionLink.link;
  const connectionError = pairingError || connectionLink.error;

  async function saveAndGenerate() {
    setIsSaving(true);
    try {
      if (await onSave()) {
        await issuePairing();
      }
    } finally {
      setIsSaving(false);
    }
  }

  async function detectFingerprint() {
    setIsDetectingFingerprint(true);
    setFingerprintStatus("");
    try {
      if (!await onSave()) return;
      const detected = await detectClientTLSFingerprint();
      if (!await onFingerprintDetected(detected.fingerprint)) return;
      setFingerprintStatus(`Detected and saved from ${detected.url}.`);
    } catch (error) {
      setFingerprintStatus(error instanceof Error ? error.message : "Could not detect the TLS fingerprint.");
    } finally {
      setIsDetectingFingerprint(false);
    }
  }

  function handleCopy() {
    if (!deepLink) return;
    navigator.clipboard.writeText(deepLink).catch(() => {});
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  if (!showLan) return <RelayClientConnectView onLan={() => setShowLan(true)} />;
  return (
    <section className="entry-editor-card">
      <h3>Connect Sloppy Client</h3>
      <button type="button" className="btn btn-secondary btn-sm" onClick={() => setShowLan(false)}>Use Console Relay</button>
      <p className="placeholder-text">
        Scan this short-lived QR code with Sloppy Client. The app will connect as the
        Dashboard user shown below; no password is placed in the QR code.
      </p>

      <div style={{ display: "flex", gap: 32, flexWrap: "wrap", alignItems: "flex-start", marginTop: 20 }}>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 12, width: 234 }}>
          <div style={{
            width: 234,
            height: 234,
            boxSizing: "border-box",
            background: deepLink ? "#fff" : "var(--surface-raised, var(--surface))",
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
              : isTokenMode ? "Operator token mode does not support QR pairing" : "Generate a new code to connect"}
          </span>
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => void issuePairing()} disabled={isLoading || isTokenMode}>
            {isLoading ? "Generating…" : "Generate new QR"}
          </button>
        </div>

        <div style={{ flex: 1, minWidth: 260, display: "flex", flexDirection: "column", gap: 16 }}>
          {connectionError ? (
            <div className="entry-form-hint" role="alert" style={{ color: "var(--danger, #ef5350)" }}>
              {connectionError}
            </div>
          ) : null}

          {connectionLink.serverURL ? (
            <p className="entry-form-hint" role="status">Client address: <code>{connectionLink.serverURL}</code></p>
          ) : null}

          <div className="entry-form-grid">
            <label style={{ gridColumn: "1 / -1" }}>
              Public Client URL
              <input
                type="text"
                value={clientPublicURL}
                onChange={(event) => onConfigChange({
                  clientPublicURL: event.target.value,
                  clientAlternateURLs,
                  clientTLSFingerprint
                })}
                placeholder="https://your-domain.example"
                autoComplete="off"
              />
              <span className="entry-form-hint">
                External addresses require HTTPS. If empty, Core uses nodeMeshPublicURL or a local network address from its listening interface. Loopback addresses are never included in pairing QR codes.
              </span>
            </label>

            <label style={{ gridColumn: "1 / -1" }}>
              Alternate Client URLs
              <textarea
                value={clientAlternateURLs.join("\n")}
                onChange={(event) => onConfigChange({
                  clientPublicURL,
                  clientAlternateURLs: event.target.value.split(/\r?\n/).map((value) => value.trim()).filter(Boolean),
                  clientTLSFingerprint
                })}
                placeholder={"http://192.168.1.10:25101\nhttps://secondary.example.com"}
                rows={3}
                spellCheck={false}
              />
            </label>

            <label style={{ gridColumn: "1 / -1" }}>
              TLS Certificate SHA-256 Fingerprint
              <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                <input
                  type="text"
                  value={clientTLSFingerprint}
                  onChange={(event) => onConfigChange({
                    clientPublicURL,
                    clientAlternateURLs,
                    clientTLSFingerprint: event.target.value
                  })}
                  placeholder="64 hexadecimal characters"
                  autoComplete="off"
                  spellCheck={false}
                  style={{ flex: 1 }}
                />
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => void detectFingerprint()}
                  disabled={isDetectingFingerprint || isSaving || !clientPublicURL.trim().startsWith("https://")}
                  style={{ whiteSpace: "nowrap" }}
                >
                  {isDetectingFingerprint ? "Detecting…" : "Detect & save"}
                </button>
              </div>
              <span className="entry-form-hint">
                Optional certificate pin for HTTPS on a raw IP or private CA. It is embedded in the short-lived setup code.
              </span>
              {fingerprintStatus ? (
                <span className="entry-form-hint" role="status">{fingerprintStatus}</span>
              ) : null}
            </label>
          </div>

          <div>
            <button type="button" className="btn btn-primary" onClick={() => void saveAndGenerate()} disabled={isSaving || isLoading}>
              {isSaving ? "Saving…" : "Save connection settings & generate QR"}
            </button>
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
                <button type="button" className="btn btn-secondary btn-sm" onClick={handleCopy} disabled={!deepLink} style={{ whiteSpace: "nowrap" }}>
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
            {connectionLink.serverURL.startsWith("http:") ? " HTTP is intended only for trusted local development networks." : ""}
          </div>
        </div>
      </div>
    </section>
  );
}
