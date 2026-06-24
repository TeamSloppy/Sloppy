# SloppySafari Start Page Design

Date: 2026-06-24

## Goal

Add a Comet-like SloppySafari start page for new tabs. The page centers a chat composer, shows a persistent left navigation/sidebar, and lets the user customize shortcuts, theme, and a personal background image. When the user submits a prompt, the start page transitions into the existing fullscreen Sloppy chat experience and sends the prompt.

## Browser Integration

The WebExtension manifest will declare:

```json
"chrome_url_overrides": {
  "newtab": "start.html"
}
```

`start.html` must be bundled with the extension. Safari support can differ from Chromium, so the feature should fail gracefully: if Safari honors the override, new tabs open Sloppy Start; if not, the page remains available as an extension resource and the existing fullscreen chat entry points continue to work.

Because manifest keys are static, the user setting cannot remove the override at runtime. Instead, `start.html` checks `startPageEnabled` from extension storage. When disabled, it shows a quiet Sloppy-disabled state with a re-enable button, a settings button, and a plain URL field so the tab remains useful without pretending to restore Safari's native new-tab page from inside the extension page.

## Pages And Scripts

- `start.html`: new extension page used by `chrome_url_overrides.newtab`.
- `startPage.js`: marks the document as a Sloppy start page and starts the shared UI in start-page mode.
- Existing `chat.html` and `chatPage.js`: continue to host fullscreen chat.
- Existing `contentScript.js`: owns the shared shell, composer, session loading, settings, and message sending behavior.
- Existing `panel.css`: extended with start-page and fullscreen-sidebar styles.

The implementation should avoid a separate React/Vite surface. SloppySafari already has a shared WebExtension UI shell and chat pipeline, so the start page should reuse those primitives.

## Layout

Both the start page and fullscreen chat include the same left sidebar:

- New chat
- Sessions/history
- Projects
- Settings
- Customize

The start page main area contains:

- Centered Sloppy chat composer.
- Model and attachment controls matching the existing composer.
- User-configured site shortcuts below the composer.
- Optional user background image.

Fullscreen chat keeps the sidebar and uses the existing thread/composer layout for active conversations. The close and open-fullscreen buttons stay hidden in fullscreen extension pages.

## Start-To-Chat Flow

On first load, start page mode renders the centered composer and shortcuts instead of an empty chat thread. When the user submits a prompt:

1. Create or reuse the selected Sloppy session through the existing session/chat pipeline.
2. Switch the UI from start page mode to fullscreen chat mode.
3. Send the prompt.
4. Show streamed assistant output in the fullscreen thread.

Selecting an existing session from the sidebar also switches to fullscreen chat and loads the session events.

## Customization

Store customization in `chrome.storage.local` as part of sanitized extension settings:

```js
{
  startPageEnabled: true,
  startPageTheme: "dark",
  startPageBackgroundImage: "",
  startPageShortcuts: [
    { title: "GitHub", url: "https://github.com" }
  ]
}
```

Rules:

- `startPageTheme` supports `"dark"` and `"light"` only.
- `startPageBackgroundImage` is a data URL created from a user-selected image file.
- Image storage should enforce a conservative size limit and reject unsupported file types with an inline settings error.
- Shortcuts require valid `http:` or `https:` URLs.
- The settings/customize UI lets the user add, edit, remove, and open shortcuts.
- The user can clear the custom image.

## Settings UI

The existing settings dialog gains a Start Page / Customize section:

- Enable Sloppy Start Page toggle.
- Theme segmented control or select for dark/light.
- Background image file picker and clear button.
- Shortcut editor rows for title and URL.

The setting is saved through the existing `sloppy.settings.save` message path and sanitized in `panel.js`/`background.js`.

## Testing

Use TDD for implementation.

Initial tests:

- Manifest declares `chrome_url_overrides.newtab` as `start.html`.
- `start.html` and `startPage.js` are packaged as extension resources for all Safari extension bundles.
- Settings sanitization defaults `startPageEnabled` on, theme to dark, and validates shortcuts.
- Invalid shortcut URLs are dropped.
- Custom background accepts image data URLs and drops unsupported values.
- Start page submission switches to fullscreen chat mode before sending.
- Fullscreen chat renders the shared sidebar.

Verification:

```bash
cd Apps/SloppySafari/Extension
npm test
```

When Swift or project files change:

```bash
cd Apps/SloppySafari
swift test
xcodebuild -project SloppySafari.xcodeproj -scheme SloppySafari-macOS build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```
