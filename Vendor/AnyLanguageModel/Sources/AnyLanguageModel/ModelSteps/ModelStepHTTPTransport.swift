import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum StepHTTPEvent: Sendable {
    case response(status: Int, headers: [String: String])
    case data(Data)
}

/// Each request owns its task/session. Terminating the consumer cancels the actual network operation.
public struct StepHTTPTransport: Sendable {
    let session: URLSession
    public init(session: URLSession) { self.session = session }

    public static func cacheKeyDigest(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    public static func failure(status: Int, headers: [String: String], body: Data) -> LanguageModelStepFailure {
        let error = (try? JSONDecoder().decode(StepJSONValue.self, from: body))?.asObject?["error"]?.asObject
        let code = error?["code"]?.asString ?? "http_\(status)"
        return .init(category: status == 401 || status == 403 ? .authentication :
            (code == "context_length_exceeded" ? .context : .provider), code: code,
            message: String((error?["message"]?.asString ?? "The model request failed with HTTP \(status).").prefix(2048)),
            retryable: [408, 409, 425, 429].contains(status) || (500...599).contains(status),
            stage: .request, retryAfterSeconds: headers["retry-after"].flatMap(Double.init),
            parameter: error?["param"]?.asString.map { String($0.prefix(256)) })
    }

    public static func normalizedFailure(_ error: any Error) -> LanguageModelStepFailure {
        if let failure = error as? LanguageModelStepFailure { return failure }
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return .init(category: .cancelled, code: "request_cancelled", message: "The model request was cancelled.", stage: .streaming)
        }
        let retryable = (error as? URLError).map {
            [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet, .dnsLookupFailed, .cannotFindHost].contains($0.code)
        } ?? false
        return .init(category: .transport, code: "request_transport_failure", message: error.localizedDescription,
            retryable: retryable, stage: .streaming)
    }

    public func stream(_ request: URLRequest) -> StepHTTPStream {
        .init(lifetime: StepHTTPLifetime(source: StepHTTPDelegate(base: session, request: request)))
    }
}

/// A pull-driven byte stream. Slow consumers accumulate bytes, not an unbounded list of callbacks.
public struct StepHTTPStream: AsyncSequence, Sendable {
    public typealias Element = StepHTTPEvent
    public struct AsyncIterator: AsyncIteratorProtocol {
        fileprivate let lifetime: StepHTTPLifetime
        fileprivate let granted: Bool
        public mutating func next() async throws -> StepHTTPEvent? {
            guard granted else {
                throw LanguageModelStepFailure(category: .protocolViolation, code: "multiple_http_consumers",
                    message: "One HTTP request supports one response consumer.", stage: .streaming)
            }
            return try await lifetime.source.next()
        }
    }
    fileprivate let lifetime: StepHTTPLifetime
    public func makeAsyncIterator() -> AsyncIterator {
        .init(lifetime: lifetime, granted: lifetime.source.claimConsumer())
    }
}

private final class StepHTTPLifetime: @unchecked Sendable {
    let source: StepHTTPDelegate
    public init(source: StepHTTPDelegate) { self.source = source }
    deinit { source.cancel() }
}

