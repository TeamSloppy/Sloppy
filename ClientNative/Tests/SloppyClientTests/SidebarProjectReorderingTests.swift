#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
import SloppyFeatureChat
@testable import SloppyClient

@Suite("Sidebar project reordering", .serialized)
@MainActor
struct SidebarProjectReorderingTests {
    @Test(arguments: [
        ("a", "c", SidebarProjectDropPlacement.before, ["b", "a", "c", "d"]),
        ("a", "c", SidebarProjectDropPlacement.after, ["b", "c", "a", "d"]),
        ("d", "b", SidebarProjectDropPlacement.before, ["a", "d", "b", "c"]),
        ("d", "b", SidebarProjectDropPlacement.after, ["a", "b", "d", "c"]),
    ])
    func insertionMatchesPreview(source: String, target: String, placement: SidebarProjectDropPlacement,
                                 expected: [String]) {
        let fixture = SidebarReorderingFixture()
        defer { fixture.close() }
        #expect(fixture.model.moveProject(source, relativeTo: target, placement: placement))
        #expect(fixture.model.projects.map(\.id) == expected)
        #expect(fixture.model.settings.projectOrderIDs == expected)
    }

    @Test func ignoresSelfUnknownAndUnchangedPositions() {
        let fixture = SidebarReorderingFixture()
        defer { fixture.close() }
        #expect(!fixture.model.moveProject("a", relativeTo: "a", placement: .after))
        #expect(!fixture.model.moveProject("unknown", relativeTo: "a", placement: .before))
        #expect(!fixture.model.moveProject("a", relativeTo: "b", placement: .before))
        #expect(fixture.model.projects.map(\.id) == ["a", "b", "c", "d"])
    }

    @Test func nativePayloadMovesOnlyOnDropAndPreviewResets() async throws {
        let fixture = SidebarReorderingFixture()
        defer { fixture.close() }
        let state = SidebarProjectDropState()
        state.update(locationY: 10, height: 100)
        #expect(state.placement == .before)
        state.update(locationY: 90, height: 100)
        #expect(state.placement == .after)
        #expect(fixture.model.projects.map(\.id) == ["a", "b", "c", "d"])
        let provider = SidebarProjectDrag.provider(projectID: "a", name: "Alpha")
        #expect(state.performDrop(providers: [provider]) { id, placement in
            fixture.model.moveProject(id, relativeTo: "c", placement: placement)
        })
        #expect(state.placement == nil)
        for _ in 0..<100 {
            if fixture.model.projects.first?.id == "b" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(fixture.model.projects.map(\.id) == ["b", "c", "a", "d"])
        state.update(locationY: 0, height: 100)
        state.reset()
        #expect(state.placement == nil)
        state.update(locationY: 0, height: 100)
        #expect(!state.performDrop(providers: [NSItemProvider(object: "a" as NSString)]) { _, _ in
            Issue.record("External text must not reorder projects")
            return false
        })
        #expect(state.placement == nil)
    }
}

