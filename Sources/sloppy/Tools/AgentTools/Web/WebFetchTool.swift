import AnyLanguageModel
import Foundation
import Protocols

struct WebFetchTool: CoreTool {
    let domain = "web"
    let title = "Web fetch"
    let status = "fully_functional"
    let name = "web.fetch"
    let description = "Fetch public HTTP(S) URL body as text (UTF-8). Respects tool policy webTimeoutMs, webMaxBytes, and webBlockPrivateNetworks."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "url", description: "https:// or http:// URL to fetch", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let url = arguments["url"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`url` is required.", retryable: false)
        }

        let g = context.policy.guardrails
        let result = await WebFetchService.shared.fetch(urlString: url, guardrails: g)

        switch result {
        case .success(let payload):
            var fields: [String: JSONValue] = [
                "url": .string(payload.finalURL),
                "status": .number(Double(payload.status)),
                "body": .string(payload.body),
                "lossy_utf8": .bool(payload.lossyText)
            ]
            if let ct = payload.contentType {
                fields["content_type"] = .string(ct)
            }
            return toolSuccess(tool: name, data: .object(fields))
        case .failure(let failure):
            switch failure {
            case .invalidURL:
                return toolFailure(tool: name, code: "invalid_url", message: "Invalid or unsupported URL.", retryable: false)
            case .schemeNotAllowed:
                return toolFailure(
                    tool: name,
                    code: "scheme_not_allowed",
                    message: "Only http:// and https:// URLs are allowed.",
                    retryable: false
                )
            case .hostBlocked:
                return toolFailure(
                    tool: name,
                    code: "host_blocked",
                    message: "Host is blocked by policy (private/local networks).",
                    retryable: false
                )
            case .responseTooLarge:
                return toolFailure(
                    tool: name,
                    code: "response_too_large",
                    message: "Response exceeded webMaxBytes guardrail.",
                    retryable: false
                )
            case .transport:
                return toolFailure(tool: name, code: "fetch_failed", message: "HTTP request failed.", retryable: true)
            }
        }
    }
}
