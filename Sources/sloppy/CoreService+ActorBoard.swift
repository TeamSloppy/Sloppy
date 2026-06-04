import Foundation
import Protocols

// MARK: - Actor Board

extension CoreService {
    public func getActorBoard() throws -> ActorBoardSnapshot {
        do {
            let agents = try listAgents()
            return try actorBoardStore.loadBoard(agents: agents)
        } catch {
            throw mapActorBoardError(error)
        }
    }

    /// Stores visual actor graph updates and re-synchronizes system actors.
    public func updateActorBoard(request: ActorBoardUpdateRequest) throws -> ActorBoardSnapshot {
        do {
            let agents = try listAgents()
            return try actorBoardStore.saveBoard(request, agents: agents)
        } catch {
            throw mapActorBoardError(error)
        }
    }

    /// Resolves which actors can receive data from the sender according to graph links.
    public func resolveActorRoute(request: ActorRouteRequest) throws -> ActorRouteResponse {
        do {
            let agents = try listAgents()
            return try actorBoardStore.resolveRoute(request, agents: agents)
        } catch {
            throw mapActorBoardError(error)
        }
    }

    /// Validates and previews the saved delegation tree rooted at one actor.
    public func previewActorDelegationTree(request: ActorDelegationTreePreviewRequest) throws -> ActorDelegationTreePreviewResponse {
        do {
            let agents = try listAgents()
            let board = try actorBoardStore.loadBoard(agents: agents)
            return Self.previewActorDelegationTree(board: board, rootActorId: request.rootActorId)
        } catch {
            throw mapActorBoardError(error)
        }
    }

