# Safari-Style Workspace Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a unified detail-scoped workspace tab container that keeps one shared `WorkspaceTab` model across macOS and iPhone, adds Safari-style desktop tab chrome, and adds iPhone swipe/overview tab navigation through `ChatComposerView`.

**Architecture:** Keep `NavigationSplitView` and the global sidebar unchanged while moving all tab lifecycle, selection, and mobile overview state through `MainViewModel`. Use `desktopContentArea()` in `MainView.swift` as the shared detail entry point, then branch only the chrome and gestures by idiom: a desktop top tab strip on macOS and a mobile composer-driven switcher plus tab overview on iPhone.

**Tech Stack:** Swift 6.2, SwiftUI, Observation, Swift Testing, existing `SloppyClient`, `SloppyFeatureChat`, and `SloppyClientCore` modules.

## Global Constraints

- Keep `MainSidebarView` global and independent from workspace tab content.
- Keep all workspace tab state in `MainViewModel`.
- Preserve the existing `WorkspaceTab` model across platforms.
- Make chat, task chat, kanban, and files tabs behave as equal peers.
- Horizontal swipe on the bottom control switches between open tabs.
- Upward swipe on the bottom control reveals an overview of all open tabs.
- `+` creates a new blank chat tab.
- `Cmd+T` creates a new blank chat tab.
- Make the macOS detail area visually resemble native browser tabs without changing the underlying workspace model.
- Prefer SwiftUI-first implementation for both platforms.
- Reuse existing `WorkspaceTab`, `ChatTabState`, `ProjectKanbanTabState`, and `WorkspaceFilesTabState`.
- Keep tab chrome separate from tab content rendering so platform styling can evolve independently.
- Avoid adding text-based heuristics or mode inference; use explicit callbacks and state.

---

## File Structure

- Modify `Sources/SloppyClient/MainView.swift`
  Responsibility: extend `MainViewModel` with blank-tab, neighbor-navigation, and overview state; replace the current detail-area chrome with shared workspace container logic; wire `Cmd+T`; host desktop and mobile tab chrome.
- Modify `Sources/SloppyFeatureChat/ChatComposerView.swift`
  Responsibility: add phone-only tab interaction callbacks, `+` action, and gesture hooks around the mobile composer shell without breaking input/send behavior.
- Create `Sources/SloppyClient/MobileWorkspaceTabsOverview.swift`
  Responsibility: render the mixed iPhone tab overview grid, close actions, selection actions, and new-tab affordance separately from the content host.
- Create `Sources/SloppyClient/DesktopWorkspaceTabStrip.swift`
  Responsibility: hold the Safari-inspired macOS tab strip UI and keep its styling isolated from `MainView.swift`.
- Modify `Tests/SloppyClientCoreTests/MainTabsSourceTests.swift`
  Responsibility: lock in the new `MainViewModel` tab lifecycle and shortcut API surface.
- Create `Tests/SloppyClientCoreTests/MobileWorkspaceTabsSourceTests.swift`
  Responsibility: source-level coverage for detail-scoped iPhone overview integration and overview state ownership.
- Modify `Tests/SloppyFeatureChatTests/ChatComposerRenderingTests.swift`
  Responsibility: lock in the new composer callback and `+` affordance surface on the phone path.

## Task 1: Extend Tab Lifecycle And Shared Detail State

**Files:**
- Modify: `Sources/SloppyClient/MainView.swift`
- Modify: `Tests/SloppyClientCoreTests/MainTabsSourceTests.swift`

**Interfaces:**
- Consumes: existing `WorkspaceTab`, `WorkspaceTabKey`, `ChatTabState`, `ProjectKanbanTabState`, `WorkspaceFilesTabState`, `MainViewModel`
- Produces:
  - `func createBlankChatTab(select: Bool = true)`
  - `func selectAdjacentTab(offset: Int)`
  - `func nextTabID(from tabID: WorkspaceTab.ID, offset: Int) -> WorkspaceTab.ID?`
  - `var isMobileTabsOverviewPresented: Bool`
  - `func presentMobileTabsOverview()`
  - `func dismissMobileTabsOverview()`

- [ ] **Step 1: Write the failing source test for shared tab lifecycle APIs**

