import AnyLanguageModel
import Foundation
import Protocols

struct SessionsListTool: CoreTool {
    let domain = "session"
    let title = "List sessions"
    let status = "fully_functional"
    let name = "sessions.list"
    let description = "Discover sessions, including workers and their latest status, execution outcome and active process count. Inspect existing workers before starting replacements. Use scope=all to find other agents; use returned agentId and id for history or messaging."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "scope", description: "current (default) or all agents", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "agentId", description: "Filter by agent", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "projectId", description: "Filter by project", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "query", description: "Search title, agent or session ID", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "limit", description: "Maximum results (default 50, max 500)", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
            .init(name: "offset", description: "Pagination offset", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        do {
            let scope = SessionToolQuery.nonempty(arguments["scope"]?.asString) ?? "current"
            guard ["current", "all"].contains(scope) else {
                return toolFailure(tool: name, code: "invalid_arguments", message: "scope must be current or all.", retryable: false)
            }
            let sessions = try SessionToolQuery.list(
                agentID: SessionToolQuery.nonempty(arguments["agentId"]?.asString) ?? (scope == "all" ? nil : context.agentID),
                projectID: SessionToolQuery.nonempty(arguments["projectId"]?.asString), query: SessionToolQuery.nonempty(arguments["query"]?.asString),
                limit: arguments["limit"]?.asInt ?? 50, offset: arguments["offset"]?.asInt ?? 0, includeWorkers: true,
                catalog: context.agentCatalogStore, store: context.sessionStore
            )
            var records: [JSONValue] = []
            for session in sessions {
                var record = encodeJSONValue(session).asObject ?? [:]
                let detail = try context.sessionStore.loadSessionPage(agentID: session.agentId, sessionID: session.id, limit: 1)
                let state = detail.stateEvents ?? detail.events
                record["status"] = .string(statusFrom(events: state))
                if let outcome = state.reversed().compactMap(\.runStatus).first?.executionOutcome {
                    record["executionOutcome"] = encodeJSONValue(outcome)
                }
                record["activeProcessCount"] = .number(Double(await context.processRegistry.activeCount(sessionID: session.id)))
                if let active = await context.sessionService?.sessionHasActiveRun(agentID: session.agentId, sessionID: session.id) {
                    record["hasActiveRun"] = .bool(active)
                }
                records.append(.object(record))
            }
            return toolSuccess(tool: name, data: .array(records))
        } catch AgentCatalogFileStore.StoreError.notFound {
            return toolFailure(tool: name, code: "agent_not_found", message: "Unknown agentId. Omit agentId with scope=all to discover agents.", retryable: false)
        } catch AgentCatalogFileStore.StoreError.invalidID {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Invalid agentId. Omit the filter or supply an ID returned by sessions.list.", retryable: false)
        } catch {
            return toolFailure(tool: name, code: "session_list_failed", message: "Failed to list sessions.", retryable: true)
        }
    }
}
