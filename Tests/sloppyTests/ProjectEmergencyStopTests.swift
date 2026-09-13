import Foundation
import Testing
import Protocols
@testable import sloppy

@Test
func projectEmergencyStopCancelsOnlyItsExecutionsAndDisablesPickup() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    await service.waitForStartup(dispatchReadyTasks: false)
    let agent = try await service.createAgent(.init(id: "stop-agent", displayName: "Stop agent", role: "Worker"))
    let session = try await service.createAgentSession(agentID: agent.id, request: .init(title: "Execution"))
    let otherSession = try await service.createAgentSession(agentID: agent.id, request: .init(title: "Other project"))
    let task = ProjectTask(id: "active", title: "Active", description: "", priority: "medium", status: "in_progress")
    let ready = ProjectTask(id: "queued", title: "Queued", description: "", priority: "medium", status: "ready")
    let other = ProjectTask(id: "other", title: "Other", description: "", priority: "medium", status: "in_progress")
    await service.store.saveProject(.init(id: "stop-project", name: "Stop", description: "", channels: [], tasks: [task, ready]))
    await service.store.saveProject(.init(id: "other-project", name: "Other", description: "", channels: [], tasks: [other,
        .init(id: "other-ready", title: "Other ready", description: "", priority: "medium", status: "ready")
    ]))
    await service.registerProjectExecutionSession(sessionID: session.id, projectID: "stop-project", taskID: task.id, agentID: agent.id)
    await service.registerProjectExecutionSession(sessionID: otherSession.id, projectID: "other-project", taskID: other.id, agentID: agent.id)
    let now = Date()
    await service.runtime.recover(
        channels: [.init(id: "work", createdAt: now, updatedAt: now)],
        tasks: [task, other].map { .init(id: $0.id, channelId: "work", status: "in_progress", title: $0.title,
                                       objective: "Working", createdAt: now, updatedAt: now) },
        events: [], artifacts: []
    )
    let router = CoreRouter(service: service)
    let response = await router.handle(method: "POST", path: "/v1/projects/stop-project/emergency-stop", body: nil)
    #expect(response.status == 200)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let result = try decoder.decode(ProjectEmergencyStopResponse.self, from: response.body)
    #expect(result.project.automaticTaskPickupEnabled == false)
    #expect(result.project.tasks.first { $0.id == task.id }?.status == "cancelled")
    #expect(result.project.tasks.first { $0.id == ready.id }?.status == "ready")
    #expect(result.stoppedWorkerCount == 1)
    #expect(result.interruptedSessionCount == 1)
    #expect(result.warnings.isEmpty)
    let workers = await service.runtime.workerSnapshots()
    #expect(workers.first { $0.taskId == task.id }?.status == .failed)
    #expect(workers.first { $0.taskId == other.id }?.status == .running)
    let interrupted = try await service.getAgentSession(agentID: agent.id, sessionID: session.id)
    #expect(interrupted.events.contains { $0.runControl?.action == .interruptTree })
    let untouched = try await service.getAgentSession(agentID: agent.id, sessionID: otherSession.id)
    #expect(!untouched.events.contains { $0.runControl?.action == .interruptTree })
    #expect(await service.store.project(id: "other-project")?.automaticTaskPickupEnabled == true)
    #expect(await service.store.project(id: "other-project")?.tasks.last?.status == "ready")
    _ = try await service.recordProjectTaskSpawnFailure(projectID: "stop-project", taskID: task.id, error: "Late cancellation")
    #expect(await service.store.project(id: "stop-project")?.tasks.first?.status == "cancelled")
    let repeated = try await service.emergencyStopProject(projectID: "stop-project")
    #expect(repeated.stoppedWorkerCount == 0)
}

@Test
func projectEmergencyStopInterruptsPendingInput() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    await service.waitForStartup(dispatchReadyTasks: false)
    let agent = try await service.createAgent(.init(id: "pending-stop-agent", displayName: "Worker", role: "Worker"))
    let session = try await service.createAgentSession(agentID: agent.id, request: .init(title: "Waiting"))
    await service.store.saveProject(.init(id: "waiting-project", name: "Waiting", description: "", channels: [], tasks: [
        .init(id: "waiting", title: "Waiting", description: "", priority: "medium", status: "waiting_input")
    ]))
    await service.registerProjectExecutionSession(sessionID: session.id, projectID: "waiting-project", taskID: "waiting", agentID: agent.id)
    _ = try await service.appendAgentSessionEvents(agentID: agent.id, sessionID: session.id, request: .init(events: [
        .init(agentId: agent.id, sessionId: session.id, type: .inputRequest,
              inputRequest: .init(id: "input", mode: "plan", title: "Choose", questions: [
                .init(id: "choice", question: "Continue?", options: [])
              ]))
    ]))
    let result = try await service.emergencyStopProject(projectID: "waiting-project")
    #expect(result.warnings.isEmpty)
    let detail = try await service.getAgentSession(agentID: agent.id, sessionID: session.id)
    #expect(detail.events.contains { $0.runStatus?.stage == .interrupted })
    #expect(result.project.tasks.first?.status == "cancelled")
}

@Test
func projectEmergencyStopReportsUnconfirmedRemoteExecution() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    var task = ProjectTask(id: "remote-task", title: "Remote", description: "", priority: "medium", status: "in_progress")
    task.executionNodeId = "remote-test-node"
    await service.store.saveProject(.init(id: "remote-project", name: "Remote", description: "", channels: [], tasks: [task]))
    let result = try await service.emergencyStopProject(projectID: "remote-project")
    #expect(result.project.automaticTaskPickupEnabled == false)
    #expect(result.stoppedWorkerCount == 0)
    #expect(result.warnings.contains { $0.contains("remote-task") && $0.contains("not confirmed") })
}
