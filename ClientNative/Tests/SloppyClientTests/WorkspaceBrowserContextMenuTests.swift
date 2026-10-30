#if os(macOS)
import AppKit
import CoreImage
import Testing
import SloppyUITestSupport
import WebKit
@testable import SloppyClient

@Suite("Browser context menu", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct WorkspaceBrowserContextMenuTests {
    @Test func rightClickBuildsTheNativePageMenu() async throws {
        let server = try BrowserHTTPFixture(responseDelay: 0)
        let url = try await server.start()
        let view = ContextMenuCaptureWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 750), configuration: WKWebViewConfiguration())
        let runtime = WorkspaceBrowserToolRuntime(webView: view)
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        _ = try await runtime.open(url: url.absoluteString)
        let point = NSPoint(x: 500, y: 500)
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: view.convert(point, to: nil),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let target = try #require(view.hitTest(point))
        target.rightMouseDown(with: event)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while view.menuIdentifiers.isEmpty {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(view.menuIdentifiers.contains("sloppy.browser.context.save"))
        #expect(view.menuIdentifiers.contains("sloppy.browser.context.print"))
        #expect(view.menuIdentifiers.contains("WKMenuItemIdentifierInspectElement") || view.menuIdentifiers.contains("sloppy.browser.context.inspect"))
        #expect(view.isInspectable)
    }

    @Test func menuPreservesWebKitItemsAndDisablesUnavailableNavigation() throws {
        let runtime = WorkspaceBrowserToolRuntime()
        let view = try #require(runtime.webView as? WorkspaceBrowserWebView)
        #expect(view.isInspectable)
        let menu = NSMenu()
        let copy = NSMenuItem(title: "Copy Link", action: nil, keyEquivalent: "")
        copy.identifier = .init("native-copy-link")
        let inspect = NSMenuItem(title: "Inspect Element", action: nil, keyEquivalent: "")
        inspect.identifier = .init("WKMenuItemIdentifierInspectElement")
        let nativeReload = NSMenuItem(title: "Native reload", action: nil, keyEquivalent: "")
        nativeReload.identifier = .init("WKMenuItemIdentifierReload")
        menu.addItem(copy)
        menu.addItem(nativeReload)
        menu.addItem(inspect)
        view.prepareContextMenu(menu)
        func item(_ name: String) -> NSMenuItem? {
            menu.items.first { $0.identifier?.rawValue == "sloppy.browser.context." + name }
        }
        #expect(item("back")?.isEnabled == false)
        #expect(item("forward")?.isEnabled == false)
        #expect(item("save")?.isEnabled == false)
        #expect(item("qr")?.isEnabled == false)
        #expect(menu.items.contains { $0 === copy })
        #expect(menu.items.last === inspect)
        #expect(!menu.items.contains { $0 === nativeReload })
        let count = menu.items.count
        view.prepareContextMenu(menu)
        #expect(menu.items.count == count)
        #expect(zip(menu.items, menu.items.dropFirst()).allSatisfy { !$0.isSeparatorItem || !$1.isSeparatorItem })
    }

    @Test func loadedPageMenuNavigatesAndExportsTheCurrentDocument() async throws {
        let server = try BrowserHTTPFixture(responseDelay: 0)
        let url = try await server.start()
        let runtime = WorkspaceBrowserToolRuntime()
        _ = try await runtime.open(url: url.absoluteString)
        _ = try await runtime.open(url: url.appendingPathComponent("second").absoluteString)
        let view = try #require(runtime.webView as? WorkspaceBrowserWebView)
        let menu = NSMenu()
        view.prepareContextMenu(menu)
        let back = try #require(menu.items.first { $0.identifier?.rawValue == "sloppy.browser.context.back" })
        #expect(back.isEnabled)
        #expect(menu.items.first { $0.identifier?.rawValue == "sloppy.browser.context.translate" }?.isEnabled == false)
        let action = try #require(back.action)
        #expect(NSApp.sendAction(action, to: back.target, from: back))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while view.url?.path != "/" || view.isLoading {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(view.canGoForward)
        let actions = WorkspaceBrowserPageActions(webView: view)
        let archive = try await actions.archiveData()
        let contents = try #require(try PropertyListSerialization.propertyList(from: archive, format: nil) as? [String: Any])
        #expect(contents["WebMainResource"] != nil)
        _ = try await view.evaluateJavaScript("document.body.dataset.sourceTest='current-dom'")
        #expect(try await actions.pageSource().contains("current-dom"))
        let qr = try #require(WorkspaceBrowserPageActions.qrImage(for: url))
        let cgImage = try #require(qr.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(),
                                              options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let decoded = detector.features(in: CIImage(cgImage: cgImage)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(decoded == [url.absoluteString])
    }

    @Test func translationEncodesTheAddressAndKeepsLocalPagesOnDevice() throws {
        let original = try #require(URL(string: "https://example.com/a?q=one+two&lang=ja#heading"))
        let translated = try #require(WorkspaceBrowserPageActions.translationURL(for: original))
        let components = try #require(URLComponents(url: translated, resolvingAgainstBaseURL: false))
        #expect(components.host == "translate.google.com")
        #expect(components.queryItems?.first { $0.name == "u" }?.value == original.absoluteString)
        #expect(components.queryItems?.first { $0.name == "tl" }?.value == "ru")
        #expect(!translated.absoluteString.contains("+"))
        for address in ["http://localhost:25102", "http://127.0.0.1", "http://192.168.1.1", "http://172.16.1.1", "http://10.0.0.1", "http://office.local", "http://intranet", "file:///tmp/page.html"] {
            #expect(WorkspaceBrowserPageActions.translationURL(for: URL(string: address)) == nil)
        }
    }
}

@MainActor
private final class ContextMenuCaptureWebView: WorkspaceBrowserWebView {
    var menuIdentifiers: [String] = []
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        menuIdentifiers = menu.items.compactMap { $0.identifier?.rawValue }
        // Verify WebKit's real right-click path without leaving a modal menu tracking
        // loop or a system-owned menu window for the shared UI fixture to tear down.
        menu.removeAllItems()
    }
}
#endif
