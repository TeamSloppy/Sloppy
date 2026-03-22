import Foundation
import Testing
@testable import sloppy
@testable import Protocols

private func makeProjectWithTask(router: CoreRouter) async throws -> (projectID: String, taskID: String) {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectID = "comment-proj-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Comment Test Project", description: "Test", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    let taskBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(title: "Test Task", description: "Desc", priority: "medium", status: "backlog")
    )
    let taskResp = await router.handle(method: "POST", path: "/v1/projects/\(projectID)/tasks", body: taskBody)
    #expect(taskResp.status == 200)
    let project = try decoder.decode(ProjectRecord.self, from: taskResp.body)
    let taskID = try #require(project.tasks.first?.id)
    return (projectID, taskID)
}

@Test
func listTaskCommentsReturnsEmptyInitially() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/comments",
        body: nil
    )
    #expect(resp.status == 200)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let comments = try decoder.decode([TaskComment].self, from: resp.body)
    #expect(comments.isEmpty)
}

@Test
func addTaskCommentCreatesAndReturnsComment() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let payload = try JSONEncoder().encode(
        TaskCommentCreateRequest(content: "Hello world", authorActorId: "user1")
    )
    let postResp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/comments",
        body: payload
    )
    #expect(postResp.status == 201)
    let comment = try decoder.decode(TaskComment.self, from: postResp.body)
    #expect(comment.content == "Hello world")
    #expect(comment.authorActorId == "user1")
    #expect(comment.taskId == taskID)
    #expect(comment.isAgentReply == false)
    #expect(comment.mentionedActorId == nil)
}

@Test
func addTaskCommentWithMentionPersistsMentionedActorId() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let payload = try JSONEncoder().encode(
        TaskCommentCreateRequest(content: "Hey CEO", authorActorId: "user1", mentionedActorId: "ceo")
    )
    let postResp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/comments",
        body: payload
    )
    #expect(postResp.status == 201)
    let comment = try decoder.decode(TaskComment.self, from: postResp.body)
    #expect(comment.mentionedActorId == "ceo")
}

@Test
func listTaskCommentsReturnsPreviouslyAddedComments() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    for text in ["First comment", "Second comment"] {
        let payload = try JSONEncoder().encode(
            TaskCommentCreateRequest(content: text, authorActorId: "user1")
        )
        _ = await router.handle(
            method: "POST",
            path: "/v1/projects/\(projectID)/tasks/\(taskID)/comments",
            body: payload
        )
    }

    let listResp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/comments",
        body: nil
    )
    #expect(listResp.status == 200)
    let comments = try decoder.decode([TaskComment].self, from: listResp.body)
    #expect(comments.count == 2)
    #expect(comments[0].content == "First comment")
    #expect(comments[1].content == "Second comment")
}

@Test
func deleteTaskCommentRemovesIt() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let payload = try JSONEncoder().encode(
        TaskCommentCreateRequest(content: "To be deleted", authorActorId: "user1")
    )
    let postResp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/comments",
        body: payload
    )
    #expect(postResp.status == 201)
    let comment = try decoder.decode(TaskComment.self, from: postResp.body)

    let deleteResp = await router.handle(
        method: "DELETE",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/comments/\(comment.id)",
        body: nil
    )
    #expect(deleteResp.status == 200)

    let listResp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/comments",
        body: nil
    )
    let remaining = try decoder.decode([TaskComment].self, from: listResp.body)
    #expect(remaining.isEmpty)
}

@Test
func deleteTaskCommentReturns404ForUnknownId() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let resp = await router.handle(
        method: "DELETE",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/comments/nonexistent-id",
        body: nil
    )
    #expect(resp.status == 404)
}

@Test
func addTaskCommentInvalidPayloadReturns400() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, taskID) = try await makeProjectWithTask(router: router)

    let resp = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectID)/tasks/\(taskID)/comments",
        body: Data("not json".utf8)
    )
    #expect(resp.status == 400)
}
