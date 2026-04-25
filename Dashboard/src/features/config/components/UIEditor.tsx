import React, { useCallback, useEffect, useState } from "react";

const ACCENT_STORAGE_KEY = "sloppy_accent_color";
const DEFAULT_ACCENT = "#ccff00";

const PRESET_COLORS = [
  "#ccff00",
  "#00ffff",
  "#ff00ff",
  "#ffcc00",
  "#ff6600",
  "#00ff88",
  "#6366f1",
  "#f43f5e",
  "#3b82f6",
  "#a855f7",
  "#ec4899",
  "#14b8a6",
];

function isValidHex(value: string): boolean {
  return /^#([0-9a-fA-F]{3}){1,2}$/.test(value);
}

function hexToOpacity(hex: string, alpha: string): string {
  return hex + alpha;
}

function applyAccentColor(color: string) {
  document.documentElement.style.setProperty("--accent-color", color);
  document.documentElement.style.setProperty("--accent-opacity-bg", hexToOpacity(color, "97"));
}

function loadStoredAccent(): string {
  const stored = localStorage.getItem(ACCENT_STORAGE_KEY);
  if (stored && isValidHex(stored)) {
    return stored;
  }
  return DEFAULT_ACCENT;
}

interface UIEditorProps {
  draftConfig: Record<string, any>;
  mutateDraft: (mutator: (draft: Record<string, any>) => void) => void;
}

