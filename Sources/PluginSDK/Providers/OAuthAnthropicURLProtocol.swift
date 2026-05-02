import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Intercepts Anthropic `Messages` HTTP(S) requests from ``OAuthAnthropicLanguageModel`` / ``AnthropicLanguageModel`` (which always sends `x-api-key`)
/// and rewrites auth headers for Claude Code–compatible routing (Bearer OAuth, MiniMax, third-party `x-api-key`, etc.).
///
/// Uses a plain ``URLSession`` for the actual load so this protocol is not re-entered.
final class OAuthAnthropicURLProtocol: URLProtocol {
    private var activeTask: URLSessionDataTask?
    private var activeSession: URLSession?
    private var activeDelegate: OAuthAnthropicURLProtocolSessionDelegate?

    /// Session without custom `protocolClasses` so sub-requests do not loop through this type.
    private static let plainSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        // We need a session that can handle delegates for individual tasks if possible,
        // but FoundationNetworking is more restrictive.
        return URLSession(configuration: config)
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
        
        // Keep URLProtocol separate from URLSessionDataDelegate: FoundationNetworking
        // makes URLSession delegates Sendable, while URLProtocol cannot conform to Sendable on Linux.
        let config = URLSessionConfiguration.ephemeral
        let delegate = OAuthAnthropicURLProtocolSessionDelegate(owner: self)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        let task = session.dataTask(with: modified)
        self.activeDelegate = delegate
        self.activeSession = session
        self.activeTask = task
        task.resume()
    }

    override func stopLoading() {
        activeTask?.cancel()
        activeSession?.invalidateAndCancel()
        activeDelegate = nil
        activeSession = nil
        activeTask = nil
    }

    fileprivate func didReceive(response: URLResponse) {
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    fileprivate func didReceive(data: Data) {
        self.client?.urlProtocol(self, didLoad: data)
    }

    fileprivate func didComplete(with error: Error?) {
        if let error = error {
            self.client?.urlProtocol(self, didFailWithError: error)
        } else {
            self.client?.urlProtocolDidFinishLoading(self)
        }
        activeDelegate = nil
        activeSession = nil
        activeTask = nil
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

private final class OAuthAnthropicURLProtocolSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private weak var owner: OAuthAnthropicURLProtocol?

    init(owner: OAuthAnthropicURLProtocol) {
        self.owner = owner
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        owner?.didReceive(response: response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        owner?.didReceive(data: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        owner?.didComplete(with: error)
        session.finishTasksAndInvalidate()
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
