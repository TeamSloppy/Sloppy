import AnyLanguageModel
import Foundation
import Protocols

struct RuntimeProcessTool: CoreTool {
    let domain = "runtime"
    let title = "Manage process"
    let status = "fully_functional"
    let name = "runtime.process"
    var advertisesWait = false
    var description: String {
        if advertisesWait {
            return "Manage session processes: start, wait, status, stop, list. For a background build or test, start with captureOutput: true. When you need the final result, use wait with its processId and a suitable timeoutMs to receive exitCode and outputTail on exit. Use status for an immediate snapshot."
        }
        return legacyDescription
    }
    private let legacyDescription = "Manage long-lived background session processes. A successful start returns `verificationEvidence.id` for `session.complete`. Use this only when a process must stay alive across steps; for one-shot commands use `runtime.exec`. Supported actions: start, status, stop, list."

    var parameters: GenerationSchema {
        var fields: [DynamicGenerationSchema.Property] = [
            .init(name: "action", description: advertisesWait ? "start, wait, status, stop, or list" : "start, status, stop, or list", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "command", description: "Executable name or path to start (e.g. 'bash', '/bin/ls', 'git'). Required for start. Do NOT repeat the command name in arguments.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "arguments", description: "Array of arguments passed to the command (argv). For shell one-liners use command='bash' arguments=['-lc', 'your command here']. Do NOT include the command name itself.", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "cwd", description: "Working directory (absolute path or relative to current session directory). Defaults to current session directory if omitted.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "processId", description: "Process ID for actions targeting a process", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ]
        if advertisesWait {
            fields.append(.init(name: "timeoutMs", description: "Maximum wait time in milliseconds, from 1 through 600000. Default 60000.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true))
            fields.append(.init(name: "captureOutput", description: "Capture a bounded output tail on start for use with wait.", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true))
        }
        return .objectSchema(fields)
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let action = arguments["action"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "list"
        do {
            switch action {
            case "start":
                return try await handleStart(arguments: arguments, context: context)
            case "wait" where CodeMode.enabled(workspaceRoot: context.workspaceRootURL):
                return try await handleWait(arguments: arguments, context: context)
            case "status":
                return try await handleStatus(arguments: arguments, context: context)
            case "stop":
                return try await handleStop(arguments: arguments, context: context)
            case "list":
                let payload = await context.processRegistry.list(sessionID: context.sessionID)
                return toolSuccess(tool: name, data: payload)
            default:
                return toolFailure(tool: name, code: "invalid_arguments", message: "Unsupported action '\(action)'.", retryable: false)
            }
        } catch SessionProcessRegistry.RegistryError.waitTimedOut {
            return toolFailure(tool: name, code: "process_wait_timeout", message: "The process has not exited yet.", retryable: true)
        } catch is CancellationError {
            return toolFailure(tool: name, code: "tool_cancelled", message: "Process wait cancelled.", retryable: false)
        } catch SessionProcessRegistry.RegistryError.processLimitReached {
            return toolFailure(tool: name, code: "process_limit_reached", message: "Max process count per session reached.", retryable: false)
        } catch SessionProcessRegistry.RegistryError.processNotFound {
            return toolFailure(tool: name, code: "process_not_found", message: "Process not found.", retryable: false)
        } catch {
            return toolFailure(tool: name, code: "process_error", message: "Failed to execute process action.", retryable: true)
        }
    }

    private func handleStart(arguments: [String: JSONValue], context: ToolContext) async throws -> ToolInvocationResult {
        let command = arguments["command"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !command.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`command` is required for start action.", retryable: false)
        }
        guard isCommandAllowed(command, deniedPrefixes: context.policy.guardrails.deniedCommandPrefixes) else {
            return toolFailure(tool: name, code: "command_blocked", message: "Command blocked by guardrail denylist.", retryable: false)
        }
        let args = arguments["arguments"]?.asArray?.compactMap(\.asString) ?? []
        let cwdValue = arguments["cwd"]?.asString
        let cwdPath: String
        if let cwdValue, !cwdValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let resolved = context.resolveExecCwd(cwdValue) {
            cwdPath = resolved.path
        } else if let cwdValue, !cwdValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return toolFailure(tool: name, code: "cwd_not_allowed", message: "CWD is outside allowed execution roots.", retryable: false)
        } else {
            cwdPath = context.currentDirectoryURL.path
        }
        let payload = try await context.processRegistry.start(
            sessionID: context.sessionID,
            command: command,
            arguments: args,
            cwd: cwdPath,
            maxProcesses: context.policy.guardrails.maxProcessesPerSession,
            environmentOverrides: context.environmentOverrides,
            captureOutput: arguments["captureOutput"]?.asBool == true && CodeMode.enabled(workspaceRoot: context.workspaceRootURL)
        )
        return toolSuccess(tool: name, data: payload)
    }

    static func waitTimeoutMs(_ value: JSONValue?) -> Int? {
        guard let value else { return CodeMode.defaultTimeoutMs }
        guard let number = value.asNumber, number >= 1, number <= Double(CodeMode.maximumTimeoutMs),
              number.rounded(.towardZero) == number else { return nil }
        return Int(number)
    }

    private func handleWait(arguments: [String: JSONValue], context: ToolContext) async throws -> ToolInvocationResult {
        guard let processID = arguments["processId"]?.asString, !processID.isEmpty,
              let timeoutMs = Self.waitTimeoutMs(arguments["timeoutMs"]) else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "wait requires processId and an optional timeoutMs from 1 through 600000.", retryable: false)
        }
        let payload = try await context.processRegistry.wait(sessionID: context.sessionID, processID: processID, timeoutMs: timeoutMs)
        return toolSuccess(tool: name, data: payload)
    }

    private func handleStatus(arguments: [String: JSONValue], context: ToolContext) async throws -> ToolInvocationResult {
        let processID = arguments["processId"]?.asString ?? ""
        guard !processID.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`processId` is required for status action.", retryable: false)
        }
        let payload = try await context.processRegistry.status(sessionID: context.sessionID, processID: processID)
        return toolSuccess(tool: name, data: payload)
    }

    private func handleStop(arguments: [String: JSONValue], context: ToolContext) async throws -> ToolInvocationResult {
        let processID = arguments["processId"]?.asString ?? ""
        guard !processID.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`processId` is required for stop action.", retryable: false)
        }
        let payload = try await context.processRegistry.stop(sessionID: context.sessionID, processID: processID)
        return toolSuccess(tool: name, data: payload)
    }
}
