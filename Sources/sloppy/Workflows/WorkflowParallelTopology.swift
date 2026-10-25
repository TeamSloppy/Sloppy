import Foundation
import Protocols

struct WorkflowParallelTopology: Sendable {
    let joinID: String
    let branches: [String: Set<String>]

    init(definition: WorkflowDefinition, fork: WorkflowNode) throws {
        func invalid(_ text: String) -> WorkflowGraphContracts.Violation { .init("Parallel \(fork.id): \(text)") }
        guard let join = fork.config["joinNodeId"]?.asString,
              definition.nodes.contains(where: { $0.id == join && $0.type == .join }) else { throw invalid("joinNodeId must reference a Join node.") }
        let edges = definition.edges.filter { $0.sourceNodeId == fork.id }
        guard (2...16).contains(edges.count), edges.allSatisfy({ $0.condition == nil && $0.conditionKey == nil }),
              Set(edges.map(\.targetNodeId)).count == edges.count else { throw invalid("requires 2...16 distinct unconditional branches.") }
        let nodes = Dictionary(definition.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var regions: [String: Set<String>] = [:]
        var occupied: Set<String> = []
        for edge in edges {
            var region: Set<String> = []
            var pending = [edge.targetNodeId]
            while let id = pending.popLast() {
                if id == join { continue }
                guard id != fork.id, let node = nodes[id], ![WorkflowNodeType.trigger, .end, .parallel, .join].contains(node.type) else {
                    throw invalid("branches must stay inside their group; nested parallel groups are not supported.")
                }
                guard region.insert(id).inserted else { continue }
                let outgoing = definition.edges.filter { $0.sourceNodeId == id }
                guard !outgoing.isEmpty else { throw invalid("branch \(id) has no route to Join.") }
                pending += outgoing.map(\.targetNodeId)
            }
            guard !region.isEmpty, occupied.isDisjoint(with: region) else { throw invalid("branches may overlap only at Join.") }
            for incoming in definition.edges where region.contains(incoming.targetNodeId) {
                guard region.contains(incoming.sourceNodeId) || incoming.sourceNodeId == fork.id else { throw invalid("a branch has an external incoming edge.") }
            }
            var reachable: Set<String> = [join]
            var changed = true
            while changed {
                let before = reachable.count
                for candidate in definition.edges where region.contains(candidate.sourceNodeId) && reachable.contains(candidate.targetNodeId) { reachable.insert(candidate.sourceNodeId) }
                changed = before != reachable.count
            }
            guard region.isSubset(of: reachable) else { throw invalid("every branch node must have a route to Join.") }
            occupied.formUnion(region)
            regions[edge.targetNodeId] = region
        }
        guard definition.edges.filter({ $0.targetNodeId == join }).allSatisfy({ occupied.contains($0.sourceNodeId) }) else { throw invalid("Join has an incoming edge outside this group.") }
        // Concurrent branches must not mutate the same shared native conversation.
        let shared = definition.nodes.filter { occupied.contains($0.id) && $0.config["sessionMode"] == .string("shared") }
        for node in shared {
            let source = node.config["sessionSourceNodeId"]?.asString ?? ""
            guard regions.values.contains(where: { $0.contains(node.id) && $0.contains(source) }) else { throw invalid("shared sessions must originate in the same branch.") }
        }
        joinID = join
        branches = regions
    }
}
