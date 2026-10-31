# Browse and the agent-controlled browser

## Work / Browse

The native client has a Work / Browse switch on macOS, iPhone and iPad. Work
keeps the existing chats, projects and canvas. Browse uses vertical tabs in its
own sidebar on macOS; switching modes preserves the work selection and browser pages.
iPhone and iPad use a bottom address panel and a full-screen tab overview.

- **Command-T** opens the search/address launcher for a new tab in either mode.
- **Command-L** edits the current tab's address.
- **Command-Shift-S** hides or shows the sidebar in the active Work or Browse
  mode on macOS. The same command is available in the Workspace menu.
- Enter opens an HTTP(S) address or searches. Google is the default; the launcher
  also offers DuckDuckGo, Bing and Yandex. The choice is saved on the device.
- **Ask agent** opens Assistant beside the page in Browse and adds the launcher
  text to its draft. It does not send a message or replace a Work draft.
- The launcher finds open tabs, bookmarks and history by title or address. On Mac it floats over the current page as a compact glass panel, without sheet chrome. Arrow keys select a result, Enter opens it, Escape or an outside click closes the panel, and Command-Return starts an agent draft.
- **Command-W** closes the selected browser tab in Browse; **Command-R** reloads it.
  The corresponding page controls are available without a hardware keyboard.
- **Collect tabs on canvas** creates a personal research workspace containing
  source titles and URLs as editable text elements. It uses the existing canvas,
  so notes, agent conversations and further work stay together. This needs Core.

Tabs, their order, the selected tab, the search engine and the last Work / Browse
mode are saved locally under `sloppy.browser-workspace.v1`. Pages retain their
WKWebView while switching tabs or modes. Session restoration uses WebKit's public
`interactionState` when available, with a URL fallback. Inactive restored tabs
load on selection. WebKit's default website data store retains cookies and logins.
On macOS, HTTP web pages are allowed through `NSAllowsArbitraryLoadsInWebContent`
(owner-approved on 2026-10-30). This applies to WKWebView content; URLSession
connections keep their existing ATS policy. Bare loopback addresses (`localhost`, `*.localhost`, `127.x.x.x`, `[::1]`)
default to HTTP; other bare addresses default to HTTPS. Explicit HTTP/HTTPS is
preserved. Failed HTTPS loopback pages offer an explicit Open using HTTP action,
without automatically downgrading a TLS connection.
An app restart reloads page content; restoration does not promise to preserve
unsent site forms or running JavaScript. Tabs are device-local, without server sync.

The feature reuses the native browser and the existing desktop/mobile themes.
Zephium is an interaction reference: https://github.com/zephium-browser/Zephium.
Its canvas keeps research sources and results available outside a chat transcript;
Collect tabs on canvas brings that idea to Sloppy's current canvas.

## iPhone and iPad

Browse opens immediately on mobile, before connecting to Core or relay. Its
WebKit views remain mounted through connection failures, authentication and
workspace changes. Saved connections are restored in the background with bounded
retry delays; inactive scenes pause restoration. Reconnecting never switches the
user out of Browse. Transient network/server failures keep stored login sessions.

Work and Assistant can open the connection flow when needed. A compact
briefcase/globe switch lives in the native navigation bar on Work screens,
including loading and connection screens. Its globe returns to the retained
page immediately; the selected briefcase marks Work. There is no extra return
row above the screen content. An Assistant prompt is kept for the
successful sign-in; returning to Browse cancels that deferred action. Settings,
tabs, history, bookmarks and local downloads remain accessible without Core.

The floating bottom panel keeps the address, loading/stop control, Assistant,
Back, Forward, New tab, tab count and menu within reach. Assistant has its own
round button beside the address capsule, using the shared Sloppy mark in both
expanded and compact controls. Pages fill the available
content area. Scrolling down on a loaded page collapses the panel to a glass
host capsule and a separate Assistant button. Scrolling up or returning to the
top restores navigation. The compact address opens search; cancelling returns
the full controls. The transition respects Reduce Motion and does not replace
WebKit's scroll delegate. Page-script positioning and viewport changes do not
collapse the controls.
Tapping the address opens an in-place search layer over the retained page.
There is no modal sheet or navigation header: a close control floats at the top,
and a glass editor stays above the keyboard. Search-engine selection and Ask
Sloppy sit beside it as separate glass controls. Real top sites, tabs, bookmarks
and history provide suggestions. The current URL is selected on first focus;
Return or Go navigates, and closing keeps the current page or blank tab open.
The layer adapts to light/dark appearance, Reduce Motion and Reduce Transparency.


