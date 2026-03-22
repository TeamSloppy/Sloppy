import AnyLanguageModel
import Foundation
import Protocols

struct RuntimeProcessTool: CoreTool {
    let domain = "runtime"
    let title = "Manage process"
    let status = "fully_functional"
    let name = "runtime.process"
    let description = "Start, inspect, list, and stop background session processes."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "action", description: "Action: start, status, stop, list", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "command", description: "Command to start (required for start)", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "arguments", description: "Command arguments", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "cwd", description: "Working directory", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "processId", description: "Process ID (required for status/stop)", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let action = arguments["action"]?.asString?.lowercased() ?? "list"
        do {
            switch action {
            case "start":
                return try await handleStart(arguments: arguments, context: context)
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
        if let cwdValue, !cwdValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           context.resolveExecCwd(cwdValue) == nil {
            return toolFailure(tool: name, code: "cwd_not_allowed", message: "CWD is outside allowed execution roots.", retryable: false)
        }
        let payload = try await context.processRegistry.start(
            sessionID: context.sessionID,
            command: command,
            arguments: args,
            cwd: cwdValue,
            maxProcesses: context.policy.guardrails.maxProcessesPerSession
        )
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
