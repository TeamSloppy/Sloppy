import Foundation
import SloppyClientCore
import Testing

@Suite("Canvas workspace integration")
struct CanvasWorkspaceIntegrationTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("chat session metadata carries an optional workspace")
    func chatSessionMetadataCarriesWorkspace() throws {
        let summary = ChatSessionSummary(
            id: "session-1",
            agentId: "agent-1",
            title: "Canvas planning",
            projectId: "project-1",
            workspaceId: "ws-1"
        )
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(ChatSessionSummary.self, from: data)

        #expect(decoded.workspaceId == "ws-1")
        #expect(decoded.projectId == "project-1")
    }

    @Test("workspace summary decodes the Core list payload")
    func workspaceSummaryDecodesCorePayload() throws {
        let payload = """
        {
          "id": "ws-1",
          "title": "Architecture",
          "description": "Shared canvas",
          "ownerId": "user-1",
          "projectId": "project-1",
          "revision": 7,
          "isArchived": false,
          "createdAt": "2026-07-28T00:00:00Z",
          "updatedAt": "2026-07-28T01:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let workspace = try decoder.decode(
            CanvasWorkspaceSummary.self,
            from: Data(payload.utf8)
        )

        #expect(workspace.id == "ws-1")
        #expect(workspace.projectId == "project-1")
        #expect(workspace.revision == 7)
    }

    @Test("workspace creation request preserves the project link")
    func workspaceCreationRequestCoding() throws {
        let request = CanvasWorkspaceCreateRequest(
            title: "Architecture",
            description: "Shared canvas",
            projectId: "project-1"
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CanvasWorkspaceCreateRequest.self, from: data)

        #expect(decoded == request)
        #expect(decoded.projectId == "project-1")
        #expect(decoded.templateId == nil)
    }

    @Test("main view keeps coding and workspace surfaces mounted")
    func mainViewKeepsBothModesMounted() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")

        #expect(mainView.contains("@SceneStorage(\"sloppy.main-content-mode\")"))
        #expect(!mainView.contains("mainContentModePicker"))
        #expect(mainView.contains("viewModel.selectedAppSection == .workspace"))
        #expect(mainView.contains("CanvasWorkspaceSurface(viewModel: canvasWorkspaceViewModel)"))
        #expect(mainView.contains(".opacity(isCanvasWorkspaceSelected ? 0.0 : 1.0)"))
        #expect(mainView.contains(".opacity(isCanvasWorkspaceSelected ? 1.0 : 0.0)"))
        #expect(mainView.contains(".task(id: canvasResolutionKey)"))
        #expect(mainView.contains("ToolbarItem(placement: .navigation)"))
        #expect(mainView.contains("returnToCanvasWorkspaceLibrary()"))
    }

    @Test("canvas starts native and opens a narrow WKWebView bridge on selection")
    func canvasUsesNativeLibraryBeforeWebViewBridge() throws {
        let surface = try source(
            "Sources/SloppyClient/Workspace/Canvas/CanvasWorkspaceSurface.swift"
        )
        let library = try source(
            "Sources/SloppyClient/Workspace/Canvas/CanvasWorkspaceLibraryView.swift"
        )
        let webView = try source(
            "Sources/SloppyClient/Workspace/Canvas/CanvasWorkspaceWebView.swift"
        )
        let viewModel = try source(
            "Sources/SloppyClient/Workspace/Canvas/CanvasWorkspaceViewModel.swift"
        )

        #expect(surface.contains("if viewModel.isShowingLibrary"))
        #expect(surface.contains("CanvasWorkspaceLibraryView(viewModel: viewModel)"))
        #expect(!surface.contains(".overlay(alignment: .topLeading)"))
        #expect(library.contains("List(filteredWorkspaces)"))
        #expect(library.contains("viewModel.openWorkspace(workspace)"))
        #expect(library.contains("CanvasWorkspaceCreateSheet(viewModel: viewModel)"))
        #expect(webView.contains("struct CanvasWorkspaceWebView: NSViewRepresentable"))
        #expect(webView.contains("configuration.websiteDataStore = .default()"))
        #expect(webView.contains("requestedReloadToken != reloadToken"))
        #expect(viewModel.contains("http://localhost:25102"))
        #expect(viewModel.contains("dashboardBaseURL: URL? = nil"))
        #expect(viewModel.contains("URLQueryItem(name: \"embed\", value: \"workspace\")"))
        #expect(viewModel.contains("URLQueryItem(name: \"apiBase\", value: apiBaseURL.absoluteString)"))
        #expect(viewModel.contains("fetchCanvasWorkspaces(projectId: projectID)"))
        #expect(viewModel.contains("func openWorkspace(_ workspace: CanvasWorkspaceSummary)"))
        #expect(viewModel.contains("func showLibrary()"))
    }
}
