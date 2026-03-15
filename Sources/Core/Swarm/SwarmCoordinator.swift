import Foundation
import Logging
import Protocols

struct SwarmHierarchy: Sendable, Equatable {
    var rootActorId: String
    var levels: [[String]]
    var parentByActor: [String: String]
}

enum SwarmHierarchyBuildResult: Sendable, Equatable {
    case noHierarchy
    case cycle
    case hierarchy(SwarmHierarchy)
}

struct SwarmCoordinator {
    static func buildHierarchy(
        rootActorId: String,
        links: [ActorLink],
        logger: Logger? = nil
    ) -> SwarmHierarchyBuildResult {
        var adjacency: [String: Set<String>] = [:]

        for link in links {
            guard link.communicationType == .task else {
                continue
            }

            let relationship = link.effectiveRelationship
            guard relationship == .hierarchical else {
                continue
            }

            guard link.direction == .oneWay else {
                logger?.warning(
                    "Ignoring ambiguous hierarchical two-way task link for swarm hierarchy",
                    metadata: [
                        "link_id": .string(link.id),
                        "source_actor_id": .string(link.sourceActorId),
                        "target_actor_id": .string(link.targetActorId)
                    ]
                )
                continue
            }

            adjacency[link.sourceActorId, default: []].insert(link.targetActorId)
        }

        guard let children = adjacency[rootActorId], !children.isEmpty else {
            return .noHierarchy
        }

        let reachable = collectReachable(from: rootActorId, adjacency: adjacency)
        if hasCycle(root: rootActorId, adjacency: adjacency, allowed: reachable) {
            return .cycle
        }

        let hierarchy = buildLevels(rootActorId: rootActorId, adjacency: adjacency, allowed: reachable)
        return .hierarchy(hierarchy)
    }

    private static func collectReachable(
        from root: String,
        adjacency: [String: Set<String>]
    ) -> Set<String> {
        var queue: [String] = [root]
        var visited: Set<String> = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for child in adjacency[current] ?? [] where visited.insert(child).inserted {
                queue.append(child)
            }
        }
        return visited
    }

    private static func hasCycle(
        root: String,
        adjacency: [String: Set<String>],
        allowed: Set<String>
    ) -> Bool {
        enum State {
            case visiting
            case done
        }
        var states: [String: State] = [:]

        func visit(_ actor: String) -> Bool {
            if states[actor] == .visiting {
                return true
            }
            if states[actor] == .done {
                return false
            }
            states[actor] = .visiting
            for next in adjacency[actor] ?? [] where allowed.contains(next) {
                if visit(next) {
                    return true
                }
            }
            states[actor] = .done
            return false
        }

        return visit(root)
    }

    private static func buildLevels(
        rootActorId: String,
        adjacency: [String: Set<String>],
        allowed: Set<String>
    ) -> SwarmHierarchy {
        var queue: [(actorId: String, depth: Int)] = [(rootActorId, 0)]
        var visited: Set<String> = [rootActorId]
        var levelsByDepth: [Int: [String]] = [:]
        var parentByActor: [String: String] = [:]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            for child in (adjacency[current.actorId] ?? []).sorted() where allowed.contains(child) {
                if !visited.insert(child).inserted {
                    continue
                }
                let depth = current.depth + 1
                levelsByDepth[depth, default: []].append(child)
                parentByActor[child] = current.actorId
                queue.append((child, depth))
            }
        }

        let maxDepth = levelsByDepth.keys.max() ?? 0
        let levels = (1...maxDepth).map { depth in
            (levelsByDepth[depth] ?? []).sorted()
        }.filter { !$0.isEmpty }

        return SwarmHierarchy(
            rootActorId: rootActorId,
            levels: levels,
            parentByActor: parentByActor
        )
    }
}

private extension ActorLink {
    var effectiveRelationship: ActorRelationshipType {
        if let relationship {
            return relationship
        }

        let sourceSocket = sourceSocket ?? .right
        let targetSocket = targetSocket ?? .left
        if (sourceSocket == .bottom && targetSocket == .top)
            || (sourceSocket == .top && targetSocket == .bottom) {
            return .hierarchical
        }
        return .peer
    }
}
