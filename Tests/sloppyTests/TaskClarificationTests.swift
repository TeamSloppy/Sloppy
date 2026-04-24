import Foundation
import Testing
@testable import sloppy
@testable import Protocols

private func makeProjectWithTask(router: CoreRouter, loopMode: ProjectLoopMode = .human) async throws -> (projectID: String, taskID: String) {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectID = "clar-proj-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Clarification Test", description: "Test", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResp.status == 201)

    if loopMode != .human {
        let updateBody = try JSONEncoder().encode(ProjectUpdateRequest(taskLoopMode: loopMode))
        let updateResp = await router.handle(method: "PATCH", path: "/v1/projects/\(projectID)", body: updateBody)
        #expect(updateResp.status == 200)
    }

    let taskBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(title: "Test Task", description: "Desc", priority: "medium", status: "backlog", kind: .execution)
    )
    let taskResp = await router.handle(method: "POST", path: "/v1/projects/\(projectID)/tasks", body: taskBody)
    #expect(taskResp.status == 200)
    let project = try decoder.decode(ProjectRecord.self, from: taskResp.body)
    let taskID = try #require(project.tasks.first?.id)
    return (projectID, taskID)
}

private func basePath(_ projectID: String, _ taskID: String) -> String {
    "/v1/projects/\(projectID)/tasks/\(taskID)/clarifications"
}

@Test
func listClarificationsReturnsEmptyInitially() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (pid, tid) = try await makeProjectWithTask(router: router)

    let resp = await router.handle(method: "GET", path: basePath(pid, tid), body: nil)
    #expect(resp.status == 200)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let items = try decoder.decode([TaskClarificationRecord].self, from: resp.body)
    #expect(items.isEmpty)
}

@Test
func createClarificationReturnsPendingRecord() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (pid, tid) = try await makeProjectWithTask(router: router)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let payload = try JSONEncoder().encode(
        TaskClarificationCreateRequest(
            questionText: "Which approach?",
            options: [
                ClarificationOption(id: "a", label: "Option A"),
                ClarificationOption(id: "b", label: "Option B")
            ],
            allowNote: true,
            createdByAgentId: "agent-1"
        )
    )
    let resp = await router.handle(method: "POST", path: basePath(pid, tid), body: payload)
    #expect(resp.status == 201)
    let record = try decoder.decode(TaskClarificationRecord.self, from: resp.body)
    #expect(record.status == .pending)
    #expect(record.questionText == "Which approach?")
    #expect(record.options.count == 2)
    #expect(record.allowNote == true)
    #expect(record.projectId == pid)
    #expect(record.taskId == tid)
    #expect(record.createdByAgentId == "agent-1")
    #expect(record.targetType == .human)
}

@Test
func createClarificationSetsTaskToWaitingInput() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (pid, tid) = try await makeProjectWithTask(router: router)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let payload = try JSONEncoder().encode(
        TaskClarificationCreateRequest(questionText: "Need clarification")
    )
    _ = await router.handle(method: "POST", path: basePath(pid, tid), body: payload)

    let projResp = await router.handle(method: "GET", path: "/v1/projects/\(pid)", body: nil)
    #expect(projResp.status == 200)
    let project = try decoder.decode(ProjectRecord.self, from: projResp.body)
    let task = try #require(project.tasks.first(where: { $0.id == tid }))
    #expect(task.status == ProjectTaskStatus.waitingInput.rawValue)
}

