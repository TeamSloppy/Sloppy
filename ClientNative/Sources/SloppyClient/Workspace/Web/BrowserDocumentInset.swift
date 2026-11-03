#if os(macOS)
import Foundation
import OSLog
import WebKit

@MainActor
final class BrowserDocumentInset {
    private static let marker = "// SloppyBrowserDocumentInset\n"
    static let world = WKContentWorld.world(name: "SloppyBrowserDocumentInset")
    private static let script: String = {
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle.main
#endif
        guard let url = bundle.url(forResource: "BrowserDocumentInset", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            Logger(subsystem: "team.sloppy.client", category: "browser-layout").error("BrowserDocumentInset.js is missing")
            return ""
        }
        return source
    }()

    private weak var webView: WKWebView?
    private(set) var inset: CGFloat = 0
    private var zoom: CGFloat = 1
    private var zoomObservation: NSKeyValueObservation?

    init(webView: WKWebView) {
        self.webView = webView
        zoomObservation = webView.observe(\.pageZoom, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, inset > 0 else { return }
                update(inset)
            }
        }
    }

    func update(_ value: CGFloat) {
        let value = value.isFinite ? max(0, value) : 0
        guard let webView else { return }
        let scale = max(0.01, webView.pageZoom)
        guard value != inset || zoom != scale else { return }
        inset = value
        zoom = scale
        let controller = webView.configuration.userContentController
        let scripts = controller.userScripts.filter { !$0.source.hasPrefix(Self.marker) }
        // WebKit only exposes bulk removal. Retain the original objects, worlds
        // and order of every other owner's scripts when replacing our script.
        controller.removeAllUserScripts()
        for script in scripts { controller.addUserScript(script) }
        if value > 0 {
            controller.addUserScript(WKUserScript(source: source(), injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true, in: Self.world))
        }
        refresh()
    }

    func refresh() {
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            let source = inset > 0 ? self.source() : "globalThis.__sloppyBrowserDocumentInset?.setInset(0); true;"
            _ = try? await webView.evaluateJavaScript(source, in: nil, contentWorld: Self.world)
        }
    }

    private func source() -> String {
        // Insets arrive in window points; the injected page styles use CSS pixels.
        Self.marker + Self.script.replacingOccurrences(of: "__SLOPPY_DOCUMENT_INSET__", with: String(Double(inset / zoom)))
    }
}
#endif
