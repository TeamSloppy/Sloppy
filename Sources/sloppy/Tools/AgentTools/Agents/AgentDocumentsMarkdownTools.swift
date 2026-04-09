import AnyLanguageModel
import Foundation
import Protocols

struct AgentDocumentsSetUserMarkdownTool: CoreTool {
    let domain = "agent"
    let title = "Set USER.md"
    let status = "fully_functional"
    let name = "agent.documents.set_user_markdown"
    let description = "Replace the agent USER.md document (max \(AgentMarkdownLimits.userMarkdownMaxCharacters) characters)."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "content", description: "Full USER.md contents", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let content = arguments["content"]?.asString ?? ""
        guard let apply = context.applyAgentMarkdown else {
            return toolFailure(tool: name, code: "not_available", message: "Agent document updates are not available in this context.", retryable: false)
        }
        do {
            try await apply(.user, content)
            return toolSuccess(tool: name, data: .object(["updated": .bool(true), "chars": .number(Double(content.count))]))
        } catch let error as AgentDocumentLengthError {
            if case .exceeded(let resource, let limit) = error {
                return toolFailure(
                    tool: name,
                    code: "document_too_long",
                    message: "\(resource) exceeds the limit of \(limit) characters. Remove content or store it elsewhere.",
                    retryable: false
                )
            }
            return toolFailure(tool: name, code: "update_failed", message: "Failed to update USER.md.", retryable: false)
        } catch let error as CoreService.AgentConfigError {
            if case .documentLengthExceeded(let resource, let limit) = error {
                return toolFailure(
                    tool: name,
                    code: "document_too_long",
                    message: "\(resource) exceeds the limit of \(limit) characters. Remove content or store it elsewhere.",
                    retryable: false
                )
            }
            return toolFailure(tool: name, code: "update_failed", message: String(describing: error), retryable: false)
        } catch {
            return toolFailure(tool: name, code: "update_failed", message: String(describing: error), retryable: true)
        }
    }
}

struct AgentDocumentsSetMemoryMarkdownTool: CoreTool {
    let domain = "agent"
    let title = "Set MEMORY.md"
    let status = "fully_functional"
    let name = "agent.documents.set_memory_markdown"
    let description = "Replace the agent MEMORY.md document (max \(AgentMarkdownLimits.memoryMarkdownMaxCharacters) characters)."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "content", description: "Full MEMORY.md contents", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let content = arguments["content"]?.asString ?? ""
        guard let apply = context.applyAgentMarkdown else {
            return toolFailure(tool: name, code: "not_available", message: "Agent document updates are not available in this context.", retryable: false)
        }
        do {
            try await apply(.memory, content)
            return toolSuccess(tool: name, data: .object(["updated": .bool(true), "chars": .number(Double(content.count))]))
        } catch let error as AgentDocumentLengthError {
            if case .exceeded(let resource, let limit) = error {
                return toolFailure(
                    tool: name,
                    code: "document_too_long",
                    message: "\(resource) exceeds the limit of \(limit) characters. Remove content or store it elsewhere.",
                    retryable: false
                )
            }
            return toolFailure(tool: name, code: "update_failed", message: "Failed to update MEMORY.md.", retryable: false)
        } catch {
            return toolFailure(tool: name, code: "update_failed", message: String(describing: error), retryable: true)
        }
    }
}
