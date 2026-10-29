import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SloppyClientCore

private final class WorkspaceProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let url = request.url else { return }
        let path = url.absoluteString
        let body: String
        let status: Int
        if url.path.hasSuffix("/cron") && request.httpMethod == "GET" {
            // A slash inside the agent ID must remain inside a single URL path segment.
            status = path.contains("agent%2Fone") ? 200 : 400
            body = "[]"
        } else if url.path.hasSuffix("/cron/task") && request.httpMethod == "PUT" {
            let payload = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            status = payload?["enabled"] as? Bool == false ? 200 : 400
            body = #"{"id":"task","agentId":"agent","channelId":"channel","schedule":"0 9 * * *","command":"Check builds","enabled":false,"createdAt":"2026-10-27T10:00:00Z","updatedAt":"2026-10-27T10:01:00Z"}"#
        } else if url.path == "/v1/workspaces" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            status = items?.first(where: { $0.name == "projectId" })?.value == "a&b" ? 200 : 400
            body = #"{"workspaces":[{"id":"canvas","title":"Notes","description":"","projectId":"a&b","revision":2,"ownerId":"owner"}]}"#
        } else if url.path == "/v1/projects/fallback/files/search" {
            status = 404
            body = #"{"error":"Missing route"}"#
        } else if url.path.hasSuffix("/transactions") && request.httpMethod == "POST" {
            let payload = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            status = payload?["baseRevision"] as? Int == 3 && (payload?["expectedElementRevisions"] as? [String: Int])?["note"] == 2 && path.contains("canvas%2Fone") ? 200 : 400
            body = #"{"id":"tx","workspaceId":"canvas/one","revision":4,"operations":[{"kind":"element.delete","targetId":"note"}]}"#
        } else if url.path.hasSuffix("/automations/check/run") && request.httpMethod == "POST" {
            let payload = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            status = payload?["actorId"] as? String == "human:admin" && (payload?["input"] as? [String: String])?["branch"] == "main" ? 200 : 400
            body = #"{"run":{"id":"run","automationId":"check","projectId":"project","workflowId":"workflow","repositoryFullName":"sample/repo","triggerType":"manual","status":"queued","startedAt":"2026-10-27T10:00:00Z"}}"#
        } else if url.path == "/v1/projects/fallback/files" {
            let directory = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "path" })?.value ?? ""
            status = 200
            body = directory.isEmpty ? #"[{"name":"Sources","path":"Sources","type":"directory"}]"# : #"[{"name":"loop","path":"Sources","type":"directory"},{"name":"Target.swift","path":"Sources/Target.swift","type":"file"}]"#
        } else if url.path.hasSuffix("/files/search") {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            status = items?.first(where: { $0.name == "q" })?.value == "a&b #c" && items?.first(where: { $0.name == "limit" })?.value == "100" ? 200 : 400
            body = #"[{"path":"Sources/a&b.swift","type":"file"}]"#
        } else if url.path.hasSuffix("/tasks/task") && request.httpMethod == "PATCH" {
            let payload = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            status = payload?["status"] as? String == "done" && payload?["title"] == nil ? 200 : 400
            body = #"{"id":"project","name":"Project","description":"","tasks":[{"id":"task","title":"Existing title","status":"done"}]}"#
        } else {
            status = 503
            body = #"{"error":"Provider unavailable"}"#
        }
        if let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

@Suite("Workspace API")
struct WorkspaceServiceTests {
    private func service() throws -> WorkspaceService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WorkspaceProtocol.self]
        let url = try #require(URL(string: "https://workspace.invalid"))
        return WorkspaceService(http: BackendHTTPClient(baseURL: url, session: URLSession(configuration: config)))
    }
    @Test func encodesAgentPathSegment() async throws {
        let response = try await service().scheduledTasks(agentID: "agent/one")
        #expect(response.isEmpty)
    }
    @Test func preservesProjectQueryAndDecodesNativeSummary() async throws {
        let response = try await service().workspaces(projectID: "a&b")
        #expect(response.first?.id == "canvas")
        #expect(response.first?.revision == 2)
    }
    @Test func pausesScheduledTaskUsingPut() async throws {
        let task = ScheduledTask(id: "task", agentId: "agent", channelId: "channel", schedule: "0 9 * * *", command: "Check builds", enabled: true, createdAt: Date(), updatedAt: Date())
        let response = try await service().updateScheduledTask(task, enabled: false)
        #expect(!response.enabled)
    }
    @Test func surfacesProviderFailure() async throws {
        do {
            _ = try await service().pullRequests()
            Issue.record("Expected provider failure")
        } catch let error as APIError {
            #expect(error.statusCode == 503)
            #expect(error.localizedDescription.contains("503"))
        }
    }
    @Test func fileSearchEncodesQueryAndBoundsLimit() async throws {
        let response = try await service().searchFiles(projectID: "project", term: "a&b #c", limit: 500)
        #expect(response.first?.path == "Sources/a&b.swift")
    }
    @Test func taskEditSendsOnlyChangedPropertiesUsingPatch() async throws {
        let response = try await service().updateTask(projectID: "project", taskID: "task", request: APIProjectTaskUpdateRequest(status: "done"))
        #expect(response.tasks?.first?.status == "done")
        #expect(response.tasks?.first?.title == "Existing title")
    }
    @Test func oldServerFileSearchTraversesDirectoriesAndAvoidsCycles() async throws {
        let response = try await service().searchFiles(projectID: "fallback", term: "Target")
        #expect(response.map(\.path) == ["Sources/Target.swift"])
    }
    @Test func canvasCommitEncodesPathAndConflictGuards() async throws {
        let response = try await service().commitCanvas(workspaceID: "canvas/one", request: .init(id: "tx", baseRevision: 3,
            expectedElementRevisions: ["note": 2], operations: [.init(kind: .deleteElement, targetId: "note")]))
        #expect(response.revision == 4)
        #expect(response.operations.first?.targetId == "note")
    }
    @Test func automationRunSendsStructuredInput() async throws {
        let automation = ProjectAutomationDefinition(id: "check", projectId: "project", name: "Check", workflowId: "workflow",
            repositoryFullName: "sample/repo", trigger: .init(type: .manual))
        let response = try await service().runAutomation(automation, input: ["branch": .string("main")])
        #expect(response.run.status == .queued)
        #expect(response.run.automationId == automation.id)
    }
}
