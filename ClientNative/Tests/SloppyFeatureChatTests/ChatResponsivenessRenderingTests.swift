#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyFeatureChat

@Suite("Chat responsiveness native rendering", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ChatResponsivenessRenderingTests {
    @Test func copyUnknownAndBashRunIsDisabled() async throws {
        AppKitTestAccessibility.enable()
        let code = "printf 'fixture-only\\n'\n"
        let previous = NSPasteboard.general.string(forType: .string)
        defer { NSPasteboard.general.clearContents(); if let previous { NSPasteboard.general.setString(previous, forType: .string) } }
        for language in ["", "unknown", "swift", "bash"] {
            let (host, window) = makeHost(AnyView(ChatMarkdownTextStack(text: "```\(language)\n\(code)```")), height: 240)
            defer { window.contentView = nil; window.close() }
            try await settle(host)
            try snapshot(host, name: "code-debug-" + (language.isEmpty ? "none" : language))
            let copy = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.code.copy"))
            #expect(AppKitTestAccessibility.press(copy))
            #expect(NSPasteboard.general.string(forType: .string) == code)
            let run = AppKitTestAccessibility.element(in: host, identifier: "chat.code.run")
            if language == "bash" {
                let button = try #require(run)
                #expect((button as AnyObject).isAccessibilityEnabled?() == false)
                try snapshot(host, name: "bash-copy-disabled-run")
            } else {
                #expect(run == nil)
                if language.isEmpty { try snapshot(host, name: "unlabelled-code-copy") }
            }
        }
    }

    @Test func brandedLoadingAndSuggestionStatesRender() async throws {
        let (host, window) = makeHost(AnyView(ChatTranscriptLoadingView()), height: 360)
        defer { window.contentView = nil; window.close() }
        try await settle(host)
        try snapshot(host, name: "loading-messages")
        host.rootView = styled(AnyView(ComposerSuggestionsView(suggestions: [], selectedSuggestionID: nil, select: { _ in }, loadState: .loading)))
        try await settle(host)
        #expect(AppKitTestAccessibility.element(in: host, identifier: "chat.suggestions.loading") != nil)
        try snapshot(host, name: "suggestions-loading")
        host.rootView = styled(AnyView(ComposerSuggestionsView(suggestions: [], selectedSuggestionID: nil, select: { _ in }, loadState: .failed("Fixture network failure"))))
        try await settle(host)
        try snapshot(host, name: "suggestions-error")
    }

    @Test func nativeMidtextCaretOpensSuggestionsWithoutLosingEditor() async throws {
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "http://native-caret.invalid")))
        let model = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"), settings: ClientSettings(),
            connectionMonitor: ConnectionMonitor(baseURL: api.baseURL), restoresLastSession: false,
            responseNotificationScheduler: RenderingNotifications(), onOpenSettings: { _ in })
        model.selectedAgent = .init(id: "agent", displayName: "Agent")
        let prefix = "Привет 👩🏽‍💻\nпроверь @"
        model.composerDraft.text = prefix + " потом"
        let item = ChatComposerSuggestion(id: "fixture", kind: .file, title: "README.md", subtitle: "Fixture", insertion: "@README.md")
        _ = try await model.composerResultCache.load(model.composerCatalogScope + "|@") { [item] }
        _ = try await model.composerCommandCache.load(model.composerCatalogScope) { [] }
        let (host, window) = makeHost(AnyView(ChatComposerOverlay(viewModel: model, contentWidth: 700, composerBottomInset: 12, tabs: [], tabActions: nil)), height: 540)
        defer { model.closeSession(); window.contentView = nil; window.close() }
        try await settle(host)
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let editor = try #require(descendants(host).compactMap { $0 as? ComposerNSTextView }.first)
        #expect(window.makeFirstResponder(editor))
        editor.setSelectedRange(NSRange(location: (prefix as NSString).length, length: 0))
        try await settle(host)
        #expect(model.composerSuggestionState == .ready)
        #expect(model.composerSuggestions.first?.id == "fixture")
        #expect(model.applySelectedComposerSuggestion())
        try await settle(host)
        #expect(model.composerDraft.text == "Привет 👩🏽‍💻\nпроверь @README.md потом")
        #expect(descendants(host).compactMap { $0 as? ComposerNSTextView }.first === editor)
        #expect(window.firstResponder === editor)
        try snapshot(host, name: "midtext-native-composer")
    }

    private func styled(_ view: AnyView) -> AnyView {
        AnyView(view.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.sloppyDark.colors.background)
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
    }
    private func makeHost(_ view: AnyView, height: CGFloat) -> (NSHostingView<AnyView>, NSWindow) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: styled(view))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 760, height: height), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return (host, window)
    }
    private func settle(_ host: NSView) async throws {
        for _ in 0..<12 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
    }
    private func snapshot(_ host: NSView, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["SLOPPY_CHAT_PROOF_DIR"] else { return }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path).appendingPathComponent(name + ".png"))
    }
}
@MainActor
private final class RenderingNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
