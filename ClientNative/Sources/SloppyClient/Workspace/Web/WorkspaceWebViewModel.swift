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
    var currentURL: URL?
    var addressText: String = ""
    var pageTitle: String?
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var lastError: String?
    weak var controller: WorkspaceWebViewControlling?
    var browserRuntime: WorkspaceBrowserToolRuntime?

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
