import Foundation
import Testing

@Suite("Workspace panel source")
struct WorkspacePanelSourceTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("workspace panel loads lazy directories and file previews")
    func workspacePanelLoadsLazyDirectoriesAndPreview() throws {
        let vm = try source("Sources/SloppyClient/Workspace/Panel/WorkspacePanelViewModel.swift")

        #expect(vm.contains("func activate(context: WorkspacePanelContext)"))
        #expect(vm.contains("func refresh() async"))
        #expect(vm.contains("func toggleDirectory(_ path: String) async"))
        #expect(vm.contains("func selectFile(_ path: String) async"))
        #expect(vm.contains("fetchProjectFiles(projectId: context.projectId"))
        #expect(vm.contains("fetchProjectFileContent(projectId: context.projectId"))
    }

    @Test("chat view model accepts dropped project file references")
    func chatViewModelAcceptsDroppedProjectFileReferences() throws {
        let chatVM = try source("Sources/SloppyFeatureChat/Screens/Chat/ChatScreenViewModel.swift")
        let chatScreen = try source("Sources/SloppyFeatureChat/Screens/Chat/ChatScreen.swift")

        #expect(chatVM.contains("func attachProjectFileReference(projectId: String, path: String, type: String)"))
        #expect(chatScreen.contains(".dropDestination(for: String.self)"))
    }

    @Test("chat accepts imported and dropped local file references")
    func chatAcceptsImportedAndDroppedLocalFileReferences() throws {
        let chatVM = try source("Sources/SloppyFeatureChat/Screens/Chat/ChatScreenViewModel.swift")
        let chatScreen = try source("Sources/SloppyFeatureChat/Screens/Chat/ChatScreen.swift")

        #expect(chatVM.contains("func attachFileURLs(_ urls: [URL])"))
        #expect(chatVM.contains("func attachItemProviders(_ providers: [NSItemProvider])"))
        #expect(chatScreen.contains("case .success(let urls):"))
        #expect(chatScreen.contains("viewModel.attachFileURLs(urls)"))
        let dropZone = try source("Sources/SloppyFeatureChat/Screens/Chat/Views/ChatAttachmentDropZone.swift")
        #expect(chatScreen.contains(".modifier(ChatAttachmentDropZone(viewModel: viewModel))"))
        #expect(dropZone.contains("of: [.fileURL, .data, .url]"))
        #expect(dropZone.contains("viewModel.attachItemProviders(providers)"))
    }
}
