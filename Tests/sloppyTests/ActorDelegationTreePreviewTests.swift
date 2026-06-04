import Testing
@testable import sloppy
@testable import Protocols

@Test
func delegationTreePreviewReturnsBranchingLevels() {
    let board = ActorBoardSnapshot(
        nodes: [
            agentNode("agent:lead", "Lead", linkedAgentId: "lead"),
            agentNode("agent:ios", "iOS", linkedAgentId: "ios"),
            agentNode("agent:backend", "Backend", linkedAgentId: "backend"),
            agentNode("agent:qa", "QA", linkedAgentId: "qa")
        ],
        links: [
            taskLink("lead-ios", "agent:lead", "agent:ios"),
            taskLink("lead-backend", "agent:lead", "agent:backend"),
            taskLink("ios-qa", "agent:ios", "agent:qa")
        ],
        teams: []
    )

    let preview = CoreService.previewActorDelegationTree(board: board, rootActorId: "agent:lead")

    #expect(preview.status == .valid)
    #expect(preview.errors.isEmpty)
    #expect(preview.levels.map { $0.map(\.actorId) } == [["agent:backend", "agent:ios"], ["agent:qa"]])
    #expect(preview.levels[0].map(\.linkedAgentId) == ["backend", "ios"])
}

@Test
func delegationTreePreviewBlocksRootWithoutChildren() {
    let board = ActorBoardSnapshot(
        nodes: [agentNode("agent:lead", "Lead", linkedAgentId: "lead")],
        links: [],
        teams: []
    )

    let preview = CoreService.previewActorDelegationTree(board: board, rootActorId: "agent:lead")

    #expect(preview.status == .invalid)
    #expect(preview.errors.contains { $0.code == "root_without_children" })
}

@Test
func delegationTreePreviewBlocksReachableCycle() {
    let board = ActorBoardSnapshot(
        nodes: [
            agentNode("agent:lead", "Lead", linkedAgentId: "lead"),
            agentNode("agent:ios", "iOS", linkedAgentId: "ios")
        ],
        links: [
            taskLink("lead-ios", "agent:lead", "agent:ios"),
            taskLink("ios-lead", "agent:ios", "agent:lead")
        ],
        teams: []
    )

    let preview = CoreService.previewActorDelegationTree(board: board, rootActorId: "agent:lead")

    #expect(preview.status == .invalid)
    #expect(preview.errors.contains { $0.code == "cycle" })
}

@Test
func delegationTreePreviewBlocksNonAgentExecutionTarget() {
    let board = ActorBoardSnapshot(
        nodes: [
            agentNode("agent:lead", "Lead", linkedAgentId: "lead"),
            ActorNode(id: "human:reviewer", displayName: "Reviewer", kind: .human)
        ],
        links: [
            taskLink("lead-reviewer", "agent:lead", "human:reviewer")
        ],
        teams: []
    )

    let preview = CoreService.previewActorDelegationTree(board: board, rootActorId: "agent:lead")

    #expect(preview.status == .invalid)
    #expect(preview.errors.contains { $0.code == "non_agent_execution_node" && $0.actorId == "human:reviewer" })
}

@Test
func delegationTreePreviewWarnsAboutIgnoredTwoWayTaskLink() {
    let board = ActorBoardSnapshot(
        nodes: [
            agentNode("agent:lead", "Lead", linkedAgentId: "lead"),
            agentNode("agent:ios", "iOS", linkedAgentId: "ios")
        ],
        links: [
            ActorLink(
                id: "lead-ios-two-way",
                sourceActorId: "agent:lead",
                targetActorId: "agent:ios",
                direction: .twoWay,
                relationship: .hierarchical,
                communicationType: .task
            )
        ],
        teams: []
    )

    let preview = CoreService.previewActorDelegationTree(board: board, rootActorId: "agent:lead")

    #expect(preview.status == .invalid)
    #expect(preview.errors.contains { $0.code == "root_without_children" })
    #expect(preview.warnings.contains { $0.code == "ignored_two_way_task_link" && $0.linkId == "lead-ios-two-way" })
}

private func agentNode(_ id: String, _ name: String, linkedAgentId: String?) -> ActorNode {
    ActorNode(
        id: id,
        displayName: name,
        kind: .agent,
        linkedAgentId: linkedAgentId,
        channelId: id
    )
}

private func taskLink(_ id: String, _ source: String, _ target: String) -> ActorLink {
    ActorLink(
        id: id,
        sourceActorId: source,
        targetActorId: target,
        direction: .oneWay,
        relationship: .hierarchical,
        communicationType: .task
    )
}
