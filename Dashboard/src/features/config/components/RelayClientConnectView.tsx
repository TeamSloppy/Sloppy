import React, { useCallback, useEffect, useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { requestJson } from "../../../shared/api/httpClient";

interface RelaySetup {
  setupCode: string;
  profile: { instanceName: string; relayURL: string; consoleURL: string; identityURL: string; expiresAt: number };
}

export function RelayClientConnectView({ onLan }: { onLan: () => void }) {
  const [setup, setSetup] = useState<RelaySetup | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [copied, setCopied] = useState(false);
  const generate = useCallback(async (signal?: AbortSignal) => {
    setLoading(true); setSetup(null); setError("");
    try {
      const response = await requestJson<RelaySetup & { error?: string }>({ path: "/v1/console/client-setup", signal });
      if (signal?.aborted) return;
      if (!response.ok || !response.data?.setupCode) {
        const code = response.data?.error;
        throw new Error(code === "console_instance_not_bound"
          ? "Connect this Core to Console first in Settings → Console."
          : code === "console_relay_offline" ? "Core is offline in Relay. Check Console connection status, then retry."
          : "Relay setup is unavailable. Use the local owner's Dashboard and check the Core Console connection.");
      }
      setSetup(response.data);
    } catch (failure) { if (!signal?.aborted) setError(failure instanceof Error ? failure.message : "Relay setup failed."); }
    finally { if (!signal?.aborted) setLoading(false); }
  }, []);
  useEffect(() => { const controller = new AbortController(); void generate(controller.signal); return () => controller.abort(); }, [generate]);
  useEffect(() => {
    if (!setup) return;
    const timer = window.setTimeout(() => { setSetup(null); setError("QR expired. Generate a fresh Relay QR."); }, Math.max(0, setup.profile.expiresAt - Date.now()));
    return () => window.clearTimeout(timer);
  }, [setup]);
  return <section className="entry-editor-card">
    <h3>Connect through Console Relay</h3>
    <p className="placeholder-text">Scan with Sloppy on RV101. Both devices connect outward through Relay; the glasses do not need your Mac's LAN address.</p>
    {error && <p role="alert" className="entry-form-hint">{error}</p>}
    <div style={{ display: "flex", flexWrap: "wrap", gap: 32, marginTop: 20, alignItems: "flex-start" }}>
      <div style={{ width: "min(100%, 560px)", display: "flex", flexDirection: "column", gap: 12, alignItems: "center" }}>
        <div style={{ background: "white", padding: 24, boxSizing: "border-box", width: "100%", aspectRatio: "1", display: "grid", placeItems: "center" }} aria-label="Relay setup QR">
          {setup ? <QRCodeSVG value={setup.setupCode} size={512} level="L" style={{ width: "100%", height: "auto" }} />
            : <span style={{ color: "black" }}>{loading ? "Preparing Relay QR…" : "QR unavailable"}</span>}
        </div>
        <button type="button" className="btn btn-secondary" disabled={loading} onClick={() => void generate()}>{loading ? "Preparing…" : "Generate new Relay QR"}</button>
        {setup && <button type="button" className="btn btn-secondary btn-sm" onClick={() => {
          void navigator.clipboard.writeText(setup.setupCode).then(() => setCopied(true)).catch(() => setError("Could not copy the Relay link."));
        }}>{copied ? "Copied" : "Copy Relay link"}</button>}
      </div>
      <div style={{ flex: 1, minWidth: 240 }}>
        {setup && <><h4>{setup.profile.instanceName}</h4><p>Relay: <code style={{ overflowWrap: "anywhere" }}>{setup.profile.relayURL}</code></p></>}
        <ol style={{ paddingLeft: 24, lineHeight: 1.7 }}>
          <li>Scan and confirm this server on the glasses.</li>
          <li>Enter the short Console sign-in code shown on the glasses in your Mac browser and complete sign-in.</li>
          <li>In Console → Devices, review Sloppy Rokid RV101 and approve its requested chat access.</li>
        </ol>
        <p className="entry-form-hint">This QR contains public server identity and addresses. It expires after ten minutes and grants no access by itself. The glasses keep their own key and sign-in credentials.</p>
        {setup && <a className="btn btn-secondary" href={setup.profile.consoleURL} target="_blank" rel="noreferrer">Open Console</a>}
      </div>
    </div>
    <details style={{ marginTop: 24 }}><summary>Advanced connection</summary><p className="placeholder-text">Direct LAN pairing requires an address reachable from the glasses.</p><button className="btn btn-secondary btn-sm" type="button" onClick={onLan}>Use LAN pairing</button></details>
  </section>;
}
