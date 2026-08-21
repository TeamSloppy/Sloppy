import Foundation
import Observation
import SloppyClientCore

@Observable
@MainActor
public final class ProjectAutomationViewModel {
    public private(set) var automations: [ProjectAutomationDefinition] = []
    public private(set) var runs: [ProjectAutomationRun] = []
    public private(set) var workflows: [ProjectAutomationWorkflowSummary] = []
    public private(set) var isLoading = false
    public private(set) var runningAutomationIDs: Set<String> = []
    public private(set) var errorMessage: String?

    @ObservationIgnored private let apiClient: SloppyAPIClient

    public init(apiClient: SloppyAPIClient) {
        self.apiClient = apiClient
    }

    public func load(projectId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let automationsRequest = apiClient.fetchProjectAutomations(projectId: projectId)
            async let runsRequest = apiClient.fetchProjectAutomationRuns(projectId: projectId)
            async let workflowsRequest = apiClient.fetchProjectAutomationWorkflows(projectId: projectId)
            let (automations, runs, workflows) = try await (
                automationsRequest,
                runsRequest,
                workflowsRequest
            )
            self.automations = Self.projectAutomations(automations, projectId: projectId)
                .sorted { $0.updatedAt > $1.updatedAt }
            self.runs = Self.projectRuns(runs, projectId: projectId)
                .sorted { $0.startedAt > $1.startedAt }
            self.workflows = Self.projectWorkflows(workflows, projectId: projectId)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func create(
        request: ProjectAutomationDefinitionUpsertRequest,
        projectId: String
    ) async throws {
        let automation = try await apiClient.createProjectAutomation(
            projectId: projectId,
            request: request
        )
        guard automation.projectId == projectId else {
            throw ProjectAutomationViewModelError.projectMismatch
        }

        automations.removeAll { $0.id == automation.id }
        automations.insert(automation, at: 0)
        errorMessage = nil
    }

    public func run(_ automation: ProjectAutomationDefinition, projectId: String) async {
        guard automation.enabled, !runningAutomationIDs.contains(automation.id) else { return }

        runningAutomationIDs.insert(automation.id)
        defer { runningAutomationIDs.remove(automation.id) }

        do {
            let detail = try await apiClient.runProjectAutomation(
                projectId: projectId,
                automationId: automation.id
            )
            runs.removeAll { $0.id == detail.run.id }
            runs.insert(detail.run, at: 0)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func latestRun(for automationID: String) -> ProjectAutomationRun? {
        runs.first { $0.automationId == automationID }
    }

    nonisolated static func projectAutomations(
        _ automations: [ProjectAutomationDefinition],
        projectId: String
    ) -> [ProjectAutomationDefinition] {
        automations.filter { $0.projectId == projectId }
    }

    nonisolated static func projectRuns(
        _ runs: [ProjectAutomationRun],
        projectId: String
    ) -> [ProjectAutomationRun] {
        runs.filter { $0.projectId == projectId }
    }

    nonisolated static func projectWorkflows(
        _ workflows: [ProjectAutomationWorkflowSummary],
        projectId: String
    ) -> [ProjectAutomationWorkflowSummary] {
        workflows.filter { $0.projectId == projectId }
    }

    nonisolated private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return "Could not load automations (\(apiError.diagnosticDescription))."
        }
        return "Could not load automations."
    }
}

private enum ProjectAutomationViewModelError: Error {
    case projectMismatch
}
