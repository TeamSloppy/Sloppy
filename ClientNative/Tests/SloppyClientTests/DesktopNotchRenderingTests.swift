#if os(macOS)
import AppKit
import Foundation
import SloppyClientCore
import SwiftUI
import Testing
import SloppyUITestSupport
@testable import SloppyClient
@testable import SloppyFeatureChat

@Suite("Desktop notch rendering", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct DesktopNotchRenderingTests {
    @Test func subagentGroupsExpandAndOpenTheExactChildChat() async throws {
        AppKitTestAccessibility.enable()
        let state = SloppyDesktopOverlayState()
        state.notchGeometry = SloppyDesktopNotchGeometry(hardwareWidth: 200, hardwareHeight: 32)
        state.agentPalettes = ["yadev": "mint"]
        state.setRecentChats([
            .init(id: "yadev/review", agentID: "yadev", sessionID: "review",
                title: "Review mobile presentation changes", agentName: "Yadev", updatedAt: Date(timeIntervalSince1970: 1),
                projectName: "Promozavr"),
            .init(id: "yadev/ios", agentID: "yadev", sessionID: "ios",
                title: "Check iOS lifecycle coverage", agentName: "Yadev", updatedAt: Date(timeIntervalSince1970: 10),
                parentSessionID: "review", kind: "worker"),
            .init(id: "yadev/android", agentID: "yadev", sessionID: "android",
                title: "Verify Android regressions", agentName: "Yadev", updatedAt: Date(timeIntervalSince1970: 8),
                parentSessionID: "review", kind: "worker"),
            .init(id: "yadev/logs", agentID: "yadev", sessionID: "logs",
                title: "Inspect emulator logs", agentName: "Yadev", updatedAt: Date(timeIntervalSince1970: 9),
                parentSessionID: "android", kind: "worker"),
            .init(id: "yadev/metrics", agentID: "yadev", sessionID: "metrics",
                title: "Update development metrics", agentName: "Yadev", updatedAt: Date(timeIntervalSince1970: 5)),
        ])
        state.selectSection(.chats)
        let size = SloppyDesktopNotchView.size(for: state)
        let host = NSHostingView(rootView: SloppyDesktopNotchView(state: state, isPointerInsidePanel: { true }))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await capture(host, name: "notch-subagents-collapsed")
        #expect(state.recentChatGroups.count == 2)
        #expect(AppKitTestAccessibility.element(in: host, identifier: "notch.session.yadev/ios") == nil)
        let disclosure = try #require(AppKitTestAccessibility.element(in: host, identifier: "notch.session.yadev/review.subagents"))
        #expect(AppKitTestAccessibility.press(disclosure))
        try await capture(host, name: "notch-subagents-expanded")
        #expect(state.selectedChat == nil)
        #expect(AppKitTestAccessibility.element(in: host, identifier: "notch.session.yadev/ios") != nil)
        #expect(AppKitTestAccessibility.element(in: host, identifier: "notch.session.yadev/logs") == nil)
        let nested = try #require(AppKitTestAccessibility.element(in: host, identifier: "notch.session.yadev/android.subagents"))
        #expect(AppKitTestAccessibility.press(nested))
        try await capture(host, name: "notch-subagents-nested")
        let child = try #require(AppKitTestAccessibility.element(in: host, identifier: "notch.session.yadev/logs"))
        #expect(AppKitTestAccessibility.press(child))
        #expect(state.selectedChat?.sessionSummary.id == "logs")
        #expect(state.selectedChat?.sessionSummary.parentSessionId == "android")
        state.backToChats()
        try await capture(host, name: "notch-subagents-return")
        #expect(state.expandedRecentChatIDs == ["yadev/review", "yadev/android"])
    }

    @Test func collapsedNotchHasVisibleWingsBesideCameraHousing() async throws {
        let state = SloppyDesktopOverlayState()
        state.notchGeometry = SloppyDesktopNotchGeometry(hardwareWidth: 200, hardwareHeight: 32)
        state.setActiveAgentRuns([
            .init(id: "agent/session", agentID: "yadev", sessionID: "session",
                  sessionTitle: "Working", agentName: "Yadev", stage: .thinking,
                  statusLabel: "Thinking", statusDetails: nil, needsInput: false,
                  inputPrompt: nil, updatedAt: Date())
        ])
        let size = SloppyDesktopNotchView.size(for: state)
        let host = NSHostingView(rootView: SloppyDesktopNotchView(state: state, isPointerInsidePanel: { true }))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await capture(host, name: "notch-collapsed")
        #expect(!state.isExpanded)
        #expect(host.bounds.width > state.notchGeometry.hardwareWidth)
        #expect(host.bounds.size == size)
    }

    @Test func sectionsAndInlineChatKeepThePanelGeometry() async throws {
        let settings = ClientSettings()
        let previous = (settings.lastAgentId, settings.lastProjectId, settings.lastSessionId)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NotchOfflineURLProtocol.self]
        let api = SloppyAPIClient(
            baseURL: try #require(URL(string: "http://notch-render.invalid")),
            session: URLSession(configuration: configuration)
        )
        let agents = [
            APIAgentRecord(id: "yadev", displayName: "Yadev"),
            APIAgentRecord(id: "ada", displayName: "Ada"),
            APIAgentRecord(id: "promozavr", displayName: "Promozavr"),
        ]
        let cache = ClientCacheStore(path: ":memory:")
        await cache.cacheAgents(agents)
        let model = ChatScreenViewModel(
            apiClient: api, cacheStore: cache, settings: settings,
            connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            restoresLastSession: false,
            responseNotificationScheduler: NotchRenderingNotifications(),
            sessionStreamProvider: { _, _ in AsyncStream { $0.finish() } },
            onOpenSettings: { _ in }
        )
        await model.waitForInitialData()
        defer {
            model.closeSession()
            settings.lastAgentId = previous.0
            settings.lastProjectId = previous.1
            settings.lastSessionId = previous.2
        }
        let state = SloppyDesktopOverlayState()
        state.notchGeometry = SloppyDesktopNotchGeometry(hardwareWidth: 200, hardwareHeight: 32)
        state.agents = agents
        state.agentPalettes = ["yadev": "mint", "ada": "violet", "promozavr": "amber"]
        state.onMakeChatViewModel = { model }
        state.setRecentChats([
            .init(id: "yadev/parallel", agentID: "yadev", sessionID: "parallel",
                  title: "Parallel agents in Sloppy", agentName: "Yadev", updatedAt: Date(),
                  projectID: "sloppy", projectName: "Sloppy"),
            .init(id: "ada/editor", agentID: "ada", sessionID: "editor",
                  title: "Editor grid and guides", agentName: "Ada", updatedAt: Date()),
        ])
        state.setExpanded(true)
        let size = SloppyDesktopNotchView.size(for: state)
        let host = NSHostingView(rootView: SloppyDesktopNotchView(state: state, isPointerInsidePanel: { true }))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }

        try await capture(host, name: "notch-home")
        state.selectSection(.chats)
        #expect(SloppyDesktopNotchView.size(for: state) == size)
        try await capture(host, name: "notch-chats")
        state.openRecentChat(state.recentChats[0])
        for _ in 0..<100 where model.isLoadingTranscript {
            try await Task.sleep(for: .milliseconds(10))
        }
        model.transcript.replaceAll([
            .init(id: "user", role: .user, segments: [
                .init(kind: .text, text: "I like that Sloppy can work on several tasks in parallel.")
            ]),
            .init(id: "assistant", role: .assistant, segments: [
                .init(kind: .text, text: "I'll split the work between agents and bring their results back to this conversation.")
            ]),
        ])
        #expect(model.selectedAgent?.id == "yadev")
        #expect(model.selectedSessionId == "parallel")
        #expect(SloppyDesktopNotchView.size(for: state) == size)
        try await capture(host, name: "notch-chat")
        state.selectSection(.tasks)
        #expect(SloppyDesktopNotchView.size(for: state) == size)
        #expect(host.bounds.size == size)
    }

    private func capture(_ host: NSView, name: String) async throws {
        for _ in 0..<8 {
            await Task.yield()
            host.layoutSubtreeIfNeeded()
        }
        try await Task.sleep(for: .milliseconds(150))
        host.needsDisplay = true
        host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        if let path = ProcessInfo.processInfo.environment["SLOPPY_NOTCH_CAPTURE_DIR"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }
}

private final class NotchOfflineURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

@MainActor
private final class NotchRenderingNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
