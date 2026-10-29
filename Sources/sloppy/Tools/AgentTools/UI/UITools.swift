import Foundation
import AnyLanguageModel
import Protocols

protocol UIToolService: Sendable {
    func agentUICatalog(agentID: String, sessionID: String, surfaceID: String?) async throws -> JSONValue
    func renderAgentUI(agentID: String, sessionID: String, request: AgentUIRenderRequest) async throws -> AgentUISurfaceSnapshot
}

struct UICatalogTool: CoreTool {
    let name = "ui.catalog"
    let domain = "ui"
    let title = "Read UI catalog"
    let status = "fully_functional"
    let description = "Read supported UI schemas and current revisions for this session. Optional surfaceId returns its complete snapshot."
    var parameters: GenerationSchema {
        .objectSchema([
            .init(
                name: "surfaceId", description: "Optional surface to inspect before updating.",
                schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }
    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard context.channelID == nil, let service = context.uiService else {
            return toolFailure(tool: name, code: "not_available", message: "UI requires an agent session.", retryable: false)
        }
        do {
            return toolSuccess(
                tool: name,
                data: try await service.agentUICatalog(
                    agentID: context.agentID, sessionID: context.sessionID, surfaceID: arguments["surfaceId"]?.asString))
        } catch {
            return toolFailure(
                tool: name, code: "ui_session_unavailable", message: "Cannot read this session's UI catalog.", retryable: false)
        }
    }
}

struct UIRenderTool: CoreTool {
    let name = "ui.render"
    let domain = "ui"
    let title = "Publish session UI"
    let status = "fully_functional"
    let description =
        "Atomically publish one surface using the catalog's A2UI envelopes. This publishes UI and text only; it neither executes actions nor waits for input."
    var parameters: GenerationSchema {
        .objectSchema([
            .init(
                name: "messages",
                description: "JSON-encoded array of 1–32 v0.9.1 A2UI envelopes for one surface, at most 64 KiB. Read ui.catalog first.",
                schema: DynamicGenerationSchema(type: String.self)),
            .init(
                name: "expectedRevision", description: "Latest surface revision from ui.catalog; 0 for a never-created surface.",
                schema: DynamicGenerationSchema(type: Int.self)),
            .init(
                name: "fallbackText", description: "Readable text for clients without UI support; required even for deletion.",
                schema: DynamicGenerationSchema(type: String.self)),
        ])
    }
    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard context.channelID == nil, let service = context.uiService else {
            return toolFailure(tool: name, code: "not_available", message: "UI requires an agent session.", retryable: false)
        }
        guard Set(arguments.keys).isSubset(of: ["messages", "expectedRevision", "fallbackText"]) else {
            return toolFailure(
                tool: name, code: "invalid_arguments",
                message: "Only messages, expectedRevision and fallbackText are accepted; the session is supplied by the host.",
                retryable: false)
        }
        do {
            let request = try JSONDecoder().decode(AgentUIRenderRequest.self, from: JSONEncoder().encode(arguments))
            let surface = try await service.renderAgentUI(agentID: context.agentID, sessionID: context.sessionID, request: request)
            return toolSuccess(
                tool: name,
                data: .object([
                    "surfaceId": .string(surface.surfaceId), "revision": .number(Double(surface.revision)),
                    "isDeleted": .bool(surface.isDeleted == true),
                ]))
        } catch CoreService.AgentUIError.revisionConflict(let current) {
            return ToolInvocationResult(
                tool: name, ok: false, data: .object(["currentRevision": .number(Double(current))]),
                error: .init(code: "ui_revision_conflict", message: "Read ui.catalog and retry with the current revision.", retryable: true)
            )
        } catch let error as AgentUITransactionFailure {
            return ToolInvocationResult(
                tool: name, ok: false, data: .object(["path": .string(error.path)]),
                error: .init(code: "invalid_ui_payload", message: error.reason, retryable: false))
        } catch CoreService.AgentSessionError.storageFailure {
            return toolFailure(tool: name, code: "ui_storage_failure", message: "Failed to save the UI.", retryable: true)
        } catch {
            return toolFailure(
                tool: name, code: "invalid_arguments", message: "Invalid UI request or unavailable session.", retryable: false)
        }
    }
}
