import Foundation

extension SloppyAPIClient {
    public func fetchProjectWorkflows(projectId: String) async throws -> [ProjectWorkflow] {
        try await http.get("/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/workflows")
    }

    public func fetchProjectWorkflowRuns(projectId: String) async throws -> [ProjectWorkflowRun] {
        try await http.get("/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/workflow-runs")
    }

    public func fetchProjectWorkflowRun(projectId: String, runId: String) async throws -> ProjectWorkflowRunDetail {
        try await http.get("/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/workflow-runs/\(BackendHTTPClient.encodePathSegment(runId))")
    }
}
