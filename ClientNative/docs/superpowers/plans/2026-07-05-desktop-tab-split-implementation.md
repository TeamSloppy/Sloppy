# Desktop Tab Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a temporary desktop-only split mode where dragging one tab onto another renders both tabs side by side with a central drag indicator and resize handle.

**Architecture:** Keep the existing linear `tabs` array and tab state stores unchanged. Add a temporary `DesktopTabSplitState` to `MainViewModel`, wire drag/drop in the desktop tab strip, and let `MainView` switch between normal single-tab rendering and a two-pane overlay split renderer.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, existing `MainViewModel` / `DesktopWorkspaceTabStrip` desktop tab architecture.

---

### Task 1: Add split state model and source coverage

**Files:**
- Modify: `Sources/SloppyClient/MainTabs.swift`
- Create: `Tests/SloppyClientCoreTests/DesktopTabSplitStateSourceTests.swift`

- [ ] **Step 1: Write the failing source test for split state**

```swift
import Foundation
import Testing

@Suite("Desktop tab split state source")
struct DesktopTabSplitStateSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("main tabs defines temporary desktop split state")
    func mainTabsDefinesTemporaryDesktopSplitState() throws {
        let source = try source("Sources", "SloppyClient", "MainTabs.swift")

        #expect(source.contains("struct DesktopTabSplitState"))
        #expect(source.contains("var primaryTabID: WorkspaceTab.ID"))
        #expect(source.contains("var secondaryTabID: WorkspaceTab.ID"))
        #expect(source.contains("var fraction: CGFloat"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DesktopTabSplitStateSourceTests`
Expected: FAIL because `DesktopTabSplitState` is not defined yet.

- [ ] **Step 3: Write minimal split state model**

```swift
import Foundation
import CoreGraphics
import SloppyClientCore
import SloppyFeatureChat
import SloppyFeatureProjects

struct DesktopTabSplitState: Equatable {
    var primaryTabID: WorkspaceTab.ID
    var secondaryTabID: WorkspaceTab.ID
    var fraction: CGFloat
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DesktopTabSplitStateSourceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyClient/MainTabs.swift Tests/SloppyClientCoreTests/DesktopTabSplitStateSourceTests.swift
git commit -m "feat: add desktop tab split state model"
```

### Task 2: Add split lifecycle to MainViewModel

**Files:**
- Modify: `Sources/SloppyClient/MainView.swift`
- Create: `Tests/SloppyClientCoreTests/DesktopTabSplitLifecycleSourceTests.swift`

- [ ] **Step 1: Write the failing source test for split lifecycle API**

```swift
import Foundation
import Testing

@Suite("Desktop tab split lifecycle source")
struct DesktopTabSplitLifecycleSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("main view model exposes temporary desktop split lifecycle")
    func mainViewModelExposesTemporaryDesktopSplitLifecycle() throws {
        let source = try source("Sources", "SloppyClient", "MainView.swift")

        #expect(source.contains("var desktopSplitState: DesktopTabSplitState?"))
        #expect(source.contains("func beginDesktopSplit(source sourceTabID: WorkspaceTab.ID, target targetTabID: WorkspaceTab.ID)"))
        #expect(source.contains("func updateDesktopSplitFraction(_ fraction: CGFloat)"))
        #expect(source.contains("func clearDesktopSplit()"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DesktopTabSplitLifecycleSourceTests`
Expected: FAIL because split lifecycle state and methods are missing.

- [ ] **Step 3: Add desktop split state and lifecycle methods**

```swift
var desktopSplitState: DesktopTabSplitState?

func beginDesktopSplit(source sourceTabID: WorkspaceTab.ID, target targetTabID: WorkspaceTab.ID) {
    guard sourceTabID != targetTabID,
          tabs.contains(where: { $0.id == sourceTabID }),
          tabs.contains(where: { $0.id == targetTabID }) else {
        return
    }

    desktopSplitState = DesktopTabSplitState(
        primaryTabID: targetTabID,
        secondaryTabID: sourceTabID,
        fraction: 0.5
    )
    selectedTabID = targetTabID
}

func updateDesktopSplitFraction(_ fraction: CGFloat) {
    guard var desktopSplitState else { return }
    desktopSplitState.fraction = min(0.72, max(0.28, fraction))
    self.desktopSplitState = desktopSplitState
}

func clearDesktopSplit() {
    desktopSplitState = nil
}
```

- [ ] **Step 4: Clear invalid split state from tab selection and close paths**

