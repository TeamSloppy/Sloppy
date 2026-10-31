import Foundation
import Observation
import SloppyClientCore

@Observable
@MainActor
public final class ProjectWorkflowViewModel {
    public private(set) var workflows: [ProjectWorkflow] = []
    public private(set) var runs: [ProjectWorkflowRun] = []
    public private(set) var selectedWorkflowID: String?
    public private(set) var selectedRunID: String?
    public private(set) var detail: ProjectWorkflowRunDetail?
    public private(set) var isLoading = false
    public private(set) var isLoadingDetail = false
    public private(set) var errorMessage: String?
    public private(set) var detailErrorMessage: String?

    @ObservationIgnored private let apiClient: SloppyAPIClient
    @ObservationIgnored private var projectID: String?
    @ObservationIgnored private var loadID = UUID()
    @ObservationIgnored private var detailLoadID = UUID()

    public init(apiClient: SloppyAPIClient) {
        self.apiClient = apiClient
    }

    public var selectedWorkflow: ProjectWorkflow? {
        workflows.first { $0.id == selectedWorkflowID }
    }

    public var workflowRuns: [ProjectWorkflowRun] {
        runs.filter { $0.workflowId == selectedWorkflowID }
    }

    public var selectedRun: ProjectWorkflowRun? {
        workflowRuns.first { $0.id == selectedRunID }
    }

    /// The API exposes today's definition, not the historical graph saved by a run.
    public var canOverlayRun: Bool {
        guard let workflow = selectedWorkflow, let run = detail?.run else { return false }
        return run.workflowVersion == workflow.version
    }

    public func selectWorkflow(_ id: String) {
        guard id != selectedWorkflowID, workflows.contains(where: { $0.id == id }) else { return }
        selectedWorkflowID = id
        selectRun(workflowRuns.first?.id)
    }

    public func selectRun(_ id: String?) {
        guard id == nil || workflowRuns.contains(where: { $0.id == id }) else { return }
        selectedRunID = id
        detailLoadID = UUID()
        detail = nil
        detailErrorMessage = nil
        isLoadingDetail = false
    }

    public func load(projectId: String) async {
        let requestID = UUID()
        loadID = requestID
        if projectID != projectId {
            projectID = projectId
            workflows = []
            runs = []
            selectedWorkflowID = nil
            selectRun(nil)
            errorMessage = nil
        }
        isLoading = true
        defer { if loadID == requestID { isLoading = false } }
        do {
            async let definitions = apiClient.fetchProjectWorkflows(projectId: projectId)
            async let history = apiClient.fetchProjectWorkflowRuns(projectId: projectId)
            let snapshot = try await (definitions, history)
            guard loadID == requestID, !Task.isCancelled else { return }
            workflows = snapshot.0.filter { $0.projectId == projectId }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            runs = snapshot.1.filter { $0.projectId == projectId }
                .sorted { $0.startedAt > $1.startedAt }
            if !workflows.contains(where: { $0.id == selectedWorkflowID }) {
                selectedWorkflowID = runs.first(where: { run in workflows.contains { $0.id == run.workflowId } })?.workflowId
                    ?? workflows.first?.id
                selectRun(workflowRuns.first?.id)
            } else if let selectedRunID, !workflowRuns.contains(where: { $0.id == selectedRunID }) {
                selectRun(workflowRuns.first?.id)
            }
            errorMessage = nil
        } catch {
            guard loadID == requestID, !Task.isCancelled else { return }
            errorMessage = Self.message("Could not load workflows", error: error)
        }
    }

    public func loadSelectedRun(projectId: String) async {
        guard let runID = selectedRunID, let workflowID = selectedWorkflowID else { return }
        let requestID = UUID()
        detailLoadID = requestID
        isLoadingDetail = true
        defer { if detailLoadID == requestID { isLoadingDetail = false } }
        do {
            let result = try await apiClient.fetchProjectWorkflowRun(projectId: projectId, runId: runID)
            guard detailLoadID == requestID, !Task.isCancelled else { return }
            guard result.run.id == runID, result.run.projectId == projectId,
                  result.run.workflowId == workflowID else { throw APIError.invalidResponse }
            detail = result
            detailErrorMessage = nil
        } catch {
            guard detailLoadID == requestID, !Task.isCancelled else { return }
            detailErrorMessage = Self.message("Could not load this run", error: error)
        }
    }

    nonisolated private static func message(_ prefix: String, error: Error) -> String {
        if let status = (error as? APIError)?.statusCode { return "\(prefix) (HTTP \(status))." }
        return "\(prefix)."
    }
}
