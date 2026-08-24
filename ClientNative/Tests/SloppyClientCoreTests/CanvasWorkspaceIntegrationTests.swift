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

    @Test("canvas editor is native and web views are scoped to artifacts")
    func canvasUsesNativeEditorWithArtifactWebView() throws {
        let surface = try source(
            "Sources/SloppyClient/Workspace/Canvas/CanvasWorkspaceSurface.swift"
        )
        let library = try source(
            "Sources/SloppyClient/Workspace/Canvas/CanvasWorkspaceLibraryView.swift"
        )
        let editor = try source(
            "Sources/SloppyClient/Workspace/Canvas/CanvasWorkspaceEditorView.swift"
        )
        let pencil = try source(
            "Sources/SloppyClient/Workspace/Canvas/CanvasPencilSurface.swift"
        )
        let webView = try source(
            "Sources/SloppyClient/Workspace/Web/WorkspaceWebView.swift"
        )
        let viewModel = try source(
            "Sources/SloppyClient/Workspace/Canvas/CanvasWorkspaceViewModel.swift"
        )
        let inspector = try source(
            "Sources/SloppyClient/Workspace/Canvas/CanvasWorkspaceInspector.swift"
        )

        #expect(surface.contains("if viewModel.isShowingLibrary"))
        #expect(surface.contains("CanvasWorkspaceLibraryView("))
        #expect(surface.contains("allowsProjectSelection: allowsProjectSelection"))
        #expect(surface.contains("CanvasWorkspaceEditorView(viewModel: viewModel)"))
        #expect(!surface.contains("CanvasWorkspaceWebView(viewModel: viewModel)"))
        #expect(!surface.contains(".overlay(alignment: .topLeading)"))
        #expect(library.contains("List(filteredWorkspaces)"))
        #expect(library.contains("CanvasWorkspaceLibraryCard("))
        #expect(library.contains("CanvasWorkspaceCardPreview(workspace: workspace)"))
        #expect(library.contains("AsyncImage(url: coverURL)"))
        #expect(library.contains("canvas-workspace-layout-picker"))
        #expect(!library.contains("Workspace Files"))
        #expect(library.contains("await viewModel.selectProject(project)"))
        #expect(library.contains("canvas-project-picker"))
        #expect(library.contains("viewModel.openWorkspace(workspace)"))
        #expect(library.contains("CanvasWorkspaceCreateSheet(viewModel: viewModel)"))
        #expect(library.contains("CanvasWorkspaceViewModel.personalWorkspaceName"))
        #expect(!library.contains("All Projects"))
        #expect(library.contains(".listRowBackground(Color.clear)"))
        #expect(library.contains(".scrollContentBackground(.hidden)"))
        #expect(editor.contains("CanvasWorkspaceGrid()"))
        #expect(editor.contains("viewport: viewport"))
        #expect(editor.contains("zoom: effectiveZoom"))
        #expect(editor.contains("viewport.offset.x / safeZoom"))
        #expect(editor.contains("context.stroke("))
        #expect(editor.contains("cameraPath"))
        #expect(editor.contains("CanvasPencilSurface("))
        #expect(!editor.contains(".background(Color.secondary.opacity(0.055))"))
        #expect(editor.contains("WorkspaceWebView(html: html"))
        #expect(editor.contains(".scrollIndicators(.hidden)"))
        #expect(editor.contains("MagnifyGesture()"))
        #expect(editor.contains("value.startLocation"))
        #expect(editor.contains("canvasScrollPosition.scrollTo(point:"))
        #expect(editor.contains("geometry.contentOffset"))
        #expect(editor.contains("CanvasInputToolPill(selection:"))
        #expect(editor.contains("CanvasZoomPill("))
        #expect(editor.contains("CanvasRegionPromptCard("))
        #expect(editor.contains("regionCaptureHandle.pngData(for:"))
        #expect(editor.contains("regionAction: request.action"))
        #expect(editor.contains("TextEditor(text: $draftText)"))
        #expect(editor.contains("@FocusState private var isEditorFocused: Bool"))
        #expect(editor.contains(".focused($isEditorFocused)"))
        #expect(editor.contains(".onChange(of: isEditorFocused)"))
        #expect(editor.contains(".onChange(of: isSelected)"))
        #expect(editor.contains("viewModel.selectedElementID = nil"))
        #expect(editor.contains("guard isEditing else { return }"))
        #expect(editor.contains("element.kind == .sticky || element.kind == .text || element.kind == .shape"))
        #expect(editor.contains("TapGesture(count: 2)"))
        #expect(editor.contains("viewModel.isMiniMapPresented.toggle()"))
        #expect(editor.contains("CanvasWorkspaceInspector(viewModel: viewModel"))
        #expect(editor.contains("CanvasWorkspaceLayersPanel(viewModel: viewModel"))
        #expect(editor.contains(".safeAreaInset(edge: .leading"))
        #expect(editor.contains(".safeAreaInset(edge: .trailing"))
        #expect(editor.contains("CanvasTrackpadZoomSource(onMagnify:"))
        #expect(editor.contains("NSMagnificationGestureRecognizer"))
        #expect(pencil.contains("import PencilKit"))
        #expect(pencil.contains("canvas.drawingPolicy = .pencilOnly"))
        #expect(pencil.contains("PKInkingTool"))
        #expect(pencil.contains("drawing.image("))
        #expect(pencil.contains(".pngData()"))
        #expect(pencil.contains("case select, region, pencil, eraser"))
        #expect(editor.contains("window.drawHierarchy"))
        #expect(editor.contains("bitmapImageRepForCachingDisplay"))
        #expect(webView.contains("struct WorkspaceWebView: NSViewRepresentable"))
        #expect(webView.contains("struct WorkspaceWebView: UIViewRepresentable"))
        #expect(webView.contains("init(html: String, title: String)"))
        #expect(viewModel.contains("fetchCanvasWorkspaces(projectId: requestedProjectID)"))
        #expect(viewModel.contains("requestedProjectID != nil || $0.projectId == nil"))
        #expect(viewModel.contains("static let personalWorkspaceName = \"Personal\""))
        #expect(viewModel.contains("projectName: normalizedProjectID == nil ? nil"))
        #expect(viewModel.contains("fetchProjects()"))
        #expect(!viewModel.contains("fetchProjectFiles(projectId: projectID, path: \"\")"))
        #expect(viewModel.contains("func selectProject(_ project: APIProjectRecord?) async"))
        #expect(viewModel.contains("fetchCanvasWorkspaceDocument(workspaceId:"))
        #expect(viewModel.contains("savePencilDrawing"))
        #expect(viewModel.contains("data:image/png;base64,"))
        #expect(viewModel.contains("SessionSocketManager("))
        #expect(viewModel.contains("case .sessionDelta:"))
        #expect(viewModel.contains("appendStreamingText(delta"))
        #expect(viewModel.contains("id: \"optimistic-user-\\(UUID().uuidString)\""))
        #expect(viewModel.contains("messages.removeAll { $0.id.hasPrefix(\"optimistic-user-\") }"))
        #expect(viewModel.contains("attachments: attachments"))
        #expect(viewModel.contains("enum CanvasRegionAgentAction"))
        #expect(inspector.contains("message.id == viewModel.streamingMessageID"))
        #expect(!inspector.contains("Picker(\"Inspector section\""))
        #expect(viewModel.contains("func openWorkspace(_ workspace: CanvasWorkspaceSummary)"))
        #expect(viewModel.contains("func showLibrary()"))
    }

    @Test("workspace wire model preserves native pencil data")
    func workspaceWireModelPreservesPencilData() throws {
        let drawing = Data([0, 1, 2, 3]).base64EncodedString()
        let element = CanvasWorkspaceElement(
            id: "native-pencil-drawing",
            kind: .image,
            bounds: CanvasWorkspaceRect(x: 0, y: 0, width: 3200, height: 2400),
            data: ["pencilDrawing": .string(drawing)]
        )
        let encoded = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(CanvasWorkspaceElement.self, from: encoded)

        #expect(decoded.data["pencilDrawing"]?.stringValue == drawing)
    }
}
