import AnyLanguageModel
import Foundation
import Protocols

struct SafariTabsTool: CoreTool {
    let domain = "safari"
    let title = "List Safari tabs"
    let status = "preview"
    let name = "safari.tabs"
    let description = "List tabs reported by the connected SloppySafari extension bridge."

    var parameters: GenerationSchema { .objectSchema([]) }

    func invoke(arguments _: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let payload = await context.safariBridgeService.statusPayload()
        return toolSuccess(tool: name, data: payload)
    }
}

struct SafariBridgeCommandTool: CoreTool {
    let domain = "safari"
    let title: String
    let status = "preview"
    let name: String
    let description: String
    let parameters: GenerationSchema

    init(name: String, title: String, description: String, parameters: GenerationSchema = .objectSchema([])) {
        self.name = name
        self.title = title
        self.description = description
        self.parameters = parameters
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        await safariBridgeResult(tool: name) {
            try await context.safariBridgeService.runCommand(name: name, input: .object(arguments))
        }
    }
}

enum SafariBridgeToolFactory {
    static func makeTools() -> [any CoreTool] {
        [
            SafariTabsTool(),
            SafariBridgeCommandTool(
                name: "safari.open_tab",
                title: "Open Safari tab",
                description: "Open a URL in Safari through the connected SloppySafari extension.",
                parameters: .objectSchema([
                    .init(name: "url", description: "URL to open.", schema: DynamicGenerationSchema(type: String.self)),
                ])
            ),
            SafariBridgeCommandTool(
                name: "safari.capture_visible_tab",
                title: "Capture Safari tab",
                description: "Capture a PNG screenshot of the visible Safari tab through SloppySafari."
            ),
            SafariBridgeCommandTool(
                name: "safari.click",
                title: "Click Safari selector",
                description: "Click an element in Safari by CSS selector through SloppySafari.",
                parameters: .objectSchema([
                    .init(name: "selector", description: "CSS selector to click.", schema: DynamicGenerationSchema(type: String.self)),
                    .init(name: "tabId", description: "Optional Safari tab ID. Defaults to the active tab.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
                ])
            ),
            SafariBridgeCommandTool(
                name: "safari.type",
                title: "Type in Safari selector",
                description: "Focus an element by CSS selector and insert text through SloppySafari.",
                parameters: .objectSchema([
                    .init(name: "selector", description: "CSS selector to focus.", schema: DynamicGenerationSchema(type: String.self)),
                    .init(name: "text", description: "Text to insert.", schema: DynamicGenerationSchema(type: String.self)),
                    .init(name: "tabId", description: "Optional Safari tab ID. Defaults to the active tab.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
                ])
            ),
            SafariBridgeCommandTool(
                name: "safari.scroll",
                title: "Scroll Safari tab",
                description: "Scroll the active Safari page by x/y pixels through SloppySafari.",
                parameters: .objectSchema([
                    .init(name: "x", description: "Horizontal scroll delta.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
                    .init(name: "y", description: "Vertical scroll delta.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
                    .init(name: "tabId", description: "Optional Safari tab ID. Defaults to the active tab.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
                ])
            ),
            SafariBridgeCommandTool(
                name: "safari.evaluate",
                title: "Evaluate Safari JavaScript",
                description: "Run JavaScript in the active Safari page through SloppySafari.",
                parameters: .objectSchema([
                    .init(name: "script", description: "JavaScript source to evaluate.", schema: DynamicGenerationSchema(type: String.self)),
                    .init(name: "tabId", description: "Optional Safari tab ID. Defaults to the active tab.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
                ])
            ),
            SafariBridgeCommandTool(
                name: "safari.print",
                title: "Print Safari page",
                description: "Open the print dialog for the active Safari page through SloppySafari."
            ),
            SafariBridgeCommandTool(
                name: "safari.dom_snapshot",
                title: "Read Safari DOM snapshot",
                description: "Return a compact text and element snapshot of the active Safari page."
            ),
        ]
    }
}

private func safariBridgeResult(tool: String, operation: () async throws -> JSONValue) async -> ToolInvocationResult {
    do {
        return toolSuccess(tool: tool, data: try await operation())
    } catch let error as SafariBridgeError {
        return toolFailure(tool: tool, code: error.code, message: error.localizedDescription, retryable: error == .bridgeUnavailable)
    } catch {
        return toolFailure(tool: tool, code: "safari_bridge_failed", message: error.localizedDescription, retryable: true)
    }
}
