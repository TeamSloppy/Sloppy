#if os(macOS)
import AppKit
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import Testing
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Sidebar agent avatars", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct SidebarAgentAvatarTests {
    @Test func activitiesSelectExpressionsFromTypedState() {
        #expect(SidebarSessionActivity.working.avatarEmotion == .working)
        #expect(SidebarSessionActivity.waitingForInput.avatarEmotion == .needsInput)
        #expect(SidebarSessionActivity.failed.avatarEmotion == .error)
        #expect(SidebarSessionActivity.completed.avatarEmotion == .happy)
    }

    @Test func nativeChatRowsShowStatusWithoutCharacters() async throws {
        AppKitTestAccessibility.enable()
        let host = NSHostingView(rootView: SidebarAvatarFixture()
            .environment(\.theme, .sloppyDark)
            .environment(\.scenePhase, .active)
            .preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 348, height: 390),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        let first = try snapshot(host)
        try await Task.sleep(for: .milliseconds(300))
        let second = try snapshot(host)
        #expect(first.representation(using: .png, properties: [:]) == second.representation(using: .png, properties: [:]))
        #expect(AppKitTestAccessibility.element(in: host, identifier: "sidebar.session.avatar") == nil)
        #expect(AppKitTestAccessibility.element(in: host, identifier: "sidebar.session.status") != nil)
        if let directory = ProcessInfo.processInfo.environment["SLOPPY_SIDEBAR_SCREENSHOTS"] {
            try #require(second.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("sidebar-chat-status.png"))
        }
    }

    private func snapshot(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }
}

private struct SidebarAvatarFixture: View {
    private let states: [SidebarSessionActivity?] = [nil, .working, .waitingForInput, .failed, .completed]
    private let titles = ["Plan the release", "Update the client", "Review deployment", "Check the build", "Parallel agents"]
    private let agents = ["a", "b", "c", "d", "a"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sloppy").font(.headline).foregroundStyle(.secondary).padding(.leading, 12).frame(height: 40)
            ForEach(0..<5, id: \.self) { index in
                SidebarSessionRow(
                    session: .init(id: "fixture-\(index)", agentId: agents[index], title: titles[index]),
                    projectName: "Sloppy", instanceName: "home_machine", showsProjectName: false,
                    isPinned: false, isSelected: index == 1, activity: states[index],
                    avatarAgents: index == 4 ? [
                        .init(id: "parent", agentID: "a", paletteID: "mint"),
                        .init(id: "child-1", agentID: "b", paletteID: "violet", emotion: .working),
                        .init(id: "child-2", agentID: "c", paletteID: "coral", emotion: .thinking)
                    ] : [],
                    onOpen: {}, onTogglePin: {}, onCopyDebugLink: {}, onDelete: {}
                )
                .frame(height: 54)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 348, height: 390)
        .background(AppTheme.sloppyDark.colors.background)
    }
}
#endif
