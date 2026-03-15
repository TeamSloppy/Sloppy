import AnyLanguageModel
import Foundation
import Protocols

struct WebFetchTool: CoreTool {
    let domain = "web"
    let title = "Web fetch"
    let status = "adapter"
    let name = "web.fetch"
    let description = "Fetch URL content via external adapter."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "url", description: "URL to fetch", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        toolFailure(tool: name, code: "not_configured", message: "Tool adapter is not configured.", retryable: false)
    }
}
