import Foundation
import Observation

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
    var currentURL: URL?
    var addressText: String = ""
    var pageTitle: String?
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var lastError: String?
    weak var controller: WorkspaceWebViewControlling?
    var browserRuntime: WorkspaceBrowserToolRuntime?

    init(history: WorkspaceBrowserHistory = .shared) {
        self.history = history
    }

#if os(macOS)
    func ensureBrowserRuntime() -> WorkspaceBrowserToolRuntime {
        if let browserRuntime { return browserRuntime }
        let runtime = WorkspaceBrowserToolRuntime()
        runtime.onStateChange = { [weak self] webView, error in
            guard let self else { return }
            currentURL = webView.url
            addressText = webView.url?.absoluteString ?? addressText
            pageTitle = webView.title
            isLoading = webView.isLoading
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
            lastError = error
            if error == nil, !webView.isLoading {
                history.updateTitle(url: webView.url, title: webView.title)
            }
        }
        runtime.onNavigationFinished = { [weak self] webView in
            self?.history.record(url: webView.url, title: webView.title)
        }
        browserRuntime = runtime
        controller = runtime
        return runtime
    }
#endif

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
