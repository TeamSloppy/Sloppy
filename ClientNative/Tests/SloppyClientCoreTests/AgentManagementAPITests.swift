import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SloppyClientCore

@Suite("Agent management API", .serialized)
struct AgentManagementAPITests {
    @Test("agent management models decode server payloads")
    func modelDecoding() throws {
        let usage = try JSONDecoder().decode(
            AgentTokenUsageResponse.self,
            from: Data(#"{"inputTokens":120,"outputTokens":30,"cachedTokens":40,"cacheCreationTokens":5,"reasoningTokens":7,"totalCostUSD":0.42}"#.utf8)
        )
        #expect(usage.totalTokens == 150)
        #expect(usage.cachedTokens == 40)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let installed = try decoder.decode(
            InstalledAgentSkill.self,
            from: Data(#"{"id":"swift-ui","owner":"acme","repo":"skills","name":"Swift UI","installedAt":"2026-09-17T08:00:00Z","localPath":"skills/swift-ui"}"#.utf8)
        )
        #expect(installed.userInvocable)
        #expect(installed.allowedTools.isEmpty)
    }

    @Test("agent files and skills use encoded routes and mutations")
    func routesAndMutations() async throws {
        let capture = AgentManagementRequestCapture()
        AgentManagementURLProtocol.install { request in
            capture.append(request)
            let path = request.url?.path ?? ""
            let method = request.httpMethod ?? "GET"
            let body: Data

            if path.hasSuffix("/files/content") {
                body = Data("{\"path\":\"skills/ui/SKILL.md\",\"content\":\"# UI\",\"sizeBytes\":4}".utf8)
            } else if path.hasSuffix("/files") {
                body = Data(#"[{"name":"skills","type":"directory"}]"#.utf8)
            } else if path.hasSuffix("/skills"), method == "POST" {
                body = Data(#"{"id":"ui","owner":"acme","repo":"ui","name":"UI","installedAt":"2026-09-17T08:00:00Z","localPath":"skills/ui"}"#.utf8)
            } else {
                body = Data(#"{"success":"true"}"#.utf8)
            }

            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, body)
        }
        defer { AgentManagementURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AgentManagementURLProtocol.self]
        let client = SloppyAPIClient(
            baseURL: URL(string: "https://agents.sloppy.test")!,
            session: URLSession(configuration: configuration),
            authSessionStore: AuthSessionStore(persistence: .memory)
        )

        let entries = try await client.fetchAgentFiles(agentId: "agent/one", path: "skills/ui")
        let content = try await client.fetchAgentFileContent(agentId: "agent/one", path: "skills/ui/SKILL.md")
        let installed = try await client.installAgentSkill(
            agentId: "agent/one",
            request: AgentSkillInstallRequest(owner: "acme", repo: "ui")
        )
        try await client.uninstallAgentSkill(agentId: "agent/one", skillId: "ui/skill")

        #expect(entries.first?.name == "skills")
        #expect(content.content == "# UI")
        #expect(installed.id == "ui")

        let requests = capture.snapshot()
        #expect(requests.count == 4)
        #expect(requests[0].url?.absoluteString.contains("/v1/agents/agent%2Fone/files?path=skills/ui") == true)
        #expect(requests[1].url?.absoluteString.contains("path=skills/ui/SKILL.md") == true)
        #expect(requests[2].httpMethod == "POST")
        #expect(requests[3].httpMethod == "DELETE")
        #expect(requests[3].url?.absoluteString.contains("/skills/ui%2Fskill") == true)

        let payloadData = try #require(requests[2].httpBody ?? requests[2].httpBodyStream?.agentManagementReadAllData())
        let payload = try #require(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        #expect(payload["owner"] as? String == "acme")
        #expect(payload["repo"] as? String == "ui")
    }
}

private final class AgentManagementRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    func snapshot() -> [URLRequest] {
        lock.withLock { requests }
    }
}

private extension InputStream {
    func agentManagementReadAllData() -> Data {
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

private final class AgentManagementURLProtocol: URLProtocol, @unchecked Sendable {
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
