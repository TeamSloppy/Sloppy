#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import ScreenCaptureKit
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser sidebar modes", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserSidebarModeRenderingTests {
    @Test func footerIconsAndCommandNumbersSwitchOnlyTheSidebar() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserSidebarModes.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        state.open(url, inNewTab: true)
        let tab = try #require(state.selectedID)
        let page = try #require(state.selectedPage)
        let host = NSHostingView(rootView: BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
            .theme(.sloppyDark).preferredColorScheme(.dark).environment(\.scenePhase, .active))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        let deadline = ContinuousClock.now + .seconds(10)
        while page.currentURL == nil || page.isLoading {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(50))
        }
        let webView = try #require(page.nativeWebView)
        _ = try await webView.evaluateJavaScript("document.querySelector('#name').value = 'Keep my page draft'")
        let originalBounds = webView.bounds

        for mode in BrowserSidebarMode.allCases {
            let button = try #require(AppKitTestAccessibility.element(in: host, identifier: "browser-sidebar-mode-\(mode.rawValue)"))
            #expect(AppKitTestAccessibility.press(button))
            #expect(state.sidebarMode == mode)
            #expect(window.sheets.isEmpty)
            #expect(state.selectedID == tab)
            #expect(state.selectedPage === page)
            try await Task.sleep(for: .milliseconds(100))
            #expect(abs(webView.bounds.width - originalBounds.width) < 2)
        }

        for (mode, keyCode) in zip(BrowserSidebarMode.allCases, [UInt16(18), 19, 20, 21]) {
            window.makeFirstResponder(webView)
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: String(mode.shortcut), charactersIgnoringModifiers: String(mode.shortcut), isARepeat: false, keyCode: keyCode))
            #expect(host.performKeyEquivalent(with: event))
            #expect(state.sidebarMode == mode)
            #expect(window.sheets.isEmpty)
        }
        #expect(try await webView.evaluateJavaScript("document.querySelector('#name').value") as? String == "Keep my page draft")
        #expect(state.tabs.count == 1)
        state.sidebarMode = .time
        try await Task.sleep(for: .milliseconds(200))
        try await screenshot(host, path: "/tmp/sloppy-sidebar-time.png")
    }

    @Test func switchingModesRetainsTheInlineNoteEditor() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserSidebarNoteModes.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        state.open(url, inNewTab: true)
        let noteID = state.organizer.createNote()
        state.sidebarDrafts.noteSelection = noteID
        let host = NSHostingView(rootView: BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
            .theme(.sloppyDark).preferredColorScheme(.dark).environment(\.scenePhase, .active))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))
        let notes = try #require(AppKitTestAccessibility.element(in: host, identifier: "browser-sidebar-mode-notes"))
        #expect(AppKitTestAccessibility.press(notes))
        #expect(state.sidebarMode == .notes)
        try await Task.sleep(for: .milliseconds(250))
        func editor(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.isEditable, !text.isFieldEditor { return text }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let text = try #require(editor(in: host))
        window.makeFirstResponder(text)
        text.insertText("Sidebar draft\n- [ ] Keep this task", replacementRange: NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(100))
        let id = try #require(state.organizer.notes.first?.id)
        for (mode, code) in [(BrowserSidebarMode.tasks, UInt16(20)), (.notes, UInt16(21))] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: String(mode.shortcut), charactersIgnoringModifiers: String(mode.shortcut), isARepeat: false, keyCode: code))
            #expect(host.performKeyEquivalent(with: event))
            #expect(state.sidebarMode == mode)
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(100))
        let restoredEditor = try #require(editor(in: host))
        #expect(restoredEditor.string == "Sidebar draft\n- [ ] Keep this task")
        #expect(state.organizer.note(id)?.body == restoredEditor.string)
        #expect(state.sidebarDrafts.noteSelection == id)
        #expect(window.sheets.isEmpty)
        #expect(restoredEditor.window === window)
        try await screenshot(host, path: "/tmp/sloppy-sidebar-notes.png")
    }

    private func screenshot(_ host: NSView, path: String) async throws {
        if CGPreflightScreenCaptureAccess(), let window = host.window {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            if let own = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
                let configuration = SCStreamConfiguration()
                configuration.width = Int(window.frame.width * window.backingScaleFactor)
                configuration.height = Int(window.frame.height * window.backingScaleFactor)
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: own), configuration: configuration)
                try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: path))
                return
            }
        }
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
