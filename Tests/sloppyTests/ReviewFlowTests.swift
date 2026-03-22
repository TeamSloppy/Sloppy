import Foundation
import Testing
@testable import sloppy
@testable import Protocols

// MARK: - Helpers

private func makeProjectWithTask(
    service: CoreService,
    router: CoreRouter,
    repoPath: String? = nil,
    reviewSettings: ProjectReviewSettings = ProjectReviewSettings(),
    taskStatus: String = "needs_review",
    worktreeBranch: String? = nil
) async throws -> (projectID: String, taskID: String) {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectID = "review-proj-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(
            id: projectID,
            name: "Review Test Project",
            description: "Test",
            channels: []
        )
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    if repoPath != nil || reviewSettings.enabled {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let updateBody = try encoder.encode(
            ProjectUpdateRequest(repoPath: repoPath, reviewSettings: reviewSettings)
        )
        let updateResp = await router.handle(
            method: "PATCH", path: "/v1/projects/\(projectID)", body: updateBody
        )
        #expect(updateResp.status == 200)
    }

    let taskBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(
            title: "Implement feature",
            description: "Write the feature",
            priority: "medium",
            status: taskStatus
        )
    )
    let taskResp = await router.handle(
        method: "POST", path: "/v1/projects/\(projectID)/tasks", body: taskBody
    )
    #expect(taskResp.status == 200)
    let projectWithTask = try decoder.decode(ProjectRecord.self, from: taskResp.body)
    let taskID = try #require(projectWithTask.tasks.first?.id)

    if worktreeBranch != nil || taskStatus == "needs_review" {
        let patchBody = try JSONEncoder().encode(
            ProjectTaskUpdateRequest(status: taskStatus)
        )
        _ = await router.handle(
            method: "PATCH",
            path: "/v1/projects/\(projectID)/tasks/\(taskID)",
            body: patchBody
        )
    }

    return (projectID, taskID)
}

// MARK: - Project Review Settings Tests

@Test
func projectUpdateRequestPersistsReviewSettings() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let projectID = "review-settings-\(UUID().uuidString)"
    let createBody = try encoder.encode(
        ProjectCreateRequest(
            id: projectID,
            name: "Review Project",
            description: "",
            channels: []
        )
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let updateBody = try encoder.encode(
        ProjectUpdateRequest(
            repoPath: "/tmp/my-repo",
            reviewSettings: ProjectReviewSettings(enabled: true, approvalMode: .human)
        )
    )
    let updateResp = await router.handle(
        method: "PATCH", path: "/v1/projects/\(projectID)", body: updateBody
    )
    #expect(updateResp.status == 200)
    let updated = try decoder.decode(ProjectRecord.self, from: updateResp.body)
    #expect(updated.repoPath == "/tmp/my-repo")
    #expect(updated.reviewSettings.enabled == true)
    #expect(updated.reviewSettings.approvalMode == .human)
}

@Test
func projectDefaultReviewSettingsAreDisabled() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectID = "review-default-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(
            id: projectID,
            name: "Default Project",
            description: "",
            channels: []
        )
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)
    let created = try decoder.decode(ProjectRecord.self, from: createResp.body)
    #expect(created.reviewSettings.enabled == false)
    #expect(created.repoPath == nil)
}

// MARK: - Approve / Reject Endpoint Tests

@Test
func approveEndpointReturns404ForUnknownTask() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let resp = await router.handle(
        method: "POST",
        path: "/v1/projects/nonexistent/tasks/nonexistent/approve",
        body: nil
    )
    #expect(resp.status == 404)
}

@Test
func rejectEndpointReturns404ForUnknownTask() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let resp = await router.handle(
        method: "POST",
        path: "/v1/projects/nonexistent/tasks/nonexistent/reject",
        body: nil
    )
    #expect(resp.status == 404)
}

