# Mobile browser checks

Use a Debug iPhone or iPad Simulator build. These checks exercise the production
Browse surface with isolated QA defaults and pages served from localhost.

1. Start the local pages from the ClientNative directory:

   ```sh
   python3 -m http.server 18874 --bind 127.0.0.1 --directory Tests/MobileBrowser/fixtures
   ```

2. Build and run `SloppyClient-iOS` with XcodeBuildMCP. Stop only Sloppy, then
   launch the fixture (substitute a booted simulator's UUID):

   ```sh
   BROWSER_SIMULATOR_ID="UUID"
   xcodebuildmcp simulator stop --simulator-id "$BROWSER_SIMULATOR_ID" --bundle-id team.sloppy.client
   xcodebuildmcp simulator launch-app --simulator-id "$BROWSER_SIMULATOR_ID" --bundle-id team.sloppy.client --json '{"args":["--browser-ui-fixture","--browser-fixture-reset","--browser-fixture-url=http://127.0.0.1:18874/"]}'
   maestro --device "$BROWSER_SIMULATOR_ID" test Tests/MobileBrowser/mobile-browser-smoke.yaml
   ```

The flow checks creating and cancelling blank tabs, navigation, WebKit form
retention across tab switches, bookmarks, history, close-all confirmation and
empty states. It leaves one blank QA tab open.

To check the iOS agent tool runtime, relaunch the same fixture with the additional
`--browser-fixture-runtime-check` argument. A visible `Browser tools passed`
result confirms DOM reading, typing, click navigation, scrolling and PNG capture.
This runs locally without contacting Core. Authenticated Core polling and model
responses need a separate connected-session check.

Also inspect the search field, engine menu and Ask agent with the software
keyboard visible, and the overview at portrait/landscape and iPad widths.

## Verified on 2026-10-31

- Maestro smoke: all 40 commands passed, including repeated file downloads.
- iPhone 17 Pro Simulator, iOS 26.3: build/run, navigation, search above the
  software keyboard, tab previews and retained form input, bookmarks/history,
  downloads, empty states and a refused localhost navigation with Retry.
- iPadOS simulator scheme: compilation passed; iPad interaction was not run.
- iOS runtime probe: open/read/type/click/scroll/PNG capture passed on the
  attached production WebKit view.
- Focused workspace, split and Assistant tests passed. The seven AppKit
  runtime/connection tests were then rerun with
  `SLOPPY_RUN_INTERACTIVE_UI_TESTS=1` and passed, including mocked Core polling
  and screenshot delivery. A real authenticated Core session was not tested.

## Browsing without a backend

A normal iOS launch opens Browse immediately, including when no server is saved,
relay is unavailable, or a session requires login. Work/Assistant can open the
connection flow; the globe in the navigation-bar mode switch returns to the retained page. Background
restoration never replaces the browser surface, and pauses outside the active
scene. Retries use delays of 2, 4, 8, 16 and then 30 seconds. Transient transport
and server errors keep saved authentication credentials.

Launch with `--browser-offline-root-fixture --browser-fixture-reset` and the local
fixture URL, then run `mobile-browser-offline.yaml`. This uses the production
mobile shell while its backend transitions from pending to authentication, with
isolated browsing defaults. The flow checks Work/login/Assistant entry points,
cancellation, retained page input and access to tabs. It does not sign in or
contact a real Core/relay. Also check a normal launch without fixture arguments.

Offline-launch verification on 2026-10-31: 23 focused tests passed. The 33-step
production-shell flow passed on iPhone 17 Pro Simulator (iOS 26.3), including
Work/Assistant connection entry, returning to the same input, tabs, app
background/foreground and a Work screen whose server refuses connections. A normal launch without fixture arguments also opened
Browse and loaded a page without a connected Core/relay.

A normal restart after leaving the app in Work also returned directly to Browse;
the Cloud sign-in screen did not intercept startup.

## Page edges

Launch the browser fixture at `/long.html` and run `mobile-browser-edges.yaml`.
The final page action must remain tappable above the floating browser panel.
Visually inspect `/` and `/second.html`: the actual WebKit page background should
continue through the status-bar area and around the bottom controls without black
bands. Status-bar and native chrome contrast follows the page; Home, Work and
app Settings keep the configured application appearance.

Page-edge verification on 2026-10-31: iPhone 17 Pro/iOS 26.3 build passed;
light and dark pages were inspected in Simulator, the final action on the long
page remained tappable, and the 33-step offline shell regression passed. Normal
app launch and search dismissal were also checked outside fixture mode.

## Scrolling browser controls

Launch the isolated browser at `/long.html` and run `mobile-browser-collapse.yaml`.
Gestures use coordinates inside the page, above the toolbar. Scrolling down
collapses to the host capsule plus Assistant; scrolling up restores navigation.
The compact address opens search and restores the full controls when dismissed.
The Assistant capsule also restores the expanded controls. Use `/reading.html`
for a dark article-style visual check. Native scroll observation keeps WebKit's
own delegate and ignores programmatic positioning, zooming and viewport changes.

Scrolling-controls verification on 2026-10-31: iOS build passed, 11 focused tests
passed, and all 21 steps of `mobile-browser-collapse.yaml` passed on iPhone 17 Pro
Simulator (iOS 26.3). The compact dark article layout was visually inspected.

Navigation mode-switch verification on 2026-10-31: iOS build passed, 10 focused
tests passed, and all 33 offline-shell steps passed with the new globe control.
The real Inbox navigation bar and the Attention tab were inspected, and Work
selection plus returning to the retained browser page were checked.

## In-place glass search

`mobile-browser-search-overlay.yaml` checks that search has no sheet grabber,
retains page input on cancellation, replaces the selected current URL, and
navigates with Return and Go. The 24-step flow passed on iPhone 17 Pro Simulator
in both dark and light appearances. Use `--browser-fixture-light` for the latter.
The 33-step Work/Assistant handoff regression also passed after the sheet was
removed. iPad scheme build passed and the windowed keyboard layout was visually
inspected with native XcodeBuildMCP tools; the multi-simulator Maestro run was
not a reliable iPad interaction check.

## Assistant navigation

The iOS Assistant uses a native inline navigation title and separate white
Liquid Glass menu/close controls. Its composer has 8 pt side margins; other chat
surfaces keep their existing spacing. On 2026-10-31 the iPhone Simulator build
passed, as did the 33-step offline regression and 20 final Assistant checks covering
keyboard input, the conversation menu, closing/reopening, and retained chat/page
drafts. No Core/relay connection or message sending was required for this check.
