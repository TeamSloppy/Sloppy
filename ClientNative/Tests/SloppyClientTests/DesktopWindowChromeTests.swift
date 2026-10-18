#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient
@testable import SloppyFeatureChat

@Suite("Desktop window chrome", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct DesktopWindowChromeTests {
    @Test func fullSizeToolbarDoesNotCoverSidebarOrFirstMessage() async throws {
        AppKitTestAccessibility.enable()
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "http://window-chrome.invalid")))
        let settings = ClientSettings()
        let monitor = ConnectionMonitor(baseURL: api.baseURL)
        let model = MainViewModel(endpoint: api.endpoint, settings: settings, connectionMonitor: monitor,
            cacheStore: ClientCacheStore(path: ":memory:"), apiClient: api,
            responseNotificationScheduler: WindowChromeNotifications(), onOpenSettings: { _ in }, onOpenWorkspace: {})
        model.chatViewModel.didLoadInitialData = true
        model.createBlankChatTab()
        let tab = try #require(model.selectedTabID)
        let chat = try #require(model.tabStates[tab]?.chatState?.viewModel)
        chat.didLoadInitialData = true
        chat.transcript.replaceAll([
            .init(role: .user, segments: [.init(kind: .text, text: "The first message must be fully visible below the toolbar.")]),
            .init(role: .assistant, segments: [.init(kind: .text, text: "A short response.")]),
        ])
        let main = MainView(endpoint: api.endpoint, settings: settings, connectionMonitor: monitor,
            onOpenSettings: { _ in }, onOpenWorkspace: {}, viewModel: model)
        let controller = NSHostingController(rootView: main.workspacePanelContainer
            .toolbar {
                ToolbarItem(placement: .principal) { TextField("Search chats and projects", text: .constant("")).frame(width: 320) }
                ToolbarItem(placement: .primaryAction) { main.workspaceSidePanelButton }
            }
            .theme(.sloppyDark).desktopScreenStyle().preferredColorScheme(.dark)
            .frame(minWidth: 1120, minHeight: 760))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1500, height: 900),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "window-chrome-test")
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1500, height: 900))
        window.makeKeyAndOrderFront(nil)
        defer {
            chat.closeSession()
            model.chatViewModel.closeSession()
            window.contentViewController = nil
            window.close()
        }
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        for (width, showsDock) in [(1120.0, false), (1120.0, true), (1800.0, true), (1800.0, false)] {
            window.setContentSize(NSSize(width: width, height: 900))
            if showsDock { model.workspaceDockState.open(.browser) } else { model.workspaceDockState.hide() }
            try await Task.sleep(for: .milliseconds(500))
            let host = controller.view
            host.layoutSubtreeIfNeeded()
            #expect(window.contentLayoutRect.maxY < window.contentView?.bounds.maxY ?? 0)
            let wordmark = try #require(AppKitTestAccessibility.element(in: host, identifier: "sidebar.wordmark"))
            let wordmarkFrame = window.convertFromScreen(try #require(AppKitTestAccessibility.frame(of: wordmark)))
            #expect(wordmarkFrame.maxY <= window.contentLayoutRect.maxY + 1)
            let collection = try #require(descendants(host).compactMap { $0 as? NSCollectionView }.first)
            let first = try #require(collection.item(at: IndexPath(item: 0, section: 0)))
            let firstFrame = first.view.convert(first.view.bounds, to: nil)
            let clip = try #require(collection.enclosingScrollView?.contentView)
            let viewport = clip.convert(clip.bounds, to: nil)
            #expect(firstFrame.maxY <= min(window.contentLayoutRect.maxY, viewport.maxY) + 1)
            #expect(firstFrame.minY >= viewport.minY - 1)
            if let directory = ProcessInfo.processInfo.environment["SLOPPY_WINDOW_CHROME_SCREENSHOTS"] {
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("chrome-\(Int(width))-dock-\(showsDock).png"))
                if CGPreflightScreenCaptureAccess() {
                    let capture = Process()
                    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    capture.arguments = ["-x", "-o", "-l", String(window.windowNumber),
                        directory + "/window-\(Int(width))-dock-\(showsDock).png"]
                    try capture.run()
                    capture.waitUntilExit()
                }
            }
        }
        chat.transcript.replaceAll((0..<40).map { index in
            .init(role: index.isMultiple(of: 2) ? .user : .assistant,
                  segments: [.init(kind: .text, text: "Message \(index): the first row must stay below the titlebar after scrolling.")])
        })
        try await Task.sleep(for: .milliseconds(500))
        let collection = try #require(descendants(controller.view).compactMap { $0 as? NSCollectionView }.first)
        let scroll = try #require(collection.enclosingScrollView)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(200))
        let first = try #require(collection.item(at: IndexPath(item: 0, section: 0)))
        #expect(first.view.convert(first.view.bounds, to: nil).maxY <= window.contentLayoutRect.maxY + 1)
    }
}

@MainActor
private final class WindowChromeNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