The tab count opens a searchable overview with two columns on iPhone and more
columns on wider iPads. Preview images come from retained WebKit pages. Select a
tab to return to its existing page and form state; close it with its own button.
The options menu filters by saved group and confirms closing all matching tabs.
Long-press a tab to move it to a group, share its URL or close it.

The browser menu contains sharing, bookmarking, History, Bookmarks, Downloads,
the search engine, tab-group creation, Collect tabs on canvas, Settings and
Return to Work. Home shows real frequently/recently visited pages and an
Assistant entry point. Library contents and tab state are saved on the device.

Assistant uses the same retained page on iOS as on macOS. Browser commands can
read, navigate, click, type, scroll and capture a PNG. Add page inserts the
page's bounded visible text and its source URL into the conversation draft.
Connecting browser commands to a conversation requires an authenticated Core
connection. Web Extensions and simultaneous Split View remain macOS features.

The isolated Debug launch argument `--browser-ui-fixture` opens the production
mobile browser without login. `--browser-fixture-reset` clears only its QA
defaults; `--browser-fixture-url=http://127.0.0.1:18874/` opens a local fixture.
See `Tests/MobileBrowser` for repeatable interaction checks.

### Browser-mode verification on 2026-10-30

- 58 focused browser tests passed with interactive WebKit tests enabled, including launcher keys, sidebar layout, frequency ranking, extension integration, context-menu actions, selection annotations and first-message handoff with IME/multiline input.
- These cover state restoration, search providers and URL encoding, retained
  form input across tab switches, WebKit back/forward restoration, and Command-T
  → Ask agent in the main window without replacing the previous chat draft.
- Opening and closing search preserves the sidebar's titlebar safe area in real
  full-size-content macOS windows at 1100- and 1700-point widths. The split view
  retains hit testing; the overlay intercepts background clicks itself.
- The macOS Release and iPhone Simulator builds passed after the Home/library changes; the earlier iPad Simulator build also passed. Builds used signing disabled, followed by Developer ID signing for the installed Mac app.
- Screenshots and interactive behavior were checked on macOS; physical Apple devices were not tested. The signed app was installed at `/Applications/Sloppy.app` and launch was verified.
- The full non-interactive client run executed 1,011 tests and reported six
  unrelated existing source-text assertion failures in `MainTabsSourceTests`,
  `ChatConversationNavigatorLayoutTests`, `ChatBubbleRenderingTests` and
  `ChatInitialLoadSourceTests`. The full suite is not green.

## Home, groups and browser library

### Split View on macOS

Select browser tabs with Command-click, or select a range with Shift-click.
Right-click the selection and choose **Combine in Split View** to show the pages
together. Drag the native dividers to resize panels. Two or three pages sit side
by side; larger selections use a grid.

Click a page or its panel title to make it active. The sidebar address field and
window navigation controls follow that page. **Separate Split View** in the
context menu or window toolbar returns the pages to individual tabs. Closing a
panel leaves the other tabs open. Splits are saved locally, and selecting a
member later reopens its split. Existing WebKit views are reused while combining
or separating tabs, preserving their current form input and navigation history.

The sidebar contains the address/search field, Home, a Tabs
header with its new-tab button, named groups, and a
persistent three-dot menu at the bottom. The menu opens the existing application
Settings, History, Downloads and Bookmarks, and offers New tab group and Collect
tabs on canvas.
On macOS, the Web Extensions button sits at the trailing end of the address
field. It appears when the address field is hovered or the button has keyboard
focus; its reserved space keeps the address stable. The menu retains extension
actions, options pages and Manage Web Extensions.

Right-click a tab (long-press on touch devices) → Move to group to choose a group
or create one. Group names, tab membership and collapsed state persist locally.
On Mac, hovering a tab reveals its trailing close button without shifting the title.
Removing a group keeps its tabs. Returning Home keeps all open pages available.
The Home page reuses the chat's ASCII wave field and native message editor. The
first committed input opens Assistant in Browse with that text; it does not send
the message. IME composition finishes before focus moves to Assistant, multiline
paste is kept, and the Work draft is preserved. The Home editor hides while
Assistant is open. The former quick-action row and counters
are removed. Up to six frequently visited sites appear below the composer, ranked
by recorded visits and grouped by host/port. Legacy history entries count as one
known visit each. Fewer sites are shown when there is not enough real history.

