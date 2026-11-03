# Browser agent and site controls

The Browse assistant can manage the device's real tabs, tab groups, personal notes and todos. Both Core and ClientNative need the updated source. This work does not install or restart the user's existing apps or Core.

## Agent tools

- `browser.tabs(operation: "list")` returns stable tab IDs, titles, URLs, selection and group membership. `open` creates a new tab, optionally with `url`; `select` and `close` require an observed `tabId`. Closing the last tab keeps the workspace connection available for opening another.
- `browser.groups` supports `list`, `create`, `rename` and `move`. Use observed `tabIds`, an optional `groupId`, and a `title` for creation/rename. Omitting the group ID when moving ungroups those tabs. The model chooses semantic groups from page context; application code applies structured IDs without classifying localized text.
- `browser.create_note(title, text?, url?)` saves Markdown in browser Notes.
- `browser.create_todo(title, text?, url?, dueAt?, priority?)` saves a personal browser task. `dueAt` is ISO 8601 with a time zone; priority is `normal`, `low` or `high`. These tasks do not create server project tasks or schedule notifications.

Notes and todos use the existing local organizer and return the created entry ID. The optional source defaults to the selected tab. URL credentials are removed. Command delivery never automatically replays a mutation after a failed completion response.

New commands require the registered client's `tabs_v1`, `groups_v1` or `organizer_v1` capability. Unsupported/disconnected bindings fail explicitly. Legacy `browser.open/navigate/close` keep their existing single-page semantics; use `browser.tabs` to close an actual Browse tab.

Existing click/type/scroll commands display native cursor feedback with a restrained glow and the active agent's existing portrait. The overlay uses the observed target's viewport coordinates, passes user input through, and clears on cancellation/navigation. Arbitrary JavaScript evaluation does not invent cursor actions. Reduce Motion and Reduce Transparency are respected.

## Site permission controls

On Mac, open the connection icon beside the address, then **Site Settings**. On iPhone/iPad, use **Browser menu → Site Settings**. Saved decisions can be reset from that screen.

Before top-level HTTP navigation or a direct HTTP download, Sloppy asks whether to continue once, always allow the site, or cancel. This also applies to links, restored pages and agent navigation. Server redirects are checked before the target receives a request. Remembered rules bind to the exact scheme, host and port; HTTPS certificates retain normal WebKit validation. Mixed-content policy remains WebKit's responsibility.

Camera and microphone have independent **Ask / Allow / Block** choices. OS privacy authorization is checked in addition to site consent. Resetting a choice stops active capture. Until embedding-origin policies are implemented, cross-origin iframe capture requests are denied rather than inheriting a top-level site's grant.

Location uses [Apple's public geolocation permission delegate](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:requestgeolocationpermissionfor:initiatedbyframe:decisionhandler:)) when the running system exposes that optional method. The installed 26.5 SDK does not declare it. On systems without this public callback, custom location settings are disabled and WebKit/system location prompts remain in control. No private delegate or replacement coordinate provider is used. Real location acceptance on a supporting OS remains outstanding.

## Passkeys on macOS

Site Settings shows browser-wide passkey access. **Allow Sloppy to use passkeys…**
requests macOS consent only when the signed app has the required entitlement.
After allowing access, retry sign-in on the website. WebKit handles WebAuthn and
the system credential picker; Sloppy does not intercept challenges or passkeys.
If access was denied, change **System Settings → Privacy & Security → Passkeys
Access for Web Browsers**. The state refreshes when Sloppy becomes active again.

The macOS and TestFlight target entitlements declare
`com.apple.developer.web-browser.public-key-credential`. Apple must approve this
managed capability for the app's developer account and App ID; adding the key to
a source plist alone does not enable it. See [Apple's entitlement requirements](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential)
and the [macOS Browsers Passkeys request form](https://developer.apple.com/contact/request/macos-browsers-passkeys/).
Apple currently requires an organization Account Holder to submit that request.

For a local Developer ID build, provide an approved macOS profile containing the
capability and the selected signing certificate:

```sh
MACOS_PASSKEY_PROVISIONING_PROFILE=/absolute/path/Sloppy.provisionprofile \
MACOS_REQUIRE_PASSKEYS=1 script/build_and_install.sh
```

The signing script checks the profile's App ID, team, platform, expiry and signing
certificate, embeds it, and preserves the entitlement. `MACOS_SIGNING_IDENTITY`
can select a certificate by its SHA-1 fingerprint; the default automatically
selects the project's team. TestFlight uses Xcode provisioning for its target.
Without an approved profile, local builds omit the managed entitlement and
report **Passkeys are unavailable in this build of Sloppy**. Setting
`MACOS_REQUIRE_PASSKEYS=1` instead fails signing if support is unavailable.
Use another sign-in method until a provisioned build is installed. Real passkey
sign-in still requires manual verification with an approved profile and consent.

## Website data and full reload

Site Settings offers **Clear cached files** and **Remove cookies and site storage**. Before deleting cookies/storage, the confirmation identifies the actual WebKit data record. WebKit may store a domain's subdomains and ports together; that shared scope is displayed. Removing cookies/storage signs the user out of that scope. Other sites and browser notes/tasks remain separate. The page reloads when the settings close.

On Mac, **Workspace → Reload Without Cache**, or **Command-Shift-R**, clears supported cache types across the page's shared browser profile and reloads the active page from origin. This includes memory/disk/offline/Fetch Cache, while preserving cookies, localStorage, IndexedDB, site decisions, history and organizer data. Service-worker registrations are retained. Normal Command-R remains available.

## Handoff

Handoff was already connected through `BrowserHandoffModifier`: the selected Browse HTTP(S) URL and title are advertised and continuation opens in Sloppy. Cookies/forms stay device-local. See [the browser guide](in-app-browser.md#handoff-and-shared-history). Actual transfer between compatible signed Mac and iPhone/iPad builds still needs physical-device acceptance.

## Local verification

Focused tests exercise real WebKit navigation, pre-network HTTP denial including server redirects, cancellation, origin-bound decisions, simulated OS camera/microphone results, cache removal, cookies/storage isolation, actual tab/group state, organizer persistence and native cursor rendering. Real hardware capture, location on a supporting OS and cross-device Handoff are separate manual acceptance checks.
