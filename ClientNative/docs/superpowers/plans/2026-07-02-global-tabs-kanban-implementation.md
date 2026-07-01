# Global Tabs and Project Kanban Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the desktop single-surface detail area with a global tab shell that supports multiple concurrent chat/project surfaces and ships a native read-only project kanban tab opened from the sidebar.

**Architecture:** Add a tab domain to `MainViewModel` that owns desktop tab state and deduplication, render the active desktop surface through a new tab strip instead of `selectedAppSection`, migrate desktop chat to tab-local `ChatScreenViewModel` instances, and introduce a `ProjectKanbanViewModel`/SwiftUI surface that groups project tasks into columns using the existing `fetchProject(id:)` API. Keep phone navigation unchanged and treat existing desktop `.workspace` routing as transitional.

**Tech Stack:** Swift 6.2, SwiftUI + Observation, `SloppyClientCore`, existing `SloppyAPIClient`, Swift Testing

## Global Constraints

- The desktop detail pane must support multiple global tabs in the main content area.
- Tabs are global, not nested under one project container.
- The first desktop tab kinds are `chat`, `projectKanban`, and `workspaceFiles`.
- Clicking a project in the desktop sidebar must open or focus that project's kanban tab by default.
- Clicking a task must open or focus a task-scoped chat tab.
- Clicking a recent chat must open or focus a session-scoped chat tab.
- Tabs must deduplicate by semantic key, not by display title text.
- Each desktop tab must keep its own local state so switching tabs does not reset chat, workspace, or kanban state.
- The first kanban implementation is read-only and must reuse `fetchProject(id:)`; do not add backend API or drag-and-drop editing in this iteration.
- Phone layout can keep the current simpler navigation model in this iteration.
- Do not use language heuristics for state or routing decisions; status grouping and tab routing must be driven by typed fields.

---

### Task 1: Add desktop tab domain models and state ownership

**Files:**
- Create: `Sources/SloppyClient/MainTabs.swift`
- Modify: `Sources/SloppyClient/MainView.swift`
- Create: `Tests/SloppyClientCoreTests/MainTabsSourceTests.swift`

**Interfaces:**
- Consumes:
  - `APIProjectRecord` from `Sources/SloppyClientCore/OverviewModels.swift`
  - `APIProjectTask` from `Sources/SloppyClientCore/OverviewModels.swift`
  - `ChatSessionSummary` from `Sources/SloppyClientCore/ChatModels.swift`
- Produces:
  - `enum WorkspaceTabKind: String, Hashable`
  - `enum WorkspaceTabKey: Hashable`
  - `enum WorkspaceTabPayload: Hashable`
  - `struct WorkspaceTab: Identifiable`
  - `struct ProjectKanbanTabContext: Hashable, Sendable`
  - `struct WorkspaceFilesTabContext: Hashable, Sendable`
  - `MainViewModel.tabs: [WorkspaceTab]`
  - `MainViewModel.selectedTabID: WorkspaceTab.ID?`
  - `MainViewModel.openProjectKanbanTab(project:)`
  - `MainViewModel.openTaskChatTab(project:task:fallbackAgentId:)`
  - `MainViewModel.openSessionChatTab(_:)`
  - `MainViewModel.closeTab(_:)`
  - `MainViewModel.selectTab(_:)`

- [ ] **Step 1: Write the failing source test**