@Suite("Sidebar project interaction", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct SidebarProjectInteractionTests {
    @Test func newChatAppearsOnlyWhileSectionIsHoveredAndKeepsItsProject() async throws {
        let fixture = SidebarReorderingFixture()
        defer { fixture.close() }
        let group = try #require(ChatSidebarSections.build(sessions: [], projects: fixture.model.projects,
            pinnedSessionIds: [], mode: .projects).projectGroups.first)
        let host = NSHostingView(rootView: AnyView(VStack {
            SidebarProjectGroupView(viewModel: fixture.model, group: group, tree: ChatSidebarSessionTree(sessions: []))
            Spacer()
        }.padding(12).theme(.sloppyDark).preferredColorScheme(.dark)))
        let window = makeWindow(host)
        defer { window.contentView = nil; window.close() }
        AppKitTestAccessibility.enable()
        try await settle(host)
        let identifier = "sidebar.project.a.new-chat"
        #expect(AppKitTestAccessibility.element(in: host, identifier: identifier) == nil)
        try capture(host, name: "sidebar-project-idle.png")
        try hover(host, window: window, entered: true)
        try await settle(host)
        let button = try #require(AppKitTestAccessibility.element(in: host, identifier: identifier))
        try capture(host, name: "sidebar-project-hover.png")
        #expect(AppKitTestAccessibility.press(button))
        #expect(fixture.model.selectedSidebarItem == .project("a"))
        let chat = try #require(fixture.model.selectedTabID.flatMap { fixture.model.tabStates[$0]?.chatState?.viewModel })
        #expect(chat.activeProjectIdForWorkspacePanel == "a")
        try hover(host, window: window, entered: false)
        try await settle(host)
        #expect(AppKitTestAccessibility.element(in: host, identifier: identifier) == nil)
    }

    @Test func insertionLineFollowsPointerAndDisappearsOnExit() async throws {
        let state = SidebarProjectDropState()
        let host = NSHostingView(rootView: AnyView(VStack {
            VStack(alignment: .leading) { Text("Project section"); Text("Chat").padding(.top, 30) }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .modifier(SidebarProjectDropTarget(state: state, move: { _, _ in true }))
            Spacer()
        }.padding(12).theme(.sloppyDark).preferredColorScheme(.dark)))
        let window = makeWindow(host)
        defer { window.contentView = nil; window.close() }
        try await settle(host)
        let idle = try bitmap(host)
        state.update(locationY: 1, height: 100)
        try await settle(host)
        let before = try bitmap(host)
        try capture(host, name: "sidebar-insert-before.png")
        state.update(locationY: 99, height: 100)
        try await settle(host)
        let after = try bitmap(host)
        try capture(host, name: "sidebar-insert-after.png")
        #expect(before != idle)
        #expect(after != before)
        state.reset()
        try await settle(host)
        #expect(try bitmap(host) == idle)
    }

    private func makeWindow(_ host: NSView) -> NSWindow {
        let window = NSWindow(contentRect: .init(x: 100, y: 100, width: 320, height: 220),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func settle(_ host: NSView) async throws {
        for _ in 0..<12 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
    }

    private func hover(_ host: NSView, window: NSWindow, entered: Bool) throws {
        let event = try #require(NSEvent.mouseEvent(with: .mouseMoved,
            location: .init(x: 100, y: 195), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
        func visit(_ view: NSView) {
            for area in view.trackingAreas {
                guard let responder = area.owner as? NSResponder else { continue }
                if entered { responder.mouseEntered(with: event) } else { responder.mouseExited(with: event) }
            }
            view.subviews.forEach(visit)
        }
        visit(host)
    }

    private func bitmap(_ view: NSView) throws -> Data {
        let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        return try #require(image.representation(using: .png, properties: [:]))
    }

    private func capture(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_SIDEBAR_SCREENSHOTS"] else { return }
        try bitmap(view).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}

@MainActor
private final class SidebarReorderingFixture {
    let model: MainViewModel
    private let originalOrder: [String]
    private let originalSelection: (agent: String?, project: String?, session: String?)

    init() {
        let api = SidebarLongChatFixture().api
        let settings = ClientSettings()
        originalOrder = settings.projectOrderIDs
        originalSelection = (settings.lastAgentId, settings.lastProjectId, settings.lastSessionId)
        model = MainViewModel(endpoint: api.endpoint, settings: settings,
            connectionMonitor: ConnectionMonitor(baseURL: api.baseURL), cacheStore: ClientCacheStore(path: ":memory:"),
            apiClient: api, responseNotificationScheduler: SidebarReorderingNotifications(),
            onOpenSettings: { _ in }, onOpenWorkspace: {})
        model.projects = ["a", "b", "c", "d"].map { APIProjectRecord(id: $0, name: "Project \($0.uppercased())") }
    }

    func close() {
        for state in model.tabStates.values { state.chatState?.viewModel.closeSession() }
        model.settings.projectOrderIDs = originalOrder
        model.settings.lastAgentId = originalSelection.agent
        model.settings.lastProjectId = originalSelection.project
        model.settings.lastSessionId = originalSelection.session
    }
}

@MainActor
private final class SidebarReorderingNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
