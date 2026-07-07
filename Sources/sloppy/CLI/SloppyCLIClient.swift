import Foundation
import Protocols
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum CLIClientError: Error, LocalizedError {
    case notConnected(String)
    case httpError(Int, String)
    case noData
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notConnected(let url):
            return "Cannot connect to Sloppy server at \(url). Is it running? Use `sloppy run` to start it."
        case .httpError(let code, let body):
            if let detail = Self.serverErrorDescription(from: body) {
                return "Server returned \(code): \(detail)"
            }
            return "Server returned \(code): \(body)"
        case .noData:
            return "Server returned an empty response."
        case .invalidURL:
            return "Invalid server URL."
        }
    }

    private static func serverErrorDescription(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let code = object["error"] as? String
        if let message = object["message"] as? String, !message.isEmpty {
            if let code, !code.isEmpty {
                return "\(message) (\(code))"
            }
            return message
        }
        return code
    }
}

struct SloppyCLIClient {
    let baseURL: String
    let token: String
    let verbose: Bool
    let localAuthSession: SloppyCLILocalAuthSession?

    private var session: URLSession { .shared }

    static func resolve(url: String?, token: String?, verbose: Bool) -> SloppyCLIClient {
        let resolvedURL = url
            ?? ProcessInfo.processInfo.environment["SLOPPY_URL"]
            ?? loadURLFromConfig()
            ?? "http://127.0.0.1:25101"

        let normalizedURL = resolvedURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let explicitToken = token
            ?? ProcessInfo.processInfo.environment["SLOPPY_TOKEN"]
            ?? loadTokenFromConfig()
        let localAuth = explicitToken == nil ? SloppyCLILocalAuthStore.load(baseURL: normalizedURL) : nil
        let resolvedToken = explicitToken
            ?? localAuth?.accessToken
            ?? "dev-token"

        return SloppyCLIClient(
            baseURL: normalizedURL,
            token: resolvedToken,
            verbose: verbose,
            localAuthSession: localAuth
        )
    }

    init(baseURL: String, token: String, verbose: Bool, localAuthSession: SloppyCLILocalAuthSession? = nil) {
        self.baseURL = baseURL
        self.token = token
        self.verbose = verbose
        self.localAuthSession = localAuthSession
    }

    private static func loadURLFromConfig() -> String? {
        guard let data = loadConfigData(),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let listen = json["listen"] as? [String: Any],
              let host = listen["host"] as? String,
              let port = listen["port"] as? Int
        else { return nil }
        let h = host == "0.0.0.0" ? "127.0.0.1" : host
        return "http://\(h):\(port)"
    }

    private static func loadTokenFromConfig() -> String? {
        guard let data = loadConfigData(),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["auth"] as? [String: Any],
              let token = auth["token"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }

    private static func loadConfigData() -> Data? {
        let candidates = [".sloppy/sloppy.json", "sloppy.json"]
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let home = CoreConfig.resolvedHomeDirectoryPath(fileManager: fm)

        let roots = [home, cwd]
        for root in roots {
            for relative in candidates {
                let path = (root as NSString).appendingPathComponent(relative)
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    return data
                }
            }
        }
        return nil
    }

    func get(_ path: String, query: [String: String] = [:]) async throws -> Data {
        var urlString = baseURL + path
        if !query.isEmpty {
            let qs = query.map { k, v in "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)" }.joined(separator: "&")
            urlString += "?" + qs
        }
        return try await request(method: "GET", urlString: urlString, body: nil)
    }

    func post(_ path: String, body: Data? = nil) async throws -> Data {
        try await request(method: "POST", urlString: baseURL + path, body: body)
    }

    func put(_ path: String, body: Data? = nil) async throws -> Data {
        try await request(method: "PUT", urlString: baseURL + path, body: body)
    }

    func patch(_ path: String, body: Data? = nil) async throws -> Data {
        try await request(method: "PATCH", urlString: baseURL + path, body: body)
    }

    func delete(_ path: String) async throws -> Data {
        try await request(method: "DELETE", urlString: baseURL + path, body: nil)
    }

    func streamAgentSessionEvents(agentID: String, sessionID: String) -> AsyncThrowingStream<AgentSessionStreamUpdate, Error> {
        let path = "/v1/agents/\(Self.escape(agentID))/sessions/\(Self.escape(sessionID))/stream"
        return stream(path: path, as: AgentSessionStreamUpdate.self)
    }

    func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func escape(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
    }

