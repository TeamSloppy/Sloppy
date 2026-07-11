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
}
