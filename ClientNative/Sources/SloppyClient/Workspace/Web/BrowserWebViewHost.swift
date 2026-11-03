#if os(macOS)
import AppKit
import WebKit

/// SwiftUI constrains the host; WebKit can move its view into the fullscreen
/// window and back without constraints from outside its immediate parent.
@MainActor
final class BrowserWebViewHost: NSView {
    let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: webView.frame)
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        webView.frame = bounds
        addSubview(webView)
    }

    required init?(coder: NSCoder) { nil }
}
#endif