```swift
@Test("main view model exposes blank tab and adjacent navigation helpers")
func mainViewModelExposesBlankTabAndAdjacentNavigationHelpers() throws {
    let mainView = try source("Sources/SloppyClient/MainView.swift")

    #expect(mainView.contains("var isMobileTabsOverviewPresented = false"))
    #expect(mainView.contains("func createBlankChatTab(select: Bool = true)"))
    #expect(mainView.contains("func selectAdjacentTab(offset: Int)"))
    #expect(mainView.contains("func nextTabID(from tabID: WorkspaceTab.ID, offset: Int) -> WorkspaceTab.ID?"))
    #expect(mainView.contains("func presentMobileTabsOverview()"))
    #expect(mainView.contains("func dismissMobileTabsOverview()"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MainTabsSourceTests.mainViewModelExposesBlankTabAndAdjacentNavigationHelpers`

Expected: FAIL because the new properties and functions are not present in `Sources/SloppyClient/MainView.swift`.

- [ ] **Step 3: Write the minimal implementation in `MainViewModel`**

```swift
var isMobileTabsOverviewPresented = false

func createBlankChatTab(select: Bool = true) {
    let chatState = makeChatTabState()
    let tab = WorkspaceTab(
        key: .chatSession("draft-\(UUID().uuidString)"),
        kind: .chat,
        title: "New Chat",
        payload: .chatSession(sessionID: "", title: "New Chat")
    )
    tabs.append(tab)
    chatTabStates[tab.id] = chatState
    if select {
        selectedTabID = tab.id
    }
}

func nextTabID(from tabID: WorkspaceTab.ID, offset: Int) -> WorkspaceTab.ID? {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
        return nil
    }
    let candidate = index + offset
    guard tabs.indices.contains(candidate) else {
        return nil
    }
    return tabs[candidate].id
}

func selectAdjacentTab(offset: Int) {
    guard let selectedTabID,
          let next = nextTabID(from: selectedTabID, offset: offset) else {
        return
    }
    self.selectedTabID = next
}

func presentMobileTabsOverview() {
    isMobileTabsOverviewPresented = true
}

func dismissMobileTabsOverview() {
    isMobileTabsOverviewPresented = false
}
```

- [ ] **Step 4: Fold blank-tab lifecycle into close handling**

```swift
func closeTab(_ tabID: WorkspaceTab.ID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
        return
    }

    let wasSelected = selectedTabID == tabID
    tabs.remove(at: index)
    chatTabStates.removeValue(forKey: tabID)
    projectKanbanTabStates.removeValue(forKey: tabID)
    workspaceTabStates.removeValue(forKey: tabID)

    if tabs.isEmpty {
        selectedTabID = nil
        createBlankChatTab(select: true)
        return
    }

    guard wasSelected else {
        return
    }

    let nextIndex = min(index, tabs.count - 1)
    selectedTabID = tabs[nextIndex].id
}
```

- [ ] **Step 5: Ensure first-load detail never strands without a tab**

```swift
.onAppear {
    if viewModel.tabs.isEmpty {
        viewModel.createBlankChatTab(select: true)
    }
    Task { await viewModel.loadProjects() }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter MainTabsSourceTests.mainViewModelExposesBlankTabAndAdjacentNavigationHelpers`

Expected: PASS

- [ ] **Step 7: Run the related source suite**

Run: `swift test --filter MainTabsSourceTests`

Expected: PASS with all `MainTabsSourceTests` green.

- [ ] **Step 8: Commit**

```bash
git add Sources/SloppyClient/MainView.swift Tests/SloppyClientCoreTests/MainTabsSourceTests.swift
git commit -m "feat: add shared workspace tab lifecycle"
```

## Task 2: Extract Safari-Style Desktop Tab Strip

**Files:**
- Create: `Sources/SloppyClient/DesktopWorkspaceTabStrip.swift`
- Modify: `Sources/SloppyClient/MainView.swift`
- Modify: `Tests/SloppyClientCoreTests/MainTabsSourceTests.swift`

**Interfaces:**
- Consumes: `MainViewModel`, `WorkspaceTab`, `Theme`, `MainView.desktopContentArea()`
- Produces:
  - `struct DesktopWorkspaceTabStrip: View`
  - `init(viewModel: MainViewModel)`
  - `Button` callbacks for select, close, and create blank tab

- [ ] **Step 1: Write the failing source test for desktop strip extraction**

```swift
@Test("main view uses extracted desktop workspace tab strip")
func mainViewUsesExtractedDesktopWorkspaceTabStrip() throws {
    let mainView = try source("Sources/SloppyClient/MainView.swift")
    let strip = try source("Sources/SloppyClient/DesktopWorkspaceTabStrip.swift")

    #expect(mainView.contains("DesktopWorkspaceTabStrip(viewModel: viewModel)"))
    #expect(strip.contains("struct DesktopWorkspaceTabStrip: View"))
    #expect(strip.contains("viewModel.createBlankChatTab()"))
    #expect(strip.contains("viewModel.closeTab(tab.id)"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MainTabsSourceTests.mainViewUsesExtractedDesktopWorkspaceTabStrip`

