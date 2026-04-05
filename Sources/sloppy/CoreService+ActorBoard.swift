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