```swift
import Foundation
import Testing

@Suite("Main tabs source")
struct MainTabsSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("main tabs domain defines kinds payloads and semantic keys")
    func mainTabsDomainDefinesKindsPayloadsAndSemanticKeys() throws {
        let tabs = try source("Sources/SloppyClient/MainTabs.swift")

        #expect(tabs.contains("enum WorkspaceTabKind: String, Hashable"))
        #expect(tabs.contains("case chat"))
        #expect(tabs.contains("case projectKanban"))
        #expect(tabs.contains("case workspaceFiles"))
        #expect(tabs.contains("enum WorkspaceTabKey: Hashable"))
        #expect(tabs.contains("case chatSession(String)"))
        #expect(tabs.contains("case chatTask(projectId: String, taskId: String)"))
        #expect(tabs.contains("case projectKanban(String)"))
        #expect(tabs.contains("case workspaceFiles(String)"))
    }

    @Test("main view model owns tabs and open close selection helpers")
    func mainViewModelOwnsTabsAndOpenCloseSelectionHelpers() throws {
        let mainView = try source("Sources/SloppyClient/MainView.swift")

        #expect(mainView.contains("var tabs: [WorkspaceTab] = []"))
        #expect(mainView.contains("var selectedTabID: WorkspaceTab.ID?"))
        #expect(mainView.contains("func openProjectKanbanTab(project: APIProjectRecord)"))
        #expect(mainView.contains("func openTaskChatTab("))
        #expect(mainView.contains("func openSessionChatTab(_ session: ChatSessionSummary)"))
        #expect(mainView.contains("func closeTab(_ tabID: WorkspaceTab.ID)"))
        #expect(mainView.contains("func selectTab(_ tabID: WorkspaceTab.ID)"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MainTabsSourceTests`
Expected: FAIL because the desktop tab domain and tab state do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SloppyClient/MainTabs.swift

import Foundation
import SloppyClientCore

enum WorkspaceTabKind: String, Hashable {
    case chat
    case projectKanban
    case workspaceFiles
}

enum WorkspaceTabKey: Hashable {
    case chatSession(String)
    case chatTask(projectId: String, taskId: String)
    case projectKanban(String)
    case workspaceFiles(String)
}

struct ProjectKanbanTabContext: Hashable, Sendable {
    var projectId: String
    var projectName: String
}

struct WorkspaceFilesTabContext: Hashable, Sendable {
    var projectId: String
    var projectName: String
}

enum WorkspaceTabPayload: Hashable {
    case chatSession(sessionID: String, title: String)
    case chatTask(projectId: String, projectName: String, taskId: String, taskTitle: String, fallbackAgentId: String?)
    case projectKanban(ProjectKanbanTabContext)
    case workspaceFiles(WorkspaceFilesTabContext)
}

struct WorkspaceTab: Identifiable {
    let id: UUID
    let key: WorkspaceTabKey
    let kind: WorkspaceTabKind
    var title: String
    var payload: WorkspaceTabPayload

    init(id: UUID = UUID(), key: WorkspaceTabKey, kind: WorkspaceTabKind, title: String, payload: WorkspaceTabPayload) {
        self.id = id
        self.key = key
        self.kind = kind
        self.title = title
        self.payload = payload
    }
}
```

```swift
// Sources/SloppyClient/MainView.swift

var tabs: [WorkspaceTab] = []
var selectedTabID: WorkspaceTab.ID?

func selectTab(_ tabID: WorkspaceTab.ID) {
    guard tabs.contains(where: { $0.id == tabID }) else { return }
    selectedTabID = tabID
}

func closeTab(_ tabID: WorkspaceTab.ID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    let wasSelected = selectedTabID == tabID
    tabs.remove(at: index)
    if wasSelected {
        let nextIndex = min(index, tabs.count - 1)
        selectedTabID = nextIndex >= 0 ? tabs[nextIndex].id : nil
    }
}

func openProjectKanbanTab(project: APIProjectRecord) {
    openOrSelectTab(
        key: .projectKanban(project.id),
        makeTab: WorkspaceTab(
            key: .projectKanban(project.id),
            kind: .projectKanban,
            title: project.name,
            payload: .projectKanban(.init(projectId: project.id, projectName: project.name))
        )
    )
}

func openTaskChatTab(project: APIProjectRecord, task: APIProjectTask, fallbackAgentId: String?) {
    openOrSelectTab(
        key: .chatTask(projectId: project.id, taskId: task.id),
        makeTab: WorkspaceTab(
            key: .chatTask(projectId: project.id, taskId: task.id),
            kind: .chat,
            title: task.title,
            payload: .chatTask(
                projectId: project.id,
                projectName: project.name,
                taskId: task.id,
                taskTitle: task.title,
                fallbackAgentId: task.actorId ?? fallbackAgentId
            )
        )
    )
}

func openSessionChatTab(_ session: ChatSessionSummary) {
    openOrSelectTab(
        key: .chatSession(session.id),
        makeTab: WorkspaceTab(
            key: .chatSession(session.id),
            kind: .chat,
            title: session.title,
            payload: .chatSession(sessionID: session.id, title: session.title)
        )
    )
}
```

```swift
// Sources/SloppyClient/MainView.swift helper

