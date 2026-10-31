import Foundation
import Testing
import SloppyClientCore
@testable import SloppyClient

@Suite("Mobile browser independent launch")
@MainActor
struct MobileBrowserLaunchTests {
    private func launch() throws -> (MobileBrowserLaunchState, UserDefaults, String) {
        let name = "MobileBrowserLaunch.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        let browser = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        return (MobileBrowserLaunchState(browser: browser), defaults, name)
    }

    @Test func launchesInBrowseEvenIfLastModeWasWork() throws {
        let (launch, defaults, name) = try launch()
        defer { defaults.removePersistentDomain(forName: name) }
        launch.browser.isBrowsing = false
        let restored = MobileBrowserLaunchState(browser: BrowserWorkspaceState(defaults: defaults))
        #expect(restored.browser.isBrowsing)
        #expect(restored.pendingAction == nil)
    }

    @Test func askingOfflinePreservesPromptAndReturningToBrowseCancelsTheHandoff() throws {
        let (launch, defaults, name) = try launch()
        defer { defaults.removePersistentDomain(forName: name) }
        launch.requireConnection(for: .assistant("Compare these pages"))
        #expect(!launch.browser.isBrowsing)
        #expect(launch.pendingAction == .assistant("Compare these pages"))
        launch.showBrowser()
        #expect(launch.browser.isBrowsing)
        #expect(launch.takeConnectedAction() == nil)
    }

    @Test func connectionHandoffIsConsumedOnceWithoutClosingPages() throws {
        let (launch, defaults, name) = try launch()
        defer { defaults.removePersistentDomain(forName: name) }
        launch.browser.open(try #require(URL(string: "https://example.com")), inNewTab: true)
        let page = try #require(launch.browser.selectedPage)
        let tabs = launch.browser.tabs
        launch.requireConnection(for: .collect(tabs))
        #expect(launch.takeConnectedAction() == .collect(tabs))
        #expect(launch.takeConnectedAction() == nil)
        launch.showBrowser()
        #expect(launch.browser.tabs == tabs)
        #expect(launch.browser.selectedPage === page)
    }

    @Test func offlineAssistantKeepsBrowsingAndPreservesTheRequestedAction() throws {
        let (launch, defaults, name) = try launch()
        defer { defaults.removePersistentDomain(forName: name) }
        launch.deferConnection(for: .assistant("Compare these pages"))
        #expect(launch.browser.isBrowsing)
        #expect(launch.takeConnectedAction() == .assistant("Compare these pages"))
        #expect(launch.takeConnectedAction() == nil)
    }

    @Test func failedBackgroundAttemptsRetryWithBoundedDelayAndDoNotTakeOverBrowser() async throws {
        let (launch, defaults, name) = try launch()
        defer { defaults.removePersistentDomain(forName: name) }
        var attempts = 0
        var delays: [Int] = []
        struct Finished: Error {}
        await MobileConnectionRetryLoop.run {
            attempts += 1
            #expect(launch.browser.isBrowsing)
        } wait: { seconds in
            delays.append(seconds)
            if delays.count == 7 { throw Finished() }
        }
        #expect(attempts == 7)
        #expect(delays == [2, 4, 8, 16, 30, 30, 30])
        #expect(launch.browser.isBrowsing)
    }

    @Test func cancellationStopsRetriesBeforeAnotherConnectionAttempt() async {
        var attempts = 0
        let task = Task {
            await MobileConnectionRetryLoop.run {
                attempts += 1
            } wait: { _ in
                try await Task.sleep(for: .seconds(60))
            }
        }
        while attempts == 0 { await Task.yield() }
        task.cancel()
        await task.value
        #expect(attempts == 1)
    }

    @Test func temporaryNetworkAndServerFailuresKeepSavedCredentials() {
        #expect(!MobileConnectionFailure.invalidatesSavedSession(URLError(.notConnectedToInternet)))
        #expect(!MobileConnectionFailure.invalidatesSavedSession(URLError(.timedOut)))
        #expect(!MobileConnectionFailure.invalidatesSavedSession(APIError.httpError(statusCode: 503, body: nil)))
        #expect(MobileConnectionFailure.invalidatesSavedSession(APIError.httpError(statusCode: 401, body: nil)))
        #expect(MobileConnectionFailure.invalidatesSavedSession(APIError.httpError(statusCode: 403, body: nil)))
    }
}
