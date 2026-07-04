# Safari Chrome Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh the macOS workspace chrome so the system titlebar and custom desktop tab strip read as one neutral Safari-like glass surface instead of a gray bar over a blue strip.

**Architecture:** Keep the existing navigation structure intact and only adjust visual ownership in the macOS window bridge plus `DesktopWorkspaceTabStrip`. Back the change with source-level regression tests that assert the new chrome hooks exist and the old segmented-blue treatment is gone.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing

---

### Task 1: Add failing source tests for Safari-like chrome hooks

**Files:**
- Modify: `Tests/SloppyClientCoreTests/TransparentWindowSourceTests.swift`
- Modify: `Tests/SloppyClientCoreTests/MainTabsSourceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test("desktop overlay opts into unified toolbar chrome")
func desktopOverlayOptsIntoUnifiedToolbarChrome() throws {
    let overlay = try source("Sources/SloppyClient/SloppyDesktopOverlay.swift")

    #expect(overlay.contains("window.toolbarStyle = .unified"))
    #expect(overlay.contains("window.titlebarSeparatorStyle = .none"))
}

@Test("desktop workspace strip uses safari glass gradients instead of flat fill")
func desktopWorkspaceStripUsesSafariGlassGradientsInsteadOfFlatFill() throws {
    let strip = try source("Sources/SloppyClient/DesktopWorkspaceTabStrip.swift")

    #expect(strip.contains("LinearGradient("))
    #expect(strip.contains("safariGlassBarBackground"))
    #expect(strip.contains("safariSelectedTabFill"))
    #expect(!strip.contains(".background(theme.colors.surface.opacity(0.82 as CGFloat))"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TransparentWindowSourceTests --filter MainTabsSourceTests`
Expected: FAIL because the new toolbar/window strings and Safari glass helpers do not exist yet.

- [ ] **Step 3: Commit**

```bash
git add Tests/SloppyClientCoreTests/TransparentWindowSourceTests.swift Tests/SloppyClientCoreTests/MainTabsSourceTests.swift
git commit -m "test: cover safari chrome refresh hooks"
```

### Task 2: Apply minimal macOS window chrome refresh

**Files:**
- Modify: `Sources/SloppyClient/SloppyDesktopOverlay.swift`
- Test: `Tests/SloppyClientCoreTests/TransparentWindowSourceTests.swift`

- [ ] **Step 1: Write minimal implementation**

```swift
private func configureTransparentWindow(_ window: NSWindow) {
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    window.toolbarStyle = .unified
    window.isMovableByWindowBackground = true
    window.styleMask.insert(.fullSizeContentView)
    window.contentView?.wantsLayer = true
    window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `swift test --filter TransparentWindowSourceTests`
Expected: PASS with the unified titlebar assertions present.

- [ ] **Step 3: Commit**

```bash
git add Sources/SloppyClient/SloppyDesktopOverlay.swift Tests/SloppyClientCoreTests/TransparentWindowSourceTests.swift
git commit -m "feat: unify macOS titlebar chrome"
```

### Task 3: Restyle the desktop tab strip as neutral Safari glass

**Files:**
- Modify: `Sources/SloppyClient/DesktopWorkspaceTabStrip.swift`
- Test: `Tests/SloppyClientCoreTests/MainTabsSourceTests.swift`

- [ ] **Step 1: Write minimal implementation**

```swift
private var safariGlassBarBackground: some ShapeStyle { ... }
private var safariSelectedTabFill: some ShapeStyle { ... }
private var safariIdleTabFill: some ShapeStyle { ... }
```

Use those helpers to:
- replace the flat strip fill with a layered neutral gradient
- replace the selected blue/dark tab fill with a graphite glass capsule
- keep the `+` button and close affordance on the same neutral glass treatment

- [ ] **Step 2: Run test to verify it passes**

Run: `swift test --filter MainTabsSourceTests`
Expected: PASS with the Safari glass helper names and no legacy flat strip background assertion.

- [ ] **Step 3: Commit**

```bash
git add Sources/SloppyClient/DesktopWorkspaceTabStrip.swift Tests/SloppyClientCoreTests/MainTabsSourceTests.swift
git commit -m "feat: restyle desktop tabs with safari glass chrome"
```

### Task 4: Run focused verification

**Files:**
- Modify: `Tests/SloppyClientCoreTests/TransparentWindowSourceTests.swift`
- Modify: `Tests/SloppyClientCoreTests/MainTabsSourceTests.swift`
- Modify: `Sources/SloppyClient/SloppyDesktopOverlay.swift`
- Modify: `Sources/SloppyClient/DesktopWorkspaceTabStrip.swift`

- [ ] **Step 1: Run the focused regression suite**

Run: `swift test --filter TransparentWindowSourceTests`
Expected: PASS

- [ ] **Step 2: Run the desktop tab source suite**

Run: `swift test --filter MainTabsSourceTests`
Expected: PASS

- [ ] **Step 3: Report verification results**

Document the exact commands and whether the environment allowed full execution. If sandbox limitations block test execution, record that explicitly before handoff.
