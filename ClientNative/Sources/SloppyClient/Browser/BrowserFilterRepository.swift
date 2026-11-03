import Foundation

/// Downloads data only. A new snapshot is saved only after WebKit compiles it successfully.
actor BrowserFilterRepository {
    static let sourceURL = URL(string: "https://easylist-downloads.adblockplus.org/easylist_content_blocker.json")!
    static let maximumBytes = 20 * 1024 * 1024

    struct Snapshot: Codable, Sendable {
        var json: String
        var checkedAt: Date?
        var etag: String?
        var lastModified: String?
    }

    enum Failure: Error, LocalizedError {
        case invalidResponse, invalidRules
        var errorDescription: String? {
            switch self {
            case .invalidResponse: "The filter server returned an invalid response."
            case .invalidRules: "The downloaded filter list is invalid or too large."
            }
        }
    }

    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let cacheURL: URL
    private let bundledURL: URL?
    private let fetch: Fetch

    init(cacheURL: URL, bundledURL: URL?, fetch: @escaping Fetch = { request in try await BrowserFilterRepository.download(request) }) {
        self.cacheURL = cacheURL
        self.bundledURL = bundledURL
        self.fetch = fetch
    }

    func bundled() throws -> Snapshot {
        guard let bundledURL else { throw Failure.invalidRules }
        return Snapshot(json: try Self.validatedJSON(Data(contentsOf: bundledURL)))
    }

    func cached() -> Snapshot? {
        guard let data = try? Data(contentsOf: cacheURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              (try? Self.validatedJSON(Data(snapshot.json.utf8))) != nil else { return nil }
        return snapshot
    }

    func updated(from previous: Snapshot, now: Date) async throws -> Snapshot {
        var request = URLRequest(url: Self.sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = previous.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified = previous.lastModified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await fetch(request)
        guard let response = response as? HTTPURLResponse, response.url?.scheme == "https" else {
            throw Failure.invalidResponse
        }
        if response.statusCode == 304 {
            var snapshot = previous
            snapshot.checkedAt = now
            return snapshot
        }
        guard response.statusCode == 200 else { throw Failure.invalidResponse }
        return Snapshot(json: try Self.validatedJSON(data), checkedAt: now,
                        etag: response.value(forHTTPHeaderField: "ETag"),
                        lastModified: response.value(forHTTPHeaderField: "Last-Modified"))
    }

    func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: cacheURL, options: .atomic)
    }

    func ruleCount(in snapshot: Snapshot) -> Int {
        (try? JSONSerialization.jsonObject(with: Data(snapshot.json.utf8)) as? [Any])?.count ?? 0
    }

    static func validatedJSON(_ data: Data) throws -> String {
        guard !data.isEmpty, data.count <= maximumBytes,
              let rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !rules.isEmpty, rules.count <= 150_000 else { throw Failure.invalidRules }
        // Updates contain declarative blocking data, never injected scripts or redirects.
        let allowedActions: Set<String> = ["block", "block-cookies", "css-display-none", "ignore-previous-rules", "make-https"]
        for rule in rules {
            guard let trigger = rule["trigger"] as? [String: Any], trigger["url-filter"] is String,
                  let action = rule["action"] as? [String: Any], let type = action["type"] as? String,
                  allowedActions.contains(type) else { throw Failure.invalidRules }
        }
        // A compact, canonical representation allows content-addressed compilation caching.
        return String(decoding: try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]), as: UTF8.self)
    }

    private static func download(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard response.expectedContentLength <= Int64(maximumBytes) else { throw Failure.invalidRules }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw Failure.invalidRules }
            data.append(byte)
        }
        return (data, response)
    }
}
