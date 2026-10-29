import Foundation

public enum ProjectWorkspaceSection: String, CaseIterable, Sendable {
    case kanban, workspaces, automation, chats
    public var title: String {
        switch self {
        case .kanban: "Kanban"
        case .workspaces: "Workspaces"
        case .automation: "Automation"
        case .chats: "Chats"
        }
    }
}

public actor WorkspaceService {
    let http: BackendHTTPClient
    public init(http: BackendHTTPClient) { self.http = http }

    public func scheduledTasks(agentID: String) async throws -> [ScheduledTask] {
        try await http.get("/v1/agents/\(segment(agentID))/cron")
    }
    public func createScheduledTask(agentID: String, request: ScheduledTaskCreateRequest) async throws -> ScheduledTask {
        try await http.post("/v1/agents/\(segment(agentID))/cron", body: request)
    }
    public func updateScheduledTask(_ task: ScheduledTask, enabled: Bool) async throws -> ScheduledTask {
        try await http.put("/v1/agents/\(segment(task.agentId))/cron/\(segment(task.id))", body: ScheduledTaskUpdateRequest(enabled: enabled))
    }
    public func deleteScheduledTask(_ task: ScheduledTask) async throws {
        try await http.delete("/v1/agents/\(segment(task.agentId))/cron/\(segment(task.id))")
    }
    public func attention(agentID: String) async throws -> ProactiveInbox {
        try await http.get("/v1/agents/\(segment(agentID))/proactivity")
    }
    public func updateFinding(_ finding: ProactiveFinding, action: ProactiveFindingActionRequest.Action) async throws -> ProactiveFinding {
        try await http.post("/v1/agents/\(segment(finding.agentId))/proactivity/findings/\(segment(finding.id))/action", body: ProactiveFindingActionRequest(action: action))
    }
    public func pullRequests() async throws -> CodeReviewInboxResponse {
        try await http.get("/v1/code-reviews?state=open&roles=authored,review_requested&limit=100")
    }
    public func pullRequest(_ item: CodeReviewItem) async throws -> CodeReviewDetail {
        try await http.get("/v1/code-reviews/\(segment(item.providerId))/\(segment(item.id))?maxDiffBytes=1048576")
    }
    public func sites() async throws -> [PublishedSiteRecord] {
        struct Response: Decodable { var sites: [PublishedSiteRecord] }
        let response: Response = try await http.get("/v1/sites")
        return response.sites
    }
    public func workspaces(projectID: String) async throws -> [CanvasWorkspaceSummary] {
        struct Response: Decodable { var workspaces: [CanvasWorkspaceSummary] }
        let response: Response = try await http.get("/v1/workspaces?projectId=\(query(projectID))")
        return response.workspaces
    }
    public func createWorkspace(title: String, projectID: String) async throws -> CanvasWorkspaceSummary {
        try await http.post("/v1/workspaces", body: CanvasWorkspaceCreateRequest(title: title, projectId: projectID))
    }
    public func automations(projectID: String) async throws -> [ProjectAutomationDefinition] {
        try await http.get("/v1/projects/\(segment(projectID))/automations")
    }
    public func createAutomation(projectID: String, request: ProjectAutomationDefinitionUpsertRequest) async throws -> ProjectAutomationDefinition {
        try await http.post("/v1/projects/\(segment(projectID))/automations", body: request)
    }
    public func sourceControl(projectID: String) async throws -> ProjectWorkingTreeSourceControlResponse {
        try await http.get("/v1/projects/\(segment(projectID))/source-control/working-tree")
    }
    public func files(projectID: String, path: String = "") async throws -> [ProjectFileEntry] {
        try await http.get("/v1/projects/\(segment(projectID))/files?path=\(query(path))")
    }
    public func file(projectID: String, path: String) async throws -> ProjectFileContentResponse {
        try await http.get("/v1/projects/\(segment(projectID))/files/content?path=\(query(path))")
    }
    public func searchFiles(projectID: String, term: String, limit: Int = 50) async throws -> [ProjectFileSearchEntry] {
        let limit = max(1, min(100, limit))
        do {
            return try await http.get("/v1/projects/\(segment(projectID))/files/search?q=\(query(term))&limit=\(limit)")
        } catch APIError.httpError(statusCode: 404, _) {
            // Older servers expose only the directory endpoint. Bound traversal and avoid cycles.
            var pending = [""]
            var visited = Set<String>()
            var matches: [ProjectFileSearchEntry] = []
            while let directory = pending.popLast(), visited.count < 500, matches.count < limit {
                try Task.checkCancellation()
                guard visited.insert(directory).inserted else { continue }
                for entry in try await files(projectID: projectID, path: directory) {
                    let path = entry.path ?? (directory.isEmpty ? entry.name : "\(directory)/\(entry.name)")
                    if entry.type == .directory { pending.append(path) }
                    else if term.isEmpty || path.localizedCaseInsensitiveContains(term) {
                        matches.append(ProjectFileSearchEntry(path: path, type: .file))
                        if matches.count == limit { break }
                    }
                }
            }
            return matches
        }
    }
    func segment(_ value: String) -> String { BackendHTTPClient.encodePathSegment(value) }
    func query(_ value: String) -> String { BackendHTTPClient.encodeQueryValue(value) }
}
