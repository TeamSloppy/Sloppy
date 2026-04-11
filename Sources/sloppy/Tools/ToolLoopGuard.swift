import Foundation
import Protocols

actor ToolLoopGuard {
    enum Decision: Equatable {
        case allow(signature: String)
        case block(message: String)
    }

    private struct InvocationRecord: Sendable {
        let timestamp: Date
        let signature: String
        let nonRetryableFailure: Bool
        let enforcesRepeatedCallLimits: Bool
    }

    private struct SignatureDescriptor {
        let signature: String
        let enforcesRepeatedCallLimits: Bool
    }

    private var recordsBySession: [String: [InvocationRecord]] = [:]

    func evaluate(
        sessionID: String,
        request: ToolInvocationRequest,
        policy: AgentToolsPolicy,
        workspaceRootURL: URL
    ) -> Decision {
        let now = Date()
        cleanupExpiredRepeatedCallWindow(
            sessionID: sessionID,
            now: now,
            windowSeconds: policy.guardrails.toolLoopWindowSeconds
        )

        guard let descriptor = signatureDescriptor(
            for: request,
            policy: policy,
            workspaceRootURL: workspaceRootURL
        ) else {
            return .allow(signature: "")
        }

        let records = recordsBySession[sessionID] ?? []
        let signature = descriptor.signature

        let repeatedNonRetryableFailures = records.reduce(into: 0) { count, record in
            guard record.signature == signature, record.nonRetryableFailure else {
                return
            }
            count += 1
        }
        if repeatedNonRetryableFailures >= max(1, policy.guardrails.maxRepeatedNonRetryableFailures) - 1 {
            return .block(message: "Loop blocked: repeated non-retryable tool failure.")
        }

        guard descriptor.enforcesRepeatedCallLimits else {
            return .allow(signature: signature)
        }

        let consecutiveCount = trailingIdenticalCount(signature: signature, records: records)
        if consecutiveCount >= max(1, policy.guardrails.maxConsecutiveIdenticalToolCalls) - 1 {
            return .block(message: "Loop blocked: repeated identical tool call.")
        }

        let windowStart = now.addingTimeInterval(-TimeInterval(max(1, policy.guardrails.toolLoopWindowSeconds)))
        let repeatedWindowCount = records.reduce(into: 0) { count, record in
            guard record.signature == signature, record.enforcesRepeatedCallLimits, record.timestamp >= windowStart else {
                return
            }
            count += 1
        }
        if repeatedWindowCount >= max(1, policy.guardrails.maxIdenticalToolCallsPerWindow) - 1 {
            return .block(message: "Loop blocked: too many identical tool calls in a short window.")
        }

        return .allow(signature: signature)
    }

    func recordResult(
        sessionID: String,
        request: ToolInvocationRequest,
        result: ToolInvocationResult,
        policy: AgentToolsPolicy,
        workspaceRootURL: URL
    ) {
        guard let descriptor = signatureDescriptor(
            for: request,
            policy: policy,
            workspaceRootURL: workspaceRootURL
        ) else {
            return
        }

        cleanupExpiredRepeatedCallWindow(
            sessionID: sessionID,
            now: Date(),
            windowSeconds: policy.guardrails.toolLoopWindowSeconds
        )

        let record = InvocationRecord(
            timestamp: Date(),
            signature: descriptor.signature,
            nonRetryableFailure: result.ok == false && result.error?.retryable == false,
            enforcesRepeatedCallLimits: descriptor.enforcesRepeatedCallLimits
        )
        recordsBySession[sessionID, default: []].append(record)
    }

    func cleanup(sessionID: String) {
        recordsBySession.removeValue(forKey: sessionID)
    }

    private func cleanupExpiredRepeatedCallWindow(sessionID: String, now: Date, windowSeconds: Int) {
        guard var records = recordsBySession[sessionID] else {
            return
        }

        let windowStart = now.addingTimeInterval(-TimeInterval(max(1, windowSeconds)))
        records.removeAll { record in
            record.timestamp < windowStart && !record.nonRetryableFailure
        }

        if records.isEmpty {
            recordsBySession.removeValue(forKey: sessionID)
        } else {
            recordsBySession[sessionID] = records
        }
    }

    private func trailingIdenticalCount(signature: String, records: [InvocationRecord]) -> Int {
        var count = 0
        for record in records.reversed() {
            guard record.signature == signature, record.enforcesRepeatedCallLimits else {
                break
            }
            count += 1
        }
        return count
    }

    private func signatureDescriptor(
        for request: ToolInvocationRequest,
        policy: AgentToolsPolicy,
        workspaceRootURL: URL
    ) -> SignatureDescriptor? {
        let trimmedTool = request.tool.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTool.isEmpty else {
            return nil
        }

        switch trimmedTool {
        case "runtime.exec":
            return SignatureDescriptor(
                signature: stableSignature(
                    tool: trimmedTool,
                    payload: execPayload(arguments: request.arguments, policy: policy, workspaceRootURL: workspaceRootURL)
                ),
                enforcesRepeatedCallLimits: true
            )

        case "runtime.process":
            let action = request.arguments["action"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "list"
            switch action {
            case "start":
                return SignatureDescriptor(
                    signature: stableSignature(
                        tool: trimmedTool,
                        payload: processStartPayload(arguments: request.arguments, policy: policy, workspaceRootURL: workspaceRootURL)
                    ),
                    enforcesRepeatedCallLimits: true
                )
            case "status", "list":
                return SignatureDescriptor(
                    signature: stableSignature(tool: trimmedTool, payload: .object(["action": .string(action)])),
                    enforcesRepeatedCallLimits: false
                )
            default:
                return SignatureDescriptor(
                    signature: stableSignature(tool: trimmedTool, payload: .object(request.arguments)),
                    enforcesRepeatedCallLimits: false
                )
            }

        default:
            return SignatureDescriptor(
                signature: stableSignature(tool: trimmedTool, payload: .object(request.arguments)),
                enforcesRepeatedCallLimits: false
            )
        }
    }

    private func stableSignature(tool: String, payload: JSONValue) -> String {
        let signatureValue = JSONValue.object([
            "payload": payload,
            "tool": .string(tool)
        ])
        return stableJSONString(signatureValue) ?? "\(tool)|\(String(describing: payload))"
    }

    private func execPayload(arguments: [String: JSONValue], policy: AgentToolsPolicy, workspaceRootURL: URL) -> JSONValue {
        .object([
            "arguments": .array(arguments["arguments"]?.asArray ?? []),
            "command": .string(arguments["command"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
            "cwd": normalizedExecCwd(
                rawValue: arguments["cwd"]?.asString,
                policy: policy,
                workspaceRootURL: workspaceRootURL,
                defaultPath: workspaceRootURL.standardizedFileURL.path
            )
        ])
    }

    private func processStartPayload(arguments: [String: JSONValue], policy: AgentToolsPolicy, workspaceRootURL: URL) -> JSONValue {
        .object([
            "action": .string("start"),
            "arguments": .array(arguments["arguments"]?.asArray ?? []),
            "command": .string(arguments["command"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
            "cwd": normalizedExecCwd(
                rawValue: arguments["cwd"]?.asString,
                policy: policy,
                workspaceRootURL: workspaceRootURL,
                defaultPath: workspaceRootURL.standardizedFileURL.path
            )
        ])
    }

    private func normalizedExecCwd(
        rawValue: String?,
        policy: AgentToolsPolicy,
        workspaceRootURL: URL,
        defaultPath: String
    ) -> JSONValue {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return .string(defaultPath)
        }
        if let resolved = resolveToolPath(trimmed, workspaceRootURL: workspaceRootURL, extraRoots: policy.guardrails.allowedExecRoots) {
            return .string(resolved.path)
        }
        return .string(trimmed)
    }
}
