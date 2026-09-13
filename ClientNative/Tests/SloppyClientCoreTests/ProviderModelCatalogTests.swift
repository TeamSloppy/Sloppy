import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SloppyClientCore

@Suite("Provider model catalog", .serialized)
struct ProviderModelCatalogTests {
    @Test("Codex device sign-in uses the connected server and returns polling status")
    func codexDeviceSignIn() async throws {
        let capture = ProviderModelRequestCapture()
        ProviderModelURLProtocol.install { request in
            capture.append(request)
            let payload: String
            switch request.url?.path {
            case "/v1/providers/openai/oauth/device-code/start":
                payload = #"{"deviceAuthId":"device-id","userCode":"ABCD-EFGH","verificationURL":"https://auth.openai.com/codex/device","interval":5,"expiresIn":600}"#
            case "/v1/providers/openai/oauth/device-code/poll":
                payload = #"{"status":"approved","ok":true,"message":"Connected","accountId":"account","planType":"plus"}"#
            case "/v1/providers/openai/status":
                payload = #"{"hasOAuthCredentials":true,"oauthPlanType":"plus"}"#
            default:
                Issue.record("Unexpected endpoint")
                payload = "{}"
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(payload.utf8))
        }
        defer { ProviderModelURLProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderModelURLProtocol.self]
        let client = SloppyAPIClient(baseURL: URL(string: "https://models.sloppy.test")!, session: URLSession(configuration: configuration), authSessionStore: AuthSessionStore(persistence: .memory))
        let device = try await client.startCodexDeviceAuthorization()
        #expect(device.userCode == "ABCD-EFGH")
        let result = try await client.pollCodexDeviceAuthorization(device)
        #expect(result.ok)
        #expect(result.status == "approved")
        #expect(try await client.fetchCodexAuthorizationStatus().hasOAuthCredentials)
        let body = try requestJSON(capture.snapshot()[1])
        #expect(body["deviceAuthId"] as? String == "device-id")
        #expect(body["userCode"] as? String == "ABCD-EFGH")
        #expect(capture.snapshot().count == 3)
    }

    @Test("Sloppy catalog authentication errors remain visible")
    func remoteCatalogFailure() async throws {
        ProviderModelURLProtocol.install { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"ok":false,"message":"Sloppy server returned HTTP 401","models":[]}"#.utf8))
        }
        defer { ProviderModelURLProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderModelURLProtocol.self]
        let client = SloppyAPIClient(baseURL: URL(string: "https://models.sloppy.test")!, session: URLSession(configuration: configuration), authSessionStore: AuthSessionStore(persistence: .memory))
        do {
            _ = try await client.fetchProviderModels(providerId: "sloppy", apiKey: "wrong", apiUrl: "https://remote.example")
            Issue.record("Expected visible authorization failure")
        } catch {
            #expect(error.localizedDescription.contains("401"))
        }
    }

    @Test("uses provider-specific model catalog endpoints and payloads")
    func fetchesProviderModels() async throws {
        let baseURL = try #require(URL(string: "https://models.sloppy.test"))
        let capture = ProviderModelRequestCapture()

        ProviderModelURLProtocol.install { request in
            capture.append(request)
            let body: Data
            switch request.url?.path {
            case "/v1/providers/openai/models":
                body = Data(
                    #"{"models":[{"id":"gpt-5.4-mini","title":"GPT-5.4 mini","capabilities":["tools"]}]}"#.utf8
                )
            case "/v1/providers/probe":
                body = Data(
                    #"{"models":[{"id":"claude-sonnet-4","title":"Claude Sonnet 4","capabilities":[]}]}"#.utf8
                )
            default:
                body = Data()
            }
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? baseURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, body)
        }
        defer { ProviderModelURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderModelURLProtocol.self]
        let client = SloppyAPIClient(
            baseURL: baseURL,
            session: URLSession(configuration: configuration),
            authSessionStore: AuthSessionStore(persistence: .memory)
        )

        let openAIModels = try await client.fetchProviderModels(
            providerId: "openai-api",
            apiKey: "openai-key",
            apiUrl: "https://api.openai.com/v1"
        )
        let anthropicModels = try await client.fetchProviderModels(
            providerId: "anthropic",
            apiKey: "anthropic-key",
            apiUrl: "https://api.anthropic.com"
        )

        #expect(openAIModels.map(\.id) == ["gpt-5.4-mini"])
        #expect(anthropicModels.map(\.id) == ["claude-sonnet-4"])

        let requests = capture.snapshot()
        #expect(requests.map(\.path) == [
            "/v1/providers/openai/models",
            "/v1/providers/probe",
        ])

        let openAIBody = try requestJSON(requests[0])
        #expect(openAIBody["authMethod"] as? String == "api_key")
        #expect(openAIBody["apiKey"] as? String == "openai-key")

        let anthropicBody = try requestJSON(requests[1])
        #expect(anthropicBody["providerId"] as? String == "anthropic")
        #expect(anthropicBody["apiKey"] as? String == "anthropic-key")
    }

    private func requestJSON(_ request: CapturedProviderModelRequest) throws -> [String: Any] {
        let body = try #require(request.body)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}

private struct CapturedProviderModelRequest: Sendable {
    var path: String?
    var body: Data?
}

private final class ProviderModelRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [CapturedProviderModelRequest] = []

    func append(_ request: URLRequest) {
        let captured = CapturedProviderModelRequest(
            path: request.url?.path,
            body: request.httpBody ?? request.httpBodyStream?.readAllData()
        )
        lock.withLock { requests.append(captured) }
    }

    func snapshot() -> [CapturedProviderModelRequest] {
        lock.withLock { requests }
    }
}

private extension InputStream {
    func readAllData() -> Data {
        open()
        defer { close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while hasBytesAvailable {
            let count = read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class ProviderModelURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func install(_ handler: @escaping Handler) {
        lock.withLock { self.handler = handler }
    }

    static func reset() {
        lock.withLock { handler = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock { Self.handler }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
