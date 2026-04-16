import Foundation
import Testing
@testable import sloppy
@testable import Protocols

private func makeCompletionTestContext() async throws -> (service: CoreService, router: CoreRouter, projectID: String, taskID: String) {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectID = "completion-proj-\(UUID().uuidString)"
    let createProjectBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Completion Test", description: "", channels: [])
    )
    let createProjectResponse = await router.handle(method: "POST", path: "/v1/projects", body: createProjectBody)
    #expect(createProjectResponse.status == 201)

    let taskBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(
            title: "Check completion",
            description: "Verify completion flow",
            priority: "medium",
            status: ProjectTaskStatus.inProgress.rawValue
        )
    )
    let taskResponse = await router.handle(method: "POST", path: "/v1/projects/\(projectID)/tasks", body: taskBody)
    #expect(taskResponse.status == 200)
    let project = try decoder.decode(ProjectRecord.self, from: taskResponse.body)
    let taskID = try #require(project.tasks.first?.id)
    return (service, router, projectID, taskID)
}

@Test
func agentCannotSetDoneWithoutConfirmation() async throws {
    let (service, _, projectID, taskID) = try await makeCompletionTestContext()

    await #expect(throws: CoreService.ProjectError.invalidPayload) {
        try await service.updateProjectTask(
            projectID: projectID,
            taskID: taskID,
            request: ProjectTaskUpdateRequest(
                status: ProjectTaskStatus.done.rawValue,
                changedBy: "agent:test"
            )
        )
    }
}

@Test
func agentCanSetDoneWithConfirmationPayload() async throws {
    let (service, _, projectID, taskID) = try await makeCompletionTestContext()

    let updated = try await service.updateProjectTask(
        projectID: projectID,
        taskID: taskID,
        request: ProjectTaskUpdateRequest(
            status: ProjectTaskStatus.done.rawValue,
            completionConfidence: .done,
            completionNote: "Verified the requested change and checked the final state.",
            changedBy: "agent:test"
        )
    )

    let task = try #require(updated.tasks.first(where: { $0.id == taskID }))
    #expect(task.status == ProjectTaskStatus.done.rawValue)
}

@Test
func workerCompletedWithoutExplicitDoneBlocksTask() async throws {
    let (service, _, projectID, taskID) = try await makeCompletionTestContext()

    await service.handleVisorEvent(
        EventEnvelope(
            messageType: .workerCompleted,
            channelId: "general",
            taskId: taskID,
            workerId: "worker-1",
            payload: .object([:])
        )
    )

    let saved = try await service.getProject(id: projectID)
    let task = try #require(saved.tasks.first(where: { $0.id == taskID }))
    #expect(task.status == ProjectTaskStatus.blocked.rawValue)
    #expect(task.description.contains("without explicit completion confirmation"))
}

@Test
func workerCompletedPreservesExplicitBlockedStatus() async throws {
    let (service, _, projectID, taskID) = try await makeCompletionTestContext()

    _ = try await service.updateProjectTask(
        projectID: projectID,
        taskID: taskID,
        request: ProjectTaskUpdateRequest(
            status: ProjectTaskStatus.blocked.rawValue,
            changedBy: "agent:test"
        )
    )

    await service.handleVisorEvent(
        EventEnvelope(
            messageType: .workerCompleted,
            channelId: "general",
            taskId: taskID,
            workerId: "worker-2",
            payload: .object([:])
        )
    )

    let saved = try await service.getProject(id: projectID)
    let task = try #require(saved.tasks.first(where: { $0.id == taskID }))
    #expect(task.status == ProjectTaskStatus.blocked.rawValue)
}
