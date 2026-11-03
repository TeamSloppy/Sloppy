import Foundation

public enum ToolApprovalArgumentValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([ToolApprovalArgumentValue])
    case object([String: ToolApprovalArgumentValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([Self].self) { self = .array(value) }
        else { self = .object(try container.decode([String: Self].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

public struct ClientToolApprovalGrant: Codable, Sendable, Equatable {
    public var kind: String
    public var tool: String
    public var operation: String?
    public var resource: String?

    public init(kind: String, tool: String, operation: String? = nil, resource: String? = nil) {
        self.kind = kind
        self.tool = tool
        self.operation = operation
        self.resource = resource
    }
}

/// A display of the submitted payload, without interpreting the command's intent.
public struct ToolApprovalPresentation: Sendable, Equatable {
    public let commandLine: String?
    public let parametersJSON: String?
    public let workingDirectory: String?
    public let accessDetails: [String]
    public let scopeDetail: String

    public var title: String { commandLine == nil ? "Parameters" : "Command" }
    public var content: String {
        commandLine ?? parametersJSON ?? "Arguments are not available for this request."
    }

    public init(approval: PendingToolApprovalRecord) {
        let arguments = approval.arguments
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        parametersJSON = arguments.flatMap { try? encoder.encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        if approval.tool == "runtime.exec",
           let command = arguments?["command"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !command.isEmpty {
            // Match runtime.exec's argv contract. Malformed input stays visible
            // as JSON rather than displaying a partial invocation as complete.
            let argv: [String]?
            if let value = arguments?["arguments"] {
                if case .array(let values) = value, values.allSatisfy({ $0.stringValue != nil }) {
                    argv = values.compactMap(\.stringValue)
                } else {
                    argv = nil
                }
            } else {
                argv = []
            }
            commandLine = argv.map { ([command] + $0).map(Self.quote).joined(separator: " ") }
            let cwd = arguments?["cwd"]?.stringValue
            workingDirectory = cwd?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? cwd : "Session default"
        } else {
            commandLine = nil
            workingDirectory = nil
        }
        let grants = approval.grants ?? []
        accessDetails = grants.compactMap { grant in
            if grant.kind == "tool" { return "Tool access: \(grant.tool)" }
            guard let resource = grant.resource else { return nil }
            return "\(grant.operation ?? "access"): \(resource)"
        }
        if grants.isEmpty || grants.contains(where: { $0.kind == "tool" }) {
            let tools = Set(grants.filter { $0.kind == "tool" }.map(\.tool)).sorted()
            let target = tools.isEmpty ? approval.tool ?? "this tool" : tools.joined(separator: ", ")
            scopeDetail = "Session and Always also cover other calls to \(target)."
        } else {
            scopeDetail = "Session and Always remember the access shown above."
        }
    }

    private static func quote(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if !value.isEmpty && value.unicodeScalars.allSatisfy({ safe.contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
