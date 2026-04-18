import Foundation
import Testing
@testable import sloppy
@testable import Protocols

@Test
func nextTeamHandoffDelegateFollowsTaskLinks() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())

    _ = try? await service.createAgent(AgentCreateRequest(id: "dev", displayName: "Dev", role: "Dev", isSystem: false))
    _ = try? await service.createAgent(AgentCreateRequest(id: "qa", displayName: "QA", role: "QA", isSystem: false))
    _ = try? await service.createAgent(AgentCreateRequest(id: "reviewer", displayName: "Reviewer", role: "Reviewer", isSystem: false))

    // Setup Board
    var board = ActorBoardSnapshot(nodes: [], links: [], teams: [])
    let node1 = ActorNode(id: "agent:dev", displayName: "Dev", kind: .agent, linkedAgentId: "dev")
    let node2 = ActorNode(id: "agent:qa", displayName: "QA", kind: .agent, linkedAgentId: "qa")
    let node3 = ActorNode(id: "agent:reviewer", displayName: "Reviewer", kind: .agent, linkedAgentId: "reviewer")
    
    // Links: Dev -> Reviewer -> QA. (So it skips the array order [Dev, QA, Reviewer])
    let link1 = ActorLink(
        id: "link1", sourceActorId: "agent:dev", targetActorId: "agent:reviewer",
        direction: .oneWay, communicationType: .task
    )
    let link2 = ActorLink(
        id: "link2", sourceActorId: "agent:reviewer", targetActorId: "agent:qa",
        direction: .oneWay, communicationType: .task
    )
    
    // Team: [Dev, QA, Reviewer]
    let team = ActorTeam(id: "team:1", name: "Team 1", memberActorIds: ["agent:dev", "agent:qa", "agent:reviewer"])
    board.nodes = [node1, node2, node3]
    board.links = [link1, link2]
    board.teams = [team]

    _ = try await service.updateActorBoard(request: ActorBoardUpdateRequest(nodes: board.nodes, links: board.links, teams: board.teams))

    // Create Project & Task
    let project = ProjectRecord(
        id: "proj:1", name: "Test Project", description: "Test",
        channels: [], tasks: [
            ProjectTask(
                id: "task:1", title: "Task 1", description: "", priority: "medium", status: "done",
                teamId: "team:1", claimedActorId: "agent:dev", claimedAgentId: "dev"
            )
        ]
    )

    let delegate1 = await service.nextTeamHandoffDelegate(project: project, task: project.tasks[0])
    
    // Expected: It should follow link1 to "agent:reviewer", ignoring the array order which says "agent:qa" is next.
    #expect(delegate1?.actorID == "agent:reviewer")
    #expect(delegate1?.agentID == "reviewer")
    
    // Test second handoff
    var task2 = project.tasks[0]
    task2.claimedActorId = "agent:reviewer"
    let delegate2 = await service.nextTeamHandoffDelegate(project: project, task: task2)
    #expect(delegate2?.actorID == "agent:qa")
}

@Test
func nextTeamHandoffDelegateFallsBackToArrayIndex() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())

    _ = try? await service.createAgent(AgentCreateRequest(id: "dev", displayName: "Dev", role: "Dev", isSystem: false))
    _ = try? await service.createAgent(AgentCreateRequest(id: "qa", displayName: "QA", role: "QA", isSystem: false))
    _ = try? await service.createAgent(AgentCreateRequest(id: "reviewer", displayName: "Reviewer", role: "Reviewer", isSystem: false))

    // Setup Board with NO links
    var board = ActorBoardSnapshot(nodes: [], links: [], teams: [])
    let node1 = ActorNode(id: "agent:dev", displayName: "Dev", kind: .agent, linkedAgentId: "dev")
    let node2 = ActorNode(id: "agent:qa", displayName: "QA", kind: .agent, linkedAgentId: "qa")
    let team = ActorTeam(id: "team:1", name: "Team 1", memberActorIds: ["agent:dev", "agent:qa"])
    board.nodes = [node1, node2]
    board.teams = [team]

    _ = try await service.updateActorBoard(request: ActorBoardUpdateRequest(nodes: board.nodes, links: board.links, teams: board.teams))

    let project = ProjectRecord(
        id: "proj:1", name: "Test Project", description: "Test",
        channels: [], tasks: [
            ProjectTask(
                id: "task:1", title: "Task 1", description: "", priority: "medium", status: "done",
                teamId: "team:1", claimedActorId: "agent:dev"
            )
        ]
    )

    let delegate = await service.nextTeamHandoffDelegate(project: project, task: project.tasks[0])
    
    // Should fallback to next in array: QA
    #expect(delegate?.actorID == "agent:qa")
    #expect(delegate?.agentID == "qa")
}