export function UIEditor({ draftConfig, mutateDraft }: UIEditorProps) {
  const [accentColor, setAccentColor] = useState(loadStoredAccent);
  const [hexInput, setHexInput] = useState(loadStoredAccent);
  const dashboardAuthEnabled = Boolean(draftConfig?.ui?.dashboardAuth?.enabled);
  const dashboardAuthToken = String(draftConfig?.ui?.dashboardAuth?.token || "");
  const terminalEnabled = Boolean(draftConfig?.ui?.dashboardTerminal?.enabled);
  const terminalLocalOnly =
    draftConfig?.ui?.dashboardTerminal?.localOnly == null ? true : Boolean(draftConfig?.ui?.dashboardTerminal?.localOnly);

  const commitColor = useCallback((color: string) => {
    const normalized = color.trim().toLowerCase();
    if (!isValidHex(normalized)) {
      return;
    }
    setAccentColor(normalized);
    setHexInput(normalized);
    localStorage.setItem(ACCENT_STORAGE_KEY, normalized);
    applyAccentColor(normalized);
  }, []);

  const handlePickerChange = useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
    commitColor(event.target.value);
  }, [commitColor]);

  const handleHexChange = useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
    let value = event.target.value;
    if (value && !value.startsWith("#")) {
      value = "#" + value;
    }
    setHexInput(value);
    if (isValidHex(value)) {
      commitColor(value);
    }
  }, [commitColor]);

  const handleHexBlur = useCallback(() => {
    if (!isValidHex(hexInput)) {
      setHexInput(accentColor);
    }
  }, [hexInput, accentColor]);

  const handleReset = useCallback(() => {
    commitColor(DEFAULT_ACCENT);
    localStorage.removeItem(ACCENT_STORAGE_KEY);
  }, [commitColor]);

  useEffect(() => {
    applyAccentColor(accentColor);
  }, []);

  return (
    <section className="entry-editor-card">
      <h3>Appearance</h3>
      <p className="placeholder-text">
        Customize the dashboard accent color. This setting is saved locally in your browser.
      </p>

      <div className="entry-form-grid">
        <label style={{ gridColumn: "1 / -1" }}>
          Accent Color
          <div className="ui-accent-row">
            <input
              type="color"
              className="ui-color-picker"
              value={accentColor}
              onChange={handlePickerChange}
            />
            <input
              type="text"
              className="ui-hex-input"
              placeholder="#ccff00"
              maxLength={7}
              value={hexInput}
              onChange={handleHexChange}
              onBlur={handleHexBlur}
              spellCheck={false}
            />
          </div>
          <span className="entry-form-hint">
            Pick a color or enter a HEX value (e.g. #ccff00).
          </span>
        </label>

        <div style={{ gridColumn: "1 / -1" }}>
          <span style={{ fontSize: "0.85rem", color: "var(--muted)", display: "block", marginBottom: "8px" }}>
            Presets
          </span>
          <div className="ui-preset-grid">
            {PRESET_COLORS.map((color) => (
              <button
                key={color}
                type="button"
                className={`ui-preset-swatch${accentColor === color ? " active" : ""}`}
                style={{ backgroundColor: color }}
                onClick={() => commitColor(color)}
                title={color}
              />
            ))}
          </div>
        </div>

        <div style={{ gridColumn: "1 / -1", marginTop: "4px" }}>
          <button type="button" onClick={handleReset}>
            Reset to Default
          </button>
        </div>

        <div style={{ gridColumn: "1 / -1", marginTop: "20px" }}>
          <span style={{ fontSize: "0.85rem", color: "var(--muted)", display: "block", marginBottom: "8px" }}>
            Dashboard Auth
          </span>
          <div className="settings-toggle-row">
            <label className="agent-tools-guardrail agent-tools-guardrail-toggle">
              <span className="agent-tools-guardrail-copy">
                <span className="agent-tools-guardrail-title">Require a separate operator token for dashboard mutations</span>
              </span>
              <span className="agent-tools-switch">
                <input
                  type="checkbox"
                  checked={dashboardAuthEnabled}
                  onChange={(event) => {
                    const checked = event.target.checked;
                    mutateDraft((draft) => {
                      if (!draft.ui) draft.ui = {};
                      if (!draft.ui.dashboardAuth) {
                        draft.ui.dashboardAuth = { enabled: false, token: "" };
                      }
                      draft.ui.dashboardAuth.enabled = checked;
                    });
                  }}
                />
                <span className="agent-tools-switch-track" />
              </span>
            </label>
          </div>
          <label style={{ gridColumn: "1 / -1", marginTop: "12px" }}>
            Dashboard Token
            <input
              type="password"
              value={dashboardAuthToken}
              placeholder="operator-token"
              onChange={(event) => {
                mutateDraft((draft) => {
                  if (!draft.ui) draft.ui = {};
                  if (!draft.ui.dashboardAuth) {
                    draft.ui.dashboardAuth = { enabled: false, token: "" };
                  }
                  draft.ui.dashboardAuth.token = event.target.value;
                });
              }}
            />
            <span className="entry-form-hint">
              When enabled with a non-empty token, dashboard `POST`/`PUT`/`PATCH`/`DELETE` routes and the dashboard terminal require bearer auth. The legacy `auth.token` still works for CLI compatibility.
            </span>
          </label>
        </div>

        <div style={{ gridColumn: "1 / -1", marginTop: "20px" }}>
          <span style={{ fontSize: "0.85rem", color: "var(--muted)", display: "block", marginBottom: "8px" }}>
            Dashboard Terminal
          </span>
          <div className="settings-toggle-row">
            <label className="agent-tools-guardrail agent-tools-guardrail-toggle">
              <span className="agent-tools-guardrail-copy">
                <span className="agent-tools-guardrail-title">Enable bottom terminal drawer (`Cmd+J`)</span>
              </span>
              <span className="agent-tools-switch">
                <input
                  type="checkbox"
                  checked={terminalEnabled}
                  onChange={(event) => {
                    const checked = event.target.checked;
                    mutateDraft((draft) => {
                      if (!draft.ui) draft.ui = {};
                      if (!draft.ui.dashboardTerminal) {
                        draft.ui.dashboardTerminal = { enabled: false, localOnly: true };
                      }
                      draft.ui.dashboardTerminal.enabled = checked;
                    });
                  }}
                />
                <span className="agent-tools-switch-track" />
              </span>
            </label>
            <label className="agent-tools-guardrail agent-tools-guardrail-toggle">
              <span className="agent-tools-guardrail-copy">
                <span className="agent-tools-guardrail-title">Restrict terminal access to local dashboard sessions only</span>
              </span>
              <span className="agent-tools-switch">
                <input
                  type="checkbox"
                  checked={terminalLocalOnly}
                  onChange={(event) => {
                    const checked = event.target.checked;
                    mutateDraft((draft) => {
                      if (!draft.ui) draft.ui = {};
                      if (!draft.ui.dashboardTerminal) {
                        draft.ui.dashboardTerminal = { enabled: false, localOnly: true };
                      }
                      draft.ui.dashboardTerminal.localOnly = checked;
                    });
                  }}
                />
                <span className="agent-tools-switch-track" />
              </span>
            </label>
          </div>
          <span className="entry-form-hint">
            The terminal runs as a real shell inside the current project repo path when one is open, otherwise in the workspace root.
          </span>
        </div>
      </div>
    </section>
  );
}
