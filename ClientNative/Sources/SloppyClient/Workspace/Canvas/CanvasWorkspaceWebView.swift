import SwiftUI

#if os(macOS)
import WebKit

@MainActor
struct CanvasWorkspaceWebView: NSViewRepresentable {
    let viewModel: CanvasWorkspaceViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        context.coordinator.attach(webView)
        context.coordinator.navigate(
            to: viewModel.url,
            reloadToken: viewModel.pageReloadToken,
            in: webView
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.navigate(
            to: viewModel.url,
            reloadToken: viewModel.pageReloadToken,
            in: webView
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let viewModel: CanvasWorkspaceViewModel
        private var requestedURL: URL?
        private var requestedReloadToken = -1

        init(viewModel: CanvasWorkspaceViewModel) {
            self.viewModel = viewModel
        }

        func attach(_ webView: WKWebView) {
            syncState(from: webView)
        }

        func navigate(to url: URL?, reloadToken: Int, in webView: WKWebView) {
            guard let url,
                  requestedURL != url || requestedReloadToken != reloadToken else {
                return
            }
            requestedURL = url
            requestedReloadToken = reloadToken
            viewModel.pageError = nil
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            syncState(from: webView, isLoading: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            syncState(from: webView, isLoading: false)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            handleFailure(error, webView: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            handleFailure(error, webView: webView)
        }

        private func handleFailure(_ error: Error, webView: WKWebView) {
            viewModel.pageError = error.localizedDescription
            syncState(from: webView, isLoading: false)
        }

        private func syncState(from webView: WKWebView, isLoading: Bool? = nil) {
            viewModel.isLoadingPage = isLoading ?? webView.isLoading
        }
    }
}
#else
@MainActor
struct CanvasWorkspaceWebView: View {
    let viewModel: CanvasWorkspaceViewModel

    var body: some View {
        ContentUnavailableView(
            "Workspace canvas is available on macOS",
            systemImage: "square.grid.2x2"
        )
    }
}
#endif
