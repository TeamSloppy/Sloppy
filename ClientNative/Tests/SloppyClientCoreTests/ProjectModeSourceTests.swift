import Foundation
import Testing

@Suite("Project mode source")
struct ProjectModeSourceTests {
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

    @Test("project navigation lives in workspace blocks on macOS and keeps the mobile picker")
    func projectModePill() throws {
        let projectMode = try source(
            "Sources/SloppyClient/Navigation/ProjectMode/ProjectModeView.swift"
        )

        let rail = try source("Sources/SloppyClient/Navigation/ProjectMode/ProjectModeRail.swift")
        let inspector = try source("Sources/SloppyClient/Workspace/Panel/DesktopWorkspaceInspector.swift")
        #expect(!projectMode.contains("ProjectModeRail(selectedSection: state.selectedSection"))
        #expect(inspector.contains("ProjectModeNavigationCard("))
        #expect(rail.contains("ForEach(ProjectModeSection.allCases)"))
        #expect(projectMode.contains(".background(.regularMaterial, in: Capsule())"))
        #expect(projectMode.contains("ProjectKanbanView("))
        #expect(projectMode.contains("CanvasWorkspaceSurface("))
        #expect(projectMode.contains("ProjectAutomationView("))
        #expect(projectMode.contains("ChatScreen("))
        #expect(projectMode.contains("allowsProjectSelection: false"))
    }

    @Test("project mode selection is cached and persisted per project")
    func projectModeSelectionPersistence() throws {
        let tabs = try source("Sources/SloppyClient/Navigation/Main/MainTabs.swift")
        let viewModel = try source("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")

        #expect(tabs.contains("enum ProjectModeSection: String, CaseIterable"))
        #expect(tabs.contains("case kanban"))
        #expect(tabs.contains("case workspaces"))
        #expect(tabs.contains("case automation"))
        #expect(tabs.contains("case chats"))
        #expect(tabs.contains("case .automation: \"Automation\""))
        #expect(tabs.contains("let automationViewModel: ProjectAutomationViewModel"))
        #expect(viewModel.contains("var projectModeStates: [String: ProjectKanbanTabState] = [:]"))
        #expect(viewModel.contains("settings.projectModeSections[scopedProjectID(project)] = section.rawValue"))
        #expect(viewModel.contains("settings.projectModeSections[projectStateID]"))
        #expect(viewModel.contains("projectModeStates[projectStateID] = state"))
        #expect(viewModel.contains("await state.automationViewModel.load(projectId: project.id)"))
    }
}
