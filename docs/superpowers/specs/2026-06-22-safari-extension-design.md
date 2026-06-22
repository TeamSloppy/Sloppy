# SafariExtension Design

Date: 2026-06-22
Status: Draft for user review
Owner: Sloppy maintainers

## Summary

SafariExtension is a separate Apple app project under `Apps/SafariExtension/` that ships a Safari Web Extension for using Sloppy from Safari. The MVP provides an in-page side panel and selected-text workflow backed by a locally reachable Sloppy Core server.

The project is intentionally separate from `Apps/Client/` so the Safari extension can evolve without coupling its packaging, platform support, and browser permission model to the full native Sloppy client.

## Goals

- Add a Safari side-panel experience for chatting with Sloppy from the current web page.
- Let the user send the current page URL, title, selected text, and a typed prompt to a Sloppy agent/session.
- Support macOS first while keeping the project shape compatible with iOS, iPadOS, and visionOS.
- Use the local/LAN Sloppy Core HTTP API for the MVP.
- Keep page access explicit and privacy-preserving: user selection and user actions drive what leaves Safari.

## Non-Goals

- Do not automate Safari page interaction in the MVP.
- Do not scrape or summarize the full page by default.
- Do not merge this into `Apps/Client/`.
- Do not rely on Chrome-only or non-portable side panel APIs as the core UI contract.
- Do not add model-output text heuristics for state, intent, or completion.

## Platform Strategy

The user-facing side panel is implemented as a content-script drawer injected into the current page. This is more portable across Safari on Apple platforms than depending on a browser-native side panel API.

The containing app provides extension installation, permissions onboarding, and connection settings. The app can be minimal in the MVP: a SwiftUI settings screen with Sloppy Core URL and connection status.

Default connection behavior:

- macOS: `http://127.0.0.1:25101`
- iOS, iPadOS, visionOS: user-configured LAN URL such as `http://192.168.1.50:25101`

On device platforms, `localhost` refers to the device, not the Mac running Sloppy, so the settings UI must make the LAN URL path clear.

## Project Layout

```text
Apps/SafariExtension/
  project.yml
  README.md
  Sources/
    SafariExtensionApp/
      SafariExtensionApp.swift
      SettingsView.swift
      ConnectionSettings.swift
  Extension/
    Resources/
      manifest.json
      background.js
      contentScript.js
      panel.css
      panel.js
      icons/
  SupportingFiles/
    macOS/
      Info.plist
      SafariExtension.entitlements
    iOS/
      Info.plist
      SafariExtension-iOS.entitlements
    visionOS/
      Info.plist
      SafariExtension-visionOS.entitlements
```

Exact target names can follow XcodeGen conventions, but the product and app name should be `SafariExtension`.

## User Experience

1. User installs/enables the extension in Safari.
2. User opens a web page and selects text.
3. User clicks the SafariExtension toolbar item or uses a context-menu action.
4. The extension injects or opens a right-side drawer inside the page.
5. The drawer shows:
   - connection status,
   - current page title and host,
   - selected text preview,
   - prompt input,
   - send button,
   - response transcript for the current page interaction.
6. User sends the prompt.
7. The extension posts a typed browser-context request to Sloppy Core.
8. The drawer renders the response or an actionable error.

The drawer should not permanently modify page layout. It should be removable with a close button and avoid interfering with the underlying page as much as practical.

## Data Contract

The extension sends typed browser context. The payload should be explicit enough for Core/API tests and should avoid deriving behavior from localized text.

Example request shape:

```json
{
  "source": "safari_extension",
  "page": {
    "url": "https://example.com/article",
    "title": "Example Article"
  },
  "selection": {
    "text": "Selected page text"
  },
  "prompt": "Explain this",
  "target": {
    "agentId": "default",
    "sessionId": null
  }
}
```

The first implementation may map this to an existing session/chat endpoint if it can preserve the typed context. If existing endpoints force the extension to flatten context into one prompt string, add a narrow Core API endpoint instead.

## Core Integration

Preferred MVP integration:

- Reuse existing Sloppy Core HTTP client conventions where practical.
- Add a narrow endpoint only if current session APIs cannot represent browser context cleanly.
- Keep auth/dashboard token handling compatible with local Core settings.
- Return a response payload the extension can render without parsing prose for state.

Possible endpoint:

```text
POST /v1/browser/context-message
```

Possible response shape:

```json
{
  "sessionId": "session-id",
  "messageId": "message-id",
  "status": "completed",
  "text": "Agent response"
}
```

If streaming is straightforward through existing session sockets, it can be added after the blocking request path works.

## Permissions And Privacy

The MVP should request the smallest useful permission set:

- active tab access when the user invokes the extension,
- scripting/content script access needed for the drawer,
- storage for connection settings,
- network access to configured local/LAN Sloppy Core origins.

The extension should not transmit full page text unless the user explicitly asks for that later. For MVP, send selected text plus page metadata.

Errors should make privacy boundaries clear:

- no text selected,
- Sloppy Core unavailable,
- current site permission missing,
- local network URL invalid,
- auth required or rejected.

## Testing

Initial verification should cover:

- manifest and extension resource packaging through XcodeGen/Xcode build,
- connection settings parse and persistence,
- content-script selection extraction,
- drawer open/close behavior,
- request payload construction,
- error rendering for unavailable Core,
- successful request against a local mock or test endpoint.

Manual smoke tests:

- macOS Safari loads the extension and opens the drawer on a normal web page.
- Selecting text and sending a prompt reaches local Sloppy Core.
- Device-family settings accept a LAN Core URL.

## Implementation Sequence

1. Create `Apps/SafariExtension/` XcodeGen project skeleton.
2. Add containing app settings UI and persistence.
3. Add Safari Web Extension resources and manifest.
4. Implement content-script drawer and selection capture.
5. Add Core API client from the extension side.
6. Add or reuse Core endpoint for typed browser-context messages.
7. Add focused tests and build verification.

## Open Decisions

- Which default agent/session should receive Safari messages.
- Whether MVP response should be blocking HTTP or streaming.
- Whether auth token entry lives only in the containing app or can also be edited in the panel.
- Whether context-menu actions are included in the first implementation or deferred after toolbar flow.
