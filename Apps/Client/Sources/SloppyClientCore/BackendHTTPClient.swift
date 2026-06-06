import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

public enum APIError: Error, Sendable {
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case decodingFailed(String)

    public var statusCode: Int? {
        if case let .httpError(statusCode, _) = self { return statusCode }
        return nil
    }
}

public actor BackendHTTPClient {
    public nonisolated let baseURL: URL

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: Logger

    public init(
        baseURL: URL = URL(string: "http://localhost:25101")!,
        session: URLSession = .shared,
        logger: Logger = Logger(label: "sloppy.backend-http")
    ) {
        self.baseURL = baseURL
        self.session = session
        self.logger = logger

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: str) { return date }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func get<T: Decodable>(_ path: String, timeout: TimeInterval? = nil) async throws -> T {
        let data = try await data(method: "GET", path: path, timeout: timeout)
        return try decode(T.self, from: data)
    }

    public func getData(_ path: String, timeout: TimeInterval? = nil) async throws -> Data {
        try await data(method: "GET", path: path, timeout: timeout)
    }

    public func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        let data = try await data(method: "POST", path: path, body: body)
        return try decode(T.self, from: data)
    }

    public func put<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        let data = try await data(method: "PUT", path: path, body: body)
        return try decode(T.self, from: data)
    }

    public func delete(_ path: String) async throws {
        _ = try await data(method: "DELETE", path: path)
    }

    public nonisolated func url(for path: String) -> URL {
        URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL.appendingPathComponent(path)
    }

    public nonisolated static func encodePathSegment(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    public nonisolated static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func data<Body: Encodable>(
        method: String,
        path: String,
        body: Body? = Optional<EmptyBody>.none,
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        let url = url(for: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let timeout {
            request.timeoutInterval = timeout
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        logger.debug("\(method) \(url.absoluteString)")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = data.isEmpty ? nil : String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }
}

private struct EmptyBody: Encodable {}
