import SwiftUI

#if os(macOS)
import WebKit

@MainActor
struct WorkspaceWebView: NSViewRepresentable {
    let viewModel: WorkspaceWebViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

@MainActor
final class Coordinator: NSObject, WKNavigationDelegate, WorkspaceWebViewControlling {
    private let viewModel: WorkspaceWebViewModel
    private weak var webView: WKWebView?

    init(viewModel: WorkspaceWebViewModel) {
        self.viewModel = viewModel
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        viewModel.controller = self
        viewModel.browserRuntime = WorkspaceBrowserToolRuntime(webView: webView)
        syncState(from: webView)
    }

    func open(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized) else {
            viewModel.lastError = "Invalid URL."
            return
        }

        viewModel.addressText = normalized
        viewModel.lastError = nil
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
        viewModel.lastError = error.localizedDescription
        syncState(from: webView, isLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        viewModel.lastError = error.localizedDescription
        syncState(from: webView, isLoading: false)
    }

    private func syncState(from webView: WKWebView, isLoading: Bool? = nil) {
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
#else
@MainActor
struct WorkspaceWebView: View {
    let viewModel: WorkspaceWebViewModel

    var body: some View {
        Text("Web view is unavailable on this platform.")
    }
}
#endif
