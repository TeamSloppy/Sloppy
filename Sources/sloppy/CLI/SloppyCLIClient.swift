import Foundation
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
            return "Server returned \(code): \(body)"
        case .noData:
            return "Server returned an empty response."
        case .invalidURL:
            return "Invalid server URL."
        }
    }
}

struct SloppyCLIClient {
    let baseURL: String
    let token: String
    let verbose: Bool

    private var session: URLSession { .shared }

    static func resolve(url: String?, token: String?, verbose: Bool) -> SloppyCLIClient {
        let resolvedURL = url
            ?? ProcessInfo.processInfo.environment["SLOPPY_URL"]
            ?? loadURLFromConfig()
            ?? "http://127.0.0.1:25101"

        let resolvedToken = token
            ?? ProcessInfo.processInfo.environment["SLOPPY_TOKEN"]
            ?? loadTokenFromConfig()
            ?? "dev-token"

        return SloppyCLIClient(
            baseURL: resolvedURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            token: resolvedToken,
            verbose: verbose
        )
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
        let candidates = [
            ".sloppy/sloppy.json",
            "sloppy.json"
        ]
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        for relative in candidates {
            let path = (cwd as NSString).appendingPathComponent(relative)
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                return data
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

    func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func request(method: String, urlString: String, body: Data?) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw CLIClientError.invalidURL
        }

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
}
