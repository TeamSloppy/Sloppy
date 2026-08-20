import Foundation
import Testing

@Suite("Workspace environment panel source")
struct WorkspaceEnvironmentPanelSourceTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("workspace inspector exposes an environment mode")
    func workspaceInspectorExposesEnvironmentMode() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let panelView = try source("Sources/SloppyClient/Workspace/Panel/WorkspacePanelView.swift")
        let panelViewModel = try source("Sources/SloppyClient/Workspace/Panel/WorkspacePanelViewModel.swift")

        #expect(panelViewModel.contains("case environment"))
        #expect(panelViewModel.contains("var mode: WorkspacePanelMode = .environment"))
        #expect(mainView.contains("openWorkspacePanel(mode: .environment)"))
        #expect(mainView.contains("Label(\"Environment\", systemImage: workspacePanelMenuImage"))
        #expect(panelView.contains("WorkspaceEnvironmentPanelView("))
    }

    @Test("environment mode loads typed project and source-control data")
    func environmentModeLoadsTypedData() throws {
        let panelViewModel = try source("Sources/SloppyClient/Workspace/Panel/WorkspacePanelViewModel.swift")
        let environmentView = try source(
            "Sources/SloppyClient/Workspace/Panel/WorkspaceEnvironmentPanelView.swift"
        )

        #expect(panelViewModel.contains("func refreshEnvironment() async"))
        #expect(panelViewModel.contains("fetchProjectWorkingTreeSourceControl"))
        #expect(panelViewModel.contains("fetchProject(id: context.projectId)"))
        #expect(panelViewModel.contains("func synchronizeSourceControl"))
        #expect(environmentView.contains("Source-control information unavailable."))
        #expect(environmentView.contains("Text(\"Changes\")"))
        #expect(environmentView.contains("sourceControl.linesAdded"))
        #expect(environmentView.contains("sourceControl.linesDeleted"))
        #expect(environmentView.contains("title: \"Commit or push\""))
        #expect(environmentView.contains("title: \"Pull request status unavailable\""))
        #expect(environmentView.contains("ServerAddress.isLoopbackHost"))
        #expect(environmentView.contains("workspace.environment-panel"))
        #expect(mainViewContainsLiveSourceControlSync())
    }

    private func mainViewContainsLiveSourceControlSync() -> Bool {
        guard let mainView = try? source("Sources/SloppyClient/Navigation/Main/MainView.swift") else {
            return false
        }
        return mainView.contains("workspacePanelViewModel.synchronizeSourceControl(sourceControl)")
    }

    @Test("commit and push affordance opens the project terminal")
    func commitAndPushOpensTerminal() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let environmentView = try source(
            "Sources/SloppyClient/Workspace/Panel/WorkspaceEnvironmentPanelView.swift"
        )

        #expect(mainView.contains("onOpenTerminal: { viewModel.toggleTerminalForSelectedTab() }"))
        #expect(environmentView.contains("onOpenTerminal?()"))
        #expect(environmentView.contains("Open project terminal"))
    }
}
