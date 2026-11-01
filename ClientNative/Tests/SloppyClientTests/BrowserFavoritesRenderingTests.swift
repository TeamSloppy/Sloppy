#if os(macOS)
import AppKit
import ScreenCaptureKit
import SwiftUI
import WebKit
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser Favorites rendering", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserFavoritesRenderingTests {
    @Test func nativePinMenuAndFavoriteSelectionKeepThePageAndOpenNestedFavorites() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserFavoritesRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        state.open(url, inNewTab: true)
        let first = try #require(state.selectedID)
        state.open(url.appendingPathComponent("other"), inNewTab: true)
        let other = try #require(state.selectedID)
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
                .theme(.sloppyDark).preferredColorScheme(.dark)
                .frame(minWidth: 1120, minHeight: 760))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 820),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar(identifier: "browser-favorites-test")
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1200, height: 820))
        window.makeKeyAndOrderFront(nil)
        defer { window.contentViewController = nil; window.close() }
        try await Task.sleep(for: .milliseconds(300))
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        var table = try #require(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
        table.selectRowIndexes(IndexSet(integer: table.numberOfRows - 2), byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.selectedID == first)
        let page = try #require(state.selectedPage)
        try await waitForPage(page)
        let webView = try #require(page.nativeWebView)
        _ = try await webView.evaluateJavaScript("document.querySelector('#name').value = 'Pinned page draft'")
        let rect = table.convert(table.rect(ofRow: table.numberOfRows - 2), to: nil)
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown,
            location: NSPoint(x: rect.midX, y: rect.midY), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try #require(table.menu(for: event))
        menu.update()
        let pin = try #require(menu.items.firstIndex { $0.title == "Pin to Favorites" })
        menu.performActionForItem(at: pin)
        try await Task.sleep(for: .milliseconds(150))
        let favorite = try #require(state.tabs.first(where: { $0.id == first })?.favoriteID)
        #expect(state.regularTabs.map(\.id) == [other])
        #expect(state.pages[first]?.nativeWebView === webView)
        #expect(try await webView.evaluateJavaScript("document.querySelector('#name').value") as? String == "Pinned page draft")

        let work = try #require(state.favorites.createFolder(title: "Work"))
        let research = try #require(state.favorites.createFolder(title: "Research", in: work))
        #expect(state.favorites.move(favorite, into: research))
        state.favorites.rename(favorite, title: "Reference page")
        try await Task.sleep(for: .milliseconds(200))
        table = try #require(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
        table.selectRowIndexes(IndexSet(integer: table.numberOfRows - 1), byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.selectedID == other)
        table.selectRowIndexes(IndexSet(integer: table.numberOfRows - 3), byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.selectedID == first)
        #expect(state.pages[first]?.nativeWebView === webView)

        state.close(first)
        try await Task.sleep(for: .milliseconds(100))
        table = try #require(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
        let favoriteRect = table.convert(table.rect(ofRow: table.numberOfRows - 3), to: nil)
        let location = NSPoint(x: favoriteRect.midX, y: favoriteRect.midY)
        let favoriteEvent = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let favoriteMenu = try #require(table.menu(for: favoriteEvent))
        favoriteMenu.update()
        let open = try #require(favoriteMenu.items.firstIndex { $0.title == "Open favorite" })
        favoriteMenu.performActionForItem(at: open)
        try await Task.sleep(for: .milliseconds(100))
        let reopened = try #require(state.selectedTab)
        #expect(reopened.favoriteID == favorite)
        #expect(reopened.id != first)
        #expect(state.regularTabs.map(\.id) == [other])
        try await waitForPage(try #require(state.selectedPage))
        #expect(state.favorites.entry(favorite)?.parentID == research)
        #expect(window.sheets.isEmpty)
        try await screenshot(window)
    }

    private func waitForPage(_ page: WorkspaceWebViewModel) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while page.pageTitle != "Loaded through HTTP" || page.isLoading {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func screenshot(_ window: NSWindow) async throws {
        guard CGPreflightScreenCaptureAccess() else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let own = try #require(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * window.backingScaleFactor)
        configuration.height = Int(window.frame.height * window.backingScaleFactor)
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: own), configuration: configuration)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/sloppy-browser-favorites.png"))
    }
}
#endif