@Test
func approveTaskWithoutWorktreeSetsDoneStatus() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let (projectID, taskID) = try await makeProjectWithTask(
        service: service,
        router: router,
        taskStatus: "needs_review"
    )

    let approveResp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/approve",
        body: nil
    )
    #expect(approveResp.status == 200)

    let getResp = await router.handle(method: "GET", path: "/v1/projects/\(projectID)", body: nil)
    #expect(getResp.status == 200)
    let project = try decoder.decode(ProjectRecord.self, from: getResp.body)
    let task = try #require(project.tasks.first(where: { $0.id == taskID }))
    #expect(task.status == ProjectTaskStatus.done.rawValue)
    #expect(task.worktreeBranch == nil)
}

@Test
func rejectTaskAppendsRejectionReasonToDescription() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectID = "reject-reason-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Reject Test", description: "", channels: [])
    )
    _ = await router.handle(method: "POST", path: "/v1/projects", body: createBody)

    let taskBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(
            title: "Review me",
            description: "Original description",
            priority: "medium",
            status: "needs_review"
        )
    )
    let taskResp = await router.handle(
        method: "POST", path: "/v1/projects/\(projectID)/tasks", body: taskBody
    )
    let projectWithTask = try decoder.decode(ProjectRecord.self, from: taskResp.body)
    let taskID = try #require(projectWithTask.tasks.first?.id)

    try await service.rejectTask(projectID: projectID, taskID: taskID, reason: "Missing tests")

    let saved = try await service.getProject(id: projectID)
    let task = try #require(saved.tasks.first(where: { $0.id == taskID }))
    #expect(task.description.contains("Missing tests"))
}

@Test
func rejectEndpointReturns200WithBody() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let (projectID, taskID) = try await makeProjectWithTask(
        service: service,
        router: router,
        taskStatus: "needs_review"
    )

    let rejectBody = try JSONEncoder().encode(TaskRejectRequest(reason: "Not ready"))
    let rejectResp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/reject",
        body: rejectBody
    )
    #expect(rejectResp.status == 200)
}

// MARK: - Task Diff Endpoint Tests

@Test
func taskDiffEndpointReturnsEmptyForTaskWithoutWorktree() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let (projectID, taskID) = try await makeProjectWithTask(
        service: service,
        router: router,
        taskStatus: "needs_review"
    )

    let resp = await router.handle(method: "GET", path: "/v1/projects/\(projectID)/tasks/\(taskID)/diff", body: nil)
    #expect(resp.status == 200)
    let diffResp = try decoder.decode(TaskDiffResponse.self, from: resp.body)
    #expect(diffResp.diff == "")
    #expect(diffResp.branchName == "")
}

@Test
func taskDiffEndpointReturns404ForUnknownTask() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let resp = await router.handle(method: "GET", path: "/v1/projects/nonexistent/tasks/nonexistent/diff", body: nil)
    #expect(resp.status == 404)
}

// MARK: - Review Comments Endpoint Tests

@Test
func reviewCommentsListEmptyForNewTask() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let (projectID, taskID) = try await makeProjectWithTask(
        service: service,
        router: router,
        taskStatus: "needs_review"
    )

    let resp = await router.handle(method: "GET", path: "/v1/projects/\(projectID)/tasks/\(taskID)/review-comments", body: nil)
    #expect(resp.status == 200)
    let comments = try decoder.decode([ReviewComment].self, from: resp.body)
    #expect(comments.isEmpty)
}

@Test
func reviewCommentCreateAndList() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let (projectID, taskID) = try await makeProjectWithTask(
        service: service,
        router: router,
        taskStatus: "needs_review"
    )

    let createBody = try encoder.encode(ReviewCommentCreateRequest(
        filePath: "Sources/Foo.swift",
        lineNumber: 42,
        side: "new",
        content: "This looks wrong",
        author: "user"
    ))
    let createResp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/review-comments",
        body: createBody
    )
    #expect(createResp.status == 201)
    let created = try decoder.decode(ReviewComment.self, from: createResp.body)
    #expect(created.filePath == "Sources/Foo.swift")
    #expect(created.lineNumber == 42)
    #expect(created.content == "This looks wrong")
    #expect(created.resolved == false)

    let listResp = await router.handle(method: "GET", path: "/v1/projects/\(projectID)/tasks/\(taskID)/review-comments", body: nil)
    #expect(listResp.status == 200)
    let comments = try decoder.decode([ReviewComment].self, from: listResp.body)
    #expect(comments.count == 1)
    #expect(comments[0].id == created.id)
}

