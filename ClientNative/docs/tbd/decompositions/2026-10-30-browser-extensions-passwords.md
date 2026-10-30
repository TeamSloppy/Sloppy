# Browser extensions and Passwords — decomposition map

- Created: 2026-10-30
- Scope: macOS Browse in SloppyClient; preserve the existing browser-mode changes.
- Current branch: `codex/browser-mode`; implementation remains local unless publication is requested.
- Budgets: target 600 reviewable lines per slice; maximum 1000.
- Approval: approved by the user on 2026-10-30.

| # | Slice | Purpose | Strategy | Budget | Depends on | Status |
|---|-------|---------|----------|--------|------------|--------|
| 1 | Passwords on login-field focus | Validate and integrate the supported macOS credential UI for website login/password fields. | Self-contained; use public system APIs and document platform limitations. | 500 | — | in-progress: requested autofill not delivered; API limitation recorded |
| 2 | Import and manage Web Extensions | Import compatible Safari Web Extension resources or app bundles, persist enablement, and control site access. | Empty extension list preserves existing behavior; permissions are opt-in. | 600 | — | in-review: implemented locally, no PR |
| 3 | Extension browser interactions | Connect extension tab/window APIs and action popups to Browse; verify an extension in the running Mac app. | Additive capabilities for explicitly enabled extensions. | 600 | 2 | in-review: implemented locally, no PR |

## Details

### 1 — Passwords on login-field focus

- In scope: establish whether public macOS APIs can present Passwords for arbitrary website credentials on field focus; implement the supported path, test navigation/focus boundaries, verify the system UI in the running app.
- Out of scope: reading the user's password database, storing credentials in Sloppy, bypassing Touch ID, private WebKit selectors, claiming passkeys are equivalent to passwords.
- Ships safely because: the credential flow is independent of extension installation and must preserve domain binding and user authorization.
- Cleanup owed: none.
- If the public platform does not support the requested presentation, record the evidence and implement only an honest supported alternative; do not simulate Passwords with an app-owned password store.

### 2 — Import and manage Web Extensions

- In scope: public WKWebExtension APIs; import from a selected extension directory or containing Safari extension app; persistent installation and enable/disable/remove; requested API and host permissions; clear import/load errors.
- Out of scope: legacy Safari App Extensions, automatic copying of Safari permissions, a store backend, silent broad site access, unsupported native companion messaging.
- Ships safely because: only explicitly imported and enabled extensions are loaded, and website access is granted by the user.
- Cleanup owed: none.

### 3 — Extension browser interactions

- In scope: represent Browse tabs/windows to WebKit; synchronize activation, navigation and close events; handle supported tab creation/update/close requests, options pages and action popups; integration tests and Mac runtime proof.
- Out of scope: claiming universal compatibility with every Safari extension or emulating unsupported native APIs.
- Ships safely because: these callbacks affect only installed extensions; normal browsing remains usable without extensions.
- Cleanup owed: none.

## Strategy alternatives

- Recommended: independent, complete increments as above. No temporary feature flag or replacement browser layer is needed.
- Alternative: hide all entry points behind one feature flag until all three slices pass. This delays useful independent results and requires a later flag-removal slice.

## Decision log

- 2026-10-30: Split credential integration from extension hosting and browser interaction. Investigate Passwords first because macOS support for arbitrary-domain password suggestions must be proven independently of iOS and passkeys.
- 2026-10-30: User approved the full map. Credential investigation found that the tested public password request and native AutoFill command did not provide arbitrary-site autofill. This requirement remains unfinished; no replacement password store, private API workaround or misleading success state was added.
- 2026-10-30: Extension increments implemented and validated with 49 passing browser tests and a launched, separately signed Mac QA app. Real Safari app-bundle import was verified with Obsidian Web Clipper disabled. Increment 2 is approximately 430 reviewable lines; increment 3 is approximately 430, including focused tests and debug fixture wiring. Existing browser-mode and unrelated changes remain separate; no commits, push or PR were created here.
