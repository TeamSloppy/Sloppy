import React from "react";

function ensureBrowser(draft) {
  if (!draft.browser) {
    draft.browser = {
      enabled: false,
      executablePath: "",
      profileName: "default",
      profilePath: "",
      headless: false,
      startupTimeoutMs: 10000,
      additionalArguments: []
    };
  }
  if (!Array.isArray(draft.browser.additionalArguments)) {
    draft.browser.additionalArguments = [];
  }
  return draft.browser;
}

export function BrowserEditor({ draftConfig, mutateDraft, parseLines }) {
  const browser = draftConfig.browser || {
    enabled: false,
    executablePath: "",
    profileName: "default",
    profilePath: "",
    headless: false,
    startupTimeoutMs: 10000,
    additionalArguments: []
  };

  return (
    <section className="entry-editor-card">
      <h3>Browser Control</h3>
      <p className="placeholder-text">
        Configure a Chromium-compatible browser for agent <code>browser.*</code> tools. Sloppy uses a managed profile by default.
      </p>
      <div className="entry-form-grid">
        <label className="entry-toggle-row" style={{ gridColumn: "1 / -1" }}>
          <input
            type="checkbox"
            checked={Boolean(browser.enabled)}
            onChange={(event) =>
              mutateDraft((draft) => {
                ensureBrowser(draft).enabled = event.target.checked;
              })
            }
          />
          <span>Enable browser automation</span>
        </label>

        <label style={{ gridColumn: "1 / -1" }}>
          Browser Executable Path
          <input
            placeholder="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            value={browser.executablePath || ""}
            onChange={(event) =>
              mutateDraft((draft) => {
                ensureBrowser(draft).executablePath = event.target.value;
              })
            }
          />
          <span className="entry-form-hint">
            Use Chrome, Chromium, Edge, Brave, or another browser with Chrome DevTools Protocol support.
          </span>
        </label>

        <label>
          Managed Profile Name
          <input
            placeholder="default"
            value={browser.profileName || "default"}
            onChange={(event) =>
              mutateDraft((draft) => {
                ensureBrowser(draft).profileName = event.target.value || "default";
              })
            }
          />
          <span className="entry-form-hint">Used under workspace <code>.browser-profiles</code> when profile path is empty.</span>
        </label>

        <label>
          Startup Timeout (ms)
          <input
            type="number"
            min="500"
            step="500"
            value={String(browser.startupTimeoutMs ?? 10000)}
            onChange={(event) =>
              mutateDraft((draft) => {
                const parsed = Number.parseInt(event.target.value, 10);
                ensureBrowser(draft).startupTimeoutMs = Number.isFinite(parsed) ? Math.max(500, parsed) : 10000;
              })
            }
          />
        </label>

        <label style={{ gridColumn: "1 / -1" }}>
          Profile Path Override
          <input
            placeholder="/Users/me/.sloppy-browser-profile"
            value={browser.profilePath || ""}
            onChange={(event) =>
              mutateDraft((draft) => {
                ensureBrowser(draft).profilePath = event.target.value;
              })
            }
          />
          <span className="entry-form-hint">Leave empty for Sloppy-managed profile storage. Set only when you want a specific user-data-dir.</span>
        </label>

        <label className="entry-toggle-row">
          <input
            type="checkbox"
            checked={Boolean(browser.headless)}
            onChange={(event) =>
              mutateDraft((draft) => {
                ensureBrowser(draft).headless = event.target.checked;
              })
            }
          />
          <span>Run headless</span>
        </label>

        <label style={{ gridColumn: "1 / -1" }}>
          Extra Browser Arguments
          <textarea
            rows={5}
            placeholder={"--disable-extensions\n--window-size=1440,1000"}
            value={(browser.additionalArguments || []).join("\n")}
            onChange={(event) =>
              mutateDraft((draft) => {
                ensureBrowser(draft).additionalArguments = parseLines(event.target.value);
              })
            }
          />
          <span className="entry-form-hint">One Chromium argument per line. Sloppy always adds remote debugging and user-data-dir.</span>
        </label>
      </div>
    </section>
  );
}