    private func stream<T: Decodable & Sendable>(path: String, as type: T.Type) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
            let task = Task {
                guard let url = URL(string: baseURL + path) else {
                    continuation.finish(throwing: CLIClientError.invalidURL)
                    return
                }
                var request = URLRequest(url: url, timeoutInterval: 60 * 60)
                if !token.isEmpty {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                if verbose {
                    let arrow = CLIStyle.dim("-->")
                    let out = "  \(arrow) GET \(url.absoluteString)\n"
                    FileHandle.standardError.write(Data(out.utf8))
                }

                do {
                    let (lines, response) = try await SloppyCLILineStream.open(request: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: CLIClientError.noData)
                        return
                    }
                    guard httpResponse.statusCode < 400 else {
                        continuation.finish(throwing: CLIClientError.httpError(httpResponse.statusCode, "stream failed"))
                        return
                    }

                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    for try await line in lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst("data: ".count))
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let value = try? decoder.decode(type, from: data) else { continue }
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: CLIClientError.notConnected(baseURL))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func request(method: String, urlString: String, body: Data?) async throws -> Data {
        do {
            return try await sendRequest(method: method, urlString: urlString, body: body, token: token)
        } catch CLIClientError.httpError(let code, _) where code == 401 && localAuthSession != nil {
            guard let refreshedToken = try await refreshLocalAuthSession() else {
                throw CLIClientError.httpError(code, "identity session expired; run `sloppy auth login` again")
            }
            return try await sendRequest(method: method, urlString: urlString, body: body, token: refreshedToken)
        }
    }

    private func sendRequest(method: String, urlString: String, body: Data?, token: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw CLIClientError.invalidURL
        }

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if verbose {
            let arrow = CLIStyle.dim("-->")
            let out = "  \(arrow) \(method) \(urlString)\n"
            FileHandle.standardError.write(Data(out.utf8))
        }

        let startTime = Date()
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw CLIClientError.notConnected(baseURL)
        }

        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let kb = String(format: "%.1f KB", Double(data.count) / 1024.0)
        if verbose {
            let arrow = CLIStyle.dim("<--")
            let status = HTTPURLResponse.localizedString(forStatusCode: statusCode)
            let out = "  \(arrow) \(statusCode) \(status) (\(elapsed)ms, \(kb))\n"
            FileHandle.standardError.write(Data(out.utf8))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIClientError.noData
        }

        if httpResponse.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw CLIClientError.httpError(httpResponse.statusCode, body)
        }

        return data
    }

    private func refreshLocalAuthSession() async throws -> String? {
        guard let localAuthSession else { return nil }
        guard let url = URL(string: baseURL + "/v1/auth/refresh") else {
            throw CLIClientError.invalidURL
        }

        let body = try encode(AuthRefreshRequest(refreshToken: localAuthSession.refreshToken))
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw CLIClientError.notConnected(baseURL)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIClientError.noData
        }
        guard httpResponse.statusCode < 400 else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let refreshed = try decoder.decode(AuthSessionResponse.self, from: data)
        let updated = SloppyCLILocalAuthSession(
            baseURL: baseURL,
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            accessTokenExpiresAt: refreshed.accessTokenExpiresAt,
            refreshTokenExpiresAt: refreshed.refreshTokenExpiresAt,
            user: refreshed.user
        )
        try SloppyCLILocalAuthStore.save(updated)
        return refreshed.accessToken
    }
}

private enum SloppyCLILineStream {
    static func open(request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse) {
        let delegate = SloppyCLILineStreamDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        delegate.attach(session: session, task: task)
        let response = try await delegate.start()
        return (delegate.lines(), response)
    }
}

private final class SloppyCLILineStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    nonisolated(unsafe) private var responseContinuation: CheckedContinuation<URLResponse, Error>?
    nonisolated(unsafe) private var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    nonisolated(unsafe) private var session: URLSession?
    nonisolated(unsafe) private var task: URLSessionDataTask?
    private let chunks: AsyncThrowingStream<Data, Error>

    override init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        self.chunks = AsyncThrowingStream { cont in
            continuation = cont
        }
        self.streamContinuation = continuation
        super.init()
    }

    func attach(session: URLSession, task: URLSessionDataTask) {
        self.session = session
        self.task = task
    }

    func start() async throws -> URLResponse {
        try await withCheckedThrowingContinuation { continuation in
            self.responseContinuation = continuation
            self.task?.resume()
        }
    }

    func lines() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var buffer = Data()
                do {
                    for try await chunk in chunks {
                        buffer.append(chunk)
                        while let newline = buffer.firstIndex(of: 0x0A) {
                            let lineData = buffer[..<newline]
                            buffer.removeSubrange(...newline)
                            var line = String(data: lineData, encoding: .utf8) ?? ""
                            if line.hasSuffix("\r") {
                                line.removeLast()
                            }
                            continuation.yield(line)
                        }
                    }
                    if !buffer.isEmpty,
                       let line = String(data: buffer, encoding: .utf8) {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        responseContinuation?.resume(returning: response)
        responseContinuation = nil
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        streamContinuation?.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let responseContinuation {
            if let error {
                responseContinuation.resume(throwing: error)
            } else if let response = task.response {
                responseContinuation.resume(returning: response)
            } else {
                responseContinuation.resume(throwing: CLIClientError.noData)
            }
            self.responseContinuation = nil
        }

        if let error {
            streamContinuation?.finish(throwing: error)
        } else {
            streamContinuation?.finish()
        }
        self.session?.finishTasksAndInvalidate()
    }
}
