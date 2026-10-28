import Foundation
import Testing
import SloppyClientCore
@testable import SloppyClient

@Suite("Workspace changes")
@MainActor
struct WorkspaceChangesTests {
    @Test func loadsEveryDirectoryInWorkspaceOrderAndTotalsTheirChanges() async throws {
        let model = try await workspaceChangesModel(projectID: "workspace")
        #expect(model.directoryChanges.map(\.path) == ["/work/first", "/work/second & third"])
        #expect(model.directoryChanges.map { $0.sourceControl?.fileChanges.first?.path } == ["shared.swift", "shared.swift"])
        #expect(model.directoryChanges.map { $0.sourceControl?.branch } == ["first", "second"])
        #expect(model.changesLinesAdded == 7)
        #expect(model.changesLinesDeleted == 3)
    }

    @Test func unavailableDirectoryKeepsOtherChangesVisible() async throws {
        let model = try await workspaceChangesModel(projectID: "partial")
        #expect(model.directoryChanges.count == 2)
        #expect(try #require(model.directoryChanges.first).sourceControl?.hasChanges == true)
        #expect(try #require(model.directoryChanges.last).sourceControl == nil)
        #expect(model.changesLinesAdded == 2)
        #expect(model.changesLinesDeleted == 1)
    }

    @Test func liveChatUpdateDoesNotReplaceOtherDirectories() async throws {
        let model = try await workspaceChangesModel(projectID: "workspace")
        model.areChangesExpanded = false
        model.synchronizeSourceControl(.init(providerId: "git-cli", isRepository: true, linesAdded: 999))
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.directoryChanges.count == 2)
        #expect(model.changesLinesAdded == 7)
        #expect(!model.areChangesExpanded)
    }

    @Test func singleDirectoryRetainsExistingSourceControlFlow() async throws {
        let model = try await workspaceChangesModel(projectID: "single")
        #expect(model.directoryChanges.isEmpty)
        #expect(model.changesLinesAdded == 2)
        model.synchronizeSourceControl(.init(providerId: "git-cli", isRepository: true, linesAdded: 9))
        #expect(model.changesLinesAdded == 9)
    }

    @Test func olderCoreDoesNotDuplicatePrimaryChangesForOtherDirectories() async throws {
        let model = try await workspaceChangesModel(projectID: "legacy")
        #expect(model.directoryChanges.count == 2)
        #expect(try #require(model.directoryChanges.last).sourceControl == nil)
        #expect(model.changesLinesAdded == 2)
    }

}

@MainActor
private func workspaceChangesModel(projectID: String) async throws -> WorkspacePanelViewModel {
    let model = WorkspacePanelViewModel(apiClient: try workspaceChangesAPI())
    model.activate(context: .init(projectId: projectID, projectName: "Workspace"))
    for _ in 0..<300 {
        if model.project != nil && !model.isLoadingEnvironment { return model }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Workspace environment did not finish loading")
    return model
}

private func workspaceChangesAPI() throws -> SloppyAPIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WorkspaceChangesURLProtocol.self]
    return SloppyAPIClient(
        baseURL: try #require(URL(string: "https://workspace-changes.invalid")),
        session: URLSession(configuration: configuration),
        authSessionStore: AuthSessionStore(persistence: .memory)
    )
}

private final class WorkspaceChangesURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "workspace-changes.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let projectID = url.pathComponents.dropFirst(3).first ?? "workspace"
        let directory = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "directoryPath" }?.value
        let isSecondary = directory == "/work/second & third"
        let status = isSecondary && projectID == "partial" ? 503 : isSecondary && projectID == "legacy" ? 404 : 200
        let data: Data
        if url.path.contains("/source-control/working-tree") {
            let diff = """
            diff --git a/shared.swift b/shared.swift
            --- a/shared.swift
            +++ b/shared.swift
            @@ -1 +1 @@
            -old
            +new
            """
            data = try! JSONEncoder().encode(ProjectWorkingTreeSourceControlResponse(
                providerId: "git-cli", isRepository: true, branch: isSecondary ? "second" : "first",
                linesAdded: isSecondary ? 5 : 2, linesDeleted: isSecondary ? 2 : 1, diff: diff
            ))
        } else if url.path.contains("/projects/") {
            data = try! JSONEncoder().encode(APIProjectRecord(
                id: projectID, name: "Workspace", kind: projectID == "single" ? .project : .workspace,
                directoryPaths: projectID == "single" ? ["/work/first"] : ["/work/first", "/work/second & third"]
            ))
        } else {
            data = Data("{\"items\":[],\"providers\":[],\"failures\":{}}".utf8)
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

#if os(macOS)
import AppKit
import SwiftUI
import SloppyClientUI
import SloppyUITestSupport

@Suite("Workspace changes interaction", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct WorkspaceChangesInteractionTests {
    @Test func extractedDesktopCardCollapsesAndExpandsAfterRefresh() async throws {
        AppKitTestAccessibility.enable()
        let model = try await workspaceChangesModel(projectID: "workspace")
        // The inspector renders this property without mounting the environment view's body.
        let host = NSHostingView(rootView: AnyView(WorkspaceChangesCardFixture(model: model)
            .theme(.sloppyDark).preferredColorScheme(.dark)))
        let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 304, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        try capture(host, name: "workspace-changes-initial.png")
        let directoryID = "workspace.changes.directory./work/second & third"
        #expect(AppKitTestAccessibility.element(in: host, identifier: directoryID) != nil)
        let toggle = try #require(AppKitTestAccessibility.element(in: host, identifier: "workspace.changes.toggle"))
        #expect(AppKitTestAccessibility.press(toggle))
        try await Task.sleep(for: .milliseconds(200))
        #expect(!model.areChangesExpanded)
        #expect(AppKitTestAccessibility.element(in: host, identifier: directoryID) == nil)
        try capture(host, name: "workspace-changes-collapsed.png")
        await model.refreshEnvironment()
        #expect(!model.areChangesExpanded)
        #expect(AppKitTestAccessibility.press(toggle))
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.areChangesExpanded)
        #expect(AppKitTestAccessibility.element(in: host, identifier: directoryID) != nil)
        try capture(host, name: "workspace-changes-expanded.png")
    }

    private func capture(_ host: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_INSPECTOR_SCREENSHOTS"] else { return }
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}

private struct WorkspaceChangesCardFixture: View {
    let model: WorkspacePanelViewModel

    var body: some View {
        VStack {
            WorkspaceEnvironmentPanelView(viewModel: model, onOpenTerminal: nil).desktopChangesCard
            Spacer()
        }
        .padding(12)
    }
}
#endif