Expected: FAIL because the extracted file and references do not exist yet.

- [ ] **Step 3: Create the extracted desktop strip view**

```swift
import SwiftUI
import SloppyClientUI

@MainActor
struct DesktopWorkspaceTabStrip: View {
    let viewModel: MainViewModel

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.xs) {
                    ForEach(viewModel.tabs) { tab in
                        DesktopWorkspaceTabButton(
                            tab: tab,
                            isSelected: viewModel.selectedTabID == tab.id,
                            onSelect: { viewModel.selectTab(tab.id) },
                            onClose: { viewModel.closeTab(tab.id) }
                        )
                    }
                }
            }

            Button(action: { viewModel.createBlankChatTab() }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, theme.spacing.s)
        .padding(.vertical, theme.spacing.xs)
    }
}
```

- [ ] **Step 4: Add the compact Safari-style tab button styling**

```swift
private struct DesktopWorkspaceTabButton: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    let onSelect: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.xs) {
            Button(action: onSelect) {
                Text(tab.title)
                    .lineLimit(1)
                    .padding(.leading, theme.spacing.m)
                    .padding(.trailing, theme.spacing.xs)
                    .padding(.vertical, theme.spacing.s)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .padding(.trailing, theme.spacing.s)
        }
        .background(tabBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tabBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? theme.colors.surfaceRaised : theme.colors.surface.opacity(0.72 as CGFloat))
    }
}
```

- [ ] **Step 5: Replace the inline strip in `desktopContentArea()`**

```swift
VStack(spacing: 0) {
    if idiom == .phone {
        EmptyView()
    } else {
        DesktopWorkspaceTabStrip(viewModel: viewModel)
        Divider()
    }

    if let activeDesktopTab {
        desktopTabContent(for: activeDesktopTab)
    } else {
        DesktopTabsEmptyState()
    }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter MainTabsSourceTests.mainViewUsesExtractedDesktopWorkspaceTabStrip`

Expected: PASS

- [ ] **Step 7: Run the related source suite**

