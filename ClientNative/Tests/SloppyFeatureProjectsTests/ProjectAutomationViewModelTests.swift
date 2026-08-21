import Foundation
import SloppyClientCore
import Testing
@testable import SloppyFeatureProjects

@Suite("Project automations")
struct ProjectAutomationViewModelTests {
    @Test("project automation content is strictly scoped to the selected project")
    func projectScoping() {
        let selectedAutomation = automation(id: "selected", projectId: "project-a")
        let foreignAutomation = automation(id: "foreign", projectId: "project-b")
        let selectedRun = run(id: "selected-run", projectId: "project-a")
        let foreignRun = run(id: "foreign-run", projectId: "project-b")
        let selectedWorkflow = ProjectAutomationWorkflowSummary(
            id: "workflow-a",
            projectId: "project-a",
            name: "A",
            enabled: true
        )
        let foreignWorkflow = ProjectAutomationWorkflowSummary(
            id: "workflow-b",
            projectId: "project-b",
            name: "B",
            enabled: true
        )

        #expect(
            ProjectAutomationViewModel.projectAutomations(
                [selectedAutomation, foreignAutomation],
                projectId: "project-a"
            ).map(\.id) == ["selected"]
        )
        #expect(
            ProjectAutomationViewModel.projectRuns(
                [selectedRun, foreignRun],
                projectId: "project-a"
            ).map(\.id) == ["selected-run"]
        )
        #expect(
            ProjectAutomationViewModel.projectWorkflows(
                [selectedWorkflow, foreignWorkflow],
                projectId: "project-a"
            ).map(\.id) == ["workflow-a"]
        )
    }

    private func automation(id: String, projectId: String) -> ProjectAutomationDefinition {
        ProjectAutomationDefinition(
            id: id,
            projectId: projectId,
            name: id,
            workflowId: "workflow",
            repositoryFullName: "owner/repository",
            trigger: .init(type: .manual)
        )
    }

    private func run(id: String, projectId: String) -> ProjectAutomationRun {
        ProjectAutomationRun(
            id: id,
            automationId: "automation",
            projectId: projectId,
            workflowId: "workflow",
            repositoryFullName: "owner/repository",
            triggerType: .manual,
            status: .completed
        )
    }
}
