import SwiftUI
import WebKit

/// Static, isolated viewing. Never shares the Browse session or its cookies.
struct WorkspaceHTMLPreview: View {
    let source: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        HTMLDocumentWebView(source: source, openLink: { openURL($0) })
    }
}

@MainActor
private struct HTMLDocumentWebView {
    let source: String
    let openLink: (URL) -> Void

    func makeCoordinator() -> HTMLPreviewCoordinator {
        HTMLPreviewCoordinator(openLink: openLink)
    }

    func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }

    func update(_ view: WKWebView, coordinator: HTMLPreviewCoordinator) {
        guard coordinator.source != source else { return }
        coordinator.source = source
        view.loadHTMLString(HTMLPreviewPolicy.document(source), baseURL: nil)
    }
}

#if os(macOS)
extension HTMLDocumentWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ view: WKWebView, context: Context) { update(view, coordinator: context.coordinator) }
}
#else
extension HTMLDocumentWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ view: WKWebView, context: Context) { update(view, coordinator: context.coordinator) }
}
#endif

/// CSP precedes untrusted markup, including an existing head or CSP.
enum HTMLPreviewPolicy {
    static func document(_ source: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>:root { color-scheme: light dark; } body { font: 15px -apple-system, sans-serif; margin: 20px; overflow-wrap: anywhere; } img { max-width: 100%; height: auto; } pre { overflow-x: auto; } table { border-collapse: collapse; }</style>
        </head><body>\(source)</body></html>
        """
    }

    static func isExternalLink(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "")
    }

    static func isInternalNavigation(_ url: URL) -> Bool {
        url.absoluteString == "about:blank" || url.absoluteString.hasPrefix("about:blank#")
    }
}

@MainActor
private final class HTMLPreviewCoordinator: NSObject, WKNavigationDelegate {
    var source: String?
    let openLink: (URL) -> Void

    init(openLink: @escaping (URL) -> Void) { self.openLink = openLink }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.navigationType == .linkActivated, HTMLPreviewPolicy.isExternalLink(url) {
            decisionHandler(.cancel)
            openLink(url)
        } else if action.targetFrame?.isMainFrame == true, HTMLPreviewPolicy.isInternalNavigation(url) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }
}
