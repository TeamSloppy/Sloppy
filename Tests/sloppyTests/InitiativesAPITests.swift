import Foundation
import Testing
@testable import sloppy
import Protocols

@Test
func createInitiativeEndpointPersistsRecord() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectId = "initiative-router-\(UUID().uuidString)"
    let createProjectBody = try encoder.encode(
        ProjectCreateRequest(id: projectId, name: "Initiatives", description: "Test", channels: [])
    )
    let projectResponse = await router.handle(method: "POST", path: "/v1/projects", body: createProjectBody)
    #expect(projectResponse.status == 201)

    let createBody = try encoder.encode(
        CreateInitiativeRequest(
            title: "Optimize CI pipeline",
            goal: "Reduce CI duration without reducing confidence",
            successMetrics: ["duration_p95_minutes <= 12"],
            constraints: ["keep release builds green"]
        )
    )
    let createResponse = await router.handle(method: "POST", path: "/v1/projects/\(projectId)/initiatives", body: createBody)
    #expect(createResponse.status == 200)

    let created = try decoder.decode(InitiativeDetailResponse.self, from: createResponse.body)
    #expect(created.initiative.phase == .intake)
    #expect(created.initiative.executionMode == .singleAgent)
    #expect(created.initiative.resumePoint == "start framing")

    let listResponse = await router.handle(method: "GET", path: "/v1/projects/\(projectId)/initiatives", body: nil)
    #expect(listResponse.status == 200)
    let list = try decoder.decode(InitiativeListResponse.self, from: listResponse.body)
    #expect(list.initiatives.map(\.id) == [created.initiative.id])

    let patchBody = try encoder.encode(
        UpdateInitiativeRequest(
            phase: .executing,
            executionMode: .delegation,
            resumePoint: "benchmark sharded tests"
        )
    )
    let patchResponse = await router.handle(
        method: "PATCH",
        path: "/v1/projects/\(projectId)/initiatives/\(created.initiative.id)",
        body: patchBody
    )
    #expect(patchResponse.status == 200)
    let updated = try decoder.decode(InitiativeDetailResponse.self, from: patchResponse.body)
    #expect(updated.initiative.phase == .executing)
    #expect(updated.initiative.executionMode == .delegation)
    #expect(updated.initiative.resumePoint == "benchmark sharded tests")

    let packetBody = try encoder.encode(
        CreateDecisionPacketRequest(
            summary: "Need bigger runner budget",
            rationale: "Queueing dominates CI time.",
            tradeoffs: ["Higher monthly spend"],
            requestedAction: "Approve a larger macOS runner pool",
            resumePoint: "rerun benchmark matrix"
        )
    )
    let packetResponse = await router.handle(
        method: "POST",
        path: "/v1/projects/\(projectId)/initiatives/\(created.initiative.id)/decision-packets",
        body: packetBody
    )
    #expect(packetResponse.status == 200)
    let createdPacket = try decoder.decode(DecisionPacketDetailResponse.self, from: packetResponse.body)
    #expect(createdPacket.decisionPacket.status == "open")

    let packetListResponse = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectId)/initiatives/\(created.initiative.id)/decision-packets",
        body: nil
    )
    #expect(packetListResponse.status == 200)
    let packetList = try decoder.decode(DecisionPacketListResponse.self, from: packetListResponse.body)
    #expect(packetList.decisionPackets.map(\.id) == [createdPacket.decisionPacket.id])
}
