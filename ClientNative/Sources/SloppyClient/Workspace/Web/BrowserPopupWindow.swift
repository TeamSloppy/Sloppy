#if os(macOS)
import AppKit
import WebKit

@MainActor
final class BrowserPopupWindow: NSWindowController, NSWindowDelegate {
    let runtime: WorkspaceBrowserToolRuntime
    var onClose: (() -> Void)?

    init(configuration: WKWebViewConfiguration, features: WKWindowFeatures, parent: WorkspaceBrowserToolRuntime) {
        // Return a view made with WebKit's supplied configuration. It carries the
        // related browsing context, opener, process pool and cookie store for OAuth.
        // Page message handlers belong to one runtime. Reusing the opener's
        // controller would register duplicate handlers and mix page activity.
        configuration.userContentController = WKUserContentController()
        let view = WorkspaceBrowserWebView(frame: .zero, configuration: configuration)
        runtime = WorkspaceBrowserToolRuntime(webView: view, contentBlocker: parent.contentBlocker,
                                              sitePermissions: parent.sitePermissions)
        runtime.onDownload = parent.onDownload
        runtime.onOpenLinkInNewTab = parent.onOpenLinkInNewTab
        runtime.navigationBlock = parent.navigationBlock
        let size = NSSize(width: min(1200, max(400, features.width?.doubleValue ?? 720)),
                          height: min(900, max(300, features.height?.doubleValue ?? 640)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "New Window"
        window.contentView = BrowserWebViewHost(webView: view)
        window.center()
        super.init(window: window)
        window.delegate = self
        runtime.onCloseWindow = { [weak self] in self?.close() }
        runtime.onStateChange = { [weak window] view, _ in
            window?.title = view.title ?? "New Window"
            window?.subtitle = view.url?.host ?? ""
        }
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        runtime.stop()
        onClose?()
        onClose = nil
    }
}

extension WorkspaceBrowserToolRuntime {
    @objc func webViewDidClose(_ webView: WKWebView) { onCloseWindow?() }
}
#endif