@Test
func reviewCommentResolve() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let (projectID, taskID) = try await makeProjectWithTask(
        service: service,
        router: router,
        taskStatus: "needs_review"
    )

    let createBody = try encoder.encode(ReviewCommentCreateRequest(
        filePath: "main.swift",
        content: "Fix this",
        author: "user"
    ))
    let createResp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/review-comments",
        body: createBody
    )
    let created = try decoder.decode(ReviewComment.self, from: createResp.body)

    let updateBody = try encoder.encode(ReviewCommentUpdateRequest(resolved: true))
    let updateResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/review-comments/\(created.id)",
        body: updateBody
    )
    #expect(updateResp.status == 200)
    let updated = try decoder.decode(ReviewComment.self, from: updateResp.body)
    #expect(updated.resolved == true)
}

@Test
func reviewCommentDelete() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let (projectID, taskID) = try await makeProjectWithTask(
        service: service,
        router: router,
        taskStatus: "needs_review"
    )

    let createBody = try encoder.encode(ReviewCommentCreateRequest(
        filePath: "file.swift",
        content: "Delete me",
        author: "user"
    ))
    let createResp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/review-comments",
        body: createBody
    )
    let created = try decoder.decode(ReviewComment.self, from: createResp.body)

    let deleteResp = await router.handle(
        method: "DELETE",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/review-comments/\(created.id)",
        body: nil
    )
    #expect(deleteResp.status == 200)

    let listResp = await router.handle(method: "GET", path: "/v1/projects/\(projectID)/tasks/\(taskID)/review-comments", body: nil)
    let comments = try decoder.decode([ReviewComment].self, from: listResp.body)
    #expect(comments.isEmpty)
}

// MARK: - ActorNode systemRole in ActorBoard

@Test
func actorBoardAdminNodeHasManagerSystemRole() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let getBoardResp = await router.handle(method: "GET", path: "/v1/actors/board", body: nil)
    #expect(getBoardResp.status == 200)

    let board = try decoder.decode(ActorBoardSnapshot.self, from: getBoardResp.body)
    let adminNode = try #require(board.nodes.first(where: { $0.id == "human:admin" }))
    #expect(adminNode.systemRole == .manager)
}

@Test
func actorBoardNodeWithReviewerRolePersists() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let getBoardResp = await router.handle(method: "GET", path: "/v1/actors/board", body: nil)
    #expect(getBoardResp.status == 200)
    let board = try decoder.decode(ActorBoardSnapshot.self, from: getBoardResp.body)

    let reviewerNode = ActorNode(
        id: "human:reviewer-1",
        displayName: "Code Reviewer",
        kind: .human,
        role: "Reviewer",
        systemRole: .reviewer,
        positionX: 300,
        positionY: 200
    )
    var updatedNodes = board.nodes
    updatedNodes.append(reviewerNode)

    let updateRequest = ActorBoardUpdateRequest(
        nodes: updatedNodes,
        links: board.links,
        teams: board.teams
    )
    let updateBody = try encoder.encode(updateRequest)
    let updateResp = await router.handle(method: "PUT", path: "/v1/actors/board", body: updateBody)
    #expect(updateResp.status == 200)

    let afterResp = await router.handle(method: "GET", path: "/v1/actors/board", body: nil)
    let afterBoard = try decoder.decode(ActorBoardSnapshot.self, from: afterResp.body)
    let savedNode = try #require(afterBoard.nodes.first(where: { $0.id == "human:reviewer-1" }))
    #expect(savedNode.systemRole == .reviewer)
    #expect(savedNode.displayName == "Code Reviewer")
}