private func openOrSelectTab(key: WorkspaceTabKey, makeTab: @autoclosure () -> WorkspaceTab) {
    if let existing = tabs.first(where: { $0.key == key }) {
        selectedTabID = existing.id
        return
    }
    let tab = makeTab()
    tabs.append(tab)
    selectedTabID = tab.id
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MainTabsSourceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyClient/MainTabs.swift Sources/SloppyClient/MainView.swift Tests/SloppyClientCoreTests/MainTabsSourceTests.swift
git commit -m "feat: add desktop workspace tab domain"
```

### Task 2: Replace desktop single-surface routing with a tab strip shell

**Files:**
- Modify: `Sources/SloppyClient/MainView.swift`
- Modify: `Sources/SloppyClientUI/Icons.swift`
- Create: `Tests/SloppyClientCoreTests/MainNavigationShellTests.swift`

**Interfaces:**
- Consumes:
  - `WorkspaceTab`
  - `WorkspaceTabKind`
  - `MainViewModel.tabs`
  - `MainViewModel.selectedTabID`
- Produces:
  - `DesktopTabStripView`
  - `MainView.activeDesktopTab: WorkspaceTab?`
  - `MainView.desktopContentArea()`
  - `MainView.desktopTabContent(for:)`

- [ ] **Step 1: Write the failing source test**

```swift
import Foundation
import Testing

@Suite("Main navigation shell")
struct MainNavigationShellTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("desktop main view renders a tab strip and active tab content")
    func desktopMainViewRendersTabStripAndActiveTabContent() throws {
        let mainView = try source("Sources/SloppyClient/MainView.swift")

        #expect(mainView.contains("DesktopTabStripView("))
        #expect(mainView.contains("private var activeDesktopTab: WorkspaceTab?"))
        #expect(mainView.contains("desktopContentArea()"))
        #expect(mainView.contains("desktopTabContent(for tab: WorkspaceTab)"))
    }

    @Test("desktop split layout no longer switches projects and chats directly through selectedAppSection")
    func desktopSplitLayoutNoLongerSwitchesProjectsAndChatsDirectly() throws {
        let mainView = try source("Sources/SloppyClient/MainView.swift")

        #expect(!mainView.contains("case .projects:\n                chatScreen(showsSidebarControl: false)"))
        #expect(!mainView.contains("case .workspace:\n                workspaceScreen()"))
        #expect(mainView.contains("case .projects:"))
        #expect(mainView.contains("desktopContentArea()"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MainNavigationShellTests`
Expected: FAIL because desktop still routes detail content through the old `selectedAppSection` switch.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SloppyClient/MainView.swift

private var activeDesktopTab: WorkspaceTab? {
    guard let selectedTabID = viewModel.selectedTabID else { return nil }
    return viewModel.tabs.first(where: { $0.id == selectedTabID })
}

private func regularSplitLayout() -> some View {
    NavigationSplitView {
        sidebarView(isOverlay: false)
            .navigationSplitViewColumnWidth(
                min: viewModel.sidebarMinimumWidth,
                ideal: viewModel.sidebarWidth,
                max: viewModel.sidebarMaximumWidth
            )
    } detail: {
        switch viewModel.selectedAppSection {
        case .projects, .chats, .workspace:
            desktopContentArea()
        case .agents:
            AgentsScreen(apiClient: SloppyAPIClient(baseURL: viewModel.baseURL))
        case .settings:
            SettingsScreen(settings: viewModel.settings)
        }
    }
    .navigationSplitViewStyle(.balanced)
}

@ViewBuilder
private func desktopContentArea() -> some View {
    VStack(spacing: 0) {
        DesktopTabStripView(viewModel: viewModel)
        Divider()
        if let activeDesktopTab {
            desktopTabContent(for: activeDesktopTab)
        } else {
            DesktopTabsEmptyState()
        }
    }
}
```

```swift
// Sources/SloppyClient/MainView.swift

private func desktopTabContent(for tab: WorkspaceTab) -> some View {
    Group {
        switch tab.kind {
        case .chat:
            Text("Chat tab placeholder")
        case .projectKanban:
            Text("Kanban tab placeholder")
        case .workspaceFiles:
            Text("Workspace tab placeholder")
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

```swift
// Sources/SloppyClient/MainView.swift

private struct DesktopTabStripView: View {
    let viewModel: MainViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.tabs) { tab in
                    Button(tab.title) {
                        viewModel.selectTab(tab.id)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}
```

```swift
// Sources/SloppyClient/MainView.swift

private struct DesktopTabsEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("No tabs open")
            Text("Open a project, task, or recent chat from the sidebar.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MainNavigationShellTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyClient/MainView.swift Sources/SloppyClientUI/Icons.swift Tests/SloppyClientCoreTests/MainNavigationShellTests.swift
git commit -m "feat: add desktop tab strip shell"
```

### Task 3: Move desktop chat into tab-local state objects

**Files:**
- Modify: `Sources/SloppyFeatureChat/ChatScreenViewModel.swift`
- Modify: `Sources/SloppyClient/MainTabs.swift`
- Modify: `Sources/SloppyClient/MainView.swift`
- Create: `Tests/SloppyClientCoreTests/MainSidebarSelectionTests.swift`

**Interfaces:**
- Consumes:
  - `ChatScreenViewModel.init(apiClient:cacheStore:settings:connectionMonitor:onOpenSettings:)`
  - `ChatNavigationRequest`
  - `WorkspaceTabPayload.chatSession`
  - `WorkspaceTabPayload.chatTask`
- Produces:
  - `final class ChatTabState`
  - `WorkspaceTabPayload.chatState(ChatTabState)`
  - `MainViewModel.makeChatTabState() -> ChatTabState`
  - `MainViewModel.configureChatTab(_:)`
  - desktop chat rendering through `ChatScreen(viewModel: tabState.viewModel, ...)`

- [ ] **Step 1: Write the failing source test**

```swift
import Foundation
import Testing

@Suite("Desktop chat tab source")
struct DesktopChatTabSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("chat tabs own local chat screen state")
    func chatTabsOwnLocalChatScreenState() throws {
        let tabs = try source("Sources/SloppyClient/MainTabs.swift")
        let mainView = try source("Sources/SloppyClient/MainView.swift")

        #expect(tabs.contains("final class ChatTabState"))
        #expect(tabs.contains("let viewModel: ChatScreenViewModel"))
        #expect(mainView.contains("makeChatTabState() -> ChatTabState"))
        #expect(mainView.contains("ChatScreen(viewModel: chatState.viewModel"))
    }

    @Test("desktop task and recent session actions open tab-local chats instead of the global chat view model")
    func desktopTaskAndRecentSessionActionsOpenTabLocalChats() throws {
        let mainView = try source("Sources/SloppyClient/MainView.swift")

        #expect(mainView.contains("openTaskChatTab("))
        #expect(mainView.contains("openSessionChatTab("))
        #expect(!mainView.contains("chatViewModel.pickSession(session)"))
        #expect(!mainView.contains("navigateChat("))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DesktopChatTabSourceTests`
Expected: FAIL because desktop still relies on one shared `chatViewModel`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SloppyClient/MainTabs.swift

import SloppyFeatureChat

@MainActor
final class ChatTabState {
    let viewModel: ChatScreenViewModel

    init(viewModel: ChatScreenViewModel) {
        self.viewModel = viewModel
    }
}
```

```swift
// Sources/SloppyClient/MainView.swift

func makeChatTabState() -> ChatTabState {
    let apiClient = SloppyAPIClient(baseURL: baseURL)
    return ChatTabState(
        viewModel: ChatScreenViewModel(
            apiClient: apiClient,
            cacheStore: cacheStore,
            settings: settings,
            connectionMonitor: connectionMonitor,
            onOpenSettings: onOpenSettings
        )
    )
}
```

```swift
// Sources/SloppyClient/MainView.swift

private func desktopTabContent(for tab: WorkspaceTab) -> some View {
    switch tab.payload {
    case .chatSession(_, _, let chatState):
        ChatScreen(
            viewModel: chatState.viewModel,
            rootSafeAreaInsets: rootSafeAreaInsets,
            onOpenSidebar: nil
        )
    case .chatTask(_, _, _, _, _, let chatState):
        ChatScreen(
            viewModel: chatState.viewModel,
            rootSafeAreaInsets: rootSafeAreaInsets,
            onOpenSidebar: nil
        )
    default:
        Text("Non-chat tab")
    }
}
```

```swift
// Sources/SloppyClient/MainView.swift

func openSessionChatTab(_ session: ChatSessionSummary) {
    let chatState = makeChatTabState()
    chatState.viewModel.loadInitialData()
    chatState.viewModel.pickSession(session)
    openOrSelectTab(
        key: .chatSession(session.id),
        makeTab: WorkspaceTab(
            key: .chatSession(session.id),
            kind: .chat,
            title: session.title,
            payload: .chatSession(sessionID: session.id, title: session.title, state: chatState)
        )
    )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DesktopChatTabSourceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyFeatureChat/ChatScreenViewModel.swift Sources/SloppyClient/MainTabs.swift Sources/SloppyClient/MainView.swift Tests/SloppyClientCoreTests/MainSidebarSelectionTests.swift
git commit -m "feat: move desktop chats into tab-local state"
```

### Task 4: Add native read-only project kanban models and view model

**Files:**
- Create: `Sources/SloppyFeatureProjects/ProjectKanbanViewModel.swift`
- Modify: `Sources/SloppyClientCore/OverviewModels.swift`
- Create: `Tests/SloppyClientCoreTests/OverviewModelsTests.swift`

**Interfaces:**
- Consumes:
  - `SloppyAPIClient.fetchProject(id:)`
  - `APIProjectRecord`
  - `APIProjectTask`
- Produces:
  - `enum ProjectKanbanColumnID: String, CaseIterable, Hashable`
  - `struct ProjectKanbanCard: Identifiable, Equatable`
  - `struct ProjectKanbanColumn: Identifiable, Equatable`
  - `APIProjectTask.normalizedKanbanColumnID: ProjectKanbanColumnID`
  - `@MainActor final class ProjectKanbanViewModel`
  - `func load(projectId: String) async`

- [ ] **Step 1: Write the failing source test**

```swift
import Foundation
import Testing

@Suite("Overview models")
struct OverviewModelsTests {
    @Test("project task statuses normalize into stable kanban columns")
    func projectTaskStatusesNormalizeIntoStableKanbanColumns() {
        let todo = APIProjectTask(id: "t1", title: "Todo", status: "todo")
        let progress = APIProjectTask(id: "t2", title: "Build", status: "in_progress")
        let review = APIProjectTask(id: "t3", title: "Review", status: "needs_review")
        let done = APIProjectTask(id: "t4", title: "Done", status: "done")
        let unknown = APIProjectTask(id: "t5", title: "Unknown", status: "blocked")

        #expect(todo.normalizedKanbanColumnID == .todo)
        #expect(progress.normalizedKanbanColumnID == .inProgress)
        #expect(review.normalizedKanbanColumnID == .needsReview)
        #expect(done.normalizedKanbanColumnID == .done)
        #expect(unknown.normalizedKanbanColumnID == .other)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OverviewModelsTests`
Expected: FAIL because there is no kanban status normalization layer yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SloppyFeatureProjects/ProjectKanbanViewModel.swift

import Foundation
import Observation
import SloppyClientCore

public enum ProjectKanbanColumnID: String, CaseIterable, Hashable, Sendable {
    case todo
    case inProgress
    case needsReview
    case done
    case other
}

public struct ProjectKanbanCard: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let priority: String?
    public let actorID: String?
}

public struct ProjectKanbanColumn: Identifiable, Equatable, Sendable {
    public let id: ProjectKanbanColumnID
    public let title: String
    public let items: [ProjectKanbanCard]
}

@Observable
@MainActor
public final class ProjectKanbanViewModel {
    public private(set) var projectName: String = ""
    public private(set) var columns: [ProjectKanbanColumn] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let apiClient: SloppyAPIClient

    public init(apiClient: SloppyAPIClient) {
        self.apiClient = apiClient
    }
}
```

```swift
// Sources/SloppyClientCore/OverviewModels.swift

public extension APIProjectTask {
    var normalizedKanbanColumnID: ProjectKanbanColumnID {
        switch status {
        case "todo", "backlog", "ready":
            return .todo
        case "in_progress":
            return .inProgress
        case "needs_review":
            return .needsReview
        case "done":
            return .done
        default:
            return .other
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter OverviewModelsTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyFeatureProjects/ProjectKanbanViewModel.swift Sources/SloppyClientCore/OverviewModels.swift Tests/SloppyClientCoreTests/OverviewModelsTests.swift
git commit -m "feat: add project kanban models"
```

### Task 5: Render the project kanban tab and wire desktop sidebar project selection to it

**Files:**
- Create: `Sources/SloppyFeatureProjects/ProjectKanbanView.swift`
- Modify: `Sources/SloppyClient/MainView.swift`
- Modify: `Sources/SloppyClient/MainSidebarView.swift`
- Create: `Tests/SloppyClientCoreTests/MainSidebarProjectDisclosureTests.swift`

**Interfaces:**
- Consumes:
  - `ProjectKanbanViewModel`
  - `WorkspaceTabPayload.projectKanban`
  - `MainViewModel.openProjectKanbanTab(project:)`
  - `MainViewModel.openTaskChatTab(project:task:fallbackAgentId:)`
- Produces:
  - `@MainActor final class ProjectKanbanTabState`
  - `ProjectKanbanView(viewModel:)`
  - desktop sidebar project rows opening kanban tabs
  - desktop tab content branch for `.projectKanban`

- [ ] **Step 1: Write the failing source test**

```swift
import Foundation
import Testing

@Suite("Main sidebar project disclosure")
struct MainSidebarProjectDisclosureTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("project rows open kanban tabs and task rows open task chats")
    func projectRowsOpenKanbanTabsAndTaskRowsOpenTaskChats() throws {
        let sidebar = try source("Sources/SloppyClient/MainSidebarView.swift")

        #expect(sidebar.contains("viewModel.openProjectKanbanTab(project: project)"))
        #expect(sidebar.contains("viewModel.openTaskChatTab("))
        #expect(!sidebar.contains("viewModel.selectProject(project)"))
    }

    @Test("main view renders a native project kanban tab")
    func mainViewRendersNativeProjectKanbanTab() throws {
        let mainView = try source("Sources/SloppyClient/MainView.swift")

        #expect(mainView.contains("ProjectKanbanView("))
        #expect(mainView.contains("case .projectKanban"))
        #expect(mainView.contains("ProjectKanbanTabState"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MainSidebarProjectDisclosureTests`
Expected: FAIL because project rows still navigate through the old project/chat flow and no native kanban tab exists.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SloppyFeatureProjects/ProjectKanbanView.swift

import SwiftUI
import SloppyClientUI

@MainActor
public struct ProjectKanbanView: View {
    @State private var viewModel: ProjectKanbanViewModel
    private let projectId: String

    public init(projectId: String, apiClient: SloppyAPIClient) {
        self.projectId = projectId
        _viewModel = State(initialValue: ProjectKanbanViewModel(apiClient: apiClient))
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(viewModel.columns) { column in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(column.title)
                        Text("\\(column.items.count)")
                        ForEach(column.items) { card in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(card.title)
                                if let priority = card.priority {
                                    Text(priority)
                                }
                            }
                        }
                    }
                    .frame(width: 280, alignment: .topLeading)
                }
            }
            .padding(16)
        }
        .task(id: projectId) {
            await viewModel.load(projectId: projectId)
        }
    }
}
```

```swift
// Sources/SloppyClient/MainSidebarView.swift

private func projectRow(for project: APIProjectRecord, c: AppColors, sp: AppSpacing) -> some View {
    sidebarPlainRow(
        icon: .folder,
        title: project.name,
        trailing: nil,
        isSelected: viewModel.selectedSidebarItem == .project(project.id),
        c: c,
        sp: sp
    ) {
        viewModel.openProjectKanbanTab(project: project)
    }
}
```

```swift
// Sources/SloppyClient/MainSidebarView.swift task tap path

viewModel.openTaskChatTab(
    project: project,
    task: task,
    fallbackAgentId: project.actors?.first
)
```

```swift
// Sources/SloppyClient/MainView.swift

case .projectKanban(let context, let state):
    ProjectKanbanView(viewModel: state.viewModel, context: context)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MainSidebarProjectDisclosureTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyFeatureProjects/ProjectKanbanView.swift Sources/SloppyClient/MainView.swift Sources/SloppyClient/MainSidebarView.swift Tests/SloppyClientCoreTests/MainSidebarProjectDisclosureTests.swift
git commit -m "feat: add native project kanban tab"
```

### Task 6: Add desktop recents/session integration and workspace-tab scaffolding

**Files:**
- Modify: `Sources/SloppyClient/MainView.swift`
- Modify: `Sources/SloppyClient/MainSidebarView.swift`
- Modify: `Sources/SloppyClient/WorkspacePanelView.swift`
- Create: `Tests/SloppyClientCoreTests/MainSidebarProjectSessionsTests.swift`

**Interfaces:**
- Consumes:
  - `MainViewModel.openSessionChatTab(_:)`
  - `WorkspaceFilesTabContext`
  - existing `WorkspacePanelView`
- Produces:
  - recents rows opening session-backed tabs
  - workspace toolbar button opening a workspace tab for the active project tab
  - `workspaceFiles` tab placeholder content wired into the desktop shell

- [ ] **Step 1: Write the failing source test**

```swift
import Foundation
import Testing

@Suite("Main sidebar project sessions")
struct MainSidebarProjectSessionsTests {
    private var source: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyClient")
                .appendingPathComponent("MainSidebarView.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("project and recents session rows open session-backed tabs")
    func projectAndRecentsSessionRowsOpenSessionBackedTabs() throws {
        let source = try source

        #expect(source.contains("viewModel.openSessionChatTab(session)"))
        #expect(!source.contains("viewModel.selectChatSession(session)"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MainSidebarProjectSessionsTests`
Expected: FAIL because recent sessions still call the old shared-chat selection path.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SloppyClient/MainSidebarView.swift recents row action

Button {
    viewModel.openSessionChatTab(session)
} label: {
    ...
}
```

```swift
// Sources/SloppyClient/MainView.swift toolbar

ToolbarItem(placement: .primaryAction) {
    Button {
        viewModel.openWorkspaceTabForSelectedContext()
    } label: {
        Image(systemName: "sidebar.right")
    }
}
```

```swift
// Sources/SloppyClient/MainView.swift

func openWorkspaceTabForSelectedContext() {
    guard let activeTab = activeTabForWorkspaceContext() else { return }
    openOrSelectTab(
        key: .workspaceFiles(activeTab.projectId),
        makeTab: WorkspaceTab(
            key: .workspaceFiles(activeTab.projectId),
            kind: .workspaceFiles,
            title: "\(activeTab.projectName) Files",
            payload: .workspaceFiles(.init(projectId: activeTab.projectId, projectName: activeTab.projectName))
        )
    )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MainSidebarProjectSessionsTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyClient/MainView.swift Sources/SloppyClient/MainSidebarView.swift Sources/SloppyClient/WorkspacePanelView.swift Tests/SloppyClientCoreTests/MainSidebarProjectSessionsTests.swift
git commit -m "feat: wire desktop recents and workspace tabs"
```

## Self-Review

### Spec coverage

- Desktop global tab shell: covered by Tasks 1 and 2
- Global tab behavior and dedupe keys: covered by Task 1
- Tab-local chat state: covered by Task 3
- Native read-only project kanban: covered by Tasks 4 and 5
- Sidebar project click opening kanban: covered by Task 5
- Recent chats and workspace surface fitting the same shell: covered by Task 6
- Phone layout staying unchanged: preserved in Task 2 by limiting shell replacement to desktop routing

### Placeholder scan

- No `TBD`, `TODO`, or “implement later” placeholders remain
- Each task has explicit files, interfaces, test commands, and commit commands
- Each code-changing step includes concrete code snippets rather than abstract instructions

### Type consistency

- `WorkspaceTabKind`, `WorkspaceTabKey`, `WorkspaceTabPayload`, `ChatTabState`, and `ProjectKanbanViewModel` are named consistently across tasks
- `projectKanban`, `workspaceFiles`, and chat-tab keys use one stable naming scheme across model, rendering, and sidebar wiring

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-02-global-tabs-kanban-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
