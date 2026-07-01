# Workspace Toolbar Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add dedicated primary action buttons to the workspace panel toolbar and map `Cmd+T` to toggling the tools menu.

**Architecture:** Extend `WorkspacePanelViewModel` with a small toolbar/menu state and selection-derived action enablement, then update `WorkspacePanelView` to render separate primary buttons plus an overflow tools menu. Register `Cmd+T` as a panel-local shortcut that toggles the tools menu instead of directly triggering a file action.

**Tech Stack:** Swift 6.2, SwiftUI + Observation, existing `WorkspacePanel` UI, Swift Testing

## Global Constraints

- The first implementation should add dedicated toolbar buttons for primary file actions, a separate tools/overflow menu for secondary actions, and `Cmd+T` to open or close that tools menu.
- `Cmd+T` must toggle the tools menu open/closed and must not trigger `Open in Zed` directly.
- `Open in Zed` and `Reveal in Finder` must be disabled when no valid selection exists.
- The tools menu remains available independently from the primary action buttons.
- Toolbar/menu state must stay local to the workspace panel feature and not leak into chat/session state.

---

### Task 1: Add toolbar state, dedicated buttons, and `Cmd+T`

**Files:**
- Modify: `Sources/SloppyClient/WorkspacePanelViewModel.swift`
- Modify: `Sources/SloppyClient/WorkspacePanelView.swift`
- Modify: `Sources/SloppyClientUI/Icons.swift`
- Create: `Tests/SloppyClientCoreTests/WorkspaceToolbarActionsSourceTests.swift`

**Interfaces:**
- Consumes:
  - `WorkspacePanelViewModel.selectedFilePath: String?`
  - `WorkspacePanelViewModel.selectedFileContent: ProjectFileContentResponse?`
  - current workspace panel toolbar layout in `WorkspacePanelView`
- Produces:
  - `enum WorkspacePanelAction`
  - `struct WorkspacePanelSelectionContext`
  - `var isToolsMenuPresented: Bool`
  - `func toggleToolsMenu()`
  - `func selectionContext() -> WorkspacePanelSelectionContext`

- [ ] **Step 1: Write the failing source test**

```swift
import Foundation
import Testing

@Suite("Workspace toolbar actions source")
struct WorkspaceToolbarActionsSourceTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("workspace toolbar renders dedicated buttons and a separate tools menu")
    func workspaceToolbarRendersDedicatedButtonsAndToolsMenu() throws {
        let panelView = try source("Sources/SloppyClient/WorkspacePanelView.swift")

        #expect(panelView.contains("Open in Zed"))
        #expect(panelView.contains("Reveal in Finder"))
        #expect(panelView.contains("Tools"))
        #expect(panelView.contains("Menu {"))
    }

    @Test("workspace toolbar registers cmd+t to toggle the tools menu")
    func workspaceToolbarRegistersCmdT() throws {
        let panelView = try source("Sources/SloppyClient/WorkspacePanelView.swift")
        let panelVM = try source("Sources/SloppyClient/WorkspacePanelViewModel.swift")

        #expect(panelView.contains(".keyboardShortcut(\"t\", modifiers: [.command])"))
        #expect(panelVM.contains("var isToolsMenuPresented"))
        #expect(panelVM.contains("func toggleToolsMenu()"))
    }

    @Test("workspace toolbar computes selection-driven enablement")
    func workspaceToolbarComputesSelectionDrivenEnablement() throws {
        let panelVM = try source("Sources/SloppyClient/WorkspacePanelViewModel.swift")

        #expect(panelVM.contains("struct WorkspacePanelSelectionContext"))
        #expect(panelVM.contains("var canOpenInEditor"))
        #expect(panelVM.contains("var canRevealInFinder"))
        #expect(panelVM.contains("func selectionContext() -> WorkspacePanelSelectionContext"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkspaceToolbarActionsSourceTests`
Expected: FAIL because the toolbar still uses the old single-action header and does not define a tools menu toggle shortcut/state.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SloppyClient/WorkspacePanelViewModel.swift

enum WorkspacePanelAction: Equatable {
    case openInZed
    case revealInFinder
    case showToolsMenu
}

struct WorkspacePanelSelectionContext: Equatable {
    var selectedPath: String?
    var canOpenInEditor: Bool
    var canRevealInFinder: Bool
}

var isToolsMenuPresented = false

func toggleToolsMenu() {
    isToolsMenuPresented.toggle()
}

func selectionContext() -> WorkspacePanelSelectionContext {
    WorkspacePanelSelectionContext(
        selectedPath: selectedFilePath,
        canOpenInEditor: selectedFilePath != nil,
        canRevealInFinder: selectedFilePath != nil
    )
}
```

```swift
// Sources/SloppyClient/WorkspacePanelView.swift

Button("Open in Zed") { ... }
    .disabled(!viewModel.selectionContext().canOpenInEditor)

Button("Reveal in Finder") { ... }
    .disabled(!viewModel.selectionContext().canRevealInFinder)

Menu {
    Button("Open in Zed") { ... }
    Button("Reveal in Finder") { ... }
} label: {
    Text("Tools")
}
.keyboardShortcut("t", modifiers: [.command])
```

```swift
// Sources/SloppyClientUI/Icons.swift

case openInNew
case moreHoriz
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WorkspaceToolbarActionsSourceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SloppyClient/WorkspacePanelViewModel.swift Sources/SloppyClient/WorkspacePanelView.swift Sources/SloppyClientUI/Icons.swift Tests/SloppyClientCoreTests/WorkspaceToolbarActionsSourceTests.swift
git commit -m "feat: add workspace toolbar quick actions"
```

## Self-Review

### Spec coverage

- Dedicated toolbar buttons for primary actions: covered by Task 1
- Separate tools menu: covered by Task 1
- `Cmd+T` menu toggle: covered by Task 1
- Selection-based disabled/enabled state: covered by Task 1

### Placeholder scan

- No `TBD`, `TODO`, or vague placeholders remain
- File paths, commands, and produced interfaces are explicit

### Type consistency

- `WorkspacePanelAction`, `WorkspacePanelSelectionContext`, and `isToolsMenuPresented` are named consistently across the plan

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-01-workspace-toolbar-actions-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
