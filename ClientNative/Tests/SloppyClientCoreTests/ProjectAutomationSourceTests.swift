import Foundation
import Testing

@Suite("Project automation source")
struct ProjectAutomationSourceTests {
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

    @Test("project automation screen creates automations in a local item-driven sheet")
    func creationSheetWiring() throws {
        let view = try source(
            "Sources/SloppyFeatureProjects/Screens/Projects/Automation/ProjectAutomationView.swift"
        )
        let sheet = try source(
            "Sources/SloppyFeatureProjects/Screens/Projects/Automation/ProjectAutomationCreateSheet.swift"
        )
        let api = try source("Sources/SloppyClientCore/SloppyAPIClient.swift")

        #expect(view.contains("Label(\"New Automation\", systemImage: \"plus\")"))
        #expect(view.contains(".sheet(item: $presentedSheet)"))
        #expect(view.contains("ProjectAutomationCreateSheet("))
        #expect(sheet.contains("ProjectAutomationDefinitionUpsertRequest("))
        #expect(sheet.contains("This automation will be created only for \\(projectName)."))
        #expect(api.contains("func createProjectAutomation("))
        #expect(api.contains("/automations\""))
    }

    @Test("automation definitions runs and workflows are scoped by project ID")
    func projectScopeWiring() throws {
        let viewModel = try source(
            "Sources/SloppyFeatureProjects/Screens/Projects/Automation/ProjectAutomationViewModel.swift"
        )

        #expect(viewModel.contains("projectAutomations(automations, projectId: projectId)"))
        #expect(viewModel.contains("projectRuns(runs, projectId: projectId)"))
        #expect(viewModel.contains("projectWorkflows(workflows, projectId: projectId)"))
        #expect(viewModel.contains("automations.filter { $0.projectId == projectId }"))
        #expect(viewModel.contains("runs.filter { $0.projectId == projectId }"))
        #expect(viewModel.contains("workflows.filter { $0.projectId == projectId }"))
    }
}
