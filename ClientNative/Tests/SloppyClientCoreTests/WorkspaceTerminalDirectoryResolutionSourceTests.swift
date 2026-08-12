import Foundation
import Testing

@Suite("Workspace terminal directory resolution source")
struct WorkspaceTerminalDirectoryResolutionSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("project record and tab contexts expose project root path metadata")
    func projectRecordAndTabContextsExposeProjectRootPathMetadata() throws {
        let overview = try source("Sources", "SloppyClientCore", "OverviewModels.swift")
        let tabs = try source("Sources", "SloppyClientUI", "Tabs.swift")

        #expect(overview.contains("public var repoPath: String?"))
        #expect(overview.contains("public var worktreeRootPath: String?"))
        #expect(overview.contains("public var projectRootPath: String?"))
        #expect(tabs.contains("public var projectRootPath: String?"))
        #expect(tabs.contains("case chatTask(projectId: String, projectName: String, projectRootPath: String?"))
    }

    @Test("main view model resolves working directory from tab payload and chat context")
    func mainViewModelResolvesWorkingDirectoryFromTabPayloadAndChatContext() throws {
        let viewModel = try source("Sources", "SloppyClient", "Navigation", "Main", "MainViewModel.swift")

        #expect(viewModel.contains("func resolveWorkingDirectory(for tabID: WorkspaceTab.ID) -> URL?"))
        #expect(viewModel.contains("func terminalWorkingDirectory(for tabID: WorkspaceTab.ID) -> URL"))
        #expect(viewModel.contains("context.projectRootPath"))
        #expect(viewModel.contains("projects.first(where: { $0.id == projectId })?.projectRootPath"))
        #expect(viewModel.contains("FileManager.default.homeDirectoryForCurrentUser"))
    }
}
