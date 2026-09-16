# Agent-controlled in-app browser (macOS)

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