Run: `swift test --filter MainTabsSourceTests`

Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/SloppyClient/MainView.swift Sources/SloppyClient/DesktopWorkspaceTabStrip.swift Tests/SloppyClientCoreTests/MainTabsSourceTests.swift
git commit -m "feat: add safari-style desktop workspace strip"
```

## Task 3: Add iPhone Composer Tab Gestures And Mixed Tab Overview

**Files:**
- Modify: `Sources/SloppyFeatureChat/ChatComposerView.swift`
- Create: `Sources/SloppyClient/MobileWorkspaceTabsOverview.swift`
- Modify: `Sources/SloppyClient/MainView.swift`
- Create: `Tests/SloppyClientCoreTests/MobileWorkspaceTabsSourceTests.swift`
- Modify: `Tests/SloppyFeatureChatTests/ChatComposerRenderingTests.swift`

**Interfaces:**
- Consumes: `ChatComposerView`, `MainViewModel`, `WorkspaceTab`, `Theme`
- Produces:
  - `public struct ChatComposerTabActions`
  - `public init(previousTab: ..., nextTab: ..., showOverview: ..., createTab: ...)`
  - `struct MobileWorkspaceTabsOverview: View`
  - `init(tabs:selectedTabID:onSelect:onClose:onCreate:onDismiss:)`

- [ ] **Step 1: Write the failing source test for mobile composer tab actions**

```swift
@Test("chat composer phone layout exposes tab action hooks")
func chatComposerPhoneLayoutExposesTabActionHooks() throws {
    let source = try source("Sources/SloppyFeatureChat/ChatComposerView.swift")

    #expect(source.contains("public struct ChatComposerTabActions"))
    #expect(source.contains("var tabActions: ChatComposerTabActions?"))
    #expect(source.contains("tabActions?.createTab()"))
    #expect(source.contains("tabActions?.showOverview()"))
}
```

- [ ] **Step 2: Write the failing source test for detail-scoped mobile overview**

```swift
@Test("main view presents mobile overview from detail container")
func mainViewPresentsMobileOverviewFromDetailContainer() throws {
    let mainView = try source("Sources/SloppyClient/MainView.swift")
    let overview = try source("Sources/SloppyClient/MobileWorkspaceTabsOverview.swift")

    #expect(mainView.contains("MobileWorkspaceTabsOverview("))
    #expect(mainView.contains("viewModel.isMobileTabsOverviewPresented"))
    #expect(overview.contains("struct MobileWorkspaceTabsOverview: View"))
    #expect(overview.contains("ForEach(tabs)"))
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter ChatComposerRenderingTests.chatComposerPhoneLayoutExposesTabActionHooks`

Expected: FAIL because the tab-action API does not exist.

Run: `swift test --filter MobileWorkspaceTabsSourceTests.mainViewPresentsMobileOverviewFromDetailContainer`

Expected: FAIL because the overview file and detail wiring do not exist.

- [ ] **Step 4: Add phone-only tab action surface to `ChatComposerView`**

```swift
public struct ChatComposerTabActions {
    public let previousTab: @MainActor () -> Void
    public let nextTab: @MainActor () -> Void
    public let showOverview: @MainActor () -> Void
    public let createTab: @MainActor () -> Void

    public init(
        previousTab: @escaping @MainActor () -> Void,
        nextTab: @escaping @MainActor () -> Void,
        showOverview: @escaping @MainActor () -> Void,
        createTab: @escaping @MainActor () -> Void
    ) {
        self.previousTab = previousTab
        self.nextTab = nextTab
        self.showOverview = showOverview
        self.createTab = createTab
    }
}

public let tabActions: ChatComposerTabActions?
```

- [ ] **Step 5: Replace the inert mobile leading button and add directional gesture handling**

```swift
MobileComposerCircleButton(symbol: .add, action: {
    tabActions?.createTab()
})

.gesture(
    DragGesture(minimumDistance: 16)
        .onEnded { value in
            let horizontal = value.translation.width
            let vertical = value.translation.height

            if abs(horizontal) > abs(vertical), abs(horizontal) > 44 {
                if horizontal < 0 {
                    tabActions?.nextTab()
                } else {
                    tabActions?.previousTab()
                }
                return
            }

            if vertical < -56, abs(vertical) > abs(horizontal) {
                tabActions?.showOverview()
            }
        }
)
```

- [ ] **Step 6: Create the mobile mixed overview view**

```swift
import SwiftUI
import SloppyClientUI

@MainActor
struct MobileWorkspaceTabsOverview: View {
    let tabs: [WorkspaceTab]
    let selectedTabID: WorkspaceTab.ID?
    let onSelect: @MainActor (WorkspaceTab.ID) -> Void
    let onClose: @MainActor (WorkspaceTab.ID) -> Void
    let onCreate: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(tabs) { tab in
                    Button(action: { onSelect(tab.id) }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tab.title)
                            Text(tab.kind.rawValue)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button(action: { onClose(tab.id) }) {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
                }
            }

            Button(action: onCreate) {
                Image(systemName: "plus")
            }
        }
    }
}
```

- [ ] **Step 7: Present the overview from the detail container and wire composer callbacks**

```swift
private func desktopContentArea() -> some View {
    ZStack {
        workspaceContentHost()

        if idiom == .phone, viewModel.isMobileTabsOverviewPresented {
            MobileWorkspaceTabsOverview(
                tabs: viewModel.tabs,
                selectedTabID: viewModel.selectedTabID,
                onSelect: { id in
                    viewModel.selectTab(id)
                    viewModel.dismissMobileTabsOverview()
                },
                onClose: { id in
                    viewModel.closeTab(id)
                },
                onCreate: {
                    viewModel.createBlankChatTab()
                    viewModel.dismissMobileTabsOverview()
                },
                onDismiss: {
                    viewModel.dismissMobileTabsOverview()
                }
            )
        }
    }
}

ChatComposerView(
    draft: viewModel.composerDraft,
    viewModel: viewModel,
    tabActions: ChatComposerTabActions(
        previousTab: { mainViewModel.selectAdjacentTab(offset: -1) },
        nextTab: { mainViewModel.selectAdjacentTab(offset: 1) },
        showOverview: { mainViewModel.presentMobileTabsOverview() },
        createTab: { mainViewModel.createBlankChatTab() }
    )
)
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test --filter ChatComposerRenderingTests.chatComposerPhoneLayoutExposesTabActionHooks`

Expected: PASS

Run: `swift test --filter MobileWorkspaceTabsSourceTests.mainViewPresentsMobileOverviewFromDetailContainer`

Expected: PASS

- [ ] **Step 9: Run the related source suites**

Run: `swift test --filter ChatComposerRenderingTests`

Expected: PASS

Run: `swift test --filter MobileWorkspaceTabsSourceTests`

Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add Sources/SloppyFeatureChat/ChatComposerView.swift Sources/SloppyClient/MobileWorkspaceTabsOverview.swift Sources/SloppyClient/MainView.swift Tests/SloppyClientCoreTests/MobileWorkspaceTabsSourceTests.swift Tests/SloppyFeatureChatTests/ChatComposerRenderingTests.swift
git commit -m "feat: add mobile workspace tab gestures and overview"
```

