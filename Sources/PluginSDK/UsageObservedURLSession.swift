import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

/// One scope per language-model session; no task-local/global "current channel".
public enum UsageObservedURLSession {
    static let header = "x-sloppy-usage-observation"
    private static let lock = NSLock()
    private nonisolated(unsafe) static var scopes: [String: WeakScope] = [:]
    private final class WeakScope { weak var value: Scope?; init(_ value: Scope) { self.value = value } }

    fileprivate final class Scope: @unchecked Sendable {
        let base: URLSession
        let context: ModelUsageContext
        let decoder: UsageWireDecoder
        init(base: URLSession, context: ModelUsageContext) {
            self.base = base; self.context = context; self.decoder = UsageWireDecoder(context: context)
        }
    }

    public static func make(wrapping base: URLSession?, context: ModelUsageContext) throws -> URLSession {
        let base = base ?? URLSession(configuration: .default)
        let scope = Scope(base: base, context: context)
        let id = UUID().uuidString
        lock.withLock {
            scopes = scopes.filter { $0.value.value != nil }
            scopes[id] = WeakScope(scope)
        }
        let config = try copyConfiguration(of: base)
        config.protocolClasses = [UsageObservationURLProtocol.self] + (config.protocolClasses ?? [])
        var headers = config.httpAdditionalHeaders ?? [:]
        headers.removeValue(forKey: TokenUsageCaptureRegistry.headerField)
        headers[header] = id
        config.httpAdditionalHeaders = headers
        return URLSession(configuration: config, delegate: ScopeAnchor(scope: scope), delegateQueue: nil)
    }

    static func copyConfiguration(of session: URLSession) throws -> URLSessionConfiguration {
        guard let copy = session.configuration.copy() as? URLSessionConfiguration else {
            throw ModelStepFailure(category: .unavailable, code: "configuration_copy_failed",
                message: "The configured HTTP transport could not be copied.", stage: .preparation)
        }
        return copy
    }

    fileprivate static func scope(_ request: URLRequest, task: URLSessionTask?) -> Scope? {
        // The receiving session owns direct requests, including a reused request carrying
        // another scope's header. Native delegate transports retain the header fallback.
        if let anchor = task?.delegate as? ScopeAnchor { return anchor.scope }
        guard let id = request.value(forHTTPHeaderField: header) else { return nil }
        return lock.withLock { scopes[id]?.value }
    }

    private final class ScopeAnchor: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let scope: Scope
        init(scope: Scope) { self.scope = scope }
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            #if canImport(FoundationNetworking)
            completionHandler(.performDefaultHandling, nil)
            #else
            if let delegate = scope.base.delegate, delegate.responds(to: #selector(URLSessionDelegate.urlSession(_:didReceive:completionHandler:))) {
                delegate.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
            } else { completionHandler(.performDefaultHandling, nil) }
            #endif
        }
    }
}

