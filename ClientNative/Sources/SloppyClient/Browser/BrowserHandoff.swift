import Foundation
import SwiftUI

struct BrowserHandoffPage: Equatable {
    static let activityType = "team.sloppy.client.browse"
    let url: URL
    let title: String

    @MainActor
    init?(workspace: BrowserWorkspaceState) {
        guard workspace.isBrowsing, let page = workspace.selectedPage, page.lastError == nil,
              let currentURL = page.currentURL, let url = WorkspaceBrowserHistory.websiteURL(currentURL),
              url.absoluteString.utf8.count <= 2048 else { return nil }
        self.url = url
        title = WorkspaceBrowserHistory.pageTitle(page.pageTitle) ?? url.host ?? "Page"
    }

    func update(_ activity: NSUserActivity) {
        activity.title = title
        activity.webpageURL = url
        activity.userInfo = ["version": 1]
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.isEligibleForPublicIndexing = false
#if os(iOS) || os(visionOS)
        activity.isEligibleForPrediction = false
#endif
    }

    @MainActor
    static func destination(_ activity: NSUserActivity) -> URL? {
        guard activity.activityType == activityType || activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL else { return nil }
        return WorkspaceBrowserHistory.websiteURL(url)
    }
}

struct BrowserHandoffModifier: ViewModifier {
    let root: RootShellViewModel
    @Environment(\.scenePhase) private var scenePhase

    private var page: BrowserHandoffPage? {
        guard root.launchPreferences.hasCompletedWelcome, root.presentedSettings == nil,
              root.presentedProactivity == nil, root.consoleConnectionCode == nil, scenePhase != .background else { return nil }
#if !os(iOS)
        if !root.showsStandaloneBrowser {
            guard case .chat = root.appState else { return nil }
        }
#endif
        return BrowserHandoffPage(workspace: root.browserWorkspace)
    }

    func body(content: Content) -> some View {
        content
            .userActivity(BrowserHandoffPage.activityType, element: page) { page, activity in
                page.update(activity)
            }
            .onContinueUserActivity(BrowserHandoffPage.activityType, perform: resume)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb, perform: resume)
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { root.browserWorkspace.history.synchronizeHistory() }
            }
    }

    private func resume(_ activity: NSUserActivity) {
        guard let url = BrowserHandoffPage.destination(activity) else { return }
        root.handleDeepLink(url)
    }
}
