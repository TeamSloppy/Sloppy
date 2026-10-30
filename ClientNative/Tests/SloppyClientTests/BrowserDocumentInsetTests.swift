#if os(macOS)
import Foundation
import AppKit
import WebKit
import Testing
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser document inset", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserDocumentInsetTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_BROWSER_LAYOUT_SMOKE_URL"] != nil,
                   "Optional live page layout check"))
    func livePageHeaderStartsBelowTheDocumentInset() async throws {
        let address = try #require(ProcessInfo.processInfo.environment["SLOPPY_BROWSER_LAYOUT_SMOKE_URL"])
        let runtime = WorkspaceBrowserToolRuntime()
        let window = show(runtime)
        defer { window.close() }
        runtime.documentInset.update(96)
        _ = try await runtime.open(url: address)
        for width in [1000.0, 1700.0] {
            window.setContentSize(NSSize(width: width, height: 750))
            try await Task.sleep(for: .milliseconds(350))
            let result = try await runtime.webView.evaluateJavaScript("""
        (() => {
          const header = [...document.querySelectorAll('header')].find(node => node.getClientRects().length > 0);
          if (!header) throw new Error('No visible page header');
          const controls = [...header.querySelectorAll('a, button')].filter(node => {
            const r = node.getBoundingClientRect();
            const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
            return r.width > 0 && r.height > 0 && hit && node.contains(hit);
          });
          return {padding: parseFloat(getComputedStyle(document.documentElement).paddingTop),
                  header: header.getBoundingClientRect().top, controls: controls.length,
                  controlTop: Math.min(...controls.map(node => node.getBoundingClientRect().top))};
        })()
        """)
            let values = try #require(result as? [String: Double])
            #expect(try #require(values["padding"]) >= 96)
            #expect(try #require(values["header"]) >= 95)
            #expect(try #require(values["controls"]) > 0)
            #expect(try #require(values["controlTop"]) >= 95)
            if let directory = ProcessInfo.processInfo.environment["SLOPPY_BROWSER_SCREENSHOTS"] {
                try await runtime.screenshot().imageData.write(to: URL(fileURLWithPath: directory).appendingPathComponent("live-document-inset-\(Int(width)).png"))
            }
        }
    }

    @Test func documentFlowAndViewportHeadersStayBelowTheChrome() async throws {
        let server = try BrowserHTTPFixture(html: Self.html)
        let url = try await server.start()
        let runtime = WorkspaceBrowserToolRuntime()
        let window = show(runtime)
        defer { window.close() }
        runtime.documentInset.update(96)
        _ = try await runtime.open(url: url.absoluteString)
        try await settle()
        let first = try await geometry(runtime.webView)
        #expect(first["padding"] == 108)
        #expect(first["fixed"] == 96)
        #expect(try #require(first["flow"]) >= 108)
        #expect(try #require(first["sticky"]) >= 96)
        #expect(first["nestedTop"] == 0)
        #expect(first["localMargin"] == 0)
        #expect(first["overlayMargin"] == 0)
        _ = try await runtime.webView.evaluateJavaScript("window.scrollTo(0, 500)")
        try await settle()
        let scrolled = try await geometry(runtime.webView)
        #expect(scrolled["fixed"] == 96)
        #expect(scrolled["sticky"] == 96)
        runtime.documentInset.refresh()
        try await settle()
        #expect(try await geometry(runtime.webView)["padding"] == 108)
    }

    @Test func dynamicHeadersResizeAndRemovalPreserveSiteStylesAndFormInput() async throws {
        let server = try BrowserHTTPFixture(html: Self.html)
        let url = try await server.start()
        let runtime = WorkspaceBrowserToolRuntime()
        let window = show(runtime)
        defer { window.close() }
        runtime.documentInset.update(96)
        _ = try await runtime.open(url: url.absoluteString)
        _ = try await runtime.webView.evaluateJavaScript("""
        document.querySelector('input').value = 'Retained draft';
        document.documentElement.style.paddingTop = '20px';
        const header = document.createElement('div');
        header.id = 'dynamic';
        header.style.cssText = 'position:fixed;top:4px;margin-top:3px;height:20px';
        document.body.append(header);
        """)
        try await settle()
        #expect(try await number(runtime.webView, "getComputedStyle(document.documentElement).paddingTop") == 116)
        #expect(try await number(runtime.webView, "document.querySelector('#dynamic').getBoundingClientRect().top") == 103)
        runtime.documentInset.update(144)
        try await settle()
        #expect(try await number(runtime.webView, "getComputedStyle(document.documentElement).paddingTop") == 164)
        #expect(try await number(runtime.webView, "document.querySelector('#dynamic').getBoundingClientRect().top") == 151)
        _ = try await runtime.webView.evaluateJavaScript("document.querySelector('#dynamic').style.marginTop='7px'")
        try await settle()
        #expect(try await number(runtime.webView, "document.querySelector('#dynamic').getBoundingClientRect().top") == 155)
        runtime.documentInset.update(0)
        try await settle()
        #expect(try await number(runtime.webView, "getComputedStyle(document.documentElement).paddingTop") == 20)
        #expect(try await number(runtime.webView, "getComputedStyle(document.documentElement).scrollPaddingTop") == 4)
        #expect(try await number(runtime.webView, "getComputedStyle(document.querySelector('#dynamic')).marginTop") == 7)
        #expect(try await number(runtime.webView, "getComputedStyle(document.querySelector('#sticky')).top") == 0)
        #expect(try await runtime.webView.evaluateJavaScript("document.querySelector('input').value") as? String == "Retained draft")
    }

    @Test func navigationCspAndOtherOwnersScriptsRemainIntact() async throws {
        let server = try BrowserHTTPFixture(contentSecurityPolicy: "default-src 'none'; script-src 'none'; style-src 'none'", html: "<title>Inset CSP</title><p>Content</p>")
        let url = try await server.start()
        let runtime = WorkspaceBrowserToolRuntime()
        let window = show(runtime)
        defer { window.close() }
        let sentinel = WKUserScript(source: "globalThis.layoutSentinel = (globalThis.layoutSentinel || 0) + 1;",
                                    injectionTime: .atDocumentStart, forMainFrameOnly: true)
        runtime.webView.configuration.userContentController.addUserScript(sentinel)
        runtime.documentInset.update(96)
        runtime.documentInset.update(112)
        for path in ["one", "two"] {
            _ = try await runtime.open(url: url.appendingPathComponent(path).absoluteString)
            try await settle()
            #expect(try await number(runtime.webView, "getComputedStyle(document.documentElement).paddingTop") == 112)
            #expect(try await runtime.webView.evaluateJavaScript("globalThis.layoutSentinel") as? Int == 1)
        }
        #expect(runtime.webView.configuration.userContentController.userScripts.count == 2)
        runtime.documentInset.update(0)
        #expect(runtime.webView.configuration.userContentController.userScripts.count == 1)
        #expect(runtime.webView.configuration.userContentController.userScripts.first === sentinel)
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(150)) }

    private func show(_ runtime: WorkspaceBrowserToolRuntime) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 750),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = runtime.webView
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func number(_ webView: WKWebView, _ expression: String) async throws -> Double? {
        try await webView.evaluateJavaScript("parseFloat(\(expression))") as? Double
    }

    private func geometry(_ webView: WKWebView) async throws -> [String: Double] {
        let result = try await webView.evaluateJavaScript("""
        ({padding: parseFloat(getComputedStyle(document.documentElement).paddingTop),
          fixed: document.querySelector('#fixed').getBoundingClientRect().top,
          flow: document.querySelector('#flow').getBoundingClientRect().top,
          sticky: document.querySelector('#sticky').getBoundingClientRect().top,
          nestedTop: parseFloat(getComputedStyle(document.querySelector('#nested')).top),
          localMargin: parseFloat(getComputedStyle(document.querySelector('#local')).marginTop),
          overlayMargin: parseFloat(getComputedStyle(document.querySelector('#overlay')).marginTop)})
        """)
        return try #require(result as? [String: Double])
    }

    private static let html = """
    <!doctype html><html style="padding-top:12px;scroll-padding-top:4px"><head><title>Inset fixture</title>
    <style>body{margin:0;min-height:2400px}#fixed{position:fixed;top:0;height:24px}#sticky{position:sticky;top:0;height:28px}
    #scroller{height:100px;overflow:auto}#nested{position:sticky;top:0}#transformed{transform:translateZ(0)}#local{position:fixed;top:0}
    #overlay{position:fixed;top:0}</style></head><body><div id="fixed">Fixed</div><div id="sticky">Sticky</div>
    <p id="flow">Document content</p><input><div id="scroller"><div id="nested">Nested sticky</div><p style="height:400px"></p></div>
    <div id="transformed"><div id="local">Local fixed</div></div><div id="overlay" data-sloppy-browser-overlay="test">Browser UI</div>
    </body></html>
    """
}
#endif
