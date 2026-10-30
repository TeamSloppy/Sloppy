#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import ScreenCaptureKit
import SecurityInterface
import Testing
import SloppyClientCore
import SloppyFeatureChat
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser workspace rendering", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserWorkspaceRenderingTests {
    @Test func webKitSurvivesSwitchingAndRestoresNavigationAfterRestart() async throws {
        let name = "BrowserWorkspaceRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let state = BrowserWorkspaceState(defaults: defaults)
        state.open(url, inNewTab: true)
        let firstID = try #require(state.selectedID)
        let page = try #require(state.selectedPage)
        let host = NSHostingView(rootView: BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await waitForPage(page)
        let webView = try #require(page.nativeWebView)
        _ = try await webView.evaluateJavaScript("document.querySelector('#name').value='Retained draft'")
        state.open(url.appendingPathComponent("second"), inNewTab: true)
        try await Task.sleep(for: .milliseconds(500))
        state.select(firstID)
        try await Task.sleep(for: .milliseconds(200))
        #expect(state.selectedPage?.nativeWebView === webView)
        let input = try await webView.evaluateJavaScript("document.querySelector('#name').value") as? String
        #expect(input == "Retained draft")
        _ = try await page.ensureBrowserRuntime().open(url: url.appendingPathComponent("next").absoluteString)
        #expect(webView.canGoBack)
        state.checkpoint()
        #expect(state.selectedTab?.interactionState != nil)
        try await save(host, name: "browser-desktop.png")
        let restored = BrowserWorkspaceState(defaults: defaults)
        host.rootView = BrowserWorkspaceView(state: restored, onAskAgent: { _ in }, onCollect: { _ in })
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark)
        let restoredPage = try #require(restored.selectedPage)
        try await waitForPage(restoredPage)
        #expect(restoredPage.nativeWebView?.url?.path == "/next")
        #expect(restoredPage.nativeWebView?.canGoBack == true)
    }

    @Test func launcherTransfersTheQueryToTheAgentAction() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserSearchRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        state.searchText = "Compare WebKit browsers"
        var prompt: String?
        state.isSearchPresented = true
        let host = NSHostingView(rootView: BrowserWorkspaceView(state: state, onAskAgent: { prompt = $0 }, onCollect: { _ in })
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1600, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(250))
        try await save(host, name: "browser-search.png")
        state.searchText = ""
        try await Task.sleep(for: .milliseconds(150))
        try await save(host, name: "browser-search-empty.png")
        state.open(try #require(URL(string: "https://webkit.org/")), inNewTab: true)
        state.showHome()
        state.library.toggleBookmark(url: try #require(URL(string: "https://developer.apple.com/documentation/webkit")), title: "WebKit API reference")
        state.searchText = "WebKit"
        try await Task.sleep(for: .milliseconds(150))
        try await save(host, name: "browser-search-results.png")
        state.searchText = "Compare WebKit browsers"
        try await Task.sleep(for: .milliseconds(150))
        let ask = try #require(AppKitTestAccessibility.element(in: host, identifier: "browser-ask-agent"))
        #expect(AppKitTestAccessibility.press(ask))
        #expect(prompt == state.searchText)
        #expect(state.tabs.count == 1)
    }

    @Test func mainWindowCommandTOpensBrowserAndAgentStaysInBrowse() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserMainRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let settings = ClientSettings()
        let state = BrowserWorkspaceState(defaults: defaults)
        let monitor = ConnectionMonitor(baseURL: url)
        let model = MainViewModel(endpoint: .direct(baseURL: url), settings: settings, connectionMonitor: monitor,
                                  cacheStore: ClientCacheStore(path: ":memory:"),
                                  responseNotificationScheduler: BrowserTestNotifications(),
                                  onOpenSettings: { _ in }, onOpenWorkspace: {})
        let main = MainView(endpoint: .direct(baseURL: url), settings: settings, connectionMonitor: monitor,
                            onOpenSettings: { _ in }, onOpenWorkspace: {}, viewModel: model, browserWorkspace: state)
        let host = NSHostingView(rootView: main.environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))
        let previousChat = try #require(main.activeChatViewModel)
        previousChat.useStarterPrompt("Keep this draft")
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17))
        #expect(host.performKeyEquivalent(with: key))
        #expect(state.isBrowsing)
        #expect(state.isSearchPresented)
        state.isSearchPresented = false
        state.open(url, inNewTab: true)
        try await waitForPage(try #require(state.selectedPage))
        try await save(host, name: "browser-main-window.png")
        state.presentSearch(newTab: true)
        try await Task.sleep(for: .milliseconds(500))
        #expect(window.sheets.isEmpty)
        let sheet = host
        state.searchText = "Compare browsers"
        let ask = try #require(AppKitTestAccessibility.element(in: sheet, identifier: "browser-ask-agent"))
        #expect(AppKitTestAccessibility.press(ask))
        try await Task.sleep(for: .milliseconds(200))
        #expect(state.isBrowsing)
        #expect(main.browserAgentChat.panel.isPresented)
        #expect(main.activeChatViewModel === previousChat)
        #expect(main.browserAgentChat.chat.composerDraft.text == "Compare browsers")
        #expect(previousChat.composerDraft.text == "Keep this draft")
    }

    @Test func commandShiftSTogglesTheActiveSidebarAndRetainsTheBrowserPage() async throws {
        let name = "BrowserSidebarShortcut.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let settings = ClientSettings()
        let monitor = ConnectionMonitor(baseURL: url)
        let browser = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        let model = MainViewModel(endpoint: .direct(baseURL: url), settings: settings, connectionMonitor: monitor,
                                  cacheStore: ClientCacheStore(path: ":memory:"),
                                  responseNotificationScheduler: BrowserTestNotifications(),
                                  onOpenSettings: { _ in }, onOpenWorkspace: {})
        model.columnVisibility = .all
        let main = MainView(endpoint: .direct(baseURL: url), settings: settings, connectionMonitor: monitor,
                            onOpenSettings: { _ in }, onOpenWorkspace: {}, viewModel: model, browserWorkspace: browser)
        let host = NSHostingView(rootView:
            main.theme(.sloppyDark).preferredColorScheme(.dark)
                .overlay {
                    SidebarToggleButton(action: ToggleMainSidebarAction { main.toggleMainSidebar() })
                        .opacity(0.001).allowsHitTesting(false)
                })
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(250))
        let shortcut = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .shift], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "S", charactersIgnoringModifiers: "s",
            isARepeat: false, keyCode: 1))
        #expect(host.performKeyEquivalent(with: shortcut))
        #expect(model.columnVisibility == .detailOnly)
        #expect(browser.columnVisibility == .all)
        #expect(host.performKeyEquivalent(with: shortcut))
        #expect(model.columnVisibility == .all)
        browser.open(url, inNewTab: true)
        let selectedID = browser.selectedID
        let page = try #require(browser.selectedPage)
        try await waitForPage(page)
        let webView = try #require(page.nativeWebView)
        let originalWidth = webView.bounds.width
        window.makeFirstResponder(webView)
        #expect(host.performKeyEquivalent(with: shortcut))
        #expect(browser.columnVisibility == .detailOnly)
        #expect(model.columnVisibility == .all)
        try await Task.sleep(for: .milliseconds(250))
        #expect(webView.bounds.width > originalWidth + 100)
        #expect(host.performKeyEquivalent(with: shortcut))
        #expect(browser.columnVisibility == .all)
        #expect(browser.selectedID == selectedID)
        #expect(browser.selectedPage?.nativeWebView === webView)
    }

    @Test func homeKeepsNavigationInTheSidebarOnTallAndWideWindows() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserHomeRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        let host = NSHostingView(rootView: BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        for (width, height) in [(1200.0, 780.0), (1800.0, 1160.0), (800.0, 600.0)] {
            window.setContentSize(.init(width: width, height: height))
            try await Task.sleep(for: .milliseconds(300))
            try await save(host, name: "browser-home-\(Int(width)).png")
            let address = try #require(AppKitTestAccessibility.element(in: host, identifier: "browser-address-bar"))
            let rect = try #require(AppKitTestAccessibility.frame(of: address))
            let top = window.convertToScreen(window.contentLayoutRect).maxY
            #expect(top - rect.midY < 130)
            #expect(rect.height <= 110)
            #expect(rect.maxX < window.frame.minX + 420)
            #expect(AppKitTestAccessibility.element(in: host, identifier: "browser-menu") != nil)
            #expect(AppKitTestAccessibility.element(in: host, identifier: "browser-home-composer-container") != nil)
            try await save(host, name: "browser-home-\(Int(width)).png")
        }
        state.open(try #require(URL(string: "https://webkit.org/")), inNewTab: true)
        let tab = try #require(state.selectedID)
        _ = state.saveGroup(title: "Research", tabID: tab)
        state.library.toggleBookmark(url: try #require(URL(string: "https://webkit.org/")), title: "WebKit")
        state.showHome()
        for address in ["https://webkit.org/", "https://github.com/", "https://developer.apple.com/", "https://webkit.org/"] {
            state.history.record(url: URL(string: address), title: URL(string: address)?.host)
        }
        try await Task.sleep(for: .milliseconds(250))
        try await save(host, name: "browser-home-groups.png")
    }

    @Test func sidebarHeaderStaysFixedAndInteractiveWhileTabsScroll() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserSidebarScroll.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let snapshot: [String: Any] = [
            "tabs": (0..<60).map { ["id": UUID().uuidString, "title": "Research tab \($0 + 1)"] },
            "isBrowsing": true,
            "searchEngine": "google",
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: snapshot), forKey: BrowserWorkspaceState.storageKey)
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
                .toolbar { ToolbarItem(placement: .navigation) { Text("Browse") } }
                .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 650),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "browser-sidebar-scroll")
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1100, height: 650))
        window.makeKeyAndOrderFront(nil)
        defer { window.contentViewController = nil; window.close() }
        try await Task.sleep(for: .milliseconds(300))
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let scroll = try #require(descendants(controller.view).compactMap { $0 as? NSScrollView }
            .first { $0.documentView is NSTableView })
        let address = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-address"))
        let headerFrame = try #require(AppKitTestAccessibility.frame(of: address))
        for offset in [0.0, 200.0, 500.0] {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset - scroll.contentInsets.top))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(200))
            #expect(AppKitTestAccessibility.frame(of: address) == headerFrame)
            if offset > 0 { #expect(scroll.contentView.bounds.minY > 0) }
            try await save(controller.view, name: "browser-sidebar-scroll-\(Int(offset)).png")
        }
        _ = AppKitTestAccessibility.press(address)
        #expect(state.isSearchPresented)
    }

    @Test func webKitDownloadsAFileAndRetainsItInTheLibrary() async throws {
        let name = "BrowserDownloadRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = BrowserLibrary(defaults: defaults, directory: folder)
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let page = WorkspaceWebViewModel(history: WorkspaceBrowserHistory(defaults: defaults))
        page.onDownload = { library.receive($0) }
        let runtime = page.ensureBrowserRuntime()
        runtime.webView.load(URLRequest(url: url.appendingPathComponent("download")))
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while library.downloads.first?.status != .completed {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(100))
        }
        let record = try #require(library.downloads.first)
        #expect(record.filename == "source.txt")
        let file = try #require(record.fileURL)
        #expect(try String(contentsOf: file, encoding: .utf8) == "Sloppy download fixture")
        #expect(BrowserLibrary(defaults: defaults, directory: folder).downloads.first?.status == .completed)
        library.clearFinishedDownloads()
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func spotlightKeyboardMovesToATabAndEscapeDismisses() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserSpotlightKeyboard.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        state.open(try #require(URL(string: "https://example.test/docs")), inNewTab: true)
        let targetID = try #require(state.selectedID)
        state.showHome()
        state.searchText = "example"
        state.isSearchPresented = true
        let host = NSHostingView(rootView: BrowserSearchSheet(state: state, onAskAgent: { _ in })
            .frame(width: 680).environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 680, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(250))
        func field(in view: NSView) -> BrowserSearchField.Field? {
            if let field = view as? BrowserSearchField.Field { return field }
            return view.subviews.lazy.compactMap { field(in: $0) }.first
        }
        let input = try #require(field(in: host))
        let editor = try #require(input.currentEditor() as? NSTextView)
        func key(_ text: String, code: UInt16) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
        }
        editor.keyDown(with: try key("\u{f701}", code: 125))
        editor.keyDown(with: try key("\r", code: 36))
        #expect(state.selectedID == targetID)
        #expect(!state.isSearchPresented)
        state.isSearchPresented = true
        editor.keyDown(with: try key("\u{1b}", code: 53))
        #expect(!state.isSearchPresented)
    }

    @Test func homeComposerMovesCommittedInputToTheAssistantAndPreservesTheWorkDraft() async throws {
        let name = "BrowserHomeChat.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let settings = ClientSettings()
        let monitor = ConnectionMonitor(baseURL: url)
        let model = MainViewModel(endpoint: .direct(baseURL: url), settings: settings, connectionMonitor: monitor,
                                  cacheStore: ClientCacheStore(path: ":memory:"), responseNotificationScheduler: BrowserTestNotifications(),
                                  onOpenSettings: { _ in }, onOpenWorkspace: {})
        model.createBlankChatTab()
        let previous = try #require(model.selectedTabID.flatMap { model.tabStates[$0]?.chatState?.viewModel })
        previous.useStarterPrompt("Keep this draft")
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        state.isBrowsing = true
        let main = MainView(endpoint: .direct(baseURL: url), settings: settings, connectionMonitor: monitor,
                            onOpenSettings: { _ in }, onOpenWorkspace: {}, viewModel: model, browserWorkspace: state)
        let host = NSHostingView(rootView: main.environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 780),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(250))
        func field(in view: NSView) -> NSTextView? {
            if let editor = view as? NSTextView, editor.isEditable, !editor.isFieldEditor { return editor }
            return view.subviews.lazy.compactMap { field(in: $0) }.first
        }
        let editor = try #require(field(in: host))
        window.makeFirstResponder(editor)
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.firstResponder === editor)
        editor.setMarkedText("に", selectedRange: .init(location: 1, length: 0), replacementRange: .init(location: NSNotFound, length: 0))
        editor.didChangeText()
        #expect(state.isBrowsing) // Keep native composition intact until it is committed.
        editor.insertText("日本語", replacementRange: .init(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(250))
        #expect(state.isBrowsing)
        #expect(main.browserAgentChat.panel.isPresented)
        #expect(main.activeChatViewModel === previous)
        #expect(main.browserAgentChat.chat.composerDraft.text == "日本語")
        #expect(previous.composerDraft.text == "Keep this draft")
        let focusDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while (window.firstResponder === editor || !(window.firstResponder is NSTextView)), ContinuousClock.now < focusDeadline {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        let continuedEditor = try #require(window.firstResponder as? NSTextView)
        #expect(continuedEditor !== editor)
        continuedEditor.insertText("!", replacementRange: .init(location: NSNotFound, length: 0))
        #expect(main.browserAgentChat.chat.composerDraft.text == "日本語!")
        main.browserAgentChat.hide()
        try await Task.sleep(for: .milliseconds(200))
        let pasteEditor = try #require(field(in: host))
        window.makeFirstResponder(pasteEditor)
        pasteEditor.insertText("First line\nSecond line", replacementRange: .init(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(200))
        #expect(state.isBrowsing)
        #expect(main.browserAgentChat.chat.composerDraft.text.contains("日本語!"))
        #expect(main.browserAgentChat.chat.composerDraft.text.contains("First line\nSecond line"))
        #expect(previous.composerDraft.text == "Keep this draft")
    }

    @Test func slowPageUsesSidebarProgressWithoutMovingTheWebView() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserLoading.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture(responseDelay: 1.5)
        let url = try await server.start()
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        state.open(url, inNewTab: true)
        let page = try #require(state.selectedPage)
        let host = NSHostingView(rootView: BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 780),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !page.isLoading || page.estimatedProgress <= 0 {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(10))
        }
        host.layoutSubtreeIfNeeded()
        let webView = try #require(page.nativeWebView)
        let loadingFrame = webView.convert(webView.bounds, to: host)
        #expect(page.estimatedProgress < 1)
        let address = try #require(AppKitTestAccessibility.element(in: host, identifier: "browser-address"))
        func value(of element: NSObject) -> String? {
            let selector = NSSelectorFromString("accessibilityValue")
            guard element.responds(to: selector) else { return nil }
            return element.perform(selector)?.takeUnretainedValue() as? String
        }
        let loadingValue = value(of: address)
        #expect(loadingValue?.contains("Loading") == true)
        try await save(host, name: "browser-loading.png")
        try await waitForPage(page)
        host.layoutSubtreeIfNeeded()
        let loadedFrame = webView.convert(webView.bounds, to: host)
        #expect(abs(loadedFrame.minY - loadingFrame.minY) < 1)
        #expect(abs(loadedFrame.height - loadingFrame.height) < 1)
        #expect(page.estimatedProgress == 1)
        let loadedAddress = try #require(AppKitTestAccessibility.element(in: host, identifier: "browser-address"))
        let loadedValue = value(of: loadedAddress)
        #expect(loadedValue?.contains("Loading") != true)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_BROWSER_TLS_SMOKE_URL"] != nil,
                   "Optional live HTTPS check; set SLOPPY_BROWSER_TLS_SMOKE_URL"))
    func liveHttpsConnectionShowsItsOwnCertificate() async throws {
        AppKitTestAccessibility.enable()
        let address = try #require(ProcessInfo.processInfo.environment["SLOPPY_BROWSER_TLS_SMOKE_URL"])
        let url = try #require(URL(string: address))
        let name = "BrowserLiveCertificate.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        state.open(url, inNewTab: true)
        let page = try #require(state.selectedPage)
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
                .theme(.sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.makeKeyAndOrderFront(nil)
        defer { window.contentViewController = nil; window.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while page.isLoading || page.pageTitle == nil {
            guard ContinuousClock.now < deadline, page.lastError == nil else { throw URLError(.cannotConnectToHost) }
            try await Task.sleep(for: .milliseconds(100))
        }
        let certificate = try #require(page.certificateInfo(for: state.selectedTab?.url))
        #expect(certificate.sha256.split(separator: ":").count == 32)
        let security = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-connection-security"))
        _ = AppKitTestAccessibility.press(security)
        try await Task.sleep(for: .milliseconds(250))
        let popup = try #require(NSApp.windows.first { candidate in
            guard let view = candidate.contentView else { return false }
            return AppKitTestAccessibility.element(in: view, identifier: "browser-certificate-popover") != nil
        })
        try await save(try #require(popup.contentView), name: "browser-live-certificate.png")
    }

    @Test func certificatePreviewOpensReadOnlyNativeDetails() async throws {
        AppKitTestAccessibility.enable()
        let certificate = try CertificateTestFixture.info()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 420),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        var panel: SFCertificatePanel?
        let controller = NSHostingController(rootView:
            BrowserCertificatePopover(host: "Certificate preview", security: .secure, certificate: certificate,
                                      onShowDetails: { panel = $0.showDetails(in: window) })
                .preferredColorScheme(.dark))
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        defer { window.contentViewController = nil; window.close() }
        try await Task.sleep(for: .milliseconds(200))
        try await save(controller.view, name: "browser-certificate-preview.png")
        let details = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-show-certificate"))
        _ = AppKitTestAccessibility.press(details)
        try await Task.sleep(for: .milliseconds(200))
        let sheet = try #require(window.attachedSheet)
        #expect(try #require(panel).certificateView()?.isEditable() == false)
        window.endSheet(sheet)
        sheet.orderOut(nil)
    }

    @Test func connectionIconOpensAPopoverWithoutOpeningAddressSearch() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserSecurityPopover.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        state.open(url, inNewTab: true)
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
                .theme(.sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.makeKeyAndOrderFront(nil)
        defer { window.contentViewController = nil; window.close() }
        try await waitForPage(try #require(state.selectedPage))
        let security = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-connection-security"))
        _ = AppKitTestAccessibility.press(security)
        try await Task.sleep(for: .milliseconds(250))
        #expect(!state.isSearchPresented)
        let popup = try #require(NSApp.windows.first { candidate in
            guard let view = candidate.contentView else { return false }
            return AppKitTestAccessibility.element(in: view, identifier: "browser-certificate-popover") != nil
        })
        #expect(popup !== window)
        #expect(state.selectedPage?.certificateInfo(for: url) == nil)
        try await save(try #require(popup.contentView), name: "browser-connection-popover.png")
        popup.orderOut(nil)
        let address = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-address"))
        _ = AppKitTestAccessibility.press(address)
        #expect(state.isSearchPresented)
    }

    @Test func cancelledNavigationKeepsTheDisplayedPageWithoutAnErrorBanner() async throws {
        let name = "BrowserCancellation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let model = WorkspaceWebViewModel(history: WorkspaceBrowserHistory(defaults: defaults))
        let runtime = model.ensureBrowserRuntime()
        _ = try await runtime.open(url: url.absoluteString)
        runtime.webView(runtime.webView, didFailProvisionalNavigation: nil, withError: URLError(.cancelled))
        #expect(model.lastError == nil)
        #expect(try await runtime.read().title == "Loaded through HTTP")
    }

    @Test func bareLocalhostAddressLoadsAnHttpServerWithoutTlsErrors() async throws {
        let name = "BrowserLocalhost.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let fixture = try await server.start()
        let port = try #require(fixture.port)
        let address = "localhost:\(port)"
        let destination = try #require(BrowserSearchEngine.google.destination(for: address))
        let model = WorkspaceWebViewModel(history: WorkspaceBrowserHistory(defaults: defaults))
        _ = try await model.ensureBrowserRuntime().open(url: address)
        #expect(destination.scheme == "http")
        #expect(model.currentURL?.scheme == "http")
        #expect(model.pageTitle == "Loaded through HTTP")
        #expect(model.lastError == nil)
    }

    @Test func searchOverlayPreservesSidebarSafeAreaInAFullSizeContentWindow() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserSearchSafeArea.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
                .toolbar { ToolbarItem(placement: .navigation) { Text("Browse") } }
                .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1500, height: 900),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "browser-search-safe-area")
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        defer { window.contentViewController = nil; window.close() }
        for width in [1100.0, 1700.0] {
            state.isSearchPresented = false
            window.setContentSize(.init(width: width, height: 900))
            try await Task.sleep(for: .milliseconds(250))
            controller.view.layoutSubtreeIfNeeded()
            let address = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-address-bar"))
            let before = try #require(AppKitTestAccessibility.frame(of: address))
            let toolbarBottom = window.convertToScreen(window.contentLayoutRect).maxY
            #expect(before.maxY <= toolbarBottom + 1)
            for presented in [true, false, true, false] {
                state.isSearchPresented = presented
                try await Task.sleep(for: .milliseconds(200))
                controller.view.layoutSubtreeIfNeeded()
                let current = try #require(AppKitTestAccessibility.frame(of: address))
                #expect(abs(current.minY - before.minY) < 1)
                #expect(abs(current.maxY - before.maxY) < 1)
                #expect(current.maxY <= window.convertToScreen(window.contentLayoutRect).maxY + 1)
                try await save(controller.view, name: "browser-safe-area-\(Int(width))-search-\(presented).png")
            }
        }
    }

    @Test func pageFillsTheWindowWithTheToolbarInsetInsideWebKit() async throws {
        AppKitTestAccessibility.enable()
        let assistant = try BrowserAgentChatTestFixture()
        defer { assistant.close() }
        let name = "BrowserPageInsets.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        state.open(url, inNewTab: true)
        let page = try #require(state.selectedPage)
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in }, agentChat: assistant.state)
                .toolbar { ToolbarItem(placement: .navigation) { Text("Browse") } }
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
                .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 900),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "browser-page-insets")
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        defer { window.contentViewController = nil; window.close() }
        try await waitForPage(page)
        let webView = try #require(page.nativeWebView)
        let windowChrome = try #require(window.contentView?.superview)
        _ = try await webView.evaluateJavaScript("""
        document.body.style.margin = '0';
        document.body.style.padding = '44px 0 0';
        const header = document.createElement('header');
        header.id = 'toolbar-clearance';
        header.textContent = 'Page header stays clear below the toolbar';
        header.style.cssText = 'position:fixed;top:0;left:0;right:0;padding:12px;background:white;color:black;font:600 16px system-ui;border-bottom:1px solid black';
        document.body.prepend(header);
        """)
        for (width, height, showsAssistant) in [(1100.0, 900.0, false), (1100.0, 900.0, true), (1700.0, 650.0, true), (1700.0, 650.0, false)] {
            if showsAssistant { assistant.state.show() } else { assistant.state.hide() }
            window.setContentSize(.init(width: width, height: height))
            try await Task.sleep(for: .milliseconds(250))
            controller.view.layoutSubtreeIfNeeded()
            let frame = webView.convert(webView.bounds, to: nil)
            let content = try #require(window.contentView)
            let fullFrame = content.convert(content.bounds, to: nil)
            let toolbarHeight = fullFrame.maxY - window.contentLayoutRect.maxY
            #expect(abs(frame.maxY - fullFrame.maxY) < 1)
            #expect(abs(frame.minY - fullFrame.minY) < 1)
            if showsAssistant {
                #expect(frame.maxX <= fullFrame.maxX - 340)
            } else {
                #expect(abs(frame.maxX - fullFrame.maxX) < 1)
            }
            #expect(toolbarHeight > 0)
            #expect(webView.layer?.sublayers?.contains(where: {
                !$0.isHidden && ($0.backgroundFilters?.count ?? 0) >= 2 && $0.mask != nil
            }) == true)
            #expect(webView.obscuredContentInsets.top == 0)
            let documentPadding = try await webView.evaluateJavaScript("parseFloat(getComputedStyle(document.documentElement).paddingTop)") as? Double
            let headerTop = try await webView.evaluateJavaScript("document.querySelector('#toolbar-clearance').getBoundingClientRect().top") as? Double
            #expect(abs(try #require(documentPadding) - toolbarHeight - 40) < 1)
            #expect(try #require(headerTop) >= toolbarHeight + 39)
            let toolbarBottom = window.convertToScreen(window.contentLayoutRect).maxY
            let address = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-address"))
            let addressFrame = try #require(AppKitTestAccessibility.frame(of: address))
            for identifier in ["browser-go-back", "browser-go-forward"] {
                let button = try #require(AppKitTestAccessibility.element(in: windowChrome, identifier: identifier))
                let buttonFrame = try #require(AppKitTestAccessibility.frame(of: button))
                #expect(buttonFrame.minY >= toolbarBottom - 1)
                #expect(buttonFrame.minX > addressFrame.maxX)
            }
            let addressBar = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-address-bar"))
            let addressBarFrame = try #require(AppKitTestAccessibility.frame(of: addressBar))
            for identifier in ["browser-reload"] {
                let button = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: identifier))
                let buttonFrame = try #require(AppKitTestAccessibility.frame(of: button))
                #expect(buttonFrame.minX >= addressBarFrame.minX)
                #expect(buttonFrame.maxX <= addressBarFrame.maxX)
                #expect(buttonFrame.minY >= addressBarFrame.minY)
                #expect(buttonFrame.maxY <= addressBarFrame.maxY)
            }
            state.isSearchPresented = true
            try await Task.sleep(for: .milliseconds(150))
            #expect(webView.convert(webView.bounds, to: nil) == frame)
            state.isSearchPresented = false
            try await Task.sleep(for: .milliseconds(150))
            #expect(webView.convert(webView.bounds, to: nil) == frame)
            try await save(controller.view, name: "browser-full-height-\(Int(width)).png")
            if ProcessInfo.processInfo.environment["SLOPPY_BROWSER_SCREENSHOTS"] != nil {
                _ = try await webView.evaluateJavaScript("document.body.style.minHeight='2000px'; window.scrollTo(0, 110)")
                try await Task.sleep(for: .milliseconds(150))
                try await save(controller.view, name: "browser-scrolled-toolbar-\(Int(width)).png")
                _ = try await webView.evaluateJavaScript("window.scrollTo(0, 0)")
            }
        }
        let runtime = page.ensureBrowserRuntime()
        let onStarted = runtime.onNavigationStarted
        var didReload = false
        runtime.onNavigationStarted = { onStarted?(); didReload = true }
        defer { runtime.onNavigationStarted = onStarted }
        let selectedID = state.selectedID
        let reload = try #require(AppKitTestAccessibility.element(in: windowChrome, identifier: "browser-reload"))
        _ = AppKitTestAccessibility.press(reload)
        for _ in 0..<40 where !didReload { try await Task.sleep(for: .milliseconds(25)) }
        #expect(didReload)
        try await waitForPage(page)
        #expect(state.selectedID == selectedID)
        #expect(state.selectedPage?.nativeWebView === webView)
    }

    @Test func bookmarkAppearsOnlyWhenAddressActionsAreHoveredOrFocused() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserBookmarkHover.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        let url = try #require(URL(string: "https://example.test/"))
        state.open(url, inNewTab: true)
        func controls(_ hovered: Bool) -> some View {
            HStack {
                BrowserNavigationButtons(state: state, group: .page, compact: true, showsBookmark: hovered)
            }
            .buttonStyle(.plain).theme(.sloppyDark)
        }
        let host = NSHostingView(rootView: controls(false))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 260, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(AppKitTestAccessibility.element(in: host, identifier: "browser-bookmark-page") == nil)
        #expect(AppKitTestAccessibility.element(in: host, identifier: "browser-reload") != nil)
        #expect(AppKitTestAccessibility.element(in: host, identifier: "browser-close-tab") == nil)
        host.rootView = controls(true)
        try await Task.sleep(for: .milliseconds(150))
        let bookmark = try #require(AppKitTestAccessibility.element(in: host, identifier: "browser-bookmark-page"))
        _ = AppKitTestAccessibility.press(bookmark)
        #expect(state.library.isBookmarked(url))
        window.makeFirstResponder(nil)
        host.rootView = controls(false)
        try await Task.sleep(for: .milliseconds(150))
        #expect(AppKitTestAccessibility.element(in: host, identifier: "browser-bookmark-page") == nil)
        #expect(AppKitTestAccessibility.element(in: host, identifier: "browser-reload") != nil)
    }

    private func waitForPage(_ page: WorkspaceWebViewModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while page.pageTitle != "Loaded through HTTP" || page.isLoading {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func save(_ host: NSView, name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_BROWSER_SCREENSHOTS"] else { return }
        if CGPreflightScreenCaptureAccess(), let window = host.window {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            if let own = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
                let configuration = SCStreamConfiguration()
                configuration.width = Int(window.frame.width * window.backingScaleFactor)
                configuration.height = Int(window.frame.height * window.backingScaleFactor)
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: own), configuration: configuration)
                try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
                return
            }
        }
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
@MainActor
private final class BrowserTestNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
