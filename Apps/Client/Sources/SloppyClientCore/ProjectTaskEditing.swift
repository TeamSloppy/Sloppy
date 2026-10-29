import Foundation

public struct APIProjectTaskUpdateRequest: Codable, Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var priority: String?
    public var status: String?
    public var actorId: String?
    public var executionNodeId: String?
    public var tags: [String]?
    public init(title: String? = nil, description: String? = nil, priority: String? = nil, status: String? = nil,
                actorId: String? = nil, executionNodeId: String? = nil, tags: [String]? = nil) {
        self.title = title; self.description = description; self.priority = priority; self.status = status
        self.actorId = actorId; self.executionNodeId = executionNodeId; self.tags = tags
    }
}

extension SloppyAPIClient {
    public func updateProjectTask(projectId: String, taskId: String, request: APIProjectTaskUpdateRequest) async throws -> APIProjectRecord {
        try await workspace.updateTask(projectID: projectId, taskID: taskId, request: request)
    }
}

extension WorkspaceService {
    public func updateTask(projectID: String, taskID: String, request: APIProjectTaskUpdateRequest) async throws -> APIProjectRecord {
        try await http.patch(taskPath(projectID, taskID), body: request)
    }
    public func taskActivities(projectID: String, taskID: String) async throws -> [APITaskActivity] {
        try await http.get(taskPath(projectID, taskID) + "/activities")
    }
    public func taskLogs(projectID: String, taskID: String) async throws -> [APITaskLog] {
        try await http.get(taskPath(projectID, taskID) + "/logs")
    }
    public func taskClarifications(projectID: String, taskID: String) async throws -> [APITaskClarification] {
        try await http.get(taskPath(projectID, taskID) + "/clarifications")
    }
    public func taskDiff(projectID: String, taskID: String) async throws -> APITaskDiff {
        try await http.get(taskPath(projectID, taskID) + "/diff")
    }
    public func answerTaskClarification(projectID: String, taskID: String, clarificationID: String, answer: APITaskClarificationAnswer) async throws -> APITaskClarification {
        try await http.post(taskPath(projectID, taskID) + "/clarifications/\(BackendHTTPClient.encodePathSegment(clarificationID))/answer", body: answer)
    }
    private func taskPath(_ project: String, _ task: String) -> String {
        "/v1/projects/\(BackendHTTPClient.encodePathSegment(project))/tasks/\(BackendHTTPClient.encodePathSegment(task))"
    }
}
