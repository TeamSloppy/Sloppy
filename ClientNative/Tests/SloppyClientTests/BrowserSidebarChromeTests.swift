#if os(macOS)
import AppKit
import ScreenCaptureKit
import SwiftUI
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser sidebar chrome", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserSidebarChromeTests {
    @Test func scrollingContentStaysBelowTheFixedAddressBarInEveryMode() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserSidebarChrome.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        try server.allowHTTP(in: state)
        for index in 0..<80 { state.open(url.appendingPathComponent("page-\(index)"), inNewTab: true) }
        let note = state.organizer.createNote()
        state.organizer.updateNote(note) { $0.body = Array(repeating: "Long note content", count: 100).joined(separator: "\n") }
        state.sidebarDrafts.noteSelection = note
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
                .theme(.sloppyDark).preferredColorScheme(.dark).frame(minWidth: 1120, minHeight: 760))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 820),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "browser-sidebar-chrome-test")
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1200, height: 820))
        window.makeKeyAndOrderFront(nil)
        defer { window.contentViewController = nil; window.close() }
        try await Task.sleep(for: .milliseconds(500))

        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        func addressFrame() throws -> NSRect {
            let address = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-address"))
            return window.convertFromScreen(try #require(AppKitTestAccessibility.frame(of: address)))
        }
        let initialAddress = try addressFrame()
        let table = try #require(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
        let scroll = try #require(table.enclosingScrollView)
        let sidebarRight = scroll.convert(scroll.bounds, to: nil).maxX
        #expect(scroll.convert(scroll.bounds, to: nil).maxY <= initialAddress.minY)
        try await screenshot(window, name: "top")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: 35).minY))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(150))
        #expect(scroll.documentVisibleRect.minY > 0)
        #expect(abs(try addressFrame().minY - initialAddress.minY) < 1)
        #expect(scroll.convert(scroll.bounds, to: nil).maxY <= initialAddress.minY)
        try await screenshot(window, name: "scrolled")

        for mode in [BrowserSidebarMode.time, .tasks, .notes] {
            state.sidebarMode = mode
            try await Task.sleep(for: .milliseconds(150))
            let address = try addressFrame()
            #expect(abs(address.minY - initialAddress.minY) < 1)
            let sidebarScrolls = descendants(controller.view).compactMap { $0 as? NSScrollView }.filter {
                let frame = $0.convert($0.bounds, to: nil)
                return $0.window === window && frame.width > 100 && frame.height > 30 && frame.midX < sidebarRight
            }
            #expect(!sidebarScrolls.isEmpty)
            for scroll in sidebarScrolls {
                #expect(scroll.convert(scroll.bounds, to: nil).maxY <= address.minY)
            }
            try await screenshot(window, name: mode.rawValue)
        }
    }

    private func screenshot(_ window: NSWindow, name: String) async throws {
        guard CGPreflightScreenCaptureAccess() else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let own = try #require(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * window.backingScaleFactor)
        configuration.height = Int(window.frame.height * window.backingScaleFactor)
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: own), configuration: configuration)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/sloppy-sidebar-chrome-\(name).png"))
    }
}
#endif
