#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient
@testable import SloppyFeatureChat

@Suite("Persistent workspace inspector", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct WorkspaceInspectorInteractionTests {
    @Test func toolButtonOpensBrowserWithoutHidingBlocksOutsideChat() async throws {
        AppKitTestAccessibility.enable()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkspaceInspectorURLProtocol.self]
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "https://inspector-fixture.invalid")),
                                  session: URLSession(configuration: configuration),
                                  authSessionStore: AuthSessionStore(persistence: .memory))
        let settings = ClientSettings()
        let monitor = ConnectionMonitor(baseURL: api.baseURL)
        let model = MainViewModel(endpoint: api.endpoint, settings: settings, connectionMonitor: monitor,
                                  cacheStore: ClientCacheStore(path: ":memory:"), apiClient: api,
                                  responseNotificationScheduler: InspectorNotifications(),
                                  onOpenSettings: { _ in }, onOpenWorkspace: {})
        let main = MainView(endpoint: api.endpoint, settings: settings, connectionMonitor: monitor,
                            onOpenSettings: { _ in }, onOpenWorkspace: {}, viewModel: model)
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        let window = makeWindow(host, width: 1400, height: 860)
        defer { window.contentView = nil; window.close() }
        for section in [MainAppSection.usage, .sites, .agents, .chats] {
            model.selectedAppSection = section
            host.rootView = AnyView(VStack(spacing: 0) {
                HStack { Spacer(); main.workspaceSidePanelButton }.padding(8)
                main.workspacePanelContainer
            }.theme(.sloppyDark).desktopScreenStyle().preferredColorScheme(.dark))
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            #expect(AppKitTestAccessibility.element(in: host, identifier: "workspace.desktop-inspector") != nil)
            let toggle = try #require(AppKitTestAccessibility.element(in: host, identifier: "workspace.dock.toggle"))
            #expect(AppKitTestAccessibility.press(toggle))
            try await Task.sleep(for: .milliseconds(150))
            #expect(model.workspaceDockState.isPresented)
            #expect(AppKitTestAccessibility.element(in: host, identifier: "workspace.desktop-inspector") != nil)
            // Opening directly into the browser no longer adds the old picker's
            // extra click delay. Wait for the native slide transition to settle.
            for _ in 0..<80 {
                host.layoutSubtreeIfNeeded()
                if let dock = AppKitTestAccessibility.element(in: host, identifier: "workspace.dock"),
                   let frame = AppKitTestAccessibility.frame(of: dock),
                   frame.maxX <= window.convertToScreen(host.convert(host.bounds, to: nil)).maxX + 1 {
                    break
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            try save(host, name: "inspector-with-browser-\(section.rawValue).png")
            #expect(model.workspaceDockState.selectedTab?.kind == .browser)
            #expect(AppKitTestAccessibility.element(in: host, identifier: "workspace-browser-address") != nil)
            #expect(AppKitTestAccessibility.element(in: host, identifier: "workspace-browser-tool.terminal") != nil)
            let inspector = try #require(AppKitTestAccessibility.element(in: host, identifier: "workspace.desktop-inspector"))
            let dock = try #require(AppKitTestAccessibility.element(in: host, identifier: "workspace.dock"))
            let inspectorFrame = try #require(AppKitTestAccessibility.frame(of: inspector))
            let dockFrame = try #require(AppKitTestAccessibility.frame(of: dock))
            let screenFrame = window.convertToScreen(host.convert(host.bounds, to: nil))
            #expect(dockFrame.maxX <= screenFrame.maxX + 1)
            #expect(inspectorFrame.maxX <= dockFrame.minX + 1)
            #expect(AppKitTestAccessibility.press(toggle))
            try await Task.sleep(for: .milliseconds(100))
            #expect(!model.workspaceDockState.isPresented)
            #expect(AppKitTestAccessibility.element(in: host, identifier: "workspace.desktop-inspector") != nil)
            for tab in model.workspaceDockState.tabs { model.workspaceDockState.close(tab.id) }
        }
        try save(host, name: "persistent-inspector-outside-chat.png")
    }

    @Test func projectNavigationAndIdleWorkersStayInCompactBlocks() async throws {
        AppKitTestAccessibility.enable()
        var selected = ProjectModeSection.kanban
        var openedWorker: String?
        let workers = ["one", "two"].map { id in
            ChatParallelAgent(detail: ChatSessionDetail(
                summary: .init(id: id, agentId: "anton", title: "Worker \(id)"),
                events: [.init(id: "done", type: "run_status", runStatus: .init(stage: .done, label: "Done"))]
            ))
        }
        let host = NSHostingView(rootView: VStack(spacing: 12) {
            ProjectModeNavigationCard(title: "Sloppy", selectedSection: .kanban, onSelect: { selected = $0 })
            ChatWorkerActivityPanel(workers: workers, onOpenWorker: { openedWorker = $0 })
            Spacer(minLength: 0)
        }.padding(12).theme(.sloppyDark).desktopScreenStyle().preferredColorScheme(.dark))
        let window = makeWindow(host, width: 304, height: 600)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(150))
        try save(host, name: "project-and-workers-initial.png")
        for section in ProjectModeSection.allCases {
            let button = try #require(AppKitTestAccessibility.element(in: host, identifier: "project-mode-\(section.rawValue)"))
            #expect(AppKitTestAccessibility.press(button))
            #expect(selected == section)
        }
        #expect(AppKitTestAccessibility.element(in: host, identifier: "chat.worker.one") == nil)
        try save(host, name: "project-and-workers-collapsed.png")
        let expand = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.worker-activity.toggle"))
        #expect(AppKitTestAccessibility.press(expand))
        try await Task.sleep(for: .milliseconds(100))
        let worker = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.worker.one"))
        #expect(AppKitTestAccessibility.press(worker))
        #expect(openedWorker == "one")
        try save(host, name: "project-and-workers-expanded.png")
    }

    private func makeWindow(_ view: NSView, width: CGFloat, height: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: width, height: height),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func save(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_INSPECTOR_SCREENSHOTS"] else { return }
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }


}

@MainActor
private final class InspectorNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}

private final class WorkspaceInspectorURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "inspector-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
