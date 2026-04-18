import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Intercepts Anthropic `Messages` HTTP(S) requests from ``OAuthAnthropicLanguageModel`` / ``AnthropicLanguageModel`` (which always sends `x-api-key`)
/// and rewrites auth headers for Claude Code–compatible routing (Bearer OAuth, MiniMax, third-party `x-api-key`, etc.).
///
/// Uses a plain ``URLSession`` for the actual load so this protocol is not re-entered.
final class OAuthAnthropicURLProtocol: URLProtocol, @unchecked Sendable {
    private var loadTask: Task<Void, Never>?

    /// Session without custom `protocolClasses` so sub-requests do not loop through this type.
    private static let plainSession: URLSession = {
        URLSession(configuration: .ephemeral)
    }()

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return false
        }
        guard request.value(forHTTPHeaderField: "anthropic-version") != nil,
              let key = request.value(forHTTPHeaderField: "x-api-key"),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let request = self.request
        let modified = Self.modifiedRequest(from: request)
        let isEventStream = modified.value(forHTTPHeaderField: "Accept")?.contains("text/event-stream") == true
        loadTask = Task { @Sendable [weak self] in
            guard let self else { return }
            do {
                if isEventStream {
                    let (bytes, response) = try await Self.plainSession.bytes(for: modified)
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    for try await byte in bytes {
                        if Task.isCancelled { throw CancellationError() }
                        self.client?.urlProtocol(self, didLoad: Data([byte]))
                    }
                    self.client?.urlProtocolDidFinishLoading(self)
                } else {
                    let (data, response) = try await Self.plainSession.data(for: modified)
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    self.client?.urlProtocol(self, didLoad: data)
                    self.client?.urlProtocolDidFinishLoading(self)
                }
            } catch is CancellationError {
                self.client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        loadTask?.cancel()
        loadTask = nil
    }

    /// `.../v1/messages` → configured API base (e.g. `https://api.anthropic.com` or `https://proxy.example/anthropic`).
    private static func apiBaseURL(from messageURL: URL) -> URL {
        messageURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func modifiedRequest(from request: URLRequest) -> URLRequest {
        guard let url = request.url else { return request }
        let apiKey = request.value(forHTTPHeaderField: "x-api-key") ?? ""
        let apiVersion = request.value(forHTTPHeaderField: "anthropic-version") ?? OAuthAnthropicAuthHeaders.defaultAPIVersion
        let betaHeader = request.value(forHTTPHeaderField: "anthropic-beta")
        let additionalBetas = betaHeader?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let baseURL = apiBaseURL(from: url)
        let authHeaders = OAuthAnthropicAuthHeaders.make(
            apiKey: apiKey,
            baseURL: baseURL,
            apiVersion: apiVersion,
            additionalBetas: additionalBetas
        )

        var mutable = request
        for field in ["x-api-key", "Authorization", "anthropic-beta", "user-agent", "x-app"] {
            mutable.setValue(nil, forHTTPHeaderField: field)
        }
        for (field, value) in authHeaders {
            mutable.setValue(value, forHTTPHeaderField: field)
        }
        return mutable
    }
}

/// URL session that prepends ``OAuthAnthropicURLProtocol`` so Anthropic traffic gets OAuth / Claude Code–aligned auth headers.
public enum OAuthAnthropicURLSession {
    /// Use when ``OAuthAnthropicLanguageModel`` should apply OAuth, Claude Code, or MiniMax auth rules on top of `x-api-key` requests.
    public static func makeSessionRewritingAnthropicAuth() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthAnthropicURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
