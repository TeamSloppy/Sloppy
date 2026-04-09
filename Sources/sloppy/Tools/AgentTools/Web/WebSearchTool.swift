import AnyLanguageModel
import Foundation
import Protocols

struct WebSearchTool: CoreTool {
    let domain = "web"
    let title = "Web search"
    let status = "fully_functional"
    let name = "web.search"
    let description = "Search web via configured Brave or Perplexity provider."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "query", description: "Search query", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "count", description: "Number of results (1-10)", schema: DynamicGenerationSchema(type: Int.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let query = arguments["query"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`query` is required.", retryable: false)
        }
        let count = min(10, max(1, arguments["count"]?.asInt ?? 5))

        do {
            let response = try await context.searchProviderService.search(
                query: query,
                count: count,
                timeoutMs: context.policy.guardrails.webTimeoutMs,
                maxBytes: context.policy.guardrails.webMaxBytes
            )
            return toolSuccess(tool: name, data: .object([
                "query": .string(response.query),
                "provider": .string(response.provider),
                "results": .array(response.results.map { item in
                    .object([
                        "title": .string(item.title),
                        "url": .string(item.url),
                        "snippet": .string(item.snippet)
                    ])
                }),
                "citations": .array(response.citations.map { citation in
                    .object([
                        "title": .string(citation.title),
                        "url": .string(citation.url)
                    ])
                }),
                "count": .number(Double(response.count))
            ]))
        } catch let error as SearchProviderService.SearchError {
            switch error {
            case .notConfigured:
                return toolFailure(tool: name, code: "not_configured", message: "Search provider is not configured.", retryable: false)
            case .responseTooLarge:
                return toolFailure(tool: name, code: "response_too_large", message: "Search response exceeded configured size limit.", retryable: false)
            case .httpError(let status):
                return toolFailure(tool: name, code: "search_http_error", message: "Search provider returned HTTP \(status).", retryable: true)
            case .invalidResponse:
                return toolFailure(tool: name, code: "invalid_response", message: "Search provider returned an invalid response.", retryable: true)
            case .transportFailure:
                return toolFailure(tool: name, code: "transport_failed", message: "Search request failed.", retryable: true)
            }
        } catch {
            return toolFailure(tool: name, code: "search_failed", message: "Search request failed.", retryable: true)
        }
    }
}
