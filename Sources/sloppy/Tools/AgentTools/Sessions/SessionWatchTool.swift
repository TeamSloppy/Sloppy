import AnyLanguageModel
import Foundation
import Protocols

struct SessionWatchTool: CoreTool {
    static let toolName = "session.watch"
    let name = Self.toolName
    let domain = "tools"
    let title = "Watch a running job"
    let status = "fully_functional"
    let description = "Watch an existing local process or a job exposed by a read-only MCP status tool until its terminal result. Core saves the next check and reports the result in the current chat. Use when monitoring is the remaining user request. Cancel only when the user stops or replaces the watch."

    var parameters: GenerationSchema {
        let string = DynamicGenerationSchema(type: String.self)
        let strings = DynamicGenerationSchema(arrayOf: string)
        return .objectSchema([
            .init(name: "action", description: "start, status, or cancel", schema: string),
            .init(name: "watchId", description: "Existing watch ID for status or cancel", schema: string, isOptional: true),
            .init(name: "title", description: "Short display name for the job", schema: string, isOptional: true),
            .init(name: "processId", description: "Existing runtime.process ID in this session", schema: string, isOptional: true),
            .init(name: "mcpTool", description: "Exact discovered ID of the read-only MCP status tool", schema: string, isOptional: true),
            .init(name: "mcpArguments", description: "Status tool arguments as a JSON object string. Use the existing job ID and no secrets.", schema: string, isOptional: true),
            .init(name: "statusPath", description: "Keys from the MCP JSON response to its status string, including numeric array indexes", schema: strings, isOptional: true),
            .init(name: "pendingStates", description: "Exact MCP statuses that require another check", schema: strings, isOptional: true),
            .init(name: "successStates", description: "Exact MCP statuses that end the watch successfully", schema: strings, isOptional: true),
            .init(name: "failureStates", description: "Exact MCP statuses that end the watch unsuccessfully", schema: strings, isOptional: true),
            .init(name: "detailPath", description: "Optional path to a reason, log URL or error string in the response", schema: strings, isOptional: true),
            .init(name: "intervalSeconds", description: "Seconds between checks, 5–3600. Default 60.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard context.channelID == nil, let service = context.sessionService else {
            return toolFailure(tool: name, code: "watch_unavailable", message: "Job watches require an agent chat session.", retryable: false)
        }
        return await service.manageSessionWatch(
            agentID: context.agentID, sessionID: context.sessionID, arguments: arguments,
            allowedTools: context.discoveryAllowedToolIDs
        )
    }

    static func target(_ arguments: [String: JSONValue]) -> SessionWatch.Target? {
        let processID = SessionToolQuery.nonempty(arguments["processId"]?.asString)
        let mcpTool = SessionToolQuery.nonempty(arguments["mcpTool"]?.asString)
        if let processID, mcpTool == nil { return .process(id: processID) }
        guard processID == nil, let mcpTool,
              let path = strings(arguments["statusPath"]),
              let pending = strings(arguments["pendingStates"]),
              let success = strings(arguments["successStates"]),
              let failure = strings(arguments["failureStates"]),
              Set(pending + success + failure).count == pending.count + success.count + failure.count else { return nil }
        let payload: [String: JSONValue]
        switch arguments["mcpArguments"] {
        case nil: payload = [:]
        case .object(let value): payload = value
        case .string(let text):
            guard let value = try? JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8)) else { return nil }
            payload = value
        default: return nil
        }
        return .mcp(.init(tool: mcpTool, arguments: payload, statusPath: path, pending: pending,
                          success: success, failure: failure, detailPath: strings(arguments["detailPath"])))
    }

    private static func strings(_ value: JSONValue?) -> [String]? {
        guard let items = value?.asArray, !items.isEmpty else { return nil }
        let strings = items.compactMap(\.asString)
        return strings.count == items.count && strings.allSatisfy({ !$0.isEmpty }) ? strings : nil
    }
}
