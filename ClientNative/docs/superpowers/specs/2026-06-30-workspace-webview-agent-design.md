# Workspace WebView Agent Design

Date: 2026-06-30
Status: Draft for review

## Goal

Extend the right-side workspace panel so the user can switch from the file tree to an embedded web surface, and the agent can launch a web page there and interact with it.

The first implementation should support:

- opening a URL or local page in an embedded web view
- showing the same page to the user inside the right panel
- agent actions against that same live page:
  - open
  - read
  - click
  - type
  - scroll
  - screenshot

## Existing Context

The client already has:

- a desktop-only right-side `WorkspacePanel`
- project-aware chat context in `ChatScreenViewModel`
- typed project file APIs in `SloppyClientCore`

The client does not currently have:

- an embedded `WKWebView`
- a native browser automation/runtime layer
- an agent-facing tool surface bound to the workspace panel web session

## Chosen Approach

We will add an embedded `WKWebView` to the workspace panel and expose a native browser-runtime layer for agent actions.

Why this approach:

- the user and agent share the same visible browser surface
- the feature stays inside the existing right-side panel UX
- we avoid the split-brain problem of previewing in one place and automating another
- it allows progressive growth from simple viewing to real page interaction

## UX Behavior

The right panel becomes two-mode:

- `Files`
- `Web`

### Web Mode

The `Web` tab includes:

1. Toolbar
- back
- forward
- reload
- address field
- open/go action

2. Page area
- embedded `WKWebView`

3. Status
- page title
- loading/error state

The panel should remember the current mode while the project chat stays active.

## Architecture

### 1. WorkspaceWebViewModel

Owns browser session state:

- current URL
- address bar text
- current title
- loading state
- navigation availability (`canGoBack`, `canGoForward`)
- last interaction/snapshot status
- last error

This view model coordinates the visible browser state but does not directly own agent tool semantics.

### 2. WorkspaceWebView

A SwiftUI wrapper around `WKWebView` using a representable.

Responsibilities:

- create and host the `WKWebView`
- forward navigation updates into `WorkspaceWebViewModel`
- expose a stable bridge object/controller so higher-level code can run JS and issue navigation commands

It should stay thin and not absorb tool logic.

### 3. WorkspaceBrowserToolRuntime

An isolated runtime that targets the active embedded web view.

Responsibilities:

- open a page
- inspect page state
- run DOM queries
- inject JS for interaction
- capture screenshots
- translate browser results into agent-friendly responses

This runtime should live with the workspace panel/browser feature, not in `ChatScreenViewModel`.

## Agent Command Surface

The first browser command set should be:

- `open(url)`
- `read()`
- `click(selector)`
- `type(selector, text)`
- `scroll(x, y)`
- `scrollTo(selector)`
- `screenshot()`

### Selector Model

First version:

- primary: CSS selectors
- fallback: text lookup for common buttons/links

This keeps the model simple while still being useful for many pages.

## Read Semantics

`read()` should return enough page state for an agent to reason about what is on screen without dumping an entire huge DOM by default.

Recommended payload:

- current URL
- page title
- visible text snapshot
- a compact list of actionable elements when possible

Large pages should be truncated with explicit metadata that the result is partial.

## Click and Type Semantics

`click(selector)`:

- find element
- scroll it into view if needed
- dispatch click
- return success/failure plus updated page metadata

`type(selector, text)`:

- focus element
- clear value when appropriate
- insert text
- dispatch `input` and `change` events when needed

Failures must be explicit:

- selector not found
- element not interactable
- page not ready

## Screenshot Semantics

`screenshot()` should capture the currently visible page inside the embedded web view.

The result should be usable both for:

- user-facing visual inspection
- agent follow-up reasoning

## Local vs Remote Pages

The web view should support:

- normal HTTP/HTTPS URLs
- local project-served pages when available

If a page requires a local dev server, starting that server remains outside the browser runtime. The runtime only navigates to an address that is already reachable.

## Error Handling

Failure states should be visible and bounded:

- invalid URL
- navigation failure
- JS execution failure
- selector not found
- screenshot failure

The browser runtime must fail without crashing the workspace panel or chat surface.

## Testing

### Client tests

Add focused tests for:

- workspace panel renders `Files` and `Web` modes
- web mode owns `WorkspaceWebViewModel`
- browser runtime exposes the planned command surface
- workspace browser tool runtime is not coupled to `ChatScreenViewModel`

### Runtime tests

Where possible, add small deterministic tests for:

- selector lookup JS generation
- typed browser command request/response parsing
- URL normalization

## Scope Boundaries

Included in this feature:

- embedded web view in the workspace panel
- native browser runtime for the active page
- open/read/click/type/scroll/screenshot actions

Not included in this feature:

- multi-tab browsing
- browser persistence across app relaunch
- cookies/session management UI
- full devtools
- cross-window automation outside the embedded panel

## Recommendation

Implement this as a two-mode workspace panel with an embedded `WKWebView` plus a dedicated `WorkspaceBrowserToolRuntime` bound to that same live page.

This gives the cleanest mental model: the user sees the page the agent is operating on, and browser automation remains isolated from chat/session state.
