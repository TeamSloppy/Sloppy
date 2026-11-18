import AnyLanguageModel
import Foundation
import Protocols

struct SystemListToolsTool: CoreTool {
    let domain = "system"
    let title = "List tools"
    let status = "fully_functional"
    let name = "system.list_tools"
    let description = "Return the available tool catalog with argument schemas."

    var parameters: GenerationSchema {
        .objectSchema([])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let payload = await ToolCatalog.listToolsPayload(mcpRegistry: context.mcpRegistry,
            codeModeEnabled: CodeMode.enabled(workspaceRoot: context.workspaceRootURL))
        return toolSuccess(tool: name, data: .array(payload))
    }
}
