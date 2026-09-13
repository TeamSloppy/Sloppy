import Foundation
import Protocols

actor ToolLoopGuard {
    enum Decision: Equatable {
        case allow(signature: String)
        case block(message: String)
    }

    private struct InvocationRecord: Sendable {
        let timestamp: Date
        let tool: String
        let signature: String
        let nonRetryableFailure: Bool
        let timeoutFailure: Bool
        let enforcesRepeatedCallLimits: Bool
        let errorCode: String?
        let argumentRecovery: ToolArgumentRecovery?
        let recoveryValues: [String: JSONValue]
    }

    private struct SignatureDescriptor {
        let signature: String
        let enforcesRepeatedCallLimits: Bool
    }

    private var recordsBySession: [String: [InvocationRecord]] = [:]
    private var pendingBySession: [String: [String: Int]] = [:]

    func evaluate(
        sessionID: String,
        request: ToolInvocationRequest,
        policy: AgentToolsPolicy,
        workspaceRootURL: URL,
        currentDirectoryURL: URL? = nil
    ) -> Decision {
        let now = Date()
        cleanupExpiredRepeatedCallWindow(
            sessionID: sessionID,
            now: now,
            windowSeconds: policy.guardrails.toolLoopWindowSeconds
        )

        let trimmedTool = request.tool.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let descriptor = signatureDescriptor(
            for: request,
            policy: policy,
            workspaceRootURL: workspaceRootURL,
            currentDirectoryURL: currentDirectoryURL
        ) else {
            return .allow(signature: "")
        }

        let records = recordsBySession[sessionID] ?? []
        let signature = descriptor.signature

        // Match the failing fields, not incidental text such as a memory note.
        for record in records where record.tool == trimmedTool && record.nonRetryableFailure {
            guard let recovery = record.argumentRecovery, !recovery.invalidFields.isEmpty,
                  matches(fields: recovery.contextFields, request: request, values: record.recoveryValues) else { continue }
            if matches(fields: recovery.invalidFields, request: request, values: record.recoveryValues) {
                return .block(message: "The failing arguments (\(recovery.invalidFields.joined(separator: ", "))) have not changed. The operation was stopped; correct these fields before continuing.")
            }
            let familyFailures = records.filter {
                $0.tool == trimmedTool && $0.nonRetryableFailure && $0.errorCode == record.errorCode &&
                $0.argumentRecovery == recovery &&
                matches(fields: recovery.contextFields, request: request, values: $0.recoveryValues)
            }.count
            if familyFailures >= 2 {
                return .block(message: "Argument correction failed for \(recovery.invalidFields.joined(separator: ", ")). The operation was stopped after one correction attempt.")
            }
        }

        if (pendingBySession[sessionID]?[signature] ?? 0) > 0 {
            return .block(message: "Loop blocked: a matching tool call is already running.")
        }

        let recentRuntimeExecTimeouts = records.reduce(into: 0) { count, record in
            guard trimmedTool == "runtime.exec",
                  record.tool == trimmedTool,
                  record.timeoutFailure
            else {
                return
            }
            count += 1
        }
        if recentRuntimeExecTimeouts >= max(1, policy.guardrails.maxRepeatedNonRetryableFailures) {
            return .block(message: "Loop blocked: repeated runtime.exec timeouts. Summarize the blocker instead of retrying diagnostic commands.")
        }

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

    func recordStarted(
        sessionID: String,
        request: ToolInvocationRequest,
        policy: AgentToolsPolicy,
        workspaceRootURL: URL,
        currentDirectoryURL: URL? = nil
    ) {
        guard let descriptor = signatureDescriptor(
            for: request,
            policy: policy,
            workspaceRootURL: workspaceRootURL,
            currentDirectoryURL: currentDirectoryURL
        ) else {
            return
        }
        pendingBySession[sessionID, default: [:]][descriptor.signature, default: 0] += 1
    }

    @discardableResult
    func recordResult(
        sessionID: String,
        request: ToolInvocationRequest,
        result: ToolInvocationResult,
        policy: AgentToolsPolicy,
        workspaceRootURL: URL,
        currentDirectoryURL: URL? = nil
    ) -> Bool {
        guard let descriptor = signatureDescriptor(
            for: request,
            policy: policy,
            workspaceRootURL: workspaceRootURL,
            currentDirectoryURL: currentDirectoryURL
        ) else {
            return false
        }

        cleanupExpiredRepeatedCallWindow(
            sessionID: sessionID,
            now: Date(),
            windowSeconds: policy.guardrails.toolLoopWindowSeconds
        )

        if var pending = pendingBySession[sessionID] {
            let remaining = (pending[descriptor.signature] ?? 0) - 1
            if remaining > 0 {
                pending[descriptor.signature] = remaining
            } else {
                pending.removeValue(forKey: descriptor.signature)
            }
            if pending.isEmpty {
                pendingBySession.removeValue(forKey: sessionID)
            } else {
                pendingBySession[sessionID] = pending
            }
        }

        let trimmedTool = request.tool.trimmingCharacters(in: .whitespacesAndNewlines)
        let recovery = result.error?.argumentRecovery
        let recoveryFields = Set((recovery?.invalidFields ?? []) + (recovery?.contextFields ?? []))
        let record = InvocationRecord(
            timestamp: Date(),
            tool: trimmedTool,
            signature: descriptor.signature,
            nonRetryableFailure: result.ok == false && result.error?.retryable == false,
            timeoutFailure: result.error?.code == "tool_timeout" || result.data?.asObject?["timedOut"]?.asBool == true,
            enforcesRepeatedCallLimits: descriptor.enforcesRepeatedCallLimits,
            errorCode: result.error?.code,
            argumentRecovery: recovery,
            recoveryValues: Dictionary(uniqueKeysWithValues: recoveryFields.map { ($0, request.arguments[$0] ?? .null) })
        )
        recordsBySession[sessionID, default: []].append(record)
        guard record.nonRetryableFailure, let recovery, !recovery.invalidFields.isEmpty else { return false }
        return (recordsBySession[sessionID] ?? []).filter {
            $0.tool == trimmedTool && $0.nonRetryableFailure && $0.errorCode == record.errorCode &&
            $0.argumentRecovery == recovery &&
            matches(fields: recovery.contextFields, request: request, values: $0.recoveryValues)
        }.count >= 2
    }

    func cleanup(sessionID: String) {
        recordsBySession.removeValue(forKey: sessionID)
        pendingBySession.removeValue(forKey: sessionID)
    }

    /// A new user turn can retry a corrected operation; automatic model rounds cannot reset this budget.
    func beginTurn(sessionID: String) {
        recordsBySession[sessionID]?.removeAll { $0.argumentRecovery != nil }
    }

    private func matches(fields: [String], request: ToolInvocationRequest, values: [String: JSONValue]) -> Bool {
        fields.allSatisfy { (request.arguments[$0] ?? .null) == (values[$0] ?? .null) }
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
        workspaceRootURL: URL,
        currentDirectoryURL: URL?
    ) -> SignatureDescriptor? {
        let trimmedTool = request.tool.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTool.isEmpty else {
            return nil
        }
        guard trimmedTool != "project.task_update" else {
            return nil
        }

        switch trimmedTool {
        case "runtime.exec":
            return SignatureDescriptor(
                signature: stableSignature(
                    tool: trimmedTool,
                    payload: execPayload(
                        arguments: request.arguments,
                        policy: policy,
                        workspaceRootURL: workspaceRootURL,
                        currentDirectoryURL: currentDirectoryURL
                    )
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
                        payload: processStartPayload(
                            arguments: request.arguments,
                            policy: policy,
                            workspaceRootURL: workspaceRootURL,
                            currentDirectoryURL: currentDirectoryURL
                        )
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

    private func execPayload(
        arguments: [String: JSONValue],
        policy: AgentToolsPolicy,
        workspaceRootURL: URL,
        currentDirectoryURL: URL?
    ) -> JSONValue {
        let defaultURL = currentDirectoryURL ?? workspaceRootURL
        return .object([
            "arguments": .array(arguments["arguments"]?.asArray ?? []),
            "command": .string(arguments["command"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
            "cwd": normalizedExecCwd(
                rawValue: arguments["cwd"]?.asString,
                policy: policy,
                workspaceRootURL: workspaceRootURL,
                currentDirectoryURL: currentDirectoryURL,
                defaultPath: defaultURL.standardizedFileURL.path
            )
        ])
    }

    private func processStartPayload(
        arguments: [String: JSONValue],
        policy: AgentToolsPolicy,
        workspaceRootURL: URL,
        currentDirectoryURL: URL?
    ) -> JSONValue {
        let defaultURL = currentDirectoryURL ?? workspaceRootURL
        return .object([
            "action": .string("start"),
            "arguments": .array(arguments["arguments"]?.asArray ?? []),
            "command": .string(arguments["command"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
            "cwd": normalizedExecCwd(
                rawValue: arguments["cwd"]?.asString,
                policy: policy,
                workspaceRootURL: workspaceRootURL,
                currentDirectoryURL: currentDirectoryURL,
                defaultPath: defaultURL.standardizedFileURL.path
            )
        ])
    }

    private func normalizedExecCwd(
        rawValue: String?,
        policy: AgentToolsPolicy,
        workspaceRootURL: URL,
        currentDirectoryURL: URL?,
        defaultPath: String
    ) -> JSONValue {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return .string(defaultPath)
        }
        if let resolved = resolveToolPath(
            trimmed,
            workspaceRootURL: workspaceRootURL,
            currentDirectoryURL: currentDirectoryURL,
            extraRoots: policy.sandbox.mode == .fullAccess ? ["/"] : policy.guardrails.allowedExecRoots
        ) {
            return .string(resolved.path)
        }
        return .string(trimmed)
    }
}
