#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Work and Browse shortcut", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct WorkBrowseShortcutTests {
    @Test func pageShortcutsZoomAndNavigateWithFocusInsideWebKit() async throws {
        let name = "BrowserPageShortcuts.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture(responseDelay: 0)
        let url = try await server.start()
        let state = BrowserWorkspaceState(defaults: defaults)
        try server.allowHTTP(in: state)
        state.open(url.appendingPathComponent("first"), inNewTab: true)
        let page = try #require(state.selectedPage)
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
                .overlay {
                    // These are the same buttons installed in the scene's menu.
                    BrowserPageCommandButtons(workspace: state)
                        .opacity(0.001).allowsHitTesting(false)
                })
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.makeKeyAndOrderFront(nil)
        defer { window.contentViewController = nil; window.close() }
        let runtime = page.ensureBrowserRuntime()
        _ = try await runtime.open(url: url.appendingPathComponent("first").absoluteString)
        _ = try await runtime.open(url: url.appendingPathComponent("second").absoluteString)
        try await Task.sleep(for: .milliseconds(200))
        let webView = try #require(page.nativeWebView)
        _ = try await webView.evaluateJavaScript("document.querySelector('#name').value='Keep my input'; document.querySelector('#name').focus()")
        window.makeFirstResponder(webView)
        #expect(page.canGoBack)
        #expect(!page.canGoForward)
        let initialWidth = try #require(try await webView.evaluateJavaScript("innerWidth") as? NSNumber).doubleValue

        func key(_ characters: String, code: UInt16, shifted: Bool = false, ignoring: String? = nil) throws -> Bool {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: shifted ? [.command, .shift] : [.command],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: ignoring ?? characters,
                isARepeat: false, keyCode: code))
            return controller.view.performKeyEquivalent(with: event)
        }

        #expect(try key("=", code: 24))
        #expect(abs(webView.pageZoom - 1.1) < 0.001)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try #require(try await webView.evaluateJavaScript("innerWidth") as? NSNumber).doubleValue < initialWidth)
        #expect(try key("-", code: 27))
        #expect(webView.pageZoom == 1)
        #expect(try key("+", code: 24, shifted: true, ignoring: "="))
        #expect(abs(webView.pageZoom - 1.1) < 0.001)
        #expect(try key("+", code: 69))
        #expect(webView.pageZoom == 1.25)
        #expect(try key("0", code: 29))
        #expect(webView.pageZoom == 1)
        #expect(try await webView.evaluateJavaScript("document.querySelector('#name').value") as? String == "Keep my input")

        // Zooming the selected tab must not change another retained tab.
        let originalID = try #require(state.selectedID)
        #expect(try key("=", code: 24))
        state.open(url.appendingPathComponent("other"), inNewTab: true)
        let other = try #require(state.selectedPage)
        _ = other.ensureBrowserRuntime()
        #expect(other.nativeWebView?.pageZoom == 1)
        state.select(originalID)
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.selectedPage?.nativeWebView === webView)
        #expect(abs(webView.pageZoom - 1.1) < 0.001)
        window.makeFirstResponder(webView)
        #expect(try key("[", code: 33))
        for _ in 0..<100 where webView.url?.lastPathComponent != "first" || page.isLoading || !page.canGoForward {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(webView.url?.lastPathComponent == "first")
        #expect(page.canGoForward)
        #expect(try key("]", code: 30))
        for _ in 0..<100 where webView.url?.lastPathComponent != "second" || page.isLoading {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(webView.url?.lastPathComponent == "second")

        state.isBrowsing = false
        for command in BrowserPageCommand.allCases {
            #expect(!command.isEnabled(in: state))
            command.perform(in: state)
        }
        #expect(abs(webView.pageZoom - 1.1) < 0.001)
        #expect(webView.url?.lastPathComponent == "second")
    }

    @Test func pageZoomIsBoundedAndCommandsAreDisabledWithoutAPage() throws {
        for command in BrowserPageCommand.allCases { #expect(!command.isEnabled(in: nil)) }
        let name = "BrowserZoomBounds.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults)
        state.createBlankTab()
        let webView = try #require(state.selectedPage).ensureBrowserRuntime().webView
        for _ in 0..<30 { BrowserPageCommand.zoomIn.perform(in: state) }
        #expect(webView.pageZoom == 3)
        for _ in 0..<30 { BrowserPageCommand.zoomOut.perform(in: state) }
        #expect(webView.pageZoom == 0.5)
        BrowserPageCommand.actualSize.perform(in: state)
        #expect(webView.pageZoom == 1)
        state.showHome()
        for command in BrowserPageCommand.allCases { #expect(!command.isEnabled(in: state)) }
    }

    @Test func shortcutSwitchesBothWaysWhileEditingAndRetainsTabs() async throws {
        let name = "WorkBrowseShortcutTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        state.createBlankTab()
        let selectedID = state.selectedID
        let page = try #require(state.selectedPage)
        state.isBrowsing = false

        let host = NSHostingView(rootView: VStack {
            TextField("Draft", text: .constant("Keep my draft"))
            WorkBrowseToggleButton(workspace: state)
        })
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))

        func textField(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap { textField(in: $0) }.first
        }
        let field = try #require(textField(in: host))
        for browsing in [true, false] {
            window.makeFirstResponder(field)
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [.command, .shift], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: "B",
                charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11))
            #expect(host.performKeyEquivalent(with: event))
            #expect(state.isBrowsing == browsing)
            #expect(state.tabs.count == 1)
            #expect(state.selectedID == selectedID)
            #expect(state.selectedPage === page)
            #expect(field.stringValue == "Keep my draft")
            #expect(BrowserWorkspaceState(defaults: defaults).isBrowsing == browsing)
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
#endif
