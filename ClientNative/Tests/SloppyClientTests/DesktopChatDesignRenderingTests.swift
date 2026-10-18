#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient
@testable import SloppyFeatureChat

@Suite("Desktop chat design", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct DesktopChatDesignRenderingTests {
    @Test func desktopComponentsRenderAndComposerFitsNarrowWindows() async throws {
        AppKitTestAccessibility.enable()
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "http://design-fixture.invalid")))
        let chat = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
                                       settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
                                       responseNotificationScheduler: DesktopDesignNotifications(),
                                       onOpenSettings: { _ in })
        chat.didLoadInitialData = true
        chat.selectedAgent = APIAgentRecord(id: "anton", displayName: "Антон")
        chat.availableModels = [.init(id: "claude-sonnet", title: "Claude Sonnet", contextWindow: "200000")]
        chat.selectedModelId = "claude-sonnet"
        chat.contextTokenUsage = .init(prompt: 84000, completion: 0)
        chat.transcript.replaceAll([
            .init(role: .user, segments: [.init(kind: .text, text: "Проверь производительность рендера и найди узкие места")]),
            .init(role: .assistant, segments: [.init(kind: .text, text: "Начну с замеров: сравню время CPU и GPU, затем проверю горячие участки.")]),
            .init(role: .system, segments: [.init(kind: .toolCall, title: "shell", status: "completed"),
                                          .init(kind: .toolResult, text: "CPU: 8 ms", title: "shell", status: "completed")]),
            .init(role: .assistant, segments: [.init(kind: .text, text: "Основная нагрузка — подготовка мешей на CPU. GPU укладывается в бюджет кадра.\n\n```swift\nif visible != lastVisibleNodes {\n    meshes = meshCache.meshes(for: visible)\n    lastVisibleNodes = visible\n}\n```\n\n### Что изменилось\n- Убрана повторная сборка мешей\n- Добавлено кеширование"),
                                             .init(kind: .attachment, attachment: .init(id: "profile", name: "cpu-profile.json", mimeType: "application/json", sizeBytes: 327680, relativePath: "cpu-profile.json"))]),
        ])
        let monitor = ConnectionMonitor(baseURL: api.baseURL)
        let main = MainViewModel(endpoint: api.endpoint, settings: ClientSettings(), connectionMonitor: monitor,
                                 cacheStore: ClientCacheStore(path: ":memory:"), apiClient: api,
                                 responseNotificationScheduler: DesktopDesignNotifications(),
                                 onOpenSettings: { _ in }, onOpenWorkspace: {})
        main.chatViewModel.agents = [try #require(chat.selectedAgent)]
        main.chatViewModel.didLoadInitialData = true
        let host = NSHostingView(rootView:
            HStack(spacing: 0) {
                PlatformMainSidebar(viewModel: main, isOverlay: false).frame(width: 250)
                ZStack(alignment: .bottom) {
                    ChatChrome(viewModel: chat, connectionMonitor: monitor, rootSafeAreaInsets: .init(), composerTabActions: nil)
                    ChatComposerOverlay(viewModel: chat, contentWidth: 900, composerBottomInset: 24, tabs: [], tabActions: nil)
                }
                DesktopWorkspaceInspector(apiClient: api, chat: chat, context: nil, onOpenTool: { _ in }, onOpenOutput: { _ in })
                    .frame(width: 300).padding(.horizontal, 16)
            }
            .background(Theme.sloppyDark.colors.background)
            .environment(\.theme, .sloppyDark)
            .environment(\.scenePhase, .active)
            .environment(chat)
            .environment(monitor)
            .preferredColorScheme(.dark)
        )
        let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 1500, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(500))
        host.layoutSubtreeIfNeeded()
        #expect(AppKitTestAccessibility.element(in: host, identifier: "workspace.desktop-inspector") != nil)
        if let directory = ProcessInfo.processInfo.environment["SLOPPY_DESIGN_SCREENSHOTS"] {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("desktop-chat.png"))
        }

        chat.transcript.replaceAll([])
        try await Task.sleep(for: .milliseconds(300))
        if let directory = ProcessInfo.processInfo.environment["SLOPPY_DESIGN_SCREENSHOTS"] {
            for frame in 0..<2 {
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("desktop-empty-ascii-\(frame).png"))
                try await Task.sleep(for: .milliseconds(1500))
            }
        }

        let composerHost = NSHostingView(rootView:
            ChatComposerOverlay(viewModel: chat, contentWidth: 420, composerBottomInset: 16, tabs: [], tabActions: nil)
                .environment(\.theme, .sloppyDark).preferredColorScheme(.dark)
        )
        window.contentView = composerHost
        window.setContentSize(NSSize(width: 420, height: 220))
        try await Task.sleep(for: .milliseconds(250))
        composerHost.layoutSubtreeIfNeeded()
        let editor = try #require(descendants(composerHost).compactMap { $0 as? NSTextView }.first)
        let frame = editor.convert(editor.bounds, to: composerHost)
        #expect(frame.minX >= 0)
        #expect(frame.maxX <= composerHost.bounds.maxX + 1)
        #expect(frame.width > 200)
        let action = try #require(AppKitTestAccessibility.element(in: composerHost, identifier: "chat.composer.trailing-action"))
        let actionFrame = try #require(AppKitTestAccessibility.frame(of: action))
        #expect(actionFrame.width >= 36)
        if let directory = ProcessInfo.processInfo.environment["SLOPPY_DESIGN_SCREENSHOTS"] {
            let bitmap = try #require(composerHost.bitmapImageRepForCachingDisplay(in: composerHost.bounds))
            composerHost.cacheDisplay(in: composerHost.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("desktop-composer-narrow.png"))
        }
    }

    @Test func composerGrowsWithTextAndKeepsPickersOutsideInput() async throws {
        AppKitTestAccessibility.enable()
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "https://composer-layout.invalid")))
        let model = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
            settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            responseNotificationScheduler: DesktopDesignNotifications(), onOpenSettings: { _ in })
        model.selectedAgent = .init(id: "anton", displayName: "Антон")
        model.availableModels = [.init(id: "claude-sonnet", title: "Claude Sonnet")]
        model.selectedModelId = "claude-sonnet"
        let host = NSHostingView(rootView: ZStack(alignment: .bottom) {
            Theme.sloppyDark.colors.background
            ChatComposerOverlay(viewModel: model, contentWidth: 800,
                composerBottomInset: 16, tabs: [], tabActions: nil)
        }.environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 800, height: 400),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        func frame(_ id: String) throws -> CGRect {
            let element = try #require(AppKitTestAccessibility.element(in: host, identifier: id))
            return try #require(AppKitTestAccessibility.frame(of: element))
        }
        func capture(_ name: String) throws {
            guard let directory = ProcessInfo.processInfo.environment["SLOPPY_COMPOSER_CAPTURE_DIR"] else { return }
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
        }
        let empty = try frame("chat.composer.input-surface")
        #expect(empty.height <= 56)
        let settings = try frame("chat.composer.settings")
        let picker = try frame("chat.composer.model-picker")
        #expect(!empty.intersects(settings))
        #expect(settings.contains(picker))
        try capture("composer-empty.png")
        let editor = try #require(descendants(host).compactMap { $0 as? NSTextView }.first)
        #expect(window.makeFirstResponder(editor))
        editor.string = (1...12).map { "Line \($0): a longer message for native editor layout." }.joined(separator: "\n")
        editor.didChangeText()
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        let expanded = try frame("chat.composer.input-surface")
        #expect(expanded.height > empty.height + 40)
        #expect(expanded.height <= 180)
        #expect(editor.enclosingScrollView?.hasVerticalScroller == true)
        #expect(window.firstResponder === editor)
        #expect(model.composerDraft.text == editor.string)
        #expect(!expanded.intersects(try frame("chat.composer.settings")))
        try capture("composer-expanded.png")
        editor.string = ""
        editor.didChangeText()
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        #expect(abs(try frame("chat.composer.input-surface").height - empty.height) <= 1)
        #expect(window.firstResponder === editor)
        try capture("composer-cleared.png")
        window.setContentSize(NSSize(width: 420, height: 400))
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let narrowInput = try frame("chat.composer.input-surface")
        let narrowPicker = try frame("chat.composer.model-picker")
        #expect(narrowPicker.minX >= narrowInput.minX)
        #expect(narrowPicker.maxX <= narrowInput.maxX)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}

@MainActor
private final class DesktopDesignNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