## Task 4: Finish Integration, Detail Routing, And Keyboard Shortcut Coverage

**Files:**
- Modify: `Sources/SloppyClient/MainView.swift`
- Modify: `Tests/SloppyClientCoreTests/MainTabsSourceTests.swift`
- Modify: `Tests/SloppyClientCoreTests/MobileWorkspaceTabsSourceTests.swift`

**Interfaces:**
- Consumes: `MainView`, `MainViewModel`, desktop/mobile tab chrome introduced earlier
- Produces:
  - `workspaceContentHost()` or equivalent shared detail host
  - `keyboardShortcut("t", modifiers: [.command])` wired to `createBlankChatTab()`

- [ ] **Step 1: Write the failing source test for `Cmd+T` and shared detail host**

```swift
@Test("main view wires cmd t and shared detail host for workspace tabs")
func mainViewWiresCommandTAndSharedDetailHost() throws {
    let mainView = try source("Sources/SloppyClient/MainView.swift")

    #expect(mainView.contains("keyboardShortcut(\"t\", modifiers: [.command])"))
    #expect(mainView.contains("viewModel.createBlankChatTab()"))
    #expect(mainView.contains("private func workspaceContentHost() -> some View"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MainTabsSourceTests.mainViewWiresCommandTAndSharedDetailHost`

Expected: FAIL because the shortcut and shared host are not both implemented yet.

- [ ] **Step 3: Extract the shared detail host and remove stale phone-root layout**

```swift
@ViewBuilder
private func workspaceContentHost() -> some View {
    VStack(spacing: 0) {
        if idiom != .phone {
            DesktopWorkspaceTabStrip(viewModel: viewModel)
            Divider()
        }

        if let activeDesktopTab {
            desktopTabContent(for: activeDesktopTab)
        } else {
            DesktopTabsEmptyState()
        }
    }
}
```

- [ ] **Step 4: Add `Cmd+T` to the detail container toolbar/background shortcut host**

```swift
.background {
    Group {
        Button("") {
            viewModel.createBlankChatTab()
        }
        .keyboardShortcut("t", modifiers: [.command])
        .opacity(0.001)
        .allowsHitTesting(false)

        Button("") {
            Task { await viewModel.refreshContent() }
        }
        .keyboardShortcut("r", modifiers: [.command])
        .opacity(0.001)
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 5: Ensure overview dismissal and selection stay in sync after close**

```swift
func closeTab(_ tabID: WorkspaceTab.ID) {
    // existing removal logic

    if isMobileTabsOverviewPresented, tabs.count == 1 {
        dismissMobileTabsOverview()
    }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter MainTabsSourceTests.mainViewWiresCommandTAndSharedDetailHost`

Expected: PASS

- [ ] **Step 7: Run the final relevant verification**

Run: `swift test --filter MainTabsSourceTests`

Expected: PASS

Run: `swift test --filter MobileWorkspaceTabsSourceTests`

Expected: PASS

Run: `swift test --filter ChatComposerRenderingTests`

Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/SloppyClient/MainView.swift Tests/SloppyClientCoreTests/MainTabsSourceTests.swift Tests/SloppyClientCoreTests/MobileWorkspaceTabsSourceTests.swift
git commit -m "feat: wire shared workspace tab detail container"
```

## Self-Review

- Spec coverage: shared detail-scoped container is covered in Tasks 1 and 4; Safari-style desktop strip is covered in Task 2; iPhone composer swipe and upward overview are covered in Task 3; mixed tab overview and `+`/`Cmd+T` are covered in Tasks 1, 3, and 4.
- Placeholder scan: removed generic placeholders; every task names exact files, interfaces, commands, and expected outputs.
- Type consistency: `createBlankChatTab`, `selectAdjacentTab`, `nextTabID`, `presentMobileTabsOverview`, `dismissMobileTabsOverview`, `ChatComposerTabActions`, and `MobileWorkspaceTabsOverview` are named consistently across producing and consuming tasks.

Plan complete and saved to `docs/superpowers/plans/2026-07-02-safari-style-workspace-tabs-implementation.md`. Two execution options:

1. Subagent-Driven (recommended) - I dispatch a fresh subagent per task, review between tasks, fast iteration

2. Inline Execution - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
