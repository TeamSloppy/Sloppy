import Foundation
import Protocols

/// A bounded deterministic expression language. It never executes model text as code.
enum WorkflowExpression {
    indirect enum Value {
        case literal(JSONValue), path(String), exists(String), unary(String, Value), binary(String, Value, Value)
        func evaluate(_ input: [String: JSONValue]) throws -> JSONValue {
            func invalid(_ message: String) -> WorkflowGraphContracts.Violation { .init("Expression: \(message)") }
            switch self {
            case .literal(let value): return value
            case .path(let path):
                guard let value = WorkflowGraphContracts.value(at: path, in: input) else { throw invalid("missing field \(path)") }
                return value
            case .exists(let path): return .bool(WorkflowGraphContracts.value(at: path, in: input) != nil)
            case .unary(let op, let rhs):
                let value = try rhs.evaluate(input)
                if op == "!", case .bool(let flag) = value { return .bool(!flag) }
                if op == "-", case .number(let number) = value { return .number(-number) }
                throw invalid("invalid unary operand")
            case .binary(let op, let lhs, let rhs):
                let left = try lhs.evaluate(input)
                if op == "&&", left == .bool(false) { return .bool(false) }
                if op == "||", left == .bool(true) { return .bool(true) }
                let right = try rhs.evaluate(input)
                switch op {
                case "==", "===": return .bool(left == right)
                case "!=", "!==": return .bool(left != right)
                case "&&", "||":
                    guard case .bool(let a) = left, case .bool(let b) = right else { throw invalid("logical operands must be boolean") }
                    return .bool(op == "&&" ? a && b : a || b)
                case "+", "-", "*", "/":
                    guard case .number(let a) = left, case .number(let b) = right, op != "/" || b != 0 else { throw invalid("invalid arithmetic operands") }
                    let value = op == "+" ? a + b : op == "-" ? a - b : op == "*" ? a * b : a / b
                    guard value.isFinite else { throw invalid("non-finite arithmetic result") }
                    return .number(value)
                default:
                    let order: ComparisonResult
                    if case .number(let a) = left, case .number(let b) = right { order = a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame }
                    else if case .string(let a) = left, case .string(let b) = right { order = a.compare(b, options: .literal) }
                    else { throw invalid("comparison operands must have the same numeric or string type") }
                    return .bool(op == "<" ? order == .orderedAscending : op == ">" ? order == .orderedDescending : op == "<=" ? order != .orderedDescending : order != .orderedAscending)
                }
            }
        }
    }

    enum Token: Equatable { case value(JSONValue), name(String), op(String) }
    struct Parser {
        var tokens: [Token]
        var position = 0
        mutating func expression(_ minimum: Int = 0, depth: Int = 0) throws -> Value {
            guard depth < 32, position < tokens.count else { throw error("missing operand or excessive nesting") }
            let token = tokens[position]; position += 1
            var lhs: Value
            switch token {
            case .value(let value): lhs = .literal(value)
            case .name("exists"):
                try consume(.op("("))
                guard position < tokens.count, case .name(let path) = tokens[position] else { throw error("exists requires a field path") }
                position += 1; try consume(.op(")")); lhs = .exists(path)
            case .name(let path): lhs = .path(path)
            case .op("("): lhs = try expression(depth: depth + 1); try consume(.op(")"))
            case .op(let op) where op == "!" || op == "-": lhs = .unary(op, try expression(7, depth: depth + 1))
            default: throw error("unexpected operand")
            }
            let precedence = ["||": 1, "&&": 2, "==": 3, "===": 3, "!=": 3, "!==": 3, "<": 4, ">": 4, "<=": 4, ">=": 4, "+": 5, "-": 5, "*": 6, "/": 6]
            while position < tokens.count, case .op(let op) = tokens[position], let priority = precedence[op], priority >= minimum {
                position += 1
                lhs = .binary(op, lhs, try expression(priority + 1, depth: depth + 1))
            }
            return lhs
        }
        mutating func consume(_ token: Token) throws {
            guard position < tokens.count, tokens[position] == token else { throw error("unexpected token") }
            position += 1
        }
        func error(_ message: String) -> WorkflowGraphContracts.Violation { .init("Expression: \(message) at token \(position).") }
    }

