# Immersive Siri Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an immersive Siri-like glass shell for the Sloppy Apple client.

**Architecture:** The shared background gets the black-to-transparent ambience. `MainView` owns a new shell-level glass container around the sidebar and chat. Sidebar and composer surfaces become translucent enough to sit inside that shell.

**Tech Stack:** Swift 6.2, SwiftPM, AdaEngine/AdaUI views, AdaUI `glassEffect`, existing `SloppyEdgeGlowMaterial`, Swift Testing.

---

### Task 1: Rendering Guard

**Files:**
- Create: `Apps/Client/Tests/SloppyClientCoreTests/SloppyShellRenderingTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Foundation
import Testing

@Suite("Sloppy shell rendering")
struct SloppyShellRenderingTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("main split layout is wrapped in immersive glass shell")
    func mainSplitLayoutIsWrappedInImmersiveGlassShell() throws {
        let mainView = try source("Sources", "SloppyClient", "MainView.swift")

        #expect(mainView.contains("SloppyGlassShell"))
        #expect(mainView.contains(".allowsHitTesting(false)"))
    }

    @Test("glass shell composes blur and edge glow")
    func glassShellComposesBlurAndEdgeGlow() throws {
        let shell = try source("Sources", "SloppyClient", "SloppyGlassShell.swift")

        #expect(shell.contains("glassEffect("))
        #expect(shell.contains("SloppyShaderEffects.edgeGlow"))
        #expect(shell.contains("linearGradient"))
    }
}
```

- [ ] **Step 2: Run red test**

Run: `swift test --package-path Apps/Client --filter SloppyShellRenderingTests`

Expected: fails because `SloppyGlassShell.swift` does not exist and `MainView.swift` does not reference `SloppyGlassShell`.

### Task 2: Shell Container

**Files:**
- Create: `Apps/Client/Sources/SloppyClient/SloppyGlassShell.swift`
- Modify: `Apps/Client/Sources/SloppyClient/MainView.swift`

- [ ] **Step 1: Add `SloppyGlassShell`**

Create a `View` that wraps content in a rounded translucent black surface, applies `.glassEffect(.regular.tint(...))`, overlays `SloppyShaderEffects.edgeGlow`, and adds a top black-to-transparent highlight.

- [ ] **Step 2: Wrap regular and compact layouts**

In `MainView.regularSplitLayout`, wrap the existing `HStack` in `SloppyGlassShell`. Use a larger corner radius on desktop and a smaller radius on compact overlays.

- [ ] **Step 3: Run green test**

Run: `swift test --package-path Apps/Client --filter SloppyShellRenderingTests`

Expected: passes.

### Task 3: Atmosphere and Inner Surfaces

**Files:**
- Modify: `Apps/Client/Sources/SloppyClientUI/AppAtmosphericBackground.swift`
- Modify: `Apps/Client/Sources/SloppyClient/MainSidebarView.swift`
- Modify: `Apps/Client/Sources/SloppyFeatureChat/ChatComposerView.swift`

- [ ] **Step 1: Update global background**

Change `AppAtmosphericBackground` from flat theme background to layered black-to-transparent gradients with a subtle lower cool tint.

- [ ] **Step 2: Make sidebar shell-aware**

Enable liquid glass for non-iOS sidebar surfaces and replace opaque selected-row fills with translucent glow fills.

- [ ] **Step 3: Make composer glassier**

Change phone and regular composer backgrounds to use translucent fills plus `glassEffect`.

- [ ] **Step 4: Build the client**

Run: `swift build --package-path Apps/Client`

Expected: build exits 0.