    static func previewActorDelegationTree(
        board: ActorBoardSnapshot,
        rootActorId rawRootActorId: String
    ) -> ActorDelegationTreePreviewResponse {
        let rootActorId = normalizedActorEntityIDValue(rawRootActorId) ?? rawRootActorId.trimmingCharacters(in: .whitespacesAndNewlines)
        var errors: [ActorDelegationTreeIssue] = []
        var warnings: [ActorDelegationTreeIssue] = []
        let nodesByID = Dictionary(uniqueKeysWithValues: board.nodes.map { ($0.id, $0) })

        guard !rootActorId.isEmpty else {
            errors.append(actorDelegationIssue(
                code: "missing_root",
                message: "Select a root agent for the delegation tree.",
                severity: .error
            ))
            return actorDelegationPreview(rootActorId: rootActorId, levels: [], errors: errors, warnings: warnings)
        }

        guard let rootNode = nodesByID[rootActorId] else {
            errors.append(actorDelegationIssue(
                code: "unknown_root",
                message: "The selected root actor is not on the Actor Board.",
                severity: .error,
                actorId: rootActorId
            ))
            return actorDelegationPreview(rootActorId: rootActorId, levels: [], errors: errors, warnings: warnings)
        }

        validateExecutionAgent(rootNode, into: &errors, code: "root_not_agent")

        let executionLinks = board.links.filter { link in
            guard link.communicationType == .task, effectiveActorRelationship(for: link) == .hierarchical else {
                return false
            }
            if link.direction == .twoWay {
                warnings.append(actorDelegationIssue(
                    code: "ignored_two_way_task_link",
                    message: "Two-way hierarchical task links are ignored by swarm execution.",
                    severity: .warning,
                    linkId: link.id
                ))
                return false
            }
            return true
        }

        for link in executionLinks {
            if let target = nodesByID[link.targetActorId], target.kind != .agent {
                errors.append(actorDelegationIssue(
                    code: "non_agent_execution_node",
                    message: "Delegation tree execution links can only target agent nodes.",
                    severity: .error,
                    actorId: target.id,
                    linkId: link.id
                ))
            }
        }

        let disconnectedRoots = Set(executionLinks.map(\.sourceActorId)).subtracting(Set(executionLinks.map(\.targetActorId))).subtracting([rootActorId])
        for actorId in disconnectedRoots.sorted() {
            warnings.append(actorDelegationIssue(
                code: "disconnected_execution_tree",
                message: "Another execution tree exists on the board and is not reachable from the selected root.",
                severity: .warning,
                actorId: actorId
            ))
        }

        switch SwarmCoordinator.buildHierarchy(rootActorId: rootActorId, links: board.links) {
        case .noHierarchy:
            errors.append(actorDelegationIssue(
                code: "root_without_children",
                message: "The selected root agent has no one-way hierarchical task children.",
                severity: .error,
                actorId: rootActorId
            ))
            return actorDelegationPreview(rootActorId: rootActorId, levels: [], errors: errors, warnings: warnings)
        case .cycle:
            errors.append(actorDelegationIssue(
                code: "cycle",
                message: "The reachable delegation tree contains a cycle.",
                severity: .error,
                actorId: rootActorId
            ))
            return actorDelegationPreview(rootActorId: rootActorId, levels: [], errors: errors, warnings: warnings)
        case .hierarchy(let hierarchy):
            let levels = hierarchy.levels.map { level in
                level.compactMap { actorId -> ActorDelegationTreeLevelActor? in
                    guard let node = nodesByID[actorId] else {
                        errors.append(actorDelegationIssue(
                            code: "unknown_execution_node",
                            message: "A delegation tree link references an actor that is not on the board.",
                            severity: .error,
                            actorId: actorId
                        ))
                        return nil
                    }
                    guard validateExecutionAgent(node, into: &errors, code: "agent_missing_link") else {
                        return nil
                    }
                    return ActorDelegationTreeLevelActor(
                        actorId: node.id,
                        displayName: node.displayName,
                        linkedAgentId: node.linkedAgentId!.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .sorted { lhs, rhs in
                    lhs.actorId.localizedCaseInsensitiveCompare(rhs.actorId) == .orderedAscending
                }
            }
            return actorDelegationPreview(rootActorId: rootActorId, levels: levels, errors: errors, warnings: warnings)
        }
    }

    /// Creates one actor node in board.
    public func createActorNode(node: ActorNode) throws -> ActorBoardSnapshot {
        guard let nodeID = normalizedActorEntityID(node.id) else {
            throw ActorBoardError.invalidPayload
        }

        let agents = try listAgents()
        let currentBoard = try actorBoardStore.loadBoard(agents: agents)
        guard !currentBoard.nodes.contains(where: { $0.id == nodeID }) else {
            throw ActorBoardError.invalidPayload
        }

        var nextNode = node
        nextNode.id = nodeID
        nextNode.createdAt = Date()

        return try updateActorBoardSnapshot(
            nodes: currentBoard.nodes + [nextNode],
            links: currentBoard.links,
            teams: currentBoard.teams,
            agents: agents
        )
    }

    /// Updates one actor node in board.
    public func updateActorNode(actorID: String, node: ActorNode) throws -> ActorBoardSnapshot {
        guard let normalizedID = normalizedActorEntityID(actorID) else {
            throw ActorBoardError.invalidPayload
        }

        let agents = try listAgents()
        let currentBoard = try actorBoardStore.loadBoard(agents: agents)
        guard let existingNodeIndex = currentBoard.nodes.firstIndex(where: { $0.id == normalizedID }) else {
            throw ActorBoardError.actorNotFound
        }

        let existingNode = currentBoard.nodes[existingNodeIndex]
        let nextNode: ActorNode
        if isProtectedSystemActorID(normalizedID) {
            var protectedNode = existingNode
            protectedNode.positionX = node.positionX
            protectedNode.positionY = node.positionY
            nextNode = protectedNode
        } else {
            var editableNode = node
            editableNode.id = normalizedID
            editableNode.createdAt = existingNode.createdAt
            nextNode = editableNode
        }

        var nodes = currentBoard.nodes
        nodes[existingNodeIndex] = nextNode
        return try updateActorBoardSnapshot(
            nodes: nodes,
            links: currentBoard.links,
            teams: currentBoard.teams,
            agents: agents
        )
    }

    /// Deletes one actor node in board with related links and team memberships.
    public func deleteActorNode(actorID: String) throws -> ActorBoardSnapshot {
        guard let normalizedID = normalizedActorEntityID(actorID) else {
            throw ActorBoardError.invalidPayload
        }

        if isProtectedSystemActorID(normalizedID) {
            throw ActorBoardError.protectedActor
        }

        let agents = try listAgents()
        let currentBoard = try actorBoardStore.loadBoard(agents: agents)
        guard currentBoard.nodes.contains(where: { $0.id == normalizedID }) else {
            throw ActorBoardError.actorNotFound
        }

        let nodes = currentBoard.nodes.filter { $0.id != normalizedID }
        let links = currentBoard.links.filter {
            $0.sourceActorId != normalizedID && $0.targetActorId != normalizedID
        }
        let teams = currentBoard.teams.map { team in
            ActorTeam(
                id: team.id,
                name: team.name,
                memberActorIds: team.memberActorIds.filter { $0 != normalizedID },
                createdAt: team.createdAt
            )
        }

        return try updateActorBoardSnapshot(nodes: nodes, links: links, teams: teams, agents: agents)
    }

    /// Creates one link between actors.
    public func createActorLink(link: ActorLink) throws -> ActorBoardSnapshot {
        guard let linkID = normalizedActorEntityID(link.id) else {
            throw ActorBoardError.invalidPayload
        }

        let agents = try listAgents()
        let currentBoard = try actorBoardStore.loadBoard(agents: agents)
        guard !currentBoard.links.contains(where: { $0.id == linkID }) else {
            throw ActorBoardError.invalidPayload
        }

        var nextLink = link
        nextLink.id = linkID
        nextLink.createdAt = Date()

        return try updateActorBoardSnapshot(
            nodes: currentBoard.nodes,
            links: currentBoard.links + [nextLink],
            teams: currentBoard.teams,
            agents: agents
        )
    }

    /// Updates one actor link.
    public func updateActorLink(linkID: String, link: ActorLink) throws -> ActorBoardSnapshot {
        guard let normalizedID = normalizedActorEntityID(linkID) else {
            throw ActorBoardError.invalidPayload
        }

        let agents = try listAgents()
        let currentBoard = try actorBoardStore.loadBoard(agents: agents)
        guard let existingLinkIndex = currentBoard.links.firstIndex(where: { $0.id == normalizedID }) else {
            throw ActorBoardError.linkNotFound
        }

        var nextLink = link
        nextLink.id = normalizedID
        nextLink.createdAt = currentBoard.links[existingLinkIndex].createdAt

        var links = currentBoard.links
        links[existingLinkIndex] = nextLink
        return try updateActorBoardSnapshot(
            nodes: currentBoard.nodes,
            links: links,
            teams: currentBoard.teams,
            agents: agents
        )
    }

    /// Deletes one actor link.
    public func deleteActorLink(linkID: String) throws -> ActorBoardSnapshot {
        guard let normalizedID = normalizedActorEntityID(linkID) else {
            throw ActorBoardError.invalidPayload
        }

        let agents = try listAgents()
        let currentBoard = try actorBoardStore.loadBoard(agents: agents)
        guard currentBoard.links.contains(where: { $0.id == normalizedID }) else {
            throw ActorBoardError.linkNotFound
        }

        return try updateActorBoardSnapshot(
            nodes: currentBoard.nodes,
            links: currentBoard.links.filter { $0.id != normalizedID },
            teams: currentBoard.teams,
            agents: agents
        )
    }

    /// Creates one team.
    public func createActorTeam(team: ActorTeam) throws -> ActorBoardSnapshot {
        guard let teamID = normalizedActorEntityID(team.id) else {
            throw ActorBoardError.invalidPayload
        }

        let agents = try listAgents()
        let currentBoard = try actorBoardStore.loadBoard(agents: agents)
        guard !currentBoard.teams.contains(where: { $0.id == teamID }) else {
            throw ActorBoardError.invalidPayload
        }

        var nextTeam = team
        nextTeam.id = teamID
        nextTeam.createdAt = Date()

        return try updateActorBoardSnapshot(
            nodes: currentBoard.nodes,
            links: currentBoard.links,
            teams: currentBoard.teams + [nextTeam],
            agents: agents
        )
    }

    /// Updates one team.
    public func updateActorTeam(teamID: String, team: ActorTeam) throws -> ActorBoardSnapshot {
        guard let normalizedID = normalizedActorEntityID(teamID) else {
            throw ActorBoardError.invalidPayload
        }

        let agents = try listAgents()
        let currentBoard = try actorBoardStore.loadBoard(agents: agents)
        guard let existingTeamIndex = currentBoard.teams.firstIndex(where: { $0.id == normalizedID }) else {
            throw ActorBoardError.teamNotFound
        }

        var nextTeam = team
        nextTeam.id = normalizedID
        nextTeam.createdAt = currentBoard.teams[existingTeamIndex].createdAt

        var teams = currentBoard.teams
        teams[existingTeamIndex] = nextTeam
        return try updateActorBoardSnapshot(
            nodes: currentBoard.nodes,
            links: currentBoard.links,
            teams: teams,
            agents: agents
        )
    }

    /// Deletes one team.
    public func deleteActorTeam(teamID: String) throws -> ActorBoardSnapshot {
        guard let normalizedID = normalizedActorEntityID(teamID) else {
            throw ActorBoardError.invalidPayload
        }

        let agents = try listAgents()
        let currentBoard = try actorBoardStore.loadBoard(agents: agents)
        guard currentBoard.teams.contains(where: { $0.id == normalizedID }) else {
            throw ActorBoardError.teamNotFound
        }

        return try updateActorBoardSnapshot(
            nodes: currentBoard.nodes,
            links: currentBoard.links,
            teams: currentBoard.teams.filter { $0.id != normalizedID },
            agents: agents
        )
    }

    /// Lists agent chat sessions backed by JSONL files.
}

private func actorDelegationPreview(
    rootActorId: String,
    levels: [[ActorDelegationTreeLevelActor]],
    errors: [ActorDelegationTreeIssue],
    warnings: [ActorDelegationTreeIssue]
) -> ActorDelegationTreePreviewResponse {
    ActorDelegationTreePreviewResponse(
        status: errors.isEmpty ? .valid : .invalid,
        rootActorId: rootActorId,
        levels: levels,
        errors: errors,
        warnings: warnings
    )
}

private func actorDelegationIssue(
    code: String,
    message: String,
    severity: ActorDelegationTreeIssueSeverity,
    actorId: String? = nil,
    linkId: String? = nil
) -> ActorDelegationTreeIssue {
    ActorDelegationTreeIssue(
        code: code,
        message: message,
        severity: severity,
        actorId: actorId,
        linkId: linkId
    )
}

@discardableResult
private func validateExecutionAgent(
    _ node: ActorNode,
    into errors: inout [ActorDelegationTreeIssue],
    code: String
) -> Bool {
    guard node.kind == .agent else {
        errors.append(actorDelegationIssue(
            code: code,
            message: "Delegation tree execution nodes must be agents.",
            severity: .error,
            actorId: node.id
        ))
        return false
    }
    guard let linkedAgentId = node.linkedAgentId?.trimmingCharacters(in: .whitespacesAndNewlines), !linkedAgentId.isEmpty else {
        errors.append(actorDelegationIssue(
            code: code,
            message: "Delegation tree agent nodes must link to a configured agent.",
            severity: .error,
            actorId: node.id
        ))
        return false
    }
    return true
}

private func effectiveActorRelationship(for link: ActorLink) -> ActorRelationshipType {
    if let relationship = link.relationship {
        return relationship
    }

    let sourceSocket = link.sourceSocket ?? .right
    let targetSocket = link.targetSocket ?? .left
    if (sourceSocket == .bottom && targetSocket == .top)
        || (sourceSocket == .top && targetSocket == .bottom) {
        return .hierarchical
    }
    return .peer
}

private func normalizedActorEntityIDValue(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/")
    if trimmed.rangeOfCharacter(from: allowed.inverted) != nil {
        return nil
    }

    guard trimmed.count <= 180 else {
        return nil
    }

    return trimmed
}
