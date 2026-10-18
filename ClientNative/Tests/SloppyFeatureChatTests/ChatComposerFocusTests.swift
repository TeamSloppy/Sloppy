import Foundation
import SwiftUI
import SloppyClientCore
import Testing
import SloppyUITestSupport
@testable import SloppyFeatureChat
#if os(macOS)
import AppKit

@Suite("Chat composer focus", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ChatComposerFocusTests {
    @Test func commandSuggestionsReceiveWheelEventsAboveComposer() async throws {
        AppKitTestAccessibility.enable()
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "http://suggestions-scroll.invalid")))
        let model = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
            settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            responseNotificationScheduler: ComposerFocusNotifications(), onOpenSettings: { _ in })
        model.composerDraft.text = "/"
        let host = NSHostingView(rootView: ZStack(alignment: .bottom) {
            Color.black
            ChatComposerOverlay(viewModel: model, contentWidth: 720, composerBottomInset: 24,
                                tabs: [], tabActions: nil)
        })
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 650),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(200))
        let initialEditor = try #require(descendants(host).compactMap { $0 as? ComposerNSTextView }.first)
        let composerHeight = model.composerPanelHeight
        model.composerSuggestions = (0..<24).map {
            .init(id: "command-\($0)", kind: .command, title: "/command\($0)",
                  subtitle: "Command number \($0)", insertion: "/command\($0)")
        }
        model.composerSuggestionSelection.reconcile(with: model.composerSuggestions)
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        #expect(model.composerPanelHeight == composerHeight)
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.first {
            ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 100
        })
        let scrollFrame = scroll.convert(scroll.bounds, to: host)
        let hit = try #require(host.hitTest(NSPoint(x: scrollFrame.midX, y: scrollFrame.midY)))
        #expect(hit === scroll || hit.enclosingScrollView === scroll)
        let before = scroll.contentView.bounds.origin.y
        let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 1, wheel1: -180, wheel2: 0, wheel3: 0))
        hit.scrollWheel(with: try #require(NSEvent(cgEvent: wheel)))
        try await Task.sleep(for: .milliseconds(150))
        #expect(scroll.contentView.bounds.origin.y > before)

        let editor = try #require(descendants(host).compactMap { $0 as? ComposerNSTextView }.first)
        #expect(editor === initialEditor)
        #expect(window.makeFirstResponder(editor))
        for _ in 1..<24 {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
                isARepeat: false, keyCode: 125))
            editor.keyDown(with: event)
        }
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.composerSuggestionSelection.selectedID == "command-23")
        let last = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.composer.suggestion.command-23"))
        let lastFrame = try #require(AppKitTestAccessibility.frame(of: last))
        let viewport = window.convertToScreen(scroll.convert(scroll.bounds, to: nil))
        #expect(lastFrame.minY >= viewport.minY - 1)
        #expect(lastFrame.maxY <= viewport.maxY + 1)
    }

    @Test("opening and switching the active composer focuses the native editor")
    func activeComposerFocusesNativeEditor() async throws {
        _ = NSApplication.shared
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "http://composer-focus.invalid")))
        let settings = ClientSettings()
        func model() -> ChatScreenViewModel {
            ChatScreenViewModel(
                apiClient: api,
                cacheStore: ClientCacheStore(path: ":memory:"),
                settings: settings,
                connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
                responseNotificationScheduler: ComposerFocusNotifications(),
                onOpenSettings: { _ in }
            )
        }
        func composer(_ model: ChatScreenViewModel) -> ChatComposerOverlay {
            ChatComposerOverlay(
                viewModel: model,
                contentWidth: 720,
                composerBottomInset: 24,
                tabs: [],
                tabActions: nil
            )
        }

        let first = model()
        let hostingView = NSHostingView(rootView: composer(first))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)

        for _ in 0..<100 where first.composerFocusRequestToken == 0 || !(window.firstResponder is NSTextView) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(first.composerFocusRequestToken > 0)
        #expect(window.firstResponder is NSTextView)

        window.makeFirstResponder(nil)
        let second = model()
        hostingView.rootView = composer(second)
        for _ in 0..<100 where second.composerFocusRequestToken == 0 || !(window.firstResponder is NSTextView) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(second.composerFocusRequestToken > 0)
        #expect(window.firstResponder is NSTextView)
    }
}

@MainActor
private final class ComposerFocusNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