```swift
func selectTab(_ tabID: WorkspaceTab.ID) {
    guard tabs.contains(where: { $0.id == tabID }) else {
        return
    }

    if let desktopSplitState,
       tabID != desktopSplitState.primaryTabID,
       tabID != desktopSplitState.secondaryTabID {
        clearDesktopSplit()
    }

    selectedTabID = tabID
}

func closeTab(_ tabID: WorkspaceTab.ID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
        return
    }

    let splitStateBeforeClose = desktopSplitState
    let wasSelected = selectedTabID == tabID
    tabs.remove(at: index)
    chatTabStates.removeValue(forKey: tabID)
    projectKanbanTabStates.removeValue(forKey: tabID)
    taskDetailTabStates.removeValue(forKey: tabID)
    workspaceTabStates.removeValue(forKey: tabID)

    if let splitStateBeforeClose {
        if tabID == splitStateBeforeClose.primaryTabID {
            selectedTabID = splitStateBeforeClose.secondaryTabID
            clearDesktopSplit()
        } else if tabID == splitStateBeforeClose.secondaryTabID {
            selectedTabID = splitStateBeforeClose.primaryTabID
            clearDesktopSplit()
        } else if !tabs.contains(where: { $0.id == splitStateBeforeClose.primaryTabID }) ||
                    !tabs.contains(where: { $0.id == splitStateBeforeClose.secondaryTabID }) {
            clearDesktopSplit()
        }
    }

    // Keep the existing empty-state and next-tab fallback logic after this block.
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter DesktopTabSplitLifecycleSourceTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/SloppyClient/MainView.swift Tests/SloppyClientCoreTests/DesktopTabSplitLifecycleSourceTests.swift
git commit -m "feat: add desktop split lifecycle to main view model"
```

### Task 3: Add drag and drop hooks to the desktop tab strip

**Files:**
- Modify: `Sources/SloppyClient/DesktopWorkspaceTabStrip.swift`
- Create: `Tests/SloppyClientCoreTests/DesktopWorkspaceTabStripSplitSourceTests.swift`

- [ ] **Step 1: Write the failing source test for drag/drop split hooks**

```swift
import Foundation
import Testing

@Suite("Desktop tab strip split source")
struct DesktopWorkspaceTabStripSplitSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("desktop tab strip wires drag and drop into split creation")
    func desktopTabStripWiresDragAndDropIntoSplitCreation() throws {
        let source = try source("Sources", "SloppyClient", "DesktopWorkspaceTabStrip.swift")

        #expect(source.contains(".draggable(tab.id.uuidString)"))
        #expect(source.contains(".dropDestination(for: String.self)"))
        #expect(source.contains("viewModel.beginDesktopSplit(source: sourceTabID, target: tab.id)"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DesktopWorkspaceTabStripSplitSourceTests`
Expected: FAIL because tab drag/drop split hooks are missing.

- [ ] **Step 3: Add drag source and tab drop target**

```swift
DesktopWorkspaceTabButton(
    tab: tab,
    isSelected: viewModel.selectedTabID == tab.id,
    onSelect: { viewModel.selectTab(tab.id) },
    onClose: { viewModel.closeTab(tab.id) }
)
.frame(width: tabWidth)
.id(tab.id)
.draggable(tab.id.uuidString)
.dropDestination(for: String.self) { items, _ in
    guard let raw = items.first,
          let sourceTabID = UUID(uuidString: raw) else {
        return false
    }

    viewModel.beginDesktopSplit(source: sourceTabID, target: tab.id)
    return sourceTabID != tab.id
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DesktopWorkspaceTabStripSplitSourceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyClient/DesktopWorkspaceTabStrip.swift Tests/SloppyClientCoreTests/DesktopWorkspaceTabStripSplitSourceTests.swift
git commit -m "feat: add drag and drop split hooks to desktop tabs"
```

### Task 4: Render the temporary split pair and center handle

**Files:**
- Modify: `Sources/SloppyClient/MainView.swift`
- Create: `Tests/SloppyClientCoreTests/DesktopSplitRenderingSourceTests.swift`

- [ ] **Step 1: Write the failing source test for split rendering**

```swift
import Foundation
import Testing

@Suite("Desktop split rendering source")
struct DesktopSplitRenderingSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("main view renders two desktop panes with a center split handle")
    func mainViewRendersTwoDesktopPanesWithCenterSplitHandle() throws {
        let source = try source("Sources", "SloppyClient", "MainView.swift")

        #expect(source.contains("if let desktopSplitState = viewModel.desktopSplitState"))
        #expect(source.contains("DesktopSplitHandle("))
        #expect(source.contains("desktopTabContent(for: primaryTab)"))
        #expect(source.contains("desktopTabContent(for: secondaryTab)"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DesktopSplitRenderingSourceTests`
Expected: FAIL because the main view still renders only one active desktop tab.

- [ ] **Step 3: Add split-aware desktop content rendering**

```swift
@ViewBuilder
private func workspaceContentHost() -> some View {
    VStack(spacing: 0) {
        if idiom != .phone {
            DesktopWorkspaceTabStrip(viewModel: viewModel)
            Divider()
        }

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
            desktopTabContent(for: activeDesktopTab)
        } else {
            DesktopTabsEmptyState()
        }
    }
}
```

- [ ] **Step 4: Add the center split handle and resizable layout**

