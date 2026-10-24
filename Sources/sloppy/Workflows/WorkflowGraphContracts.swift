import Foundation
import Protocols

enum WorkflowGraphContracts {
    struct Violation: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    static func value(at path: String, in input: [String: JSONValue]) -> JSONValue? {
        let parts = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !parts.contains(""), let first = parts.first, var value = input[first] else { return nil }
        for part in parts.dropFirst() {
            if let object = value.asObject, let next = object[part] { value = next }
            else if case .array(let array) = value, let index = Int(part), array.indices.contains(index) { value = array[index] }
            else { return nil }
        }
        return value
    }

    static func references(in value: JSONValue) throws -> [String] {
        switch value {
        case .object(let object): return try object.keys.sorted().flatMap { try references(in: object[$0] ?? .null) }
        case .array(let values): return try values.flatMap { try references(in: $0) }
        case .string(let raw):
            var result: [String] = []
            var cursor = raw.startIndex
            while let start = raw[cursor...].range(of: "{{") {
                guard let end = raw[start.upperBound...].range(of: "}}") else { throw Violation("Unclosed workflow reference.") }
                let path = raw[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty, !path.split(separator: ".", omittingEmptySubsequences: false).contains("") else {
                    throw Violation("Invalid workflow reference: \(path).")
                }
                result.append(path)
                cursor = end.upperBound
            }
            return result
        default: return []
        }
    }

    static func validate(_ definition: WorkflowDefinition) -> [WorkflowValidationIssue] {
        var issues: [WorkflowValidationIssue] = []
        func issue(_ message: String, node: String) { issues.append(.init(severity: "error", message: message, nodeId: node)) }
        let nodeIDs = Set(definition.nodes.map(\.id))
        if Set(definition.edges.map(\.id)).count != definition.edges.count { issue("Duplicate transition identifiers.", node: "") }
        for node in definition.nodes {
            if let message = WorkflowSessionPolicy.validationIssue(node: node, definition: definition) { issue(message, node: node.id) }
            do { try WorkflowOutputContract.validateDefinition(node.config["outputSchema"]) }
            catch { issue(String(describing: error), node: node.id) }
            if let format = node.config["outputFormat"], format != .null,
               node.type != .agentStep || ![JSONValue.string("text"), .string("json")].contains(format) {
                issue("outputFormat must be text or json on an agent step.", node: node.id)
            }
            let edges = definition.edges.filter { $0.sourceNodeId == node.id }
            if node.type == .end && !edges.isEmpty { issue("End nodes cannot have outgoing transitions.", node: node.id) }
            if edges.filter({ $0.conditionKey == nil && $0.condition == nil }).count > 1 {
                issue("A node can have only one default transition; parallel execution is not supported.", node: node.id)
            }
            var legacyKeys: Set<String> = []
            for edge in edges {
                if let key = edge.conditionKey {
                    if key.trimmingCharacters(in: .whitespacesAndNewlines) != key || key.isEmpty { issue("Transition keys must be nonempty and trimmed.", node: node.id) }
                    if !legacyKeys.insert(key).inserted { issue("Duplicate transition condition: \(key).", node: node.id) }
                }
                if let condition = edge.condition {
                    if edge.conditionKey != nil { issue("Use either condition or conditionKey on a transition.", node: node.id) }
                    if condition.path.isEmpty || condition.path.trimmingCharacters(in: .whitespacesAndNewlines) != condition.path || condition.path.split(separator: ".", omittingEmptySubsequences: false).contains("") {
                        issue("Transition condition requires a valid output path.", node: node.id)
                    }
                }
            }
            do {
                for path in try references(in: .object(node.config.filter { $0.key != "outputSchema" })) where path.hasPrefix("nodes.") {
                    let parts = path.split(separator: ".").map(String.init)
                    if parts.count < 3 || !nodeIDs.contains(parts[1]) || parts[2] != "output" {
                        issue("Unknown node output reference: \(path).", node: node.id)
                    }
                }
            } catch { issue(String(describing: error), node: node.id) }
        }
        return issues
    }

    static func validateReferences(node: WorkflowNode, input: [String: JSONValue]) throws {
        for path in try references(in: .object(node.config.filter { $0.key != "outputSchema" })) {
            guard value(at: path, in: input) != nil else { throw Violation("Missing workflow reference: \(path).") }
        }
    }

    static func next(after nodeID: String, output: [String: JSONValue], definition: WorkflowDefinition) throws -> String {
        let edges = definition.edges.filter { $0.sourceNodeId == nodeID }
        let matches = try edges.filter { edge in
            if let condition = edge.condition {
                guard let actual = value(at: condition.path, in: output) else { throw Violation("Missing transition output: \(condition.path).") }
                return actual == condition.equals
            }
            guard let key = edge.conditionKey else { return false }
            if output[key] == .bool(true) { return true }
            return ["conditionKey", "decision", "status", "result"].contains { output[$0]?.asString == key }
        }
        guard matches.count <= 1 else { throw Violation("Ambiguous transition after node \(nodeID).") }
        if let match = matches.first { return match.targetNodeId }
        let defaults = edges.filter { $0.conditionKey == nil && $0.condition == nil }
        guard defaults.count <= 1 else { throw Violation("Ambiguous default transition after node \(nodeID).") }
        guard let next = defaults.first else { throw Violation("No matching transition after node \(nodeID).") }
        return next.targetNodeId
    }
}
