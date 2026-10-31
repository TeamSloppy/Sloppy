import Foundation
import Testing
import SloppyClientCore
@testable import SloppyClient

@Suite("Default browser links", .serialized)
@MainActor
struct DefaultBrowserTests {
    private func withRoot(_ body: (RootShellViewModel, UserDefaults) throws -> Void) throws {
        let name = "DefaultBrowserTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let root = RootShellViewModel(launchPreferences: ClientLaunchPreferences(defaults: defaults))
        root.browserWorkspace = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        try body(root, defaults)
    }

    @Test func coldLaunchOpensTheRequestedPageWithoutAnInstanceOrWelcomeScreen() throws {
        try withRoot { root, _ in
            let url = try #require(URL(string: "https://example.com/path?q=a%2Bb#section"))
            root.handleDeepLink(url)
            #expect(root.launchPreferences.hasCompletedWelcome)
            #expect(root.launchPreferences.mode == .browser)
            #expect(root.showsStandaloneBrowser)
            #expect(root.appState == .splash)
            #expect(root.browserWorkspace.isBrowsing)
            #expect(root.browserWorkspace.selectedTab?.url == url)
            #expect(root.browserWorkspace.tabs.count == 1)
            #expect(!root.launchPreferences.hasConfiguredInstance)
        }
    }

    @Test func connectedWorkspaceKeepsItsSessionAndExistingPages() throws {
        try withRoot { root, defaults in
            root.launchPreferences.completeWelcome(mode: .instance)
            let serverURL = try #require(URL(string: "https://core.example.com"))
            root.appState = .chat(serverURL)
            let browser = root.browserWorkspace
            let first = browser.createBlankTab()
            let firstPage = try #require(browser.selectedPage)
            browser.isBrowsing = false
            browser.isSearchPresented = true
            root.presentedSettings = .general
            root.appDeepLinkRequest = AppDeepLinkRequest(deepLink: .open)
            let urls = try ["http://example.com/one", "https://example.com/two"].map { try #require(URL(string: $0)) }
            for url in urls { root.handleDeepLink(url) }

            #expect(root.appState == .chat(serverURL))
            #expect(root.launchPreferences.mode == .instance)
            #expect(!root.showsStandaloneBrowser)
            #expect(root.browserWorkspace === browser)
            #expect(browser.pages[first] === firstPage)
            #expect(browser.tabs.compactMap(\.url) == urls)
            #expect(browser.selectedTab?.url == urls.last)
            #expect(browser.isBrowsing)
            #expect(!browser.isSearchPresented)
            #expect(root.presentedSettings == nil)
            #expect(root.appDeepLinkRequest == nil)
            let restored = BrowserWorkspaceState(defaults: defaults)
            #expect(restored.tabs.map(\.id) == browser.tabs.map(\.id))
            #expect(restored.selectedTab?.url == urls.last)
        }
    }

    @Test(arguments: ["javascript:alert(1)", "file:///tmp/page.html", "mailto:test@example.com", "https://", "unknown://example.com"])
    func unsupportedExternalURLsDoNotChangeNavigation(_ input: String) throws {
        try withRoot { root, _ in
            let url = try #require(URL(string: input))
            root.handleDeepLink(url)
            #expect(root.browserWorkspace.tabs.isEmpty)
            #expect(!root.launchPreferences.hasCompletedWelcome)
            #expect(!root.showsStandaloneBrowser)
            #expect(root.appState == .splash)
        }
    }

    @Test func consoleConnectionLinksStillUseTheExistingPairingFlow() throws {
        try withRoot { root, _ in
            let url = try #require(URL(string: "sloppy://console-connect?v=1&instance=\(UUID())&host=\(UUID())&fingerprint=\(String(repeating: "a", count: 64))"))
            let code = try #require(ConsoleConnectionCode.parse(url))
            root.handleDeepLink(url)
            #expect(root.consoleConnectionCode == code)
            #expect(root.browserWorkspace.tabs.isEmpty)
            #expect(!root.showsStandaloneBrowser)
            #expect(root.launchPreferences.mode == .instance)
        }
    }

    @Test(arguments: ["macOS/Info.plist", "macOS/TestFlight-Info.plist", "iOS/Info.plist"])
    func appBundlesRegisterBothWebSchemesAndKeepSloppyLinks(_ path: String) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("SupportingFiles/\(path)"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try #require(plist["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = Set(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] })
        #expect(schemes.isSuperset(of: ["http", "https", "sloppy"]))
    }
}
