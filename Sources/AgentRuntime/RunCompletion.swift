import Foundation
import Protocols

public enum RunCompletionDisposition: String, Codable, Sendable {
    case completed
    case blocked
    case waitingInput = "waiting_input"
}

public enum VerificationEvidenceKind: String, Codable, Sendable {
    case build, test, lint, run, screenshot
}

public struct VerificationEvidence: Codable, Sendable, Equatable {
    public var id: String
    public var kind: VerificationEvidenceKind
    public var tool: String
    public var command: String?
    public var arguments: [String]
    public var cwd: String?
    public var exitCode: Int?
    public var observedAt: Date
    public var workScopeRevision: Int? = nil
    public var sourceCallID: String? = nil

    public init(id: String = "", kind: VerificationEvidenceKind, tool: String, command: String?,
                arguments: [String], cwd: String?, exitCode: Int?, observedAt: Date,
                workScopeRevision: Int? = nil, sourceCallID: String? = nil) {
        self.id = id
        self.kind = kind
        self.tool = tool
        self.command = command
        self.arguments = arguments
        self.cwd = cwd
        self.exitCode = exitCode
        self.observedAt = observedAt
        self.workScopeRevision = workScopeRevision
        self.sourceCallID = sourceCallID
    }

    public var jsonValue: JSONValue {
        var payload: [String: JSONValue] = [
            "id": .string(id), "kind": .string(kind.rawValue), "tool": .string(tool),
            "arguments": .array(arguments.map(JSONValue.string)),
            "observedAt": .string(ISO8601DateFormatter().string(from: observedAt)),
        ]
        if let command { payload["command"] = .string(command) }
        if let cwd { payload["cwd"] = .string(cwd) }
        if let exitCode { payload["exitCode"] = .number(Double(exitCode)) }
        if let workScopeRevision { payload["workScopeRevision"] = .number(Double(workScopeRevision)) }
        if let sourceCallID { payload["sourceCallID"] = .string(sourceCallID) }
        return .object(payload)
    }
}

public struct RunCompletion: Codable, Sendable, Equatable {
    public var disposition: RunCompletionDisposition
    public var summary: String
    public var verification: [String]
    public var verificationEvidence: [VerificationEvidence]
    public var limitations: [String]
    /// A product-validated live input request, retained across journal restoration.
    public var inputRequestId: String?

    public init(disposition: RunCompletionDisposition, summary: String, verification: [String],
                verificationEvidence: [VerificationEvidence], limitations: [String], inputRequestId: String? = nil) {
        self.disposition = disposition
        self.summary = summary
        self.verification = verification
        self.verificationEvidence = verificationEvidence
        self.limitations = limitations
        self.inputRequestId = inputRequestId
    }

    public var jsonValue: JSONValue {
        var payload: [String: JSONValue] = [
            "completed": .bool(disposition == .completed), "status": .string(disposition.rawValue),
            "summary": .string(summary), "verification": .array(verification.map(JSONValue.string)),
            "verificationEvidenceIds": .array(verificationEvidence.map { .string($0.id) }),
            "verificationEvidence": .array(verificationEvidence.map(\.jsonValue)),
            "limitations": .array(limitations.map(JSONValue.string)),
        ]
        if let inputRequestId { payload["inputRequestId"] = .string(inputRequestId) }
        return .object(payload)
    }
}
