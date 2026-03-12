import AnyLanguageModel
import Foundation
import Protocols

struct AgentsListTool: CoreTool {
    let domain = "agents"
    let title = "List agents"
    let status = "fully_functional"
    let name = "agents.list"
    let description = "List all known agents."

    var parameters: GenerationSchema {
        .objectSchema([])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        do {
            let list = try context.agentCatalogStore.listAgents()
            return toolSuccess(tool: name, data: encodeJSONValue(list))
        } catch {
            return toolFailure(tool: name, code: "agents_list_failed", message: "Failed to list agents.", retryable: true)
        }
    }
}
