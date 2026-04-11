import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Helpers for [OpenRouter](https://openrouter.ai/docs).
///
/// Sloppy uses AnyLanguageModel’s `OpenResponsesLanguageModel` (Open Responses) for OpenRouter.
/// Use ``makeURLSession()`` so optional [app attribution](https://openrouter.ai/docs/api/reference/overview) headers are applied.
public enum OpenRouterLanguageModelSupport {
    public static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1")!

    /// Builds a session that adds optional OpenRouter [app attribution](https://openrouter.ai/docs/api/reference/overview) headers.
    ///
    /// Environment variables (all optional):
    /// - `OPENROUTER_APP_TITLE` — sent as `X-OpenRouter-Title` (default: `Sloppy`).
    /// - `OPENROUTER_HTTP_REFERER` — sent as `HTTP-Referer`.
    public static func makeURLSession() -> URLSession {
        let config = URLSessionConfiguration.default
        var headers: [String: String] = [:]
        let title = ProcessInfo.processInfo.environment["OPENROUTER_APP_TITLE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        headers["X-OpenRouter-Title"] = title.isEmpty ? "Sloppy" : title
        let referer = ProcessInfo.processInfo.environment["OPENROUTER_HTTP_REFERER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !referer.isEmpty {
            headers["HTTP-Referer"] = referer
        }
        config.httpAdditionalHeaders = headers
        return URLSession(configuration: config)
    }
}
