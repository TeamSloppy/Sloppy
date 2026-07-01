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
        let appSource = try source("Sources/SloppyClient/SloppyClientApp.swift")

        #expect(appSource.contains(".containerBackground(.clear, for: .window)"))
    }

    @Test("root shell installs the transparent window bridge")
    func rootShellInstallsTransparentWindowBridge() throws {
        let rootShell = try source("Sources/SloppyClient/RootShellView.swift")

        #expect(rootShell.contains("TransparentWindowConfigurationView { window in"))
    }

    @Test("desktop overlay configures a non-opaque titlebar-transparent window")
    func desktopOverlayConfiguresNonOpaqueTransparentTitlebarWindow() throws {
        let overlay = try source("Sources/SloppyClient/SloppyDesktopOverlay.swift")

        #expect(overlay.contains("window.isOpaque = false"))
        #expect(overlay.contains("window.backgroundColor = .clear"))
        #expect(overlay.contains("window.titlebarAppearsTransparent = true"))
        #expect(overlay.contains("window.isMovableByWindowBackground = true"))
    }
}
