#if os(macOS)
import Foundation
import AppKit
import SwiftUI
import Testing
import WebKit
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser extension runtime", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserExtensionRuntimeTests {
    @Test func injectsOnlyAfterGrantAndPopupCanOpenABrowserTab() async throws {
        let name = "BrowserExtensionRuntimeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: folder)
        }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let origin = "http://127.0.0.1/*"
        let destination = url.appendingPathComponent("extension-created")
        let manifest: [String: Any] = [
            "manifest_version": 3, "name": "Sloppy Browser Check", "version": "1.0",
            "permissions": ["tabs", "storage"], "host_permissions": [origin],
            "content_scripts": [["matches": [origin], "js": ["content.js"]]],
            "action": ["default_popup": "popup.html"]
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        try Data("document.documentElement.dataset.extensionVerified = 'yes';".utf8)
            .write(to: folder.appendingPathComponent("content.js"))
        try Data("<html><body><p id='status'>Loading</p><button id='open'>Open tab</button><script src='popup.js'></script></body></html>".utf8)
            .write(to: folder.appendingPathComponent("popup.html"))
        let quotedURL = String(decoding: try JSONEncoder().encode(destination.absoluteString), as: UTF8.self)
        try Data("""
        browser.tabs.query({active:true,currentWindow:true}).then(tabs => document.getElementById('status').textContent = tabs[0]?.title || 'No active tab');
        document.getElementById('open').onclick = () => browser.tabs.create({url:\(quotedURL)});
        """.utf8).write(to: folder.appendingPathComponent("popup.js"))

        let state = BrowserWorkspaceState(defaults: defaults)
        state.open(url, inNewTab: true)
        let page = try #require(state.selectedPage)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1200, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in }))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        await state.extensions.restore()
        try await state.extensions.importExtensions(at: folder)
        let record = try #require(state.extensions.records.first)
        state.extensions.setEnabled(true, id: record.id)
        let runtime = page.ensureBrowserRuntime()
        _ = try await runtime.open(url: url.absoluteString)
        #expect(try await runtime.webView.evaluateJavaScript("document.documentElement.dataset.extensionVerified") as? String == nil)
        state.extensions.setPermission(origin, allowed: true, id: record.id, website: true)
        state.extensions.setPermission("tabs", allowed: true, id: record.id, website: false)
        _ = try await runtime.open(url: url.absoluteString)
        try await waitUntil {
            try await runtime.webView.evaluateJavaScript("document.documentElement.dataset.extensionVerified") as? String == "yes"
        }
        #expect(runtime.webView.configuration.webExtensionController === state.extensions.controller)
        let context = try #require(state.extensions.contexts[record.id])
        let id = try #require(state.selectedID)
        let tab = try #require(state.extensionBridge?.tab(id))
        #expect(tab.webView(for: context) === runtime.webView)
        let action = try #require(context.action(for: tab))
        state.extensionBridge?.performAction(record.id)
        defer { action.closePopup() }
        try await waitUntil {
            guard let popup = action.popupWebView else { return false }
            return try await popup.evaluateJavaScript("document.getElementById('status')?.textContent") as? String == "Loaded through HTTP"
        }
        let popup = try #require(action.popupWebView)
        _ = try await popup.evaluateJavaScript("document.getElementById('open').click()")
        try await waitUntil { state.tabs.count == 2 }
        #expect(state.selectedTab?.url == destination)
        state.extensions.setEnabled(false, id: record.id)
        _ = try await runtime.open(url: url.absoluteString)
        #expect(try await runtime.webView.evaluateJavaScript("document.documentElement.dataset.extensionVerified") as? String == nil)
    }

    private func waitUntil(_ predicate: @MainActor () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while try await !predicate() {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
#endif