Bookmark the current page from the page controls; saved pages are searchable in
Bookmarks. History retains up to 2,000 recently visited URLs and can be searched
or cleared. Its ordering reflects the latest visit to each URL.

WebKit downloads are tracked through completion, cancellation or failure. Files
are stored in Sloppy's application-support `Sloppy/Browser Downloads` directory
on macOS and `Documents/Browser Downloads` on iOS/iPadOS. The list offers Show in
Finder on Mac and sharing on mobile. Clearing finished entries keeps the files.
No additional filesystem entitlements are introduced. A download interrupted by
an app restart is shown as failed and can be retried from its source URL.

On macOS, Back and Forward live in the page's window toolbar. Reload sits at the
trailing end of the address field. Bookmark appears there on address-field hover
or keyboard focus, beside Web Extensions; its reserved space keeps the text stable.
Tabs close from their sidebar row or Command-W. The address field
stays at the top of the sidebar with 16-point
continuous corners; mobile keeps navigation alongside the address. Loading
appears as a two-point progress line inside the
address field, driven by WebKit estimatedProgress/isLoading observations. No
spinner or loading row is inserted above the page, so its bounds stay fixed. iOS keeps search in the bottom address panel. Sidebar
layout is covered at 800×600, 1200×780 and 1800×1160 window sizes, alongside real
WebKit downloads, group/bookmark restoration and committed composer input.
The macOS sidebar header uses the system bar material through the titlebar safe
area and a hard top scroll edge, so tab rows scroll behind a blurred navigation
surface. The address field stays fixed and clickable while the list scrolls.

## Page frame, connection indicator and cancellation

On macOS, web pages fill the detail column to the window edges, without an outer
inset, border or rounded frame. Split panels are rectangular and separated by
native dividers. On iOS, pages fill the space between the system safe area and
the bottom navigation panel. The page background continues through system safe
areas and around the floating panel, without an extra gap above it. Native
browser chrome follows the page background contrast. visionOS retains the inset page frame.
The macOS page frame extends beneath the window toolbar;
the measured titlebar safe area plus the blur's 32-point fade and an 8-point gap
is applied as padding inside the main HTML document in an isolated content world.
Viewport-fixed headers and document-sticky top offsets also account for this
space; nested scrollers and transformed containers retain their own coordinates.
The layout updates incrementally for dynamically inserted headers and restores
the site's original inline values when the inset is removed, including in split
view. Other user scripts and browser selection overlays retain their behavior.
WebKit's `obscuredContentInsets` remains zero to avoid applying the offset twice.
The inset follows native window geometry rather than a fixed toolbar height.
The toolbar uses a Gaussian backdrop filter attached to the retained WebKit layer,
without a tinted material or a fill. Its alpha mask fades the blur below the controls.
The page background follows WebKit's document-derived color, including the area
beneath the toolbar. The default flat toolbar fill is hidden.
The mode switch uses a capsule glass surface with exterior edge insets;
the decorative blur does not intercept page input.
Real-window tests cover resizing and opening search without moving the page frame.
Error UI overlays the page below that inset rather than changing its bounds.
NSURLErrorCancelled (-999) is treated as cancelled navigation, including a load
superseded by another navigation; it does not show an error banner. Genuine
network failures retain a readable explanation and Retry.

The address field shows a closed lock only for a completed HTTPS document when
WebKit reports `hasOnlySecureContent`. Loading, HTTP, mixed content and failures
have separate icons/accessible descriptions. Default WebKit certificate checks
remain in effect. Tab icons request `/favicon.ico` from the visited origin,
without sending browsing domains to a third-party icon service, and fall back to
the globe when an icon is unavailable.
Hover the macOS connection icon to see the current connection status and the
certificate supplied by that page's WebKit `serverTrust`: subject, issuer,
validity dates and SHA-256 fingerprint. Move into the popover to read or copy
details; clicking the icon pins it open. Show Certificate opens the native
certificate-chain sheet with trust editing disabled. HTTP has no certificate;
loading, failed or changed pages never reuse the previous page's certificate.

