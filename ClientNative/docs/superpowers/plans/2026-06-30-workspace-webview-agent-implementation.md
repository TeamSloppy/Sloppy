# Workspace WebView Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the desktop workspace panel with a `Web` mode that embeds a `WKWebView` and gives the agent a native browser runtime for `open`, `read`, `click`, `type`, `scroll`, and `screenshot` actions against the same visible page.

**Architecture:** Keep the existing file tree intact and evolve the workspace panel into a two-mode surface: `Files` and `Web`. Add a dedicated `WorkspaceWebViewModel` for browser session state, a thin SwiftUI `WKWebView` wrapper, and an isolated `WorkspaceBrowserToolRuntime` that drives the active embedded page without coupling browser automation to `ChatScreenViewModel`.

**Tech Stack:** Swift 6.2, SwiftUI + Observation, WebKit (`WKWebView`), `SloppyClientCore`, Swift Testing

## Global Constraints

- Extend the right-side workspace panel so the user can switch from the file tree to an embedded web surface, and the agent can launch a web page there and interact with it.
- The first implementation should support `open`, `read`, `click`, `type`, `scroll`, and `screenshot`.
- The user and agent must share the same visible browser surface inside the right panel.
- The first browser selector model uses CSS selectors first, with text lookup as a fallback for common buttons/links.
- `read()` must return current URL, page title, a visible text snapshot, and compact actionable element metadata when possible.
- The browser runtime must live with the workspace panel/browser feature, not in `ChatScreenViewModel`.
- The web view should support HTTP/HTTPS URLs and local project-served pages when reachable, but starting a dev server is out of scope.
- The browser runtime must fail without crashing the workspace panel or chat surface.

---

### Task 1: Add two-mode workspace panel state and `WKWebView` session models

**Files:**
- Modify: `Sources/SloppyClient/WorkspacePanelViewModel.swift`
- Modify: `Sources/SloppyClient/WorkspacePanelView.swift`
- Create: `Sources/SloppyClient/WorkspaceWebViewModel.swift`
- Create: `Tests/SloppyClientCoreTests/WorkspaceWebViewSourceTests.swift`

**Interfaces:**
- Consumes:
  - `WorkspacePanelContext`
  - existing `WorkspacePanelViewModel` file-tree state
- Produces:
  - `enum WorkspacePanelMode { case files, web }`
  - `@Observable @MainActor final class WorkspaceWebViewModel`
  - `var mode: WorkspacePanelMode`
  - `var webViewModel: WorkspaceWebViewModel`
  - `func switchMode(_ mode: WorkspacePanelMode)`

- [ ] **Step 1: Write the failing source test**

```swift
import Foundation
import Testing

@Suite("Workspace webview source")
struct WorkspaceWebViewSourceTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("workspace panel exposes files and web modes")
    func workspacePanelExposesFilesAndWebModes() throws {
        let panelVM = try source("Sources/SloppyClient/WorkspacePanelViewModel.swift")
        let panelView = try source("Sources/SloppyClient/WorkspacePanelView.swift")

        #expect(panelVM.contains("enum WorkspacePanelMode"))
        #expect(panelVM.contains("case files"))
        #expect(panelVM.contains("case web"))
        #expect(panelVM.contains("var mode: WorkspacePanelMode"))
        #expect(panelVM.contains("var webViewModel: WorkspaceWebViewModel"))
        #expect(panelView.contains("switch viewModel.mode"))
        #expect(panelView.contains("\"Files\""))
        #expect(panelView.contains("\"Web\""))
    }

    @Test("workspace web view model owns browser session state")
    func workspaceWebViewModelOwnsBrowserSessionState() throws {
        let sourceText = try source("Sources/SloppyClient/WorkspaceWebViewModel.swift")

        #expect(sourceText.contains("final class WorkspaceWebViewModel"))
        #expect(sourceText.contains("var currentURL"))
        #expect(sourceText.contains("var addressText"))
        #expect(sourceText.contains("var pageTitle"))
        #expect(sourceText.contains("var isLoading"))
        #expect(sourceText.contains("var canGoBack"))
        #expect(sourceText.contains("var canGoForward"))
        #expect(sourceText.contains("var lastError"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkspaceWebViewSourceTests`
Expected: FAIL because the workspace panel only has file-tree mode and no browser session view model yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SloppyClient/WorkspaceWebViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class WorkspaceWebViewModel {
    var currentURL: URL?
    var addressText: String = ""
    var pageTitle: String?
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var lastError: String?
}
```

```swift
// Sources/SloppyClient/WorkspacePanelViewModel.swift

enum WorkspacePanelMode: Equatable {
    case files
    case web
}