    static func parse(_ source: String) throws -> Value {
        guard !source.isEmpty, source.utf8.count <= 8_192 else { throw WorkflowGraphContracts.Violation("Expression must contain 1–8192 bytes.") }
        let chars = Array(source)
        var tokens: [Token] = []
        var index = 0
        func invalid() -> WorkflowGraphContracts.Violation { .init("Invalid expression near character \(index).") }
        while index < chars.count {
            let character = chars[index]
            if character.isWhitespace { index += 1; continue }
            if character == "\"" || character == "'" {
                let quote = character
                var text = ""
                index += 1
                while index < chars.count && chars[index] != quote {
                    if chars[index] == "\\" {
                        index += 1
                        guard index < chars.count else { throw invalid() }
                        let escapes: [Character: String] = ["n": "\n", "r": "\r", "t": "\t", "\\": "\\", "\"": "\"", "'": "'"]
                        guard let value = escapes[chars[index]] else { throw invalid() }; text += value
                    } else { text.append(chars[index]) }
                    index += 1
                }
                guard index < chars.count else { throw invalid() }
                index += 1; tokens.append(.value(.string(text)))
            } else if "()!<>=&|+-*/".contains(character) {
                let rest = String(chars[index...])
                guard let op = ["===", "!==", "&&", "||", "==", "!=", "<=", ">=", "(", ")", "!", "<", ">", "+", "-", "*", "/"].first(where: { rest.hasPrefix($0) }) else { throw invalid() }
                tokens.append(.op(op)); index += op.count
            } else {
                let start = index
                while index < chars.count && !chars[index].isWhitespace && !"()!<>=&|+*/".contains(chars[index]) {
                    // Minus belongs in node IDs, but separates numeric arithmetic operands.
                    if chars[index] == "-" && index > start && chars[start].isNumber { break }
                    index += 1
                }
                guard index > start else { throw invalid() }
                let word = String(chars[start..<index])
                if word == "true" || word == "false" { tokens.append(.value(.bool(word == "true"))) }
                else if word == "null" { tokens.append(.value(.null)) }
                else if let number = Double(word), number.isFinite { tokens.append(.value(.number(number))) }
                else {
                    guard word.first?.isLetter == true || word.first == "_", word.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else { throw invalid() }
                    tokens.append(.name(word))
                }
            }
            guard tokens.count <= 512 else { throw invalid() }
        }
        var parser = Parser(tokens: tokens)
        let value = try parser.expression()
        guard parser.position == tokens.count else { throw parser.error("trailing tokens") }
        return value
    }

    static func run(node: WorkflowNode, input: [String: JSONValue], iteration: Int) throws -> [String: JSONValue] {
        guard let source = node.config["expression"]?.asString else { throw WorkflowGraphContracts.Violation("Expression is required.") }
        let result = try parse(source).evaluate(input.merging(["iteration": .number(Double(iteration))]) { _, new in new })
        guard case .bool(let flag) = result else { throw WorkflowGraphContracts.Violation("Expression must return a boolean.") }
        if WorkflowGraphContracts.blockKind(node) == "loop" && flag {
            let limit = node.config["maxIterations"]?.asNumber ?? node.config["maxIterations"]?.asString.flatMap(Double.init) ?? 10
            guard (1...24).contains(limit), limit.rounded() == limit, Double(iteration) <= limit else {
                throw WorkflowGraphContracts.Violation("Loop exceeded maxIterations (1–24, default 10).")
            }
        }
        return ["result": .bool(flag), "true": .bool(flag), "false": .bool(!flag), "iteration": .number(Double(iteration))]
    }
}
