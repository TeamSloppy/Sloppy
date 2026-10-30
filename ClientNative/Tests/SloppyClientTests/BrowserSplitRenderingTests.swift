#if os(macOS)
import AppKit
import ScreenCaptureKit
import SwiftUI
import WebKit
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser split rendering", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserSplitRenderingTests {
    @Test func nativeSelectionContextMenuAndPaneControlsKeepTheExistingPages() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserSplitRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        for index in 0..<3 { state.open(url.appendingPathComponent("page-\(index)"), inNewTab: true) }
        let ids = state.tabs.map(\.id)
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
                .theme(.sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1600, height: 850),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "browser-split-test")
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1600, height: 850))
        window.makeKeyAndOrderFront(nil)
        defer { window.contentViewController = nil; window.close() }
        try await Task.sleep(for: .milliseconds(300))
        try await screenshot(window, name: "browser-split-selection.png")
        try selectTabs([0], in: controller.view)
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.selectedID == ids[0])
        try await waitForPage(try #require(state.selectedPage))
        let firstWebView = try #require(state.pages[ids[0]]?.nativeWebView)
        _ = try await firstWebView.evaluateJavaScript("document.querySelector('#name').value='Keep the first draft'")
        try selectTabs([1], extending: true, in: controller.view)
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.selectedTabIDs == [ids[0], ids[1]])
        try selectTabs([0, 1, 2], in: controller.view)
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.selectedTabIDs == Set(ids))

        let table = try sidebarTable(in: controller.view)
        let rowFrame = table.convert(table.rect(ofRow: table.numberOfRows - 2), to: nil)
        let contextEvent = try #require(NSEvent.mouseEvent(with: .rightMouseDown,
            location: NSPoint(x: rowFrame.midX, y: rowFrame.midY), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try #require(table.menu(for: contextEvent))
        menu.update()
        let combine = try #require(menu.items.firstIndex { $0.title == "Combine in Split View" })
        menu.performActionForItem(at: combine)
        try await Task.sleep(for: .milliseconds(300))
        #expect(state.visibleTabs.map(\.id) == ids)
        for id in ids { try await waitForPage(try #require(state.pages[id])) }
        #expect(state.pages[ids[0]]?.nativeWebView === firstWebView)
        #expect(try await firstWebView.evaluateJavaScript("document.querySelector('#name').value") as? String == "Keep the first draft")

        let focusTracker = Coordinator(viewModel: state.pages[ids[0]])
        focusTracker.updateFocusTracking(firstWebView, onFocus: { state.select(ids[0]) })
        defer { focusTracker.stopFocusTracking() }
        let otherWebView = try #require(state.pages[ids[2]]?.nativeWebView)
        let otherFrame = otherWebView.convert(otherWebView.bounds, to: nil)
        let outside = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
            location: NSPoint(x: otherFrame.midX, y: otherFrame.midY), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        focusTracker.focusIfNeeded(for: outside, in: firstWebView)
        #expect(state.selectedID == ids[2])
        let firstFrame = firstWebView.convert(firstWebView.bounds, to: nil)
        let inside = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
            location: NSPoint(x: firstFrame.midX, y: firstFrame.midY), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        focusTracker.focusIfNeeded(for: inside, in: firstWebView)
        focusTracker.stopFocusTracking()
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.selectedID == ids[0])
        #expect(state.selectedTab?.url == url.appendingPathComponent("page-0"))
        for width in [1600.0, 1100.0] {
            window.setContentSize(NSSize(width: width, height: 850))
            try await Task.sleep(for: .milliseconds(200))
            let views = try ids.map { try #require(state.pages[$0]?.nativeWebView) }
            #expect(views.allSatisfy { $0.bounds.width > 100 && $0.bounds.height > 100 })
            #expect(views[0].convert(views[0].bounds, to: nil).maxX <= views[1].convert(views[1].bounds, to: nil).minX)
            try await screenshot(window, name: "browser-split-\(Int(width)).png")
        }
        state.close(ids[1])
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.visibleTabs.map(\.id) == [ids[0], ids[2]])
        let chrome = try #require(window.contentView?.superview)
        let separate = try #require(AppKitTestAccessibility.element(in: chrome, identifier: "browser-separate-split"))
        _ = AppKitTestAccessibility.press(separate)
        try await Task.sleep(for: .milliseconds(200))
        #expect(state.activeSplit == nil)
        #expect(state.pages[ids[0]]?.nativeWebView === firstWebView)
        #expect(try await firstWebView.evaluateJavaScript("document.querySelector('#name').value") as? String == "Keep the first draft")
        for index in 3..<5 { state.open(url.appendingPathComponent("page-\(index)"), inNewTab: true) }
        let gridIDs = state.tabs.map(\.id)
        state.combineTabsInSplit(Set(gridIDs))
        for id in gridIDs { try await waitForPage(try #require(state.pages[id])) }
        let gridViews = try gridIDs.map { try #require(state.pages[$0]?.nativeWebView) }
        let top = gridViews[0].convert(gridViews[0].bounds, to: nil)
        let bottom = gridViews[2].convert(gridViews[2].bounds, to: nil)
        #expect(top.minY > bottom.minY)
        #expect(gridViews.allSatisfy { $0.bounds.width > 100 && $0.bounds.height > 100 })
        #expect(try await firstWebView.evaluateJavaScript("document.querySelector('#name').value") as? String == "Keep the first draft")
        try await screenshot(window, name: "browser-split-grid.png")
    }

    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    private func sidebarTable(in host: NSView) throws -> NSTableView {
        return try #require(descendants(host).compactMap { $0 as? NSTableView }.first)
    }

    private func selectTabs(_ indices: [Int], extending: Bool = false, in host: NSView) throws {
        let table = try sidebarTable(in: host)
        // This fixture has Home and the Tabs header followed by three ungrouped tabs.
        let rows = IndexSet(indices.map { table.numberOfRows - 3 + $0 })
        table.selectRowIndexes(rows, byExtendingSelection: extending)
    }

    private func waitForPage(_ page: WorkspaceWebViewModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while page.pageTitle != "Loaded through HTTP" || page.isLoading {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func screenshot(_ window: NSWindow, name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_BROWSER_SCREENSHOTS"], CGPreflightScreenCaptureAccess() else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let own = try #require(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * window.backingScaleFactor)
        configuration.height = Int(window.frame.height * window.backingScaleFactor)
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: own), configuration: configuration)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}

#endif
