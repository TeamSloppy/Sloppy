import Foundation
import Testing

@Suite("SloppyClientApp wiring")
struct SloppyClientAppWiringTests {
    private var appSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let appURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyClient")
                .appendingPathComponent("App")
                .appendingPathComponent("SloppyClientApp.swift")
            return try String(contentsOf: appURL, encoding: .utf8)
        }
    }

    @Test("app entry uses a correctly sized SwiftUI main window")
    func appEntryUsesCorrectlySizedSwiftUIMainWindow() throws {
        let source = try appSource

        #expect(source.contains("@main"))
        #expect(source.contains("struct SloppyClientApp: App"))
        #expect(source.contains("@State private var viewModel: RootShellViewModel"))
        #expect(source.contains("init() {"))
        #expect(source.contains("_viewModel = State(initialValue: RootShellViewModel())"))
        #expect(source.contains("Window(\"Sloppy\", id: \"main\")"))
        #expect(source.contains("RootShellView(viewModel: viewModel)"))
        #expect(source.contains(".frame(minWidth: 1120, minHeight: 760)"))
        #expect(source.contains(".defaultSize(width: 1360, height: 880)"))
        #expect(source.contains(".windowResizability(.contentMinSize)"))
    }

    @Test("app entry exposes native mac settings scene backed by our settings screen")
    func appEntryExposesNativeMacSettingsScene() throws {
        let source = try appSource

        #expect(source.contains("Settings {"))
        #expect(source.contains("SettingsScreen("))
        #expect(source.contains("settings: viewModel.settings"))
        #expect(source.contains(".defaultSize(width:"))
        #expect(source.contains(".windowResizability("))
    }

    @Test("app exposes macOS menu bar quick actions and survives without windows")
    func appExposesMenuBarQuickActions() throws {
        let source = try appSource

        #expect(source.contains("MenuBarExtra(\"Sloppy\""))
        #expect(source.contains("Button(\"New Chat\""))
        #expect(source.contains("Button(\"Scheduled Tasks\""))
        #expect(source.contains("Button(\"Open Sloppy\""))
        #expect(source.contains("Button(\"Quit Sloppy\""))
        #expect(source.contains("applicationShouldTerminateAfterLastWindowClosed"))
        #expect(source.contains("openWindow(id: \"main\")"))
    }
}
