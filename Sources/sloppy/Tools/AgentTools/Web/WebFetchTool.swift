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
            case .methodNotAllowed:
                return toolFailure(
                    tool: name,
                    code: "method_not_allowed",
                    message: "HTTP method is not allowed.",
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

struct WebRequestTool: CoreTool {
    let domain = "web"
    let title = "Web request"
    let status = "fully_functional"
    let name = "web.request"
    let description = "Send guarded HTTP(S) requests with method, headers, and body. Respects web timeout, max bytes, and private-network policy."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "url", description: "https:// or http:// URL to request", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "method", description: "HTTP method: GET, POST, PUT, PATCH, DELETE, or HEAD", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "headers", description: "Optional HTTP headers object", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "body", description: "Optional HTTP request body", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let url = arguments["url"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`url` is required.", retryable: false)
        }
        let method = arguments["method"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "GET"
        let headers = headersObject(arguments["headers"])
        let body = arguments["body"]?.asString

        let result = await WebFetchService.shared.request(
            urlString: url,
            method: method,
            headers: headers,
            body: body,
            guardrails: context.policy.guardrails
        )

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
            return webRequestFailureResult(tool: name, failure: failure)
        }
    }

    private func headersObject(_ value: JSONValue?) -> [String: String] {
        if let object = value?.asObject {
            return object.reduce(into: [:]) { result, entry in
                if let string = entry.value.asString {
                    result[entry.key] = string
                }
            }
        }
        guard let raw = value?.asString,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
              let object = decoded.asObject
        else {
            return [:]
        }
        return object.reduce(into: [:]) { result, entry in
            if let string = entry.value.asString {
                result[entry.key] = string
            }
        }
    }
}

private func webRequestFailureResult(tool: String, failure: WebFetchService.Failure) -> ToolInvocationResult {
    switch failure {
    case .invalidURL:
        return toolFailure(tool: tool, code: "invalid_url", message: "Invalid or unsupported URL.", retryable: false)
    case .schemeNotAllowed:
        return toolFailure(tool: tool, code: "scheme_not_allowed", message: "Only http:// and https:// URLs are allowed.", retryable: false)
    case .methodNotAllowed:
        return toolFailure(tool: tool, code: "method_not_allowed", message: "HTTP method is not allowed.", retryable: false)
    case .hostBlocked:
        return toolFailure(tool: tool, code: "host_blocked", message: "Host is blocked by policy (private/local networks).", retryable: false)
    case .responseTooLarge:
        return toolFailure(tool: tool, code: "response_too_large", message: "Response exceeded webMaxBytes guardrail.", retryable: false)
    case .transport:
        return toolFailure(tool: tool, code: "request_failed", message: "HTTP request failed.", retryable: true)
    }
}