private final class UsageObservationURLProtocol: URLProtocol {
    // FoundationNetworking invokes startLoading on a session work queue. Starting a
    // forwarding session there can synchronously re-enter its shared dispatch target.
    // Own the forwarding lifecycle on a separate serial queue, including cancellation.
    private let forwardingQueue = DispatchQueue(label: "sloppy.usage-observation.forwarding")
    private var activeTask: URLSessionDataTask?
    private var activeSession: URLSession?
    private var bridge: Bridge?
    private var stopped = false
    private var finished = false
    override class func canInit(with request: URLRequest) -> Bool {
        // This protocol is installed only on observed configurations. FoundationNetworking
        // has not applied configuration headers yet; task ownership is available at start.
        request.httpMethod == "POST"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        nonisolated(unsafe) let owner = self // Lifecycle state is confined to forwardingQueue.
        forwardingQueue.async { owner.startForwarding() }
    }
    private func startForwarding() {
        guard !stopped else { return }
        guard let scope = UsageObservedURLSession.scope(request, task: self.task) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown)); return
        }
        var outgoing = request
        let body: Data?
        do {
            var payload = try Self.requestBody(outgoing)
            if let original = payload, outgoing.url?.path.hasSuffix("/chat/completions") == true,
               ["api.openai.com", "openrouter.ai"].contains(outgoing.url?.host ?? ""),
               var object = try? JSONSerialization.jsonObject(with: original) as? [String: Any], object["stream"] as? Bool == true {
                var options = object["stream_options"] as? [String: Any] ?? [:]
                options["include_usage"] = true
                object["stream_options"] = options
                payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                outgoing.setValue(nil, forHTTPHeaderField: "Content-Length")
            }
            body = payload
            if body != nil { outgoing.httpBodyStream = nil; outgoing.httpBody = body }
        } catch { client?.urlProtocol(self, didFailWithError: error); return }
        outgoing.setValue(nil, forHTTPHeaderField: UsageObservedURLSession.header)
        outgoing.setValue(nil, forHTTPHeaderField: TokenUsageCaptureRegistry.headerField)
        let config: URLSessionConfiguration
        do { config = try UsageObservedURLSession.copyConfiguration(of: scope.base) }
        catch { client?.urlProtocol(self, didFailWithError: error); return }
        var forwardingHeaders = config.httpAdditionalHeaders ?? [:]
        forwardingHeaders.removeValue(forKey: UsageObservedURLSession.header)
        forwardingHeaders.removeValue(forKey: TokenUsageCaptureRegistry.headerField)
        config.httpAdditionalHeaders = forwardingHeaders
        // Custom URL protocols on FoundationNetworking see the request before configuration
        // headers are applied. Preserve caller headers while keeping request overrides first.
        for (key, value) in forwardingHeaders {
            guard let name = key as? String, outgoing.value(forHTTPHeaderField: name) == nil else { continue }
            outgoing.setValue(String(describing: value), forHTTPHeaderField: name)
        }
        // Preserve proxy, custom auth/rewriting protocols and trust handling.
        config.protocolClasses = (config.protocolClasses ?? []).filter { $0 != UsageObservationURLProtocol.self }
        let delegate = Bridge(owner: self, scope: scope, body: body)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        bridge = delegate; activeSession = session
        activeTask = session.dataTask(with: outgoing)
        activeTask?.resume()
    }
    private static func requestBody(_ request: URLRequest) throws -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count == 0 { return result }
            guard count > 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
    override func stopLoading() {
        nonisolated(unsafe) let owner = self
        forwardingQueue.async {
            owner.stopped = true
            owner.activeTask?.cancel()
        }
    }
    fileprivate func finish(_ error: Error?) {
        nonisolated(unsafe) let owner = self
        forwardingQueue.async {
            guard !owner.finished else { return }
            owner.finished = true
            if let error { owner.client?.urlProtocol(owner, didFailWithError: error) }
            else { owner.client?.urlProtocolDidFinishLoading(owner) }
            owner.activeSession?.finishTasksAndInvalidate()
            owner.activeTask = nil; owner.bridge = nil; owner.activeSession = nil
        }
    }

    private final class Bridge: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        weak var owner: UsageObservationURLProtocol?
        let scope: UsageObservedURLSession.Scope
        let body: Data?
        let id = UUID().uuidString
        let date = Date()
        var buffer = Data()
        var truncated = false
        var statusCode = 0
        init(owner: UsageObservationURLProtocol, scope: UsageObservedURLSession.Scope, body: Data?) {
            self.owner = owner; self.scope = scope; self.body = body
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let owner { owner.client?.urlProtocol(owner, didReceive: response, cacheStoragePolicy: .notAllowed) }
            completionHandler(.allow)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            let remaining = max(0, 32 * 1024 * 1024 - buffer.count)
            buffer.append(data.prefix(remaining))
            if data.count > remaining { truncated = true }
            if let owner { owner.client?.urlProtocol(owner, didLoad: data) }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            // Await durable accounting before delivering completion to the model/tool loop.
            let response = buffer
            let incomplete = truncated
            let failed = error != nil || statusCode >= 400
            Task { [self] in
                let record = await scope.decoder.record(requestId: id, body: body, response: response,
                    createdAt: date, failed: failed, truncated: incomplete)
                await scope.context.onRequest(record)
                owner?.finish(error)
            }
        }
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            #if canImport(FoundationNetworking)
            completionHandler(.performDefaultHandling, nil)
            #else
            if let delegate = scope.base.delegate, delegate.responds(to: #selector(URLSessionDelegate.urlSession(_:didReceive:completionHandler:))) {
                delegate.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
            } else { completionHandler(.performDefaultHandling, nil) }
            #endif
        }
    }
}