@Test
func answerClarificationUpdatesStatusAndMovesTaskToReady() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (pid, tid) = try await makeProjectWithTask(router: router)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let createPayload = try JSONEncoder().encode(
        TaskClarificationCreateRequest(
            questionText: "Which approach?",
            options: [ClarificationOption(id: "a", label: "A")]
        )
    )
    let createResp = await router.handle(method: "POST", path: basePath(pid, tid), body: createPayload)
    let record = try decoder.decode(TaskClarificationRecord.self, from: createResp.body)

    let answerPayload = try JSONEncoder().encode(
        TaskClarificationAnswerRequest(selectedOptionIds: ["a"], note: "Go with A")
    )
    let answerResp = await router.handle(
        method: "POST",
        path: "\(basePath(pid, tid))/\(record.id)/answer",
        body: answerPayload
    )
    #expect(answerResp.status == 200)
    let answered = try decoder.decode(TaskClarificationRecord.self, from: answerResp.body)
    #expect(answered.status == .answered)
    #expect(answered.selectedOptionIds == ["a"])
    #expect(answered.note == "Go with A")
    #expect(answered.answeredAt != nil)

    let projResp = await router.handle(method: "GET", path: "/v1/projects/\(pid)", body: nil)
    let project = try decoder.decode(ProjectRecord.self, from: projResp.body)
    let task = try #require(project.tasks.first(where: { $0.id == tid }))
    #expect(task.status == "ready")
}

@Test
func agentLoopModeRoutesClarificationToAgent() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (pid, tid) = try await makeProjectWithTask(router: router, loopMode: .agent)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let payload = try JSONEncoder().encode(
        TaskClarificationCreateRequest(questionText: "Routing question?")
    )
    let resp = await router.handle(method: "POST", path: basePath(pid, tid), body: payload)
    #expect(resp.status == 201)
    let record = try decoder.decode(TaskClarificationRecord.self, from: resp.body)
    #expect(record.targetType == .actor)
}

@Test
func taskKindAndLoopModeOverridePersistsThroughCreateAndUpdate() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectID = "kind-proj-\(UUID().uuidString)"
    let createProjectBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Kind Test", description: "", channels: [])
    )
    _ = await router.handle(method: "POST", path: "/v1/projects", body: createProjectBody)

    let taskBody = try JSONEncoder().encode(
        ProjectTaskCreateRequest(title: "Task", priority: "high", kind: .bugfix, loopModeOverride: .agent)
    )
    let taskResp = await router.handle(method: "POST", path: "/v1/projects/\(projectID)/tasks", body: taskBody)
    let project = try decoder.decode(ProjectRecord.self, from: taskResp.body)
    let task = try #require(project.tasks.first)
    #expect(task.kind == .bugfix)
    #expect(task.loopModeOverride == .agent)

    let updateBody = try JSONEncoder().encode(
        ProjectTaskUpdateRequest(kind: .planning, loopModeOverride: .human)
    )
    let updateResp = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectID)/tasks/\(task.id)",
        body: updateBody
    )
    let updated = try decoder.decode(ProjectRecord.self, from: updateResp.body)
    let updatedTask = try #require(updated.tasks.first(where: { $0.id == task.id }))
    #expect(updatedTask.kind == .planning)
    #expect(updatedTask.loopModeOverride == .human)
}

@Test
func projectTaskLoopModeDefaultsToHuman() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectID = "loop-proj-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Loop Test", description: "", channels: [])
    )
    let createResp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    let project = try decoder.decode(ProjectCreateResult.self, from: createResp.body).project
    #expect(project.taskLoopMode == .human)
}

@Test
func projectTaskLoopModeCanBeUpdated() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectID = "loop-upd-\(UUID().uuidString)"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Loop Update Test", description: "", channels: [])
    )
    _ = await router.handle(method: "POST", path: "/v1/projects", body: createBody)

    let updateBody = try JSONEncoder().encode(ProjectUpdateRequest(taskLoopMode: .agent))
    let resp = await router.handle(method: "PATCH", path: "/v1/projects/\(projectID)", body: updateBody)
    #expect(resp.status == 200)
    let project = try decoder.decode(ProjectRecord.self, from: resp.body)
    #expect(project.taskLoopMode == .agent)
}

@Test
func waitingInputStatusIsRecognized() {
    let status = ProjectTaskStatus(rawValue: "waiting_input")
    #expect(status == .waitingInput)
    #expect(status?.isTerminal == false)
}
