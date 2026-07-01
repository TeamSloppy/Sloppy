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
        let vm = try source("Sources/SloppyClient/WorkspacePanelViewModel.swift")

        #expect(vm.contains("func activate(context: WorkspacePanelContext)"))
        #expect(vm.contains("func refresh() async"))
        #expect(vm.contains("func toggleDirectory(_ path: String) async"))
        #expect(vm.contains("func selectFile(_ path: String) async"))
        #expect(vm.contains("fetchProjectFiles(projectId: context.projectId"))
        #expect(vm.contains("fetchProjectFileContent(projectId: context.projectId"))
    }

    @Test("chat view model accepts dropped project file references")
    func chatViewModelAcceptsDroppedProjectFileReferences() throws {
        let chatVM = try source("Sources/SloppyFeatureChat/ChatScreenViewModel.swift")
        let chatScreen = try source("Sources/SloppyFeatureChat/ChatScreen.swift")

        #expect(chatVM.contains("func attachProjectFileReference(projectId: String, path: String, type: String)"))
        #expect(chatScreen.contains(".dropDestination(for: String.self)"))
    }
}