## Page context menu (macOS)

Right-click a web page for Back, Forward, Reload, Save As, Print, a local QR code,
translation and page source. Navigation actions reflect the current back/forward
history. WebKit's original link, image, selection and spelling actions remain in
the menu. Save As exports a Web Archive through the native save panel; the
sandboxed TestFlight build allows writing only to user-selected destinations.
Page Source shows the current HTML DOM in a read-only native text window.

Translate to Russian (Google) sends the current page URL to Google Translate only
when selected. It is disabled for loopback, private IP addresses and known local
host names.
Pages opt in to WebKit's public inspection support. If WebKit supplies an Inspect
Element action it is preserved; otherwise Inspect in Safari explains how to find
the running Sloppy page in Safari's Develop menu and offers to open Safari.
This does not open an in-app developer console. Chromecast/Cast is not included.

## Assistant in Browse

The Assistant button opens a conversation beside the page on Mac. Drag the
divider to resize it; hiding it retains its draft, transcript and conversation.
On iPhone and iPad the system inspector adapts to the available space. The panel
reuses the regular chat composer, including model selection, attachments,
approvals, queued messages and Stop. Its menu offers New chat and recent chats.

Add page explicitly attaches a bounded snapshot of the visible text, page title
and URL to the draft. Selection actions open this same Assistant, and Add as
annotation targets it while visible. Both preserve existing draft text and wait
for Send. Switching browser tabs keeps the conversation. Closing and reopening
a selection menu is required if its receiving conversation has changed.

On Mac, browser tools in this conversation use the selected Browse page and its
retained WebKit view. Switching tabs retargets that connection without changing
the chat. Leaving Browse disconnects this browser binding. Work conversations
continue to use their own browser panels.

### Assistant verification on 2026-10-31

The Assistant resize host extends through the toolbar safe area. Its original
toolbar inset is passed to WebKit for document clearance and blur, while the
chat alone is padded below the toolbar. Regression coverage checks full-window
web-view geometry and active blur layers with Assistant hidden, open and closed
again at 1100- and 1700-point window widths. The expanded browser/chat/split/dock
regression passed 44 tests in eight suites after this correction.

- 43 focused tests in seven suites passed with interactive macOS windows enabled.
  They cover sending and receiving through an isolated test API, page snapshots,
  selection destinations, retained form input, resizing, tab switching and
  committed IME/multiline input moving from Home to Assistant.
- macOS Release and iPhone Simulator builds passed with signing disabled.
- The full non-interactive run executed 1,055 tests and reported the same six
  existing source-text assertion failures in MainTabsSourceTests,
  ChatConversationNavigatorLayoutTests, ChatBubbleRenderingTests and
  ChatInitialLoadSourceTests. The full suite is not green.
- No live provider message was sent. At the owner's request, the Release app was
  signed with the existing Developer ID and installed at `/Applications/Sloppy.app`.
  The previous app is retained under `.build/app-backups`; signature verification,
  binary comparison and the installed process's launch passed.

## Agent-controlled in-app browser (macOS)

The macOS client connects each opened chat task to its Core endpoint. When the
agent calls `browser.open` or another browser action, Sloppy shows the Browser
panel and runs the command in that task's retained WKWebView. Hiding the panel
preserves the page. Closing the task disconnects its browser.

Both ClientNative and Core must include this feature. No Chromium installation,
local listening port, or MCP configuration is needed for the in-app surface.
The connection uses the same authentication and direct/mesh endpoint as the task.
An older Core returns an unavailable connection error; manual browsing still works.

## Agent workflow

1. `browser.open(url)` loads a page and waits for navigation to complete.
2. `browser.read(pageId?)` returns URL, title, visible text and interactive elements
   with CSS selectors, labels, roles and disabled state.
3. `browser.click(selector)` and `browser.type(selector, text)` operate on one
   observed element and return the updated page. Empty text clears an input.
4. `browser.scroll(selector)` brings an element into view; `x`/`y` instead scroll
   to absolute coordinates.
5. `browser.screenshot` saves the actual rendered PNG on Core, retaining the
   existing verification-evidence mechanism.
6. `browser.close` clears the page. `browser.open` can reuse the connection.