```swift
private struct DesktopSplitContentView<Primary: View, Secondary: View>: View {
    let fraction: CGFloat
    let onFractionChange: @MainActor (CGFloat) -> Void
    let onClearSplit: @MainActor () -> Void
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let clampedFraction = min(0.72, max(0.28, fraction))
            let handleWidth: CGFloat = 24
            let primaryWidth = max(0, width * clampedFraction - handleWidth / 2)
            let secondaryWidth = max(0, width - primaryWidth - handleWidth)

            HStack(spacing: 0) {
                primary()
                    .frame(width: primaryWidth)
                DesktopSplitHandle(
                    onClearSplit: onClearSplit,
                    onDrag: { locationX in
                        onFractionChange(locationX / width)
                    }
                )
                .frame(width: handleWidth)
                secondary()
                    .frame(width: secondaryWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter DesktopSplitRenderingSourceTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/SloppyClient/MainView.swift Tests/SloppyClientCoreTests/DesktopSplitRenderingSourceTests.swift
git commit -m "feat: render temporary desktop split content"
```

### Task 5: Add split cleanup for chat retargeting and focused regression coverage

**Files:**
- Modify: `Sources/SloppyClient/MainView.swift`
- Modify: `Tests/SloppyClientCoreTests/MainTabsSourceTests.swift`
- Create: `Tests/SloppyClientCoreTests/DesktopSplitCleanupSourceTests.swift`

- [ ] **Step 1: Write the failing source test for split cleanup on retarget and external selection**

```swift
import Foundation
import Testing

@Suite("Desktop split cleanup source")
struct DesktopSplitCleanupSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("main view model clears temporary split when retargeting selected chat tab")
    func mainViewModelClearsTemporarySplitWhenRetargetingSelectedChatTab() throws {
        let source = try source("Sources", "SloppyClient", "MainView.swift")

        #expect(source.contains("clearDesktopSplit()"))
        #expect(source.contains("private func retargetSelectedChatTab(to session: ChatSessionSummary)"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DesktopSplitCleanupSourceTests`
Expected: FAIL if retargeting still leaves stale split state around.

- [ ] **Step 3: Clear split from retargeting and update existing source assertions**

```swift
@discardableResult
private func retargetSelectedChatTab(to session: ChatSessionSummary) -> Bool {
    guard let selectedTabID,
          let index = tabs.firstIndex(where: { $0.id == selectedTabID }),
          tabs[index].kind == .chat,
          let chatState = chatTabStates[selectedTabID] else {
        return false
    }

    clearDesktopSplit()
    chatState.viewModel.openSessionFromSummary(session)
    tabs[index] = WorkspaceTab(
        id: tabs[index].id,
        key: .chatSession(session.id),
        kind: .chat,
        title: session.title,
        payload: .chatSession(sessionID: session.id, title: session.title)
    )
    return true
}
```

Add focused source assertions in `MainTabsSourceTests.swift` for:

```swift
#expect(mainView.contains("var desktopSplitState: DesktopTabSplitState?"))
#expect(mainView.contains("DesktopWorkspaceTabStrip(viewModel: viewModel)"))
#expect(mainView.contains("DesktopSplitHandle("))
```

- [ ] **Step 4: Run focused tests to verify all split regressions pass**

Run: `swift test --filter DesktopTabSplitStateSourceTests`
Expected: PASS

Run: `swift test --filter DesktopTabSplitLifecycleSourceTests`
Expected: PASS

Run: `swift test --filter DesktopWorkspaceTabStripSplitSourceTests`
Expected: PASS

Run: `swift test --filter DesktopSplitRenderingSourceTests`
Expected: PASS

Run: `swift test --filter DesktopSplitCleanupSourceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyClient/MainView.swift Tests/SloppyClientCoreTests/MainTabsSourceTests.swift Tests/SloppyClientCoreTests/DesktopSplitCleanupSourceTests.swift
git commit -m "test: lock down desktop split cleanup behavior"
```

### Task 6: Final verification

**Files:**
- Modify: none
- Test: `Tests/SloppyClientCoreTests/`

- [ ] **Step 1: Run the focused client core split suite**

Run: `swift build --target SloppyClientCoreTests`
Expected: `Build of target: 'SloppyClientCoreTests' complete!`

- [ ] **Step 2: Run the focused split-related test filters**

Run: `swift test --skip-build --filter DesktopTabSplit`
Expected: PASS for the split state and lifecycle tests

Run: `swift test --skip-build --filter DesktopWorkspaceTabStripSplit`
Expected: PASS for drag/drop split tab strip tests

Run: `swift test --skip-build --filter DesktopSplit`
Expected: PASS for split rendering and cleanup tests

- [ ] **Step 3: Sanity-check for unrelated legacy failures**

Run: `swift test --skip-build --filter MainTabsSourceTests`
Expected: PASS if split source updates are aligned with existing desktop tab expectations

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-07-05-desktop-tab-split-design.md docs/superpowers/plans/2026-07-05-desktop-tab-split-implementation.md
git commit -m "docs: add desktop tab split implementation plan"
```