/// Lifecycle state is confined to queue. Delegate callbacks synchronously hand off data so
/// neither queued closures nor consumer event counts can bypass the 32 MiB byte ceiling.
private final class StepHTTPDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "any-language-model.step.http")
    private let callbackQueue = DispatchQueue(label: "any-language-model.step.http-callbacks")
    private let base: URLSession
    private let request: URLRequest
    private let cancellation = HTTPRequestCancellation()
    private var started = false
    private var activeSession: URLSession?
    private var activeTask: URLSessionDataTask?
    private var terminal: Result<Void, any Error>?
    private var receivedBytes = 0
    private var receivedResponse = false
    private var consumerClaimed = false
    private var response: StepHTTPEvent?
    private var buffered = Data()
    private var waiter: CheckedContinuation<StepHTTPEvent?, any Error>?

    public init(base: URLSession, request: URLRequest) { self.base = base; self.request = request }

    private func startIfNeeded() {
        guard !started, terminal == nil else { return }
        started = true
        let configuration = self.base.configuration
        var outgoing = request
        for (name, value) in configuration.httpAdditionalHeaders ?? [:] {
            let key = String(describing: name)
            if outgoing.value(forHTTPHeaderField: key) == nil {
                outgoing.setValue(String(describing: value), forHTTPHeaderField: key)
            }
        }
        let callbacks = OperationQueue()
        callbacks.maxConcurrentOperationCount = 1
        callbacks.underlyingQueue = callbackQueue
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: callbacks)
        self.activeSession = session
        let task = session.dataTask(with: outgoing)
        self.activeTask = task
        if cancellation.install(task) { task.resume() }
        else { finish(CancellationError()) }
    }

    public func claimConsumer() -> Bool {
        queue.sync {
            guard !consumerClaimed else { return false }
            consumerClaimed = true
            return true
        }
    }

    public func next() async throws -> StepHTTPEvent? {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard self.waiter == nil else {
                        continuation.resume(throwing: LanguageModelStepFailure(category: .protocolViolation, code: "concurrent_http_reads",
                            message: "An HTTP response already has a pending read.", stage: .streaming))
                        return
                    }
                    self.waiter = continuation
                    self.startIfNeeded()
                    self.drain()
                }
            }
        } onCancel: { self.cancel() }
    }

    public func cancel() {
        cancellation.cancel()
        queue.async { self.finish(CancellationError()) }
    }

    private func drain() {
        guard let waiter else { return }
        if let response {
            self.waiter = nil; self.response = nil
            waiter.resume(returning: response)
        } else if !buffered.isEmpty {
            let chunk = buffered
            buffered = Data(); self.waiter = nil
            waiter.resume(returning: .data(chunk))
        } else if let terminal {
            self.waiter = nil
            switch terminal {
            case .success: waiter.resume(returning: nil)
            case .failure(let error): waiter.resume(throwing: error)
            }
        }
    }

    private func finish(_ error: (any Error)?) {
        guard terminal == nil else { return }
        let task = activeTask
        let session = activeSession
        activeTask = nil; activeSession = nil
        cancellation.finish()
        if let error {
            terminal = .failure(error)
            buffered = Data(); response = nil
        } else {
            terminal = .success(())
        }
        drain()
        // Never wait for URLSession cleanup while its delegate is handing off data to queue.
        DispatchQueue.global(qos: .userInitiated).async {
            if error != nil { task?.cancel(); session?.invalidateAndCancel() }
            else { session?.finishTasksAndInvalidate() }
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive received: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let received = received as? HTTPURLResponse else {
            queue.async { self.finish(URLError(.badServerResponse)) }
            completionHandler(.cancel)
            return
        }
        let headers = Dictionary(received.allHeaderFields.map {
            (String(describing: $0.key).lowercased(), String(describing: $0.value))
        }, uniquingKeysWith: { _, last in last })
        let accepted = queue.sync { () -> Bool in
            guard terminal == nil else { return false }
            guard !receivedResponse else {
                finish(LanguageModelStepFailure(category: .protocolViolation, code: "multiple_http_responses",
                    message: "A request received more than one final HTTP response.", stage: .streaming))
                return false
            }
            receivedResponse = true
            response = .response(status: received.statusCode, headers: headers)
            drain()
            return true
        }
        completionHandler(accepted ? .allow : .cancel)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !data.isEmpty else { return }
        queue.sync {
            guard terminal == nil else { return }
            receivedBytes += data.count
            guard receivedBytes <= 32 * 1024 * 1024 else {
                finish(LanguageModelStepFailure(category: .protocolViolation, code: "http_response_too_large",
                    message: "The model response exceeded the 32 MiB transport limit.", stage: .streaming))
                return
            }
            buffered.append(data)
            drain()
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        queue.async { self.finish(error) }
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        #if canImport(FoundationNetworking)
        completionHandler(.performDefaultHandling, nil)
        #else
        if let delegate = base.delegate, delegate.responds(to: #selector(URLSessionDelegate.urlSession(_:didReceive:completionHandler:))) {
            delegate.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
        } else { completionHandler(.performDefaultHandling, nil) }
        #endif
    }
}

/// Cancellation ownership is installed before resume; synchronous handlers cannot await queue.
private final class HTTPRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var task: URLSessionDataTask?

    public func install(_ task: URLSessionDataTask) -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            self.task = task
            return true
        }
    }
    public func cancel() {
        let active = lock.withLock { cancelled = true; return task }
        active?.cancel()
    }
    public func finish() { lock.withLock { cancelled = true; task = nil } }
}
