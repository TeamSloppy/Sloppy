import SwiftUI

#if os(macOS)
import WebKit

@MainActor
struct WorkspaceWebView: NSViewRepresentable {
    let viewModel: WorkspaceWebViewModel?
    let artifactHTML: String?
    let artifactTitle: String

    init(viewModel: WorkspaceWebViewModel) {
        self.viewModel = viewModel
        artifactHTML = nil
        artifactTitle = "Web content"
    }

    init(html: String, title: String) {
        viewModel = nil
        artifactHTML = html
        artifactTitle = title
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if artifactHTML != nil {
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(webView)
        if let artifactHTML {
            webView.loadHTMLString(Self.sandboxedDocument(artifactHTML), baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard let artifactHTML,
              context.coordinator.loadedArtifactHTML != artifactHTML else { return }
        context.coordinator.loadedArtifactHTML = artifactHTML
        nsView.loadHTMLString(Self.sandboxedDocument(artifactHTML), baseURL: nil)
    }

    private static func sandboxedDocument(_ html: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; font-src data:">
        <style>html,body{margin:0;min-height:100%;background:transparent;color-scheme:light dark}</style>
        </head><body>\(html)</body></html>
        """
    }
}

@MainActor
final class Coordinator: NSObject, WKNavigationDelegate, WorkspaceWebViewControlling {
    private let viewModel: WorkspaceWebViewModel?
    private weak var webView: WKWebView?
    var loadedArtifactHTML: String?

    init(viewModel: WorkspaceWebViewModel?) {
        self.viewModel = viewModel
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        viewModel?.controller = self
        viewModel?.browserRuntime = WorkspaceBrowserToolRuntime(webView: webView)
        syncState(from: webView)
    }

    func open(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized) else {
            viewModel?.lastError = "Invalid URL."
            return
        }

        viewModel?.addressText = normalized
        viewModel?.lastError = nil
        webView?.load(URLRequest(url: url))
    }

    func reload() {
        webView?.reload()
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        syncState(from: webView, isLoading: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncState(from: webView, isLoading: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        viewModel?.lastError = error.localizedDescription
        syncState(from: webView, isLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        viewModel?.lastError = error.localizedDescription
        syncState(from: webView, isLoading: false)
    }

    private func syncState(from webView: WKWebView, isLoading: Bool? = nil) {
        guard let viewModel else { return }
        viewModel.currentURL = webView.url
        viewModel.addressText = webView.url?.absoluteString ?? viewModel.addressText
        viewModel.pageTitle = webView.title
        viewModel.canGoBack = webView.canGoBack
        viewModel.canGoForward = webView.canGoForward
        if let isLoading {
            viewModel.isLoading = isLoading
        } else {
            viewModel.isLoading = webView.isLoading
        }
    }
}
#elseif os(iOS) || os(visionOS)
import WebKit

@MainActor
struct WorkspaceWebView: UIViewRepresentable {
    let viewModel: WorkspaceWebViewModel?
    let artifactHTML: String?
    let artifactTitle: String

    init(viewModel: WorkspaceWebViewModel) {
        self.viewModel = viewModel
        artifactHTML = nil
        artifactTitle = "Web content"
    }

    init(html: String, title: String) {
        viewModel = nil
        artifactHTML = html
        artifactTitle = title
    }

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if artifactHTML != nil {
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        viewModel?.controller = context.coordinator
        if let artifactHTML {
            context.coordinator.load(html: artifactHTML, in: webView)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let artifactHTML, context.coordinator.loadedHTML != artifactHTML {
            context.coordinator.load(html: artifactHTML, in: webView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WorkspaceWebViewControlling {
        let viewModel: WorkspaceWebViewModel?
        weak var webView: WKWebView?
        var loadedHTML: String?

        init(viewModel: WorkspaceWebViewModel?) { self.viewModel = viewModel }

        func load(html: String, in webView: WKWebView) {
            loadedHTML = html
            webView.loadHTMLString("<meta name='viewport' content='width=device-width,initial-scale=1'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; img-src data: blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; font-src data:\"><style>html,body{margin:0;color-scheme:light dark}</style>\(html)", baseURL: nil)
        }

        func open(_ address: String) {
            let value = address.contains("://") ? address : "https://\(address)"
            guard let url = URL(string: value) else { return }
            webView?.load(URLRequest(url: url))
        }
        func reload() { webView?.reload() }
        func goBack() { webView?.goBack() }
        func goForward() { webView?.goForward() }
    }
}
#else
@MainActor
struct WorkspaceWebView: View {
    init(viewModel: WorkspaceWebViewModel) {}
    init(html: String, title: String) {}

    var body: some View {
        Text("Web view is unavailable on this platform.")
    }
}
#endif
