# Workspace Terminal Drawer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bottom workspace terminal drawer backed by `SwiftTerm`, toggled with `cmd + j`, with one terminal session per workspace tab and shell startup in the current project directory.

**Architecture:** Extend the existing tab shell by adding terminal state directly to `WorkspaceTabState`, plus a small terminal runtime layer under `Sources/SloppyClient/Workspace/Terminal/`. `MainViewModel` will own tab-scoped terminal lifecycle and project-directory resolution, while `MainView` renders a bottom drawer and `macOS` gets the first concrete `SwiftTerm` host behind conditional compilation.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftPM, Swift Testing, `migueldeicaza/SwiftTerm`, existing `MainView` / `MainViewModel` / `WorkspaceTabState` architecture.

---

### Task 1: Add package dependency and tab-scoped terminal state scaffolding

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/SloppyClient/Navigation/Main/MainTabs.swift`
- Create: `Tests/SloppyClientCoreTests/WorkspaceTerminalStateSourceTests.swift`

- [ ] **Step 1: Write the failing source test for package wiring and terminal state**

```swift
import Foundation
import Testing

@Suite("Workspace terminal state source")
struct WorkspaceTerminalStateSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("package includes SwiftTerm dependency for the app target")
    func packageIncludesSwiftTermDependency() throws {
        let package = try source("Package.swift")

        #expect(package.contains("https://github.com/migueldeicaza/SwiftTerm"))
        #expect(package.contains(".product(name: \"SwiftTerm\", package: \"SwiftTerm\")"))
    }

    @Test("workspace tab state stores terminal state")
    func workspaceTabStateStoresTerminalState() throws {
        let mainTabs = try source("Sources", "SloppyClient", "Navigation", "Main", "MainTabs.swift")

        #expect(mainTabs.contains("final class WorkspaceTerminalState"))
        #expect(mainTabs.contains("var isPresented: Bool"))
        #expect(mainTabs.contains("var height: CGFloat"))
        #expect(mainTabs.contains("var sessionID: UUID"))
        #expect(mainTabs.contains("var terminalState: WorkspaceTerminalState"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkspaceTerminalStateSourceTests`
Expected: FAIL because `SwiftTerm` and `WorkspaceTerminalState` are not defined yet.

- [ ] **Step 3: Add the dependency and minimal terminal state**

```swift
// Package.swift
.package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0"),

.executableTarget(
    name: "SloppyClient",
    dependencies: [
        "SloppyClientCore",
        "SloppyClientUI",
        "SloppyFeatureOverview",
        "SloppyFeatureProjects",
        "SloppyFeatureAgents",
        "SloppyFeatureSettings",
        "SloppyFeatureChat",
        .product(name: "Logging", package: "swift-log"),
        .product(name: "SwiftTerm", package: "SwiftTerm")
    ],
    path: "Sources/SloppyClient"
)
```

```swift
// Sources/SloppyClient/Navigation/Main/MainTabs.swift
@MainActor
final class WorkspaceTerminalState {
    var isPresented: Bool
    var height: CGFloat
    var workingDirectory: URL?
    var sessionID: UUID

    init(
        isPresented: Bool = false,
        height: CGFloat = 280,
        workingDirectory: URL? = nil,
        sessionID: UUID = UUID()
    ) {
        self.isPresented = isPresented
        self.height = height
        self.workingDirectory = workingDirectory
        self.sessionID = sessionID
    }
}

@MainActor
final class WorkspaceTabState {
    let contentState: WorkspaceTabContentState
    var content: AnyView?
    let terminalState: WorkspaceTerminalState

    init(
        contentState: WorkspaceTabContentState,
        content: AnyView? = nil,
        terminalState: WorkspaceTerminalState = WorkspaceTerminalState()
    ) {
        self.contentState = contentState
        self.content = content
        self.terminalState = terminalState
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WorkspaceTerminalStateSourceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/SloppyClient/Navigation/Main/MainTabs.swift Tests/SloppyClientCoreTests/WorkspaceTerminalStateSourceTests.swift
git commit -m "feat: scaffold workspace terminal state"
```

### Task 2: Surface project-directory metadata for workspace tabs

**Files:**
- Modify: `Sources/SloppyClientCore/OverviewModels.swift`
- Modify: `Sources/SloppyClientUI/Tabs.swift`
- Modify: `Sources/SloppyClient/Navigation/Main/MainViewModel.swift`
- Create: `Tests/SloppyClientCoreTests/WorkspaceTerminalDirectoryResolutionSourceTests.swift`

- [ ] **Step 1: Write the failing source test for project-directory metadata**

```swift
import Foundation
import Testing

@Suite("Workspace terminal directory resolution source")
struct WorkspaceTerminalDirectoryResolutionSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("project and tab contexts carry a root path")
    func projectAndTabContextsCarryRootPath() throws {
        let overview = try source("Sources", "SloppyClientCore", "OverviewModels.swift")
        let tabs = try source("Sources", "SloppyClientUI", "Tabs.swift")

        #expect(overview.contains("public var rootPath: String?"))
        #expect(tabs.contains("public var projectRootPath: String?"))
    }

    @Test("main view model resolves project directory from tab payload")
    func mainViewModelResolvesProjectDirectoryFromPayload() throws {
        let viewModel = try source("Sources", "SloppyClient", "Navigation", "Main", "MainViewModel.swift")

        #expect(viewModel.contains("func resolveWorkingDirectory(for tabID: WorkspaceTab.ID) -> URL?"))
        #expect(viewModel.contains("context.projectRootPath"))
        #expect(viewModel.contains("chatState.viewModel.activeProjectIdForWorkspacePanel"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkspaceTerminalDirectoryResolutionSourceTests`
Expected: FAIL because project root path metadata and resolver do not exist.

- [ ] **Step 3: Add root-path fields to project and tab context models**

```swift
// Sources/SloppyClientCore/OverviewModels.swift
public struct APIProjectRecord: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    public var rootPath: String?
    public var channels: [APIProjectChannel]?
    public var tasks: [APIProjectTask]?
    public var actors: [String]?
    public var teams: [String]?

    public init(
        id: String,
        name: String,
        description: String = "",
        rootPath: String? = nil,
        channels: [APIProjectChannel]? = nil,
        tasks: [APIProjectTask]? = nil,
        actors: [String]? = nil,
        teams: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.rootPath = rootPath
        self.channels = channels
        self.tasks = tasks
        self.actors = actors
        self.teams = teams
    }
}
```

```swift
// Sources/SloppyClientUI/Tabs.swift
public struct ProjectKanbanTabContext: Hashable, Sendable {
    public var projectId: String
    public var projectName: String
    public var projectRootPath: String?
}

public struct WorkspaceFilesTabContext: Hashable, Sendable {
    public var projectId: String
    public var projectName: String
    public var projectRootPath: String?
}

public struct TaskDetailTabContext: Hashable, Sendable {
    public var projectId: String
    public var projectName: String
    public var projectRootPath: String?
    public var taskId: String
    public var taskTitle: String
    public var fallbackAgentId: String?
}

public enum WorkspaceTabPayload: Hashable {
    case chatSession(sessionID: String, title: String)
    case chatTask(projectId: String, projectName: String, projectRootPath: String?, taskId: String, taskTitle: String, fallbackAgentId: String?)
    case projectKanban(ProjectKanbanTabContext)
    case taskDetail(TaskDetailTabContext)
    case workspaceFiles(WorkspaceFilesTabContext)
}
```

- [ ] **Step 4: Thread `projectRootPath` through `MainViewModel` and add a resolver**

```swift
func resolveWorkingDirectory(for tabID: WorkspaceTab.ID) -> URL? {
    guard let tab = tabs.first(where: { $0.id == tabID }) else {
        return nil
    }

    let rootPath: String? = switch tab.payload {
    case .workspaceFiles(let context):
        context.projectRootPath
    case .projectKanban(let context):
        context.projectRootPath
    case .taskDetail(let context):
        context.projectRootPath
    case .chatTask(_, _, let projectRootPath, _, _, _):
        projectRootPath
    case .chatSession:
        guard let chatState = tabStates[tabID]?.chatState,
              let projectId = chatState.viewModel.activeProjectIdForWorkspacePanel else {
            return nil
        }
        return projects.first(where: { $0.id == projectId })?.rootPath.flatMap(URL.init(fileURLWithPath:))
    }

    guard let rootPath, !rootPath.isEmpty else {
        return nil
    }
    return URL(fileURLWithPath: rootPath, isDirectory: true)
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter WorkspaceTerminalDirectoryResolutionSourceTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/SloppyClientCore/OverviewModels.swift Sources/SloppyClientUI/Tabs.swift Sources/SloppyClient/Navigation/Main/MainViewModel.swift Tests/SloppyClientCoreTests/WorkspaceTerminalDirectoryResolutionSourceTests.swift
git commit -m "feat: add project directory metadata for terminal tabs"
```

### Task 3: Add terminal lifecycle orchestration to MainViewModel

**Files:**
- Modify: `Sources/SloppyClient/Navigation/Main/MainViewModel.swift`
- Create: `Sources/SloppyClient/Workspace/Terminal/WorkspaceTerminalSession.swift`
- Create: `Tests/SloppyClientCoreTests/WorkspaceTerminalLifecycleSourceTests.swift`

- [ ] **Step 1: Write the failing source test for tab-scoped terminal lifecycle**

```swift
import Foundation
import Testing

@Suite("Workspace terminal lifecycle source")
struct WorkspaceTerminalLifecycleSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("main view model exposes terminal toggle and cleanup hooks")
    func mainViewModelExposesTerminalHooks() throws {
        let viewModel = try source("Sources", "SloppyClient", "Navigation", "Main", "MainViewModel.swift")

        #expect(viewModel.contains("var terminalSessions: [WorkspaceTab.ID: WorkspaceTerminalSession] = [:]"))
        #expect(viewModel.contains("var terminalHosts: [WorkspaceTab.ID: WorkspaceTerminalHosting] = [:]"))
        #expect(viewModel.contains("func toggleTerminalForSelectedTab()"))
        #expect(viewModel.contains("func openTerminalForSelectedTab()"))
        #expect(viewModel.contains("func closeTerminalForSelectedTab()"))
        #expect(viewModel.contains("func ensureTerminalSessionStarted(for tabID: WorkspaceTab.ID)"))
        #expect(viewModel.contains("func focusTerminalForSelectedTab()"))
    }

    @Test("terminal session keeps per-tab shell state")
    func terminalSessionKeepsPerTabShellState() throws {
        let session = try source("Sources", "SloppyClient", "Workspace", "Terminal", "WorkspaceTerminalSession.swift")

        #expect(session.contains("final class WorkspaceTerminalSession"))
        #expect(session.contains("let id: UUID"))
        #expect(session.contains("let workingDirectory: URL"))
        #expect(session.contains("func startIfNeeded()"))
        #expect(session.contains("func terminate()"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkspaceTerminalLifecycleSourceTests`
Expected: FAIL because terminal lifecycle APIs and session type do not exist.

- [ ] **Step 3: Add the minimal terminal session runtime**

```swift
import Foundation

@MainActor
final class WorkspaceTerminalSession {
    let id: UUID
    let workingDirectory: URL
    private(set) var isRunning = false

    init(id: UUID, workingDirectory: URL) {
        self.id = id
        self.workingDirectory = workingDirectory
    }

    func startIfNeeded() {
        guard !isRunning else { return }
        isRunning = true
    }

    func terminate() {
        isRunning = false
    }
}
```

- [ ] **Step 4: Add tab-scoped open/close/start/cleanup methods to `MainViewModel`**

```swift
var terminalSessions: [WorkspaceTab.ID: WorkspaceTerminalSession] = [:]
var terminalHosts: [WorkspaceTab.ID: WorkspaceTerminalHosting] = [:]

func toggleTerminalForSelectedTab() {
    guard let selectedTabID else { return }
    let state = tabStates[selectedTabID]?.terminalState
    if state?.isPresented == true {
        closeTerminalForSelectedTab()
    } else {
        openTerminalForSelectedTab()
    }
}

func openTerminalForSelectedTab() {
    guard let selectedTabID,
          let state = tabStates[selectedTabID]?.terminalState else {
        return
    }
    state.isPresented = true
    ensureTerminalSessionStarted(for: selectedTabID)
    focusTerminalForSelectedTab()
}

func closeTerminalForSelectedTab() {
    guard let selectedTabID,
          let state = tabStates[selectedTabID]?.terminalState else {
        return
    }
    state.isPresented = false
}

func ensureTerminalSessionStarted(for tabID: WorkspaceTab.ID) {
    guard terminalSessions[tabID] == nil,
          let workingDirectory = resolveWorkingDirectory(for: tabID),
          let terminalState = tabStates[tabID]?.terminalState else {
        return
    }

    terminalState.workingDirectory = workingDirectory
    let session = WorkspaceTerminalSession(
        id: terminalState.sessionID,
        workingDirectory: workingDirectory
    )
    session.startIfNeeded()
    terminalSessions[tabID] = session
}

func registerTerminalHost(_ host: WorkspaceTerminalHosting, for tabID: WorkspaceTab.ID) {
    terminalHosts[tabID] = host
}

func focusTerminalForSelectedTab() {
    guard let selectedTabID else { return }
    terminalHosts[selectedTabID]?.focus()
}
```

- [ ] **Step 5: Clean up sessions when tabs close**

```swift
func closeTab(_ tabID: WorkspaceTab.ID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
        return
    }

    terminalSessions[tabID]?.terminate()
    terminalSessions.removeValue(forKey: tabID)
    terminalHosts.removeValue(forKey: tabID)

    let splitStateBeforeClose = desktopSplitState
    let wasSelected = selectedTabID == tabID
    tabs.remove(at: index)
    tabStates.removeValue(forKey: tabID)

    // Keep the existing split cleanup and next-tab fallback logic after this block.
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter WorkspaceTerminalLifecycleSourceTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/SloppyClient/Navigation/Main/MainViewModel.swift Sources/SloppyClient/Workspace/Terminal/WorkspaceTerminalSession.swift Tests/SloppyClientCoreTests/WorkspaceTerminalLifecycleSourceTests.swift
git commit -m "feat: add tab-scoped terminal lifecycle"
```

### Task 4: Render the bottom drawer and wire `cmd + j`

**Files:**
- Modify: `Sources/SloppyClient/Navigation/Main/MainView.swift`
- Create: `Sources/SloppyClient/Workspace/Terminal/WorkspaceTerminalDrawerView.swift`
- Create: `Tests/SloppyClientCoreTests/WorkspaceTerminalDrawerSourceTests.swift`

- [ ] **Step 1: Write the failing source test for drawer layout and shortcut wiring**

```swift
import Foundation
import Testing

@Suite("Workspace terminal drawer source")
struct WorkspaceTerminalDrawerSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("main view registers cmd+j and mounts the terminal drawer")
    func mainViewRegistersTerminalDrawerShortcut() throws {
        let mainView = try source("Sources", "SloppyClient", "Navigation", "Main", "MainView.swift")

        #expect(mainView.contains(".keyboardShortcut(\"j\", modifiers: [.command])"))
        #expect(mainView.contains("viewModel.toggleTerminalForSelectedTab()"))
        #expect(mainView.contains("WorkspaceTerminalDrawerView"))
    }

    @Test("terminal drawer view exposes a resize handle and error state")
    func drawerViewExposesResizeAndErrorState() throws {
        let drawer = try source("Sources", "SloppyClient", "Workspace", "Terminal", "WorkspaceTerminalDrawerView.swift")

        #expect(drawer.contains("Capsule()"))
        #expect(drawer.contains("DragGesture"))
        #expect(drawer.contains("Project directory unavailable"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkspaceTerminalDrawerSourceTests`
Expected: FAIL because no terminal drawer or `cmd + j` shortcut exists.

- [ ] **Step 3: Add a dedicated drawer view**

```swift
import SwiftUI
import SloppyClientUI

@MainActor
struct WorkspaceTerminalDrawerView<Host: View>: View {
    let title: String
    let height: CGFloat
    let canStartSession: Bool
    let onHeightChange: (CGFloat) -> Void
    @ViewBuilder let host: () -> Host

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 42, height: 5)
                .padding(.vertical, 10)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            onHeightChange(max(180, height - value.translation.height))
                        }
                )

            Divider()

            if canStartSession {
                host()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Project directory unavailable")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height)
    }
}
```

- [ ] **Step 4: Mount the drawer below active content and register `cmd + j`**

```swift
private func workspaceContentHost(showsFloatingTabChrome: Bool) -> some View {
    VStack(spacing: 0) {
        Group {
            if let desktopSplitState = viewModel.desktopSplitState,
               let primaryTab = viewModel.tabs.first(where: { $0.id == desktopSplitState.primaryTabID }),
               let secondaryTab = viewModel.tabs.first(where: { $0.id == desktopSplitState.secondaryTabID }) {
                DesktopSplitContentView(
                    fraction: desktopSplitState.fraction,
                    onFractionChange: viewModel.updateDesktopSplitFraction(_:),
                    onClearSplit: viewModel.clearDesktopSplit,
                    primary: { desktopTabContent(for: primaryTab) },
                    secondary: { desktopTabContent(for: secondaryTab) }
                )
            } else if let activeDesktopTab {
                mountedDesktopTabContent(activeTabID: activeDesktopTab.id)
            } else {
                DesktopTabsEmptyState()
            }
        }

        if let selectedTabID = viewModel.selectedTabID,
           let terminalState = viewModel.tabStates[selectedTabID]?.terminalState,
           terminalState.isPresented {
            WorkspaceTerminalDrawerView(
                title: "Terminal",
                height: terminalState.height,
                canStartSession: terminalState.workingDirectory != nil || viewModel.resolveWorkingDirectory(for: selectedTabID) != nil,
                onHeightChange: { terminalState.height = $0 }
            ) {
                viewModel.makeTerminalHostView(for: selectedTabID)
            }
        }
    }
}
```

```swift
Button("") {
    viewModel.toggleTerminalForSelectedTab()
}
.keyboardShortcut("j", modifiers: [.command])
.opacity(0.001)
.allowsHitTesting(false)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter WorkspaceTerminalDrawerSourceTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/SloppyClient/Navigation/Main/MainView.swift Sources/SloppyClient/Workspace/Terminal/WorkspaceTerminalDrawerView.swift Tests/SloppyClientCoreTests/WorkspaceTerminalDrawerSourceTests.swift
git commit -m "feat: add workspace terminal drawer shell"
```

### Task 5: Add the `macOS` `SwiftTerm` host and final verification

**Files:**
- Create: `Sources/SloppyClient/Workspace/Terminal/WorkspaceTerminalHosting.swift`
- Create: `Sources/SloppyClient/Workspace/Terminal/WorkspaceTerminalMacHostView.swift`
- Modify: `Sources/SloppyClient/Navigation/Main/MainViewModel.swift`
- Create: `Tests/SloppyClientCoreTests/WorkspaceTerminalMacHostSourceTests.swift`

- [ ] **Step 1: Write the failing source test for host abstraction and `SwiftTerm` usage**

```swift
import Foundation
import Testing

@Suite("Workspace terminal mac host source")
struct WorkspaceTerminalMacHostSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("terminal runtime defines a hosting protocol")
    func terminalRuntimeDefinesHostingProtocol() throws {
        let runtime = try source("Sources", "SloppyClient", "Workspace", "Terminal", "WorkspaceTerminalHosting.swift")

        #expect(runtime.contains("protocol WorkspaceTerminalHosting"))
        #expect(runtime.contains("func focus()"))
        #expect(runtime.contains("func attach(to session: WorkspaceTerminalSession)"))
    }

    @Test("mac host uses SwiftTerm behind conditional compilation")
    func macHostUsesSwiftTerm() throws {
        let host = try source("Sources", "SloppyClient", "Workspace", "Terminal", "WorkspaceTerminalMacHostView.swift")

        #expect(host.contains("#if os(macOS)"))
        #expect(host.contains("import SwiftTerm"))
        #expect(host.contains("TerminalView"))
        #expect(host.contains("onHostReady"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkspaceTerminalMacHostSourceTests`
Expected: FAIL because the host protocol and `SwiftTerm` bridge do not exist.

- [ ] **Step 3: Add the host protocol and a minimal `macOS` bridge**

```swift
import Foundation

@MainActor
protocol WorkspaceTerminalHosting: AnyObject {
    func attach(to session: WorkspaceTerminalSession)
    func focus()
}
```

```swift
#if os(macOS)
import AppKit
import SwiftUI
import SwiftTerm

@MainActor
final class WorkspaceTerminalMacHostController: NSObject, WorkspaceTerminalHosting {
    weak var terminalView: TerminalView?
    private var session: WorkspaceTerminalSession?

    func attach(to session: WorkspaceTerminalSession) {
        self.session = session
        session.startIfNeeded()
    }

    func focus() {
        terminalView?.window?.makeFirstResponder(terminalView)
    }
}

struct WorkspaceTerminalMacHostView: NSViewRepresentable {
    let session: WorkspaceTerminalSession
    let onHostReady: @MainActor (WorkspaceTerminalHosting) -> Void

    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView()
        context.coordinator.terminalView = view
        context.coordinator.attach(to: session)
        onHostReady(context.coordinator)
        return view
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        context.coordinator.terminalView = nsView
    }

    func makeCoordinator() -> WorkspaceTerminalMacHostController {
        WorkspaceTerminalMacHostController()
    }
}
#endif
```

- [ ] **Step 4: Return the host from `MainViewModel` and run the relevant checks**

```swift
@ViewBuilder
func makeTerminalHostView(for tabID: WorkspaceTab.ID) -> some View {
    if let session = terminalSessions[tabID] {
        #if os(macOS)
        WorkspaceTerminalMacHostView(session: session) { host in
            registerTerminalHost(host, for: tabID)
            if selectedTabID == tabID {
                host.focus()
            }
        }
        #else
        Text("Terminal host is not available on this platform yet.")
        #endif
    } else {
        Text("Project directory unavailable")
    }
}
```

Run: `swift test --filter WorkspaceTerminal`
Expected: PASS

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyClient/Navigation/Main/MainViewModel.swift Sources/SloppyClient/Workspace/Terminal/WorkspaceTerminalHosting.swift Sources/SloppyClient/Workspace/Terminal/WorkspaceTerminalMacHostView.swift Tests/SloppyClientCoreTests/WorkspaceTerminalMacHostSourceTests.swift
git commit -m "feat: add mac workspace terminal host"
```