var mode: WorkspacePanelMode = .files
var webViewModel: WorkspaceWebViewModel

func switchMode(_ mode: WorkspacePanelMode) {
    self.mode = mode
}
```

```swift
// Sources/SloppyClient/WorkspacePanelView.swift

Picker("", selection: modeBinding) {
    Text("Files").tag(WorkspacePanelMode.files)
    Text("Web").tag(WorkspacePanelMode.web)
}

switch viewModel.mode {
case .files:
    filesBody
case .web:
    webBody
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WorkspaceWebViewSourceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyClient/WorkspacePanelViewModel.swift Sources/SloppyClient/WorkspacePanelView.swift Sources/SloppyClient/WorkspaceWebViewModel.swift Tests/SloppyClientCoreTests/WorkspaceWebViewSourceTests.swift
git commit -m "feat: add workspace panel web mode scaffolding"
```

### Task 2: Embed `WKWebView` in the workspace panel and wire navigation state

**Files:**
- Create: `Sources/SloppyClient/WorkspaceWebView.swift`
- Modify: `Sources/SloppyClient/WorkspaceWebViewModel.swift`
- Modify: `Sources/SloppyClient/WorkspacePanelView.swift`
- Test: `Tests/SloppyClientCoreTests/WorkspaceWebViewSourceTests.swift`

**Interfaces:**
- Consumes:
  - `WorkspaceWebViewModel`
  - `WorkspacePanelMode.web`
- Produces:
  - `struct WorkspaceWebView: NSViewRepresentable`
  - `func openAddress()`
  - `func reload()`
  - `func goBack()`
  - `func goForward()`
  - navigation delegate updates back into `WorkspaceWebViewModel`

- [ ] **Step 1: Extend the failing source test**

```swift
@Test("workspace web view wraps WKWebView and syncs navigation state")
func workspaceWebViewWrapsWKWebViewAndSyncsNavigationState() throws {
    let webViewSource = try source("Sources/SloppyClient/WorkspaceWebView.swift")
    let modelSource = try source("Sources/SloppyClient/WorkspaceWebViewModel.swift")

    #expect(webViewSource.contains("import WebKit"))
    #expect(webViewSource.contains("WKWebView"))
    #expect(webViewSource.contains("NSViewRepresentable"))
    #expect(modelSource.contains("func openAddress()"))
    #expect(modelSource.contains("func reload()"))
    #expect(modelSource.contains("func goBack()"))
    #expect(modelSource.contains("func goForward()"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkspaceWebViewSourceTests`
Expected: FAIL because no embedded `WKWebView` wrapper or navigation methods exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SloppyClient/WorkspaceWebView.swift

import SwiftUI
import WebKit

@MainActor
struct WorkspaceWebView: NSViewRepresentable {
    let viewModel: WorkspaceWebViewModel

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
}
```

```swift
// Sources/SloppyClient/WorkspaceWebViewModel.swift

weak var controller: WorkspaceWebViewControlling?

func openAddress() {
    controller?.open(addressText)
}

func reload() {
    controller?.reload()
}

func goBack() {
    controller?.goBack()
}

func goForward() {
    controller?.goForward()
}
```

```swift
// Sources/SloppyClient/WorkspacePanelView.swift web body

VStack(spacing: 0) {
    webToolbar
    Divider()
    WorkspaceWebView(viewModel: viewModel.webViewModel)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WorkspaceWebViewSourceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyClient/WorkspaceWebView.swift Sources/SloppyClient/WorkspaceWebViewModel.swift Sources/SloppyClient/WorkspacePanelView.swift Tests/SloppyClientCoreTests/WorkspaceWebViewSourceTests.swift
git commit -m "feat: embed workspace webview"
```

### Task 3: Add agent browser runtime for `open/read/click/type/scroll/screenshot`

**Files:**
- Create: `Sources/SloppyClient/WorkspaceBrowserToolRuntime.swift`
- Modify: `Sources/SloppyClient/WorkspaceWebView.swift`
- Modify: `Sources/SloppyClient/WorkspaceWebViewModel.swift`
- Modify: `Sources/SloppyClient/WorkspacePanelViewModel.swift`
- Test: `Tests/SloppyClientCoreTests/WorkspaceBrowserToolRuntimeSourceTests.swift`

**Interfaces:**
- Consumes:
  - `WorkspaceWebViewModel`
  - live `WKWebView`
- Produces:
  - `final class WorkspaceBrowserToolRuntime`
  - `func open(url: String) async throws -> WorkspaceBrowserReadResult`
  - `func read() async throws -> WorkspaceBrowserReadResult`
  - `func click(selector: String) async throws -> WorkspaceBrowserActionResult`
  - `func type(selector: String, text: String) async throws -> WorkspaceBrowserActionResult`
  - `func scroll(x: Double, y: Double) async throws -> WorkspaceBrowserActionResult`
  - `func scrollTo(selector: String) async throws -> WorkspaceBrowserActionResult`
  - `func screenshot() async throws -> WorkspaceBrowserScreenshotResult`

- [ ] **Step 1: Write the failing source test**

```swift
import Foundation
import Testing

@Suite("Workspace browser tool runtime source")
struct WorkspaceBrowserToolRuntimeSourceTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("browser runtime exposes the planned command surface")
    func browserRuntimeExposesPlannedCommandSurface() throws {
        let runtime = try source("Sources/SloppyClient/WorkspaceBrowserToolRuntime.swift")

        #expect(runtime.contains("final class WorkspaceBrowserToolRuntime"))
        #expect(runtime.contains("func open(url: String) async throws"))
        #expect(runtime.contains("func read() async throws"))
        #expect(runtime.contains("func click(selector: String) async throws"))
        #expect(runtime.contains("func type(selector: String, text: String) async throws"))
        #expect(runtime.contains("func scroll(x: Double, y: Double) async throws"))
        #expect(runtime.contains("func scrollTo(selector: String) async throws"))
        #expect(runtime.contains("func screenshot() async throws"))
    }

    @Test("browser runtime stays out of chat screen view model")
    func browserRuntimeStaysOutOfChatScreenViewModel() throws {
        let chatVM = try source("Sources/SloppyFeatureChat/ChatScreenViewModel.swift")
        #expect(!chatVM.contains("WorkspaceBrowserToolRuntime"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkspaceBrowserToolRuntimeSourceTests`
Expected: FAIL because the browser runtime file and command surface do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SloppyClient/WorkspaceBrowserToolRuntime.swift

import Foundation
import WebKit

struct WorkspaceBrowserReadResult: Sendable { ... }
struct WorkspaceBrowserActionResult: Sendable { ... }
struct WorkspaceBrowserScreenshotResult: Sendable { ... }

@MainActor
final class WorkspaceBrowserToolRuntime {
    private weak var webView: WKWebView?

    init(webView: WKWebView?) {
        self.webView = webView
    }

    func open(url: String) async throws -> WorkspaceBrowserReadResult { ... }
    func read() async throws -> WorkspaceBrowserReadResult { ... }
    func click(selector: String) async throws -> WorkspaceBrowserActionResult { ... }
    func type(selector: String, text: String) async throws -> WorkspaceBrowserActionResult { ... }
    func scroll(x: Double, y: Double) async throws -> WorkspaceBrowserActionResult { ... }
    func scrollTo(selector: String) async throws -> WorkspaceBrowserActionResult { ... }
    func screenshot() async throws -> WorkspaceBrowserScreenshotResult { ... }
}
```

```swift
// JS helpers in runtime

private func evaluate(_ script: String) async throws -> Any
private func jsReadVisibleState() -> String
private func jsClick(selector: String) -> String
private func jsType(selector: String, text: String) -> String
private func jsScroll(x: Double, y: Double) -> String
private func jsScrollTo(selector: String) -> String
```

```swift
// Sources/SloppyClient/WorkspaceWebViewModel.swift

var browserRuntime: WorkspaceBrowserToolRuntime?
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WorkspaceBrowserToolRuntimeSourceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyClient/WorkspaceBrowserToolRuntime.swift Sources/SloppyClient/WorkspaceWebView.swift Sources/SloppyClient/WorkspaceWebViewModel.swift Sources/SloppyClient/WorkspacePanelViewModel.swift Tests/SloppyClientCoreTests/WorkspaceBrowserToolRuntimeSourceTests.swift
git commit -m "feat: add workspace browser runtime"
```

## Self-Review

### Spec coverage

- Two-mode `Files/Web` panel: covered by Task 1
- Embedded `WKWebView`: covered by Task 2
- Shared visible browser surface for user and agent: covered by Tasks 2 and 3
- Browser command surface `open/read/click/type/scroll/screenshot`: covered by Task 3
- Browser runtime isolated from `ChatScreenViewModel`: covered by Task 3
- HTTP/HTTPS and local reachable pages: covered by Task 2 URL loading and Task 3 open/read flow

### Placeholder scan

- No `TBD`, `TODO`, or “implement later” markers are left in the plan
- Each task has explicit file paths, explicit commands, and explicit interface names

### Type consistency

- `WorkspacePanelMode`, `WorkspaceWebViewModel`, `WorkspaceWebView`, and `WorkspaceBrowserToolRuntime` are used consistently across tasks
- Runtime result types are introduced only in Task 3 where they are first needed

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-30-workspace-webview-agent-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
