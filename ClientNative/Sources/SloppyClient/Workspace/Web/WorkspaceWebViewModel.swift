import Foundation
import Observation
import WebKit

@MainActor
protocol WorkspaceWebViewControlling: AnyObject {
    func open(_ address: String)
    func reload()
    func goBack()
    func goForward()
}

@Observable
@MainActor
final class WorkspaceWebViewModel {
    let history: WorkspaceBrowserHistory
    let textSelection = WorkspaceBrowserSelection()
#if os(macOS)
    let annotations = WorkspaceBrowserAnnotations()
    var webExtensionController: WKWebExtensionController?
    var onBrowserStateChange: (@MainActor () -> Void)?
#endif
    var nativeWebView: WKWebView?
    var retainedController: (any WorkspaceWebViewControlling)?
    var onDownload: (@MainActor (WKDownload) -> Void)?
    var onPageChange: (@MainActor () -> Void)?
    var currentURL: URL? { didSet { onPageChange?() } }
    var addressText: String = ""
    var pageTitle: String? { didSet { onPageChange?() } }
    var isLoading = false
    var estimatedProgress = 0.0
    var hasOnlySecureContent = false
    var canGoBack = false
    var canGoForward = false
    var lastError: String?
    weak var controller: WorkspaceWebViewControlling?
    var browserRuntime: WorkspaceBrowserToolRuntime?

    init(history: WorkspaceBrowserHistory = .shared) {
        self.history = history
    }

#if os(macOS)
    func certificateInfo(for requestedURL: URL?) -> BrowserCertificateInfo? {
        let security = connectionSecurity(for: requestedURL)
        guard security == .secure || security == .mixedContent,
              let trust = nativeWebView?.serverTrust else { return nil }
        return BrowserCertificateInfo(trust: trust)
    }

    func ensureBrowserRuntime() -> WorkspaceBrowserToolRuntime {
        if let browserRuntime { return browserRuntime }
        let runtime = WorkspaceBrowserToolRuntime(extensionController: webExtensionController, textSelection: textSelection)
        runtime.onDownload = onDownload
        runtime.onStateChange = { [weak self] webView, error in
            guard let self else { return }
            if currentURL != webView.url {
                currentURL = webView.url
                addressText = webView.url?.absoluteString ?? addressText
            }
            if pageTitle != webView.title { pageTitle = webView.title }
            isLoading = webView.isLoading
            estimatedProgress = webView.estimatedProgress
            hasOnlySecureContent = webView.hasOnlySecureContent
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
            lastError = error
            onBrowserStateChange?()
            if error == nil, !webView.isLoading {
                history.updateTitle(url: webView.url, title: webView.title)
            }
        }
        runtime.onNavigationFinished = { [weak self] webView in
            self?.history.record(url: webView.url, title: webView.title)
        }
        runtime.onNavigationStarted = { [weak self] in
            self?.annotations.stopPicking()
            self?.textSelection.dismiss()
        }
        browserRuntime = runtime
        controller = runtime
        nativeWebView = runtime.webView
        return runtime
    }
#endif

    func connectionSecurity(for requestedURL: URL?) -> BrowserConnectionSecurity {
        guard let requestedURL else { return .empty }
        if lastError != nil { return .failed }
        guard !isLoading, requestedURL == currentURL else { return .connecting }
        guard requestedURL.scheme?.lowercased() == "https" else { return .notSecure }
        return hasOnlySecureContent ? .secure : .mixedContent
    }

    func openAddress() {
        controller?.open(addressText)
    }

    func reload() {
        controller?.reload()
    }

    func goBack() {
        controller?.goBack()
    }

    func goForward() {
        controller?.goForward()
    }
}
