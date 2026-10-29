import Foundation

extension WorkspaceService {
    public func canvasDocument(workspaceID: String) async throws -> CanvasWorkspaceDocument {
        let response: CanvasWorkspaceDocumentResponse = try await http.get("/v1/workspaces/\(segment(workspaceID))/document")
        return response.document
    }

    public func commitCanvas(workspaceID: String, request: CanvasWorkspaceTransactionRequest) async throws -> CanvasWorkspaceCommittedTransaction {
        try await http.post("/v1/workspaces/\(segment(workspaceID))/transactions", body: request)
    }

    public func automationRuns(projectID: String) async throws -> [ProjectAutomationRun] {
        try await http.get("/v1/projects/\(segment(projectID))/automation-runs")
    }

    public func runAutomation(_ automation: ProjectAutomationDefinition, input: [String: ProjectAutomationJSONValue] = [:]) async throws -> ProjectAutomationRunDetail {
        try await http.post("/v1/projects/\(segment(automation.projectId))/automations/\(segment(automation.id))/run",
                            body: ProjectAutomationManualRunRequest(input: input))
    }
}
