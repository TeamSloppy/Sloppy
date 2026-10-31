#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyFeatureProjects

@Suite("Workflow rendering", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ProjectWorkflowRenderingTests {
    @Test func graphAndEmptyStatesRenderAtDesktopAndPhoneWidths() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkflowFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let model = ProjectWorkflowViewModel(apiClient: SloppyAPIClient(
            baseURL: try #require(URL(string: "https://workflow.test")), session: session,
            authSessionStore: AuthSessionStore(persistence: .memory)
        ))
        await model.load(projectId: "project")
        model.selectRun("fast")
        await model.loadSelectedRun(projectId: "project")
        let workflow = try #require(model.selectedWorkflow)

        for width in [1000.0, 390.0] {
            let host = NSHostingView(rootView: ProjectWorkflowView(viewModel: model, projectId: "project")
                .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 650),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            #expect(bitmap.pixelsWide >= Int(width))
            #expect(abs(host.bounds.width - width) < 1)
            try save(bitmap, name: "workflow-\(Int(width)).png")
            window.orderOut(nil)
            window.contentView = nil
        }

        let graph = ProjectWorkflowGraph(workflow: workflow, detail: model.detail, onSelect: { _ in })
        let graphHost = NSHostingView(rootView: graph.environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        graphHost.frame = NSRect(x: 0, y: 0, width: 1050, height: 480)
        graphHost.layoutSubtreeIfNeeded()
        let bitmap = try #require(graphHost.bitmapImageRepForCachingDisplay(in: graphHost.bounds))
        graphHost.cacheDisplay(in: graphHost.bounds, to: bitmap)
        try save(bitmap, name: "workflow-graph.png")

        await model.load(projectId: "empty")
        #expect(model.workflows.isEmpty)
        try await renderState(model, projectID: "empty", name: "workflow-empty.png")
        await model.load(projectId: "failure")
        #expect(model.errorMessage != nil)
        try await renderState(model, projectID: "failure", name: "workflow-error.png")
    }

    private func renderState(_ model: ProjectWorkflowViewModel, projectID: String, name: String) async throws {
        let host = NSHostingView(rootView: ProjectWorkflowView(viewModel: model, projectId: projectID)
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try save(bitmap, name: name)
    }

    private func save(_ bitmap: NSBitmapImageRep, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_WORKFLOW_SCREENSHOTS"] else { return }
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
#endif
