import Foundation
import Testing
@testable import sloppy
@testable import Protocols

@Test
func escalatesToDelegationWhenVerificationIsRequired() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let projectID = "initiative-policy-\(UUID().uuidString)"
    _ = try await service.createProject(
        ProjectCreateRequest(id: projectID, name: "Initiative Policy", description: "Test", channels: [])
    )

    let created = try await service.createInitiative(
        projectID: projectID,
        request: .init(
            title: "Optimize CI pipeline",
            goal: "Reduce CI duration without reducing confidence",
            successMetrics: ["duration_p95_minutes <= 12"],
            constraints: ["keep release builds green"],
            metadata: [:]
        )
    )

    let updated = try await service.updateInitiativeExecutionMode(
        projectID: projectID,
        initiativeID: created.initiative.id,
        signal: .needsIndependentVerification
    )

    #expect(updated.executionMode == .delegation)
}

@Test
func projectTaskCreateAndUpdatePreserveInitiativeID() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let projectID = "initiative-task-link-\(UUID().uuidString)"
    _ = try await service.createProject(
        ProjectCreateRequest(id: projectID, name: "Initiative Task Link", description: "Test", channels: [])
    )

    let project = try await service.createProjectTask(
        projectID: projectID,
        request: .init(
            title: "Benchmark CI",
            initiativeID: "init-ci"
        )
    )
    let createdTask = try #require(project.tasks.first)
    #expect(createdTask.initiativeID == "init-ci")

    let updatedProject = try await service.updateProjectTask(
        projectID: projectID,
        taskID: createdTask.id,
        request: .init(initiativeID: "init-ci-2")
    )
    let updatedTask = try #require(updatedProject.tasks.first(where: { $0.id == createdTask.id }))
    #expect(updatedTask.initiativeID == "init-ci-2")
}
