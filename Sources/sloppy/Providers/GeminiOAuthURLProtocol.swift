import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GeminiOAuthURLProtocol: URLProtocol {
    private var activeTask: URLSessionDataTask?
    private var activeSession: URLSession?
    private var activeDelegate: GeminiOAuthURLProtocolSessionDelegate?
    private var responseBuffer = Data()

    private static let projectCache = GeminiOAuthURLProtocolProjectCache()

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return false
        }
        guard let key = request.value(forHTTPHeaderField: "x-goog-api-key"),
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
        let modified: URLRequest
        do {
            modified = try Self.modifiedRequest(from: request)
        } catch {
            didComplete(with: error)
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        let delegate = GeminiOAuthURLProtocolSessionDelegate(owner: self)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: modified)
        activeDelegate = delegate
        activeSession = session
        activeTask = task
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
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    fileprivate func didReceive(data: Data) {
        responseBuffer.append(data)
    }

    fileprivate func didComplete(with error: Error?) {
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            if !responseBuffer.isEmpty {
                do {
                    client?.urlProtocol(self, didLoad: try Self.responseDataForGeminiParser(from: responseBuffer))
                } catch {
                    client?.urlProtocol(self, didFailWithError: error)
                    activeDelegate = nil
                    activeSession = nil
                    activeTask = nil
                    responseBuffer.removeAll(keepingCapacity: false)
                    return
                }
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        activeDelegate = nil
        activeSession = nil
        activeTask = nil
        responseBuffer.removeAll(keepingCapacity: false)
    }

    static func modifiedRequest(
        from request: URLRequest,
        projectID: String? = resolvedProjectID(),
        requestID: String = UUID().uuidString
    ) throws -> URLRequest {
        var mutable = request
        let token = request.value(forHTTPHeaderField: "x-goog-api-key")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let route = try cloudCodeRoute(for: request)
        mutable.url = route.url
        mutable.setValue(nil, forHTTPHeaderField: "x-goog-api-key")
        mutable.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        GeminiCodeAssistProjectResolver.applyHeaders(
            to: &mutable,
            authorizationHeaderValue: "Bearer \(token)",
            accept: route.isStreaming ? "text/event-stream" : "application/json"
        )
        mutable.httpBody = try cloudCodeBody(
            from: request.httpBody,
            model: route.model,
            projectID: projectID,
            requestID: requestID
        )

        let userProject = projectID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let userProject, !userProject.isEmpty {
            mutable.setValue(userProject, forHTTPHeaderField: "x-goog-user-project")
        }
        return mutable
    }

    static func responseBodyForGeminiParser(from data: Data) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = object["response"] as? [String: Any]
        else {
            return data
        }
        return try JSONSerialization.data(withJSONObject: response)
    }

    private static func responseDataForGeminiParser(from data: Data) throws -> Data {
        let text = String(decoding: data, as: UTF8.self)
        if text.contains("\ndata:") || text.hasPrefix("data:") {
            return try eventStreamBodyForGeminiParser(from: text)
        }
        return try responseBodyForGeminiParser(from: data)
    }

    private static func eventStreamBodyForGeminiParser(from text: String) throws -> Data {
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("data:") else {
                lines.append(String(line))
                continue
            }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" || payload.isEmpty {
                lines.append(String(line))
                continue
            }
            let unwrapped = try responseBodyForGeminiParser(from: Data(payload.utf8))
            lines.append("data: \(String(decoding: unwrapped, as: UTF8.self))")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func cloudCodeRoute(for request: URLRequest) throws -> (url: URL, model: String, isStreaming: Bool) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        guard let last = url.pathComponents.last,
              let separator = last.lastIndex(of: ":")
        else {
            throw URLError(.badURL)
        }
        let model = String(last[..<separator])
        let action = String(last[last.index(after: separator)...])
        guard !model.isEmpty, action == "generateContent" || action == "streamGenerateContent" else {
            throw URLError(.badURL)
        }

        var target = GeminiCodeAssistProjectResolver.defaultBaseURL.appendingPathComponent("v1internal:\(action)")
        let isStreaming = action == "streamGenerateContent"
        if isStreaming {
            target.append(queryItems: [URLQueryItem(name: "alt", value: "sse")])
        }
        return (target, model, isStreaming)
    }

    private static func cloudCodeBody(
        from body: Data?,
        model: String,
        projectID: String?,
        requestID: String
    ) throws -> Data {
        let requestObject: Any
        if let body, !body.isEmpty {
            requestObject = try JSONSerialization.jsonObject(with: body)
        } else {
            requestObject = [String: Any]()
        }

        var wrapped: [String: Any] = [
            "model": model,
            "request": requestObject,
            "requestType": "agent",
            "userAgent": GeminiCodeAssistProjectResolver.userAgent,
            "requestId": requestID,
        ]
        let trimmedProjectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedProjectID.isEmpty {
            wrapped["project"] = trimmedProjectID
        }
        return try JSONSerialization.data(withJSONObject: wrapped)
    }

    private static func resolvedProjectID() -> String? {
        projectCache.value()
    }

    static func setCompanionProjectID(_ projectID: String?) {
        projectCache.update(projectID)
    }
}

private final class GeminiOAuthURLProtocolProjectCache: @unchecked Sendable {
    private let lock = NSLock()
    private var companionProjectID: String?

    func value() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return companionProjectID
    }

    func update(_ projectID: String?) {
        let trimmed = projectID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        lock.lock()
        companionProjectID = trimmed.isEmpty ? nil : trimmed
        lock.unlock()
    }
}

private final class GeminiOAuthURLProtocolSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private weak var owner: GeminiOAuthURLProtocol?

    init(owner: GeminiOAuthURLProtocol) {
        self.owner = owner
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        owner?.didReceive(response: response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        owner?.didReceive(data: data)
    }

    #if canImport(Security)
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if SloppyExtraCertificateAuthority.handle(challenge: challenge, completionHandler: completionHandler) {
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
    #endif

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        owner?.didComplete(with: error)
        session.finishTasksAndInvalidate()
    }
}
