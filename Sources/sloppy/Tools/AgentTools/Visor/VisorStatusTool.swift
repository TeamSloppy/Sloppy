import AnyLanguageModel
import Foundation
import Protocols

struct VisorStatusTool: CoreTool {
    let domain = "visor"
    let title = "Visor status"
    let status = "fully_functional"
    let name = "visor.status"
    let description = "Returns the latest Visor runtime bulletin digest and readiness (operational snapshot, not long-term agent memory)."

    var parameters: GenerationSchema {
        .objectSchema([])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let ready = await context.runtime.isVisorReady()
        let bulletins = await context.runtime.bulletins()
        let latest = bulletins.last
        var payload: [String: JSONValue] = [
            "visorReady": .bool(ready),
            "bulletinCount": .number(Double(bulletins.count))
        ]
        if let latest {
            payload["headline"] = .string(latest.headline)
            payload["digest"] = .string(latest.digest)
            payload["generatedAt"] = .string(ISO8601DateFormatter().string(from: latest.generatedAt))
        } else {
            payload["headline"] = .null
            payload["digest"] = .null
            payload["generatedAt"] = .null
        }
        return toolSuccess(tool: name, data: .object(payload))
    }
}
