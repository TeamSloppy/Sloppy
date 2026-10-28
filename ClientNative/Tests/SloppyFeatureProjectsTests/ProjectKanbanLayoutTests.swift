#if os(macOS)
import Foundation
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyFeatureProjects

@Suite("Kanban desktop layout", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ProjectKanbanLayoutTests {
    @Test func boardFitsBetweenOpenSidebarsAndScrollsInNarrowWindows() async throws {
        AppKitTestAccessibility.enable()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KanbanLayoutURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let suite = "kanban-layout-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ProjectKanbanViewModel(
            apiClient: SloppyAPIClient(baseURL: try #require(URL(string: "https://kanban-layout.invalid")),
                session: session, authSessionStore: AuthSessionStore(persistence: .memory)),
            filterStore: ProjectKanbanFilterStore(defaults: defaults)
        )
        await model.load(projectId: "layout")
        #expect(model.filteredColumns.count == 5)
        let board = ProjectKanbanView(viewModel: model, projectId: "layout", projectName: "Layout",
            onOpenTask: { _ in })
        let host = NSHostingView(rootView: GeometryReader { geometry in
            HStack(spacing: 0) {
                Text("Sidebar").frame(width: 280)
                board
                    .frame(width: max(0, geometry.size.width - 584))
                    .clipped()
                Text("Workspace").frame(width: 304)
            }
        }.theme(.sloppyDark).desktopScreenStyle().preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1840, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }

        func frame(_ identifier: String) throws -> CGRect {
            let element = try #require(AppKitTestAccessibility.element(in: host, identifier: identifier))
            return try #require(AppKitTestAccessibility.frame(of: element))
        }
        for width in [1840.0, 1440.0, 1120.0] {
            window.setContentSize(NSSize(width: width, height: 800))
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let screen = window.convertToScreen(host.convert(host.bounds, to: nil))
            let boardBounds = CGRect(x: screen.minX + 280, y: screen.minY,
                width: screen.width - 584, height: screen.height)
            for identifier in ["kanban-task-search", "kanban-create-task", "kanban-column-todo"] {
                let control = try frame(identifier)
                #expect(control.minX >= boardBounds.minX, "\(identifier) at width \(width)")
                #expect(control.maxX <= boardBounds.maxX, "\(identifier) at width \(width)")
                #expect(control.maxY <= boardBounds.maxY)
            }
            if width == 1840 {
                #expect(try frame("kanban-column-other").maxX <= boardBounds.maxX)
            }
            if width == 1120 {
                func scrollViews(in view: NSView) -> [NSScrollView] {
                    (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
                }
                let scroll = try #require(scrollViews(in: host).first {
                    $0.hasHorizontalScroller && ($0.documentView?.bounds.width ?? 0) > $0.contentSize.width
                })
                let document = try #require(scroll.documentView)
                scroll.contentView.scroll(to: NSPoint(x: document.bounds.maxX - scroll.contentSize.width, y: 0))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await Task.sleep(for: .milliseconds(100))
                #expect(try frame("kanban-column-other").maxX <= boardBounds.maxX)
                #expect(try frame("kanban-column-other").minX >= boardBounds.minX)
            }
            if let directory = ProcessInfo.processInfo.environment["SLOPPY_KANBAN_SCREENSHOTS"] {
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("kanban-\(Int(width)).png"))
            }
        }
    }
}

private final class KanbanLayoutURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        do {
            let tasks = ProjectKanbanColumnID.allCases.map {
                APIProjectTask(id: "TASK-\($0.rawValue)", title: "A readable task in \($0.title)", status: $0.taskStatus)
            }
            let data = url.lastPathComponent == "agents" ? Data("[]".utf8)
                : try JSONEncoder().encode(APIProjectRecord(id: "layout", name: "Layout", tasks: tasks))
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
#endif
