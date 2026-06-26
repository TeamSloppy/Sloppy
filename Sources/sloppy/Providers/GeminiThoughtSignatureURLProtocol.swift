import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GeminiThoughtSignatureStore: @unchecked Sendable {
    static let shared = GeminiThoughtSignatureStore()

    private struct Entry: Equatable {
        var key: String
        var signature: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    func record(from response: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            return
        }
        var next: [Entry] = []
        collectEntries(from: object, into: &next)
        guard !next.isEmpty else { return }

        lock.lock()
        for entry in next where !entries.contains(entry) {
            entries.append(entry)
        }
        lock.unlock()
    }

    func bodyByRestoringSignatures(in body: Data?) -> Data? {
        guard let body,
              !body.isEmpty,
              var object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return body
        }
        guard var contents = object["contents"] as? [[String: Any]] else {
            return body
        }

        lock.lock()
        let snapshot = entries
        lock.unlock()

        var changed = false
        for contentIndex in contents.indices {
            guard var parts = contents[contentIndex]["parts"] as? [[String: Any]] else {
                continue
            }
            for partIndex in parts.indices {
                guard parts[partIndex]["thoughtSignature"] == nil,
                      let key = Self.callKey(from: parts[partIndex]),
                      let match = snapshot.first(where: { $0.key == key })
                else {
                    continue
                }
                parts[partIndex]["thoughtSignature"] = match.signature
                changed = true
            }
            if changed {
                contents[contentIndex]["parts"] = parts
            }
        }
        guard changed else { return body }
        object["contents"] = contents
        return try? JSONSerialization.data(withJSONObject: object)
    }

    func removeAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    private func collectEntries(from object: [String: Any], into entries: inout [Entry]) {
        guard let candidates = object["candidates"] as? [[String: Any]] else {
            return
        }
        for candidate in candidates {
            guard let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]]
            else {
                continue
            }
            for part in parts {
                guard let signature = part["thoughtSignature"] as? String,
                      !signature.isEmpty,
                      let key = Self.callKey(from: part)
                else {
                    continue
                }
                entries.append(Entry(key: key, signature: signature))
            }
        }
    }

    private static func callKey(from part: [String: Any]) -> String? {
        guard let call = part["functionCall"] as? [String: Any],
              let name = call["name"] as? String
        else {
            return nil
        }
        let args = call["args"] ?? [:]
        let argsData = (try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys])) ?? Data()
        let argsText = String(decoding: argsData, as: UTF8.self)
        return "\(name)\n\(argsText)"
    }
}

final class GeminiThoughtSignatureURLProtocol: URLProtocol {
    private static let handledKey = "sloppy.geminiThoughtSignatureHandled"

    private var activeTask: URLSessionDataTask?
    private var activeSession: URLSession?
    private var activeDelegate: GeminiThoughtSignatureURLProtocolSessionDelegate?
    private var responseBuffer = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else {
            return false
        }
        guard let scheme = request.url?.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return false
        }
        guard let key = request.value(forHTTPHeaderField: "x-goog-api-key"),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }
        return request.url?.path.contains(":generateContent") == true
            || request.url?.path.contains(":streamGenerateContent") == true
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
        let delegate = GeminiThoughtSignatureURLProtocolSessionDelegate(owner: self)
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
            Self.captureThoughtSignatures(from: responseBuffer)
            client?.urlProtocol(self, didLoad: responseBuffer)
            client?.urlProtocolDidFinishLoading(self)
        }
        activeDelegate = nil
        activeSession = nil
        activeTask = nil
        responseBuffer.removeAll(keepingCapacity: false)
    }

    static func modifiedRequest(from request: URLRequest) throws -> URLRequest {
        let mutable = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: handledKey, in: mutable)
        if let restored = GeminiThoughtSignatureStore.shared.bodyByRestoringSignatures(in: request.httpBody) {
            mutable.httpBody = restored
        }
        return mutable as URLRequest
    }

    static func captureThoughtSignatures(from data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        if text.contains("\ndata:") || text.hasPrefix("data:") {
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                guard payload != "[DONE]", !payload.isEmpty else { continue }
                GeminiThoughtSignatureStore.shared.record(from: Data(payload.utf8))
            }
            return
        }
        GeminiThoughtSignatureStore.shared.record(from: data)
    }
}

private final class GeminiThoughtSignatureURLProtocolSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private weak var owner: GeminiThoughtSignatureURLProtocol?

    init(owner: GeminiThoughtSignatureURLProtocol) {
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
