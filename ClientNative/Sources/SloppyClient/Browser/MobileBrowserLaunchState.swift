import Foundation
import Observation

struct BrowserTabCollectionRequest: Identifiable {
    let id = UUID()
    let tabs: [BrowserTabRecord]
}

/// Local browsing outlives connection screens, authentication and workspace replacement.
@Observable
@MainActor
final class MobileBrowserLaunchState {
    enum ConnectedAction: Equatable {
        case assistant(String)
        case collect([BrowserTabRecord])
    }

    let browser: BrowserWorkspaceState
    private(set) var pendingAction: ConnectedAction?

    init(browser: BrowserWorkspaceState? = nil) {
        self.browser = browser ?? BrowserWorkspaceState()
        self.browser.isBrowsing = true
    }

    func requireConnection(for action: ConnectedAction) {
        pendingAction = action
        browser.isBrowsing = false
    }

    func deferConnection(for action: ConnectedAction) {
        pendingAction = action
    }

    func showBrowser() {
        pendingAction = nil
        browser.isBrowsing = true
    }

    func takeConnectedAction() -> ConnectedAction? {
        defer { pendingAction = nil }
        return pendingAction
    }
}