Page text is untrusted content, not agent instructions. Selectors should come
from a fresh page read. Missing, ambiguous, hidden and disabled elements fail
explicitly. Navigation accepts HTTP, HTTPS and `about:blank`. New-window links
open in the same task page. DOM operations currently target the main document;
cross-origin frames, shadow roots and native file choosers are outside this version.
Automation is macOS-only; iOS/visionOS retain their existing manual web view.

## Workspace panels

The right panel has tabs for Browser, Terminal, Side chat, Files and Review.
Use **+** for additional browser, terminal or chat tabs. The panel button hides
and restores the current panel; it does not open the picker or clear the tabs.
The close button on a tab closes only that tab. Closing a terminal tab ends its
shell; hiding the panel or selecting a different tab keeps its shell and buffer.

Tabs, the selected tab and panel width are retained per project and server while
the app is running. Returning to a project restores that project's panel state.
Drag the vertical divider to resize the side panel. The main sidebar, bottom
panel and split work areas also have wider resize ranges. The browser address
field navigates on Enter. An empty browser uses the app's surface color, while
loaded websites keep their own page colors.

## Transport and lifecycle

Core exposes authenticated POST routes under `/v1/workspace-browser/`:
`register`, `poll`, `complete`, `disconnect`. A binding contains `bridgeId` (a
random UUID), `agentId`, and `sessionId`. Registration verifies the session exists
and refuses to replace a live connection from another client. Commands and results
are checked against the binding. Each page permits one pending command.

Polling runs once per second while the task remains open. Connections have a
60-second lease; commands time out after 25 seconds, and page loads after 20.
Commands are dequeued once: delivery failures never automatically replay actions.
If a client disconnects, subsequent tools fail explicitly rather than switching to
another browser. Tasks without an in-app binding keep the existing Chromium path.

## Validation

- `swift test --filter 'WorkspaceBrowser|WorkspaceWebView'` from ClientNative
  includes real WebKit navigation, element discovery, clicks, multiline input,
  clearing fields, scrolling and PNG capture against a local HTTP fixture.
- Core: `swift test --filter 'WorkspaceBrowserBridgeTests|BrowserCDPServiceTests|ToolRegistryTests'`
  checks routing, binding ownership, timeout/cancellation and the Chromium fallback.
- Set `SLOPPY_BROWSER_SMOKE_SCREENSHOT=/absolute/path.png` for the client tests to
  retain the HTTP fixture's screenshot.

### Verification on 2026-09-15

- macOS Xcode build: passed with signing disabled, using XcodeBuildMCP.
- Core `sloppy` and `SloppyNode` release builds: passed.
- Browser client tests: 12 passed, including the authenticated polling → WebKit
  → page/PNG result chain and disconnect after cancellation.
- Core browser/router/catalog tests: 32 passed with a temporary manifest selecting
  those test sources. The unmodified Core test target cannot compile because of
  an existing Swift concurrency error at `SloppyRemoteProviderTests.swift:188`.
- Full client suite after the panel changes: 482 tests, 107 existing issues. An isolated baseline with
  the original client sources ran 467 tests and reported the same 107 issues.
  The browser change did not introduce new full-suite failures.

These are local source and build results. A running installation needs both the
updated Core and the updated macOS client; no deployment is performed by building.

### Panel interaction verification

- 33 focused browser, dock, terminal and environment checks passed.
- A real macOS test window received mouse-down/drag/up events and resized the
  browser from 480 to 680 points. Hiding and showing preserved the page identity.
- Return in the native address field loaded the HTTP fixture without an Open button.
- Terminal view removal/recreation preserved the shell PID and its text buffer.
- Project/server isolation, tab selection, separate browser instances and closing
  individual tabs are covered by state tests.
- The rendered dark panel was visually inspected with Browser, Terminal and Side
  chat tabs, and an empty page matching the application's surface color.

### Panel chrome

The main toolbar owns panel visibility; the dock header contains tab controls and
its add-tab menu. The resize target overlays the shared edge, so the project rail
and dock meet without reserving a gap. The pointer target remains 12 points wide.

Canvas libraries contribute their New Workspace toolbar item only while their
own surface is active. Hidden cached project tabs and the hidden global canvas
surface keep their state without adding duplicate plus buttons. The empty-library
Create Workspace action uses the native glass button style.
