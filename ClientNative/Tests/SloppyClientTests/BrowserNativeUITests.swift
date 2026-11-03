#if os(macOS)
import AppKit
import SwiftUI
import Testing
import WebKit
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser fullscreen availability", .serialized, .appKitIsolation)
@MainActor
struct BrowserFullscreenAvailabilityTests {
    @Test(arguments: [false, true])
    func enablesTheRealFullscreenAPIForOwnedAndSuppliedPages(supplied: Bool) async throws {
        let view = supplied ? WKWebView(frame: .zero, configuration: WKWebViewConfiguration()) : nil
        let runtime = WorkspaceBrowserToolRuntime(webView: view)
        for name in ["webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:",
                     "webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:",
                     "webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:",
                     "webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:", "webViewDidClose:"] {
            #expect(runtime.responds(to: NSSelectorFromString(name)))
        }
        runtime.webView.loadHTMLString("<!doctype html><video></video>", baseURL: nil)
        _ = try await runtime.read()
        #expect(try await runtime.evaluate(expression: "document.fullscreenEnabled") == .bool(true))
        #expect(try await runtime.evaluate(expression: "typeof document.querySelector('video').requestFullscreen") == .string("function"))
    }
}

@Suite("Browser native page UI", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserNativeUITests {
    @Test func javascriptDialogsReturnTheActualUserChoiceAndText() async throws {
        let server = try BrowserHTTPFixture(responseDelay: 0)
        let url = try await server.start()
        let runtime = WorkspaceBrowserToolRuntime()
        try server.allowHTTP(in: runtime)
        let window = show(runtime)
        defer { runtime.stop(); window.close() }
        _ = try await runtime.open(url: url.absoluteString)

        let alert = Task { @MainActor in try await runtime.webView.evaluateJavaScript("alert('Notice'); true") as? Bool }
        try await wait { runtime.pageUI.sheet != nil }
        #expect(textFields(runtime.pageUI.sheet?.contentView).contains { $0.stringValue.contains("127.0.0.1") })
        try press("OK", in: runtime)
        #expect(try await alert.value == true)
        for accepted in [true, false] {
            let result = Task { @MainActor in try await runtime.webView.evaluateJavaScript("confirm('Continue?')") as? Bool }
            try await wait { runtime.pageUI.sheet != nil }
            try press(accepted ? "OK" : "Cancel", in: runtime)
            #expect(try await result.value == accepted)
        }
        let prompt = Task { @MainActor in try await runtime.webView.evaluateJavaScript("prompt('Name', 'Initial value')") as? String }
        try await wait { runtime.pageUI.sheet != nil }
        let field = try #require(textFields(runtime.pageUI.sheet?.contentView).first { $0.isEditable })
        #expect(field.stringValue == "Initial value")
        field.stringValue = "Привет 👋"
        try press("OK", in: runtime)
        #expect(try await prompt.value == "Привет 👋")
        let cancelled = Task { @MainActor in try await runtime.webView.evaluateJavaScript("prompt('Name', 'Initial')") as? String }
        try await wait { runtime.pageUI.sheet != nil }
        try press("Cancel", in: runtime)
        #expect(try await cancelled.value == nil)
    }

    @Test func stoppingOrClosingThePageCancelsItsPendingDialogOnce() async throws {
        for closesWindow in [false, true] {
            let runtime = WorkspaceBrowserToolRuntime()
            let window = show(runtime)
            defer { runtime.stop(); window.close() }
            runtime.webView.loadHTMLString("<!doctype html><body>Dialog cancellation</body>", baseURL: nil)
            _ = try await runtime.read()
            let result = Task { @MainActor in try await runtime.webView.evaluateJavaScript("confirm('Continue?')") as? Bool }
            try await wait { runtime.pageUI.sheet != nil }
            if closesWindow { window.close() } else { runtime.stop() }
            #expect(try await result.value == false)
            #expect(runtime.pageUI.sheet == nil)
            runtime.pageUI.cancel()
        }
    }

    @Test func fileUploadUsesTheNativePanelAndHonorsInputOptions() async throws {
        let runtime = WorkspaceBrowserToolRuntime()
        let panel = BrowserTestOpenPanel()
        runtime.pageUI.makeOpenPanel = { panel }
        let window = show(runtime)
        defer { runtime.stop(); window.close() }
        runtime.webView.loadHTMLString("<!doctype html><input id='file' type='file' multiple><input id='folder' type='file' webkitdirectory>", baseURL: nil)
        _ = try await runtime.read()
        for (id, directories, multiple) in [("file", false, true), ("folder", true, false)] {
            try await click("#\(id)", in: runtime)
            try await wait { runtime.pageUI.sheet != nil }
            #expect(runtime.pageUI.sheet === panel)
            #expect(panel.canChooseDirectories == directories)
            #expect(panel.canChooseFiles == !directories)
            #expect(panel.allowsMultipleSelection == multiple)
            #expect(!panel.canCreateDirectories)
            panel.cancel(nil)
            try await wait { runtime.pageUI.sheet == nil }
            #expect(try await runtime.evaluate(expression: "document.querySelector('#\(id)').files.length") == .number(0))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("upload.txt")
        try Data("Uploaded through WebKit".utf8).write(to: file)
        try await click("#file", in: runtime)
        try await wait { runtime.pageUI.sheet != nil }
        panel.selection = [file]
        panel.respond(.OK)
        try await wait { (try? await runtime.evaluate(expression: "document.querySelector('#file').files.length")) == .number(1) }
        let text = try await runtime.webView.callAsyncJavaScript("return await document.querySelector('#file').files[0].text()", arguments: [:], in: nil, contentWorld: .page) as? String
        #expect(text == "Uploaded through WebKit")
    }

    @Test func oauthPopupRetainsOpenerCookiesAndClosesWithoutReplacingThePage() async throws {
        let server = try BrowserHTTPFixture(responseDelay: 0, html: "<!doctype html><title>Original page</title><script>window.received = ''; addEventListener('message', e => { if (e.origin === location.origin) window.received = e.data; });</script>")
        let url = try await server.start()
        let runtime = WorkspaceBrowserToolRuntime()
        try server.allowHTTP(in: runtime)
        let window = show(runtime)
        defer { runtime.stop(); window.close() }
        _ = try await runtime.open(url: url.absoluteString)
        _ = try await runtime.webView.evaluateJavaScript("document.cookie='sloppyOAuth=shared; path=/'; window.oauth = window.open('about:blank', 'sloppy-oauth', 'width=540,height=420'); true")
        try await wait { runtime.popupWindows.count == 1 }
        let popup = try #require(runtime.popupWindows.values.first)
        let child = popup.runtime
        #expect(await runtime.safeToDiscard(at: .now.addingTimeInterval(120)) == false)
        _ = try await child.read()
        #expect(try await runtime.evaluate(expression: "oauth !== null && oauth.opener === window") == .bool(true))
        _ = try await child.open(url: url.appendingPathComponent("oauth-callback").absoluteString)
        #expect(try await child.evaluate(expression: "document.cookie.includes('sloppyOAuth=shared')") == .bool(true))
        _ = try await child.webView.evaluateJavaScript("window.opener.postMessage('oauth-complete', location.origin); window.close(); true")
        try await wait { runtime.popupWindows.isEmpty }
        try await wait { (try? await runtime.evaluate(expression: "window.received")) == .string("oauth-complete") }
        #expect(runtime.webView.url == url)
        #expect(try await runtime.evaluate(expression: "oauth.closed") == .bool(true))
    }

    @Test(.enabled(if: Bundle.main.bundleURL.pathExtension == "app",
                   "Fullscreen transitions require an active app-bundle runner."))
    func swiftUIPageKeepsItsViewportWhenEnteringAndLeavingFullscreen() async throws {
        NSApp.finishLaunching()
        let model = WorkspaceWebViewModel()
        let runtime = model.ensureBrowserRuntime()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: WorkspaceWebView(viewModel: model).frame(width: 1000, height: 700))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.contentView?.layoutSubtreeIfNeeded()
        defer { runtime.stop(); window.close() }
        runtime.webView.loadHTMLString("<!doctype html><button id='target' onclick='this.requestFullscreen()'>Fullscreen</button>", baseURL: nil)
        _ = try await runtime.read()
        try await wait {
            guard runtime.webView.window === window else { return false }
            return (try? await runtime.evaluate(expression: "document.visibilityState")) == .string("visible")
        }
        let original = runtime.webView.bounds.size
        #expect(original.width > 500 && original.height > 300)
        let entered = try await runtime.webView.callAsyncJavaScript("await document.querySelector('#target').requestFullscreen(); return document.fullscreenElement !== null", arguments: [:], in: nil, contentWorld: .page) as? Bool
        #expect(entered == true)
        try await wait { runtime.webView.fullscreenState == .inFullscreen }
        #expect(try await runtime.evaluate(expression: "innerWidth > 500 && innerHeight > 300 && document.fullscreenElement.id === 'target'") == .bool(true))
        _ = try await runtime.webView.evaluateJavaScript("document.exitFullscreen(); true")
        try await wait { runtime.webView.fullscreenState == .notInFullscreen }
        try await Task.sleep(for: .milliseconds(300))
        #expect(abs(runtime.webView.bounds.width - original.width) < 2)
        #expect(abs(runtime.webView.bounds.height - original.height) < 2)
        #expect(runtime.webView.superview is BrowserWebViewHost)
    }

    private func show(_ runtime: WorkspaceBrowserToolRuntime) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 650),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = BrowserWebViewHost(webView: runtime.webView)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func click(_ selector: String, in runtime: WorkspaceBrowserToolRuntime) async throws {
        _ = try await runtime.webView.evaluateJavaScript("document.querySelector('\(selector)').click(); true")
    }

    private func wait(_ condition: () async throws -> Bool) async throws {
        for _ in 0..<150 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw URLError(.timedOut)
    }

    private func descendants(_ view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { descendants($0) }
    }
    private func textFields(_ view: NSView?) -> [NSTextField] { descendants(view).compactMap { $0 as? NSTextField } }
    private func press(_ title: String, in runtime: WorkspaceBrowserToolRuntime) throws {
        let button = try #require(descendants(runtime.pageUI.sheet?.contentView).compactMap { $0 as? NSButton }.first { $0.title == title })
        button.performClick(nil)
    }
}

/// Swift's async test runner exits when a real NSOpenPanel stops its main
/// run loop. Keep WebKit's file selection/read path real and control only
/// the native panel response; interactive smoke checks use the app bundle.
@MainActor
private final class BrowserTestOpenPanel: NSOpenPanel {
    var selection: [URL] = []
    private var reply: ((NSApplication.ModalResponse) -> Void)?
    override var urls: [URL] { selection }
    override func beginSheetModal(for window: NSWindow, completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) { reply = handler }
    override func cancel(_ sender: Any?) { respond(.cancel) }
    func respond(_ response: NSApplication.ModalResponse) {
        let callback = reply
        reply = nil
        callback?(response)
    }
}
#endif
