import AnyLanguageModel
import Foundation
import Logging
import Protocols

struct RuntimeExecTool: CoreTool {
    let domain = "runtime"
    let title = "Exec command"
    let status = "fully_functional"
    let name = "runtime.exec"
    let description = "Run one foreground command with timeout and output limits."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "command", description: "Command to execute", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "arguments", description: "Command arguments", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "cwd", description: "Working directory", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "timeoutMs", description: "Timeout in milliseconds", schema: DynamicGenerationSchema(type: Int.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let command = arguments["command"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !command.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`command` is required.", retryable: false)
        }
        guard isCommandAllowed(command, deniedPrefixes: context.policy.guardrails.deniedCommandPrefixes) else {
            return toolFailure(tool: name, code: "command_blocked", message: "Command blocked by guardrail denylist.", retryable: false)
        }

        let args = arguments["arguments"]?.asArray?.compactMap(\.asString) ?? []
        let timeoutMs = max(100, arguments["timeoutMs"]?.asInt ?? context.policy.guardrails.execTimeoutMs)
        let cwdValue = arguments["cwd"]?.asString

        let cwdURL: URL?
        if let cwdValue, !cwdValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let resolved = context.resolveExecCwd(cwdValue) else {
                return toolFailure(tool: name, code: "cwd_not_allowed", message: "CWD is outside allowed execution roots.", retryable: false)
            }
            cwdURL = resolved
        } else {
            cwdURL = context.workspaceRootURL
        }

        do {
            let payload = try await runForegroundProcess(
                command: command,
                arguments: args,
                cwd: cwdURL,
                timeoutMs: timeoutMs,
                maxOutputBytes: context.policy.guardrails.maxExecOutputBytes
            )
            return toolSuccess(tool: name, data: payload)
        } catch {
            context.logger.error(
                "Command execution failed",
                metadata: [
                    "tool": .string(name),
                    "command": .string(command),
                    "error": .string(String(describing: error))
                ]
            )
            return toolFailure(tool: name, code: "exec_failed", message: "Command execution failed: \(error.localizedDescription)", retryable: true)
        }
    }
}
