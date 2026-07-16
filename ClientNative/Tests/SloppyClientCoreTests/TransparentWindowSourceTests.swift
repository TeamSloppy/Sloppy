import Foundation
import Testing

@Suite("Transparent window source")
struct TransparentWindowSourceTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("app scene clears the system window background")
    func appSceneClearsSystemWindowBackground() throws {
        let appSource = try source("Sources/SloppyClient/App/SloppyClientApp.swift")

        #expect(appSource.contains(".containerBackground(.clear, for: .window)"))
    }

    @Test("root shell installs the transparent window bridge")
    func rootShellInstallsTransparentWindowBridge() throws {
        let rootShell = try source("Sources/SloppyClient/Root/RootShellView.swift")

        #expect(rootShell.contains("TransparentWindowConfigurationView { window in"))
        #expect(rootShell.contains("WindowDragHandleStrip(height:"))
        #expect(rootShell.contains("max(0, safeAreaInsets.top)"))
        #expect(rootShell.contains(".allowsHitTesting(false)"))
        #expect(!rootShell.contains("WindowDragHandleStrip(height: 36)"))
    }

    @Test("desktop overlay configures a non-opaque titlebar-transparent window")
    func desktopOverlayConfiguresNonOpaqueTransparentTitlebarWindow() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains("window.isOpaque = false"))
        #expect(overlay.contains("window.backgroundColor = .clear"))
        #expect(overlay.contains("window.titlebarAppearsTransparent = true"))
        #expect(overlay.contains("window.isMovableByWindowBackground = false"))
    }

    @Test("desktop overlay opts into unified toolbar chrome")
    func desktopOverlayOptsIntoUnifiedToolbarChrome() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains("window.titlebarSeparatorStyle = .none"))
        #expect(overlay.contains("window.toolbarStyle = .unified"))
    }

    @Test("desktop overlay creates an always-on interactive notch panel")
    func desktopOverlayCreatesAnAlwaysOnInteractiveNotchPanel() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")
        let rootModel = try source("Sources/SloppyClient/Root/RootShellViewModel.swift")

        #expect(overlay.contains("SloppyNotchPanel"))
        #expect(overlay.contains("SloppyDesktopNotchView"))
        #expect(overlay.contains("panel.level = .statusBar"))
        #expect(overlay.contains(".canJoinAllSpaces"))
        #expect(overlay.contains("Button(\"Allow\")"))
        #expect(overlay.contains("Button(\"Deny\""))
        #expect(overlay.contains(".onHover(perform: handleHoverChange)"))
        #expect(overlay.contains("state.setExpanded(true)"))
        #expect(overlay.contains("state.toolApproval == nil"))
        #expect(overlay.contains("state.setExpanded(false)"))
        #expect(rootModel.contains("desktopOverlay.start(settings: settings)"))
    }

    @Test("desktop overlay ignores transient hover exits caused by panel resizing")
    func desktopOverlayIgnoresTransientHoverExits() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains("isPointerInsidePanel"))
        #expect(overlay.contains("Task.sleep(for: .milliseconds(120))"))
        #expect(overlay.contains("guard !isPointerInsidePanel() else { continue }"))
        #expect(overlay.contains("hoverCollapseTask?.cancel()"))
    }

    @Test("desktop overlay uses compact panel dimensions")
    func desktopOverlayUsesCompactPanelDimensions() throws {
        let overlay = try source("Sources/SloppyClient/Overlays/SloppyDesktopOverlay.swift")

        #expect(overlay.contains("collapsedSize = CGSize(width: 164, height: 32)"))
        #expect(overlay.contains("expandedSize = CGSize(width: 340, height: 148)"))
        #expect(overlay.contains("wideWidth: CGFloat = 520"))
    }
}
