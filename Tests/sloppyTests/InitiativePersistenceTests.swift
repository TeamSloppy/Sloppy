import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Test
func savesAndLoadsInitiativeRecords() async throws {
    let store = InMemoryPersistenceStore()
    let record = InitiativeRecord(
        id: "init-ci",
        projectID: "project-ci",
        title: "Optimize CI pipeline",
        goal: "Reduce CI duration without reducing confidence",
        phase: .framing,
        executionMode: .singleAgent,
        successMetrics: ["duration_p95_minutes <= 12"],
        constraints: ["keep release builds green"],
        resumePoint: "collect baseline timings",
        blocker: nil,
        metadata: ["origin": "user"],
        createdAt: Date(),
        updatedAt: Date()
    )

    await store.saveInitiative(record)
    let loaded = await store.getInitiative(projectID: "project-ci", initiativeID: "init-ci")

    #expect(loaded?.phase == .framing)
    #expect(loaded?.executionMode == .singleAgent)
    #expect(loaded?.resumePoint == "collect baseline timings")
}

@Test
func savesAndListsDecisionPacketsForInitiative() async throws {
    let store = InMemoryPersistenceStore()
    let packet = DecisionPacketRecord(
        id: "packet-1",
        projectID: "project-ci",
        initiativeID: "init-ci",
        summary: "Need runner budget increase",
        rationale: "Faster macOS capacity costs more",
        tradeoffs: ["higher monthly spend"],
        requestedAction: "Approve higher runner budget",
        resumePoint: "resume benchmark matrix",
        status: "open",
        createdAt: Date(),
        updatedAt: Date()
    )

    await store.saveDecisionPacket(packet)
    let loaded = await store.listDecisionPackets(projectID: "project-ci", initiativeID: "init-ci")

    #expect(loaded.count == 1)
    #expect(loaded.first?.requestedAction == "Approve higher runner budget")
    #expect(loaded.first?.resumePoint == "resume benchmark matrix")
}
