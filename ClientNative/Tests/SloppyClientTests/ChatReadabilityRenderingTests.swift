#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Chat readability interaction", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ChatReadabilityRenderingTests {
    @Test func capturesSyntaxHierarchyAndLiveWorkingPulse() async throws {
        AppKitTestAccessibility.enable()
        let source = SourceFileFixture(content: "import Foundation\n\n// A linked source file\nstruct Greeting {\n    let message = \"Hello, Sloppy!\"\n    let count = 42\n    func run() async throws {\n        print(message)\n    }\n}\n")
        let file = WorkspaceSourceFileViewModel(reference: .init(path: "/remote/File.swift", line: 5), apiClient: source.api,
            scope: .session(agentID: "agent", sessionID: "source-session"))
        let root = ChatSessionSummary(id: "root", agentId: "agent", title: "Parent conversation")
        let child = ChatSessionSummary(id: "child", agentId: "agent", title: "Nested execution", parentSessionId: "root")
        let leaf = ChatSessionSummary(id: "leaf", agentId: "agent", title: "Nested verification", parentSessionId: "child")
        let fixture = SidebarLongChatFixture(sessions: [root, child, leaf])
        let main = MainViewModel(endpoint: fixture.api.endpoint, settings: ClientSettings(),
            connectionMonitor: ConnectionMonitor(baseURL: fixture.api.baseURL), cacheStore: ClientCacheStore(path: ":memory:"),
            apiClient: fixture.api, responseNotificationScheduler: ReadabilityNotifications(), onOpenSettings: { _ in }, onOpenWorkspace: {})
        defer { main.chatViewModel.closeSession() }
        let tree = ChatSidebarSessionTree(sessions: [root, child, leaf])
        let host = NSHostingView(rootView: HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Conversations").font(.headline).padding(12)
                SidebarSessionRow(session: .init(id: "active", agentId: "agent", title: "Agent is working"), projectName: nil,
                    isPinned: false, isSelected: true, activity: .working, onOpen: {}, onTogglePin: {}, onCopyDebugLink: {}, onDelete: {})
                SidebarSessionBranch(viewModel: main, session: root, tree: tree)
                Spacer()
            }.frame(width: 300)
            Divider()
            WorkspaceSourceFileView(viewModel: file)
        }.environment(\.theme, .sloppyDark).environment(\.scenePhase, .active).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 1000, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        for _ in 0..<100 {
            if !file.syntaxLines.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!file.syntaxLines.isEmpty)
        for session in [root, child] {
            let button = try #require(AppKitTestAccessibility.element(in: host, identifier: "sidebar.session.\(session.storageID).children"))
            #expect(AppKitTestAccessibility.press(button))
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(AppKitTestAccessibility.element(in: host, identifier: "sidebar.session.\(leaf.storageID)") != nil)
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_READABILITY_EVIDENCE"] else { return }
        try snapshot(host).write(to: URL(fileURLWithPath: directory).appendingPathComponent("syntax-hierarchy.png"))
        var frames: [Data] = []
        for index in 0..<20 {
            let png = try snapshot(host)
            frames.append(png)
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(String(format: "pulse-%02d.png", index)))
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(Set(frames).count > 1)
    }

    private func snapshot(_ host: NSView) throws -> Data {
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor private final class ReadabilityNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
