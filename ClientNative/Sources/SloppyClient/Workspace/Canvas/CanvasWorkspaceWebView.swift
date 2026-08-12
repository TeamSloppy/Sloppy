import Foundation
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

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private static let dashboardAuthStorageKey = "sloppy_dashboard_auth_token"

        private let viewModel: CanvasWorkspaceViewModel
        private var requestedURL: URL?
        private var requestedReloadToken = -1
        private var navigationTask: Task<Void, Never>?

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
            navigationTask?.cancel()
            navigationTask = Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                let accessToken = await viewModel.currentAccessToken()
                guard !Task.isCancelled,
                      requestedURL == url,
                      requestedReloadToken == reloadToken else {
                    return
                }
                installDashboardAuthBootstrap(
                    accessToken: accessToken,
                    dashboardURL: url,
                    in: webView
                )
                webView.load(URLRequest(url: url))
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            syncState(from: webView, isLoading: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            syncState(from: webView, isLoading: false)
            clearPersistedDashboardAuthBootstrap(from: webView)
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

        private func installDashboardAuthBootstrap(
            accessToken: String?,
            dashboardURL: URL,
            in webView: WKWebView
        ) {
            let userContentController = webView.configuration.userContentController
            userContentController.removeAllUserScripts()

            let origin = Self.origin(for: dashboardURL)
            let normalizedToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let action: String
            if normalizedToken.isEmpty {
                action = "window.localStorage.removeItem(\(Self.javaScriptLiteral(Self.dashboardAuthStorageKey)));"
            } else {
                action = "window.localStorage.setItem(\(Self.javaScriptLiteral(Self.dashboardAuthStorageKey)), \(Self.javaScriptLiteral(normalizedToken)));"
            }
            let source = """
            if (window.location.origin === \(Self.javaScriptLiteral(origin))) {
                \(action)
            }
            """
            userContentController.addUserScript(
                WKUserScript(
                    source: source,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }

        private func clearPersistedDashboardAuthBootstrap(from webView: WKWebView) {
            let key = Self.javaScriptLiteral(Self.dashboardAuthStorageKey)
            webView.evaluateJavaScript("window.localStorage.removeItem(\(key));")
        }

        private static func origin(for url: URL) -> String {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url.absoluteString
            }
            components.path = ""
            components.query = nil
            components.fragment = nil
            return components.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                ?? url.absoluteString
        }

        private static func javaScriptLiteral(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let literal = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return literal
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
