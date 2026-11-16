import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AnyLanguageModel
import Protocols
import Testing
@testable import sloppy

struct KimiProviderTests {
    @Test
    func workspaceEnvironmentParsesLiteralValues() {
        let values = ProviderEnvironment.parse("""
            # Settings for Sloppy Core
            export KIMI_API_KEY = "sk-kimi-test#part" # subscription
            OTHER_KEY=a=b#literal
            TOKEN=${KEEP_LITERAL}
            broken-key=ignored
            UNQUOTED=key # note
            SINGLE='x y # z'
            """)
        #expect(values == [
            "KIMI_API_KEY": "sk-kimi-test#part",
            "OTHER_KEY": "a=b#literal",
            "TOKEN": "${KEEP_LITERAL}",
            "UNQUOTED": "key",
            "SINGLE": "x y # z",
        ])
    }

    @Test(arguments: [
        ("sk-kimi-test", "https://api.kimi.ai/coding/v1/models"),
        ("sk-moonshot-test", "https://api.moonshot.ai/v1/models"),
    ])
    func probeSelectsEndpoint(key: String, expectedURL: String) async {
        let service = ProviderProbeService(
            environmentLookup: { $0 == "KIMI_API_KEY" ? key : nil },
            transport: { request in
                #expect(request.url?.absoluteString == expectedURL)
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
                let url = try #require(request.url)
                let response = try #require(HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil, headerFields: nil
                ))
                return (Data(#"{"data":[{"id":"k3.1-pro"}]}"#.utf8), response)
            }
        )
        let result = await service.probe(config: .test, request: .init(providerId: .kimi))
        #expect(result.ok)
        #expect(result.usedEnvironmentKey)
        #expect(result.models.map(\.id) == ["k3.1-pro"])
    }

    @Test
    func workspaceKeyRegistersDefaultModelAndCanBeOverriddenByServiceEnvironment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "KIMI_API_KEY=sk-kimi-file\nOPENAI_API_KEY=file-key\n".write(
            to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8
        )
        let lookup = ProviderEnvironment.lookup(workspaceRoot: root, processLookup: {
            $0 == "OPENAI_API_KEY" ? "service-key" : nil
        })
        #expect(lookup("KIMI_API_KEY") == "sk-kimi-file")
        #expect(lookup("OPENAI_API_KEY") == "service-key")

        var config = CoreConfig.test
        config.models = []
        config.disableModelInference = false
        config.workspace = .init(name: root.lastPathComponent, basePath: root.deletingLastPathComponent().path)
        let ids = CoreModelProviderFactory.resolveModelIdentifiers(config: config)
        let key = ProcessInfo.processInfo.environment["KIMI_API_KEY"] ?? "sk-kimi-file"
        let expected = "kimi:" + KimiModelProviderFactory.defaultModel(for: key)
        if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            #expect(ids.contains(expected))
            #expect(CoreModelProviderFactory.buildModelProvider(config: config, resolvedModels: ids)?.supports(modelName: expected) == true)
        }

        config.models = [.init(title: "Kimi", apiKey: "", apiUrl: "", model: "k3.1-pro",
                               disabled: true, providerCatalogId: "kimi")]
        #expect(!CoreModelProviderFactory.resolveModelIdentifiers(config: config).contains { $0.hasPrefix("kimi:") })
    }

    @Test(arguments: [
        ("k3.1-pro", "sk-kimi-test", "", nil as Int?, 262_144 as Int?),
        ("kimi-k3.1-pro", "sk-kimi-test", "", nil, 262_144),
        ("kimi-k3.1-pro", "sk-kimi-test", "", 1_048_576, 1_048_576),
        ("k3.1-pro", "sk-moonshot-test", "", nil, nil),
        ("k3.1-pro", "sk-kimi-test", "https://proxy.example/v1", nil, nil),
        ("custom-model", "sk-kimi-test", "", nil, nil),
    ])
    func contextWindowMatchesKimiCodeEndpoint(
        model: String, key: String, apiURL: String, configuredWindow: Int?, expectedWindow: Int?
    ) throws {
        var config = CoreConfig.test
        config.models = [.init(title: "Kimi", apiKey: key, apiUrl: apiURL, model: model,
                               providerCatalogId: "kimi", contextWindowTokens: configuredWindow)]
        let modelID = "kimi:" + model
        let provider = try #require(CoreModelProviderFactory.buildModelProvider(
            config: config, resolvedModels: [modelID]
        ))
        #expect(provider.contextLimits(for: modelID)?.contextWindowTokens == expectedWindow)
    }

    @Test
    func kimiCodeOAuthUsesSameContextWindow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let auth = root.appendingPathComponent("auth", isDirectory: true)
        try FileManager.default.createDirectory(at: auth, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"accessToken":"test-oauth-token"}"#.utf8).write(to: auth.appendingPathComponent("kimi-oauth-auth.json"))

        var config = CoreConfig.test
        config.workspace = .init(name: root.lastPathComponent, basePath: root.deletingLastPathComponent().path)
        // Force the OAuth path even if the test process has KIMI_API_KEY set.
        config.models = [.init(title: "Kimi", apiKey: "$SLOPPY_TEST_MISSING_KIMI_KEY", apiUrl: "",
                               model: "kimi-k3.1-pro", providerCatalogId: "kimi")]
        let modelID = "kimi:kimi-k3.1-pro"
        let provider = try #require(CoreModelProviderFactory.buildModelProvider(
            config: config, resolvedModels: [modelID]
        ))
        #expect(provider.contextLimits(for: modelID)?.contextWindowTokens == 262_144)
    }

    @Test
    func returnsToolReasoningDuringContinuationAndReplaysItOnNextTurn() async throws {
        var config = CoreConfig.test
        config.models = [.init(title: "Kimi", apiKey: "sk-kimi-test", apiUrl: "",
                               model: "k3.1-pro", providerCatalogId: "kimi")]
        let urlConfig = URLSessionConfiguration.ephemeral
        urlConfig.protocolClasses = [KimiToolURLProtocol.self]
        let provider = try #require(CoreModelProviderFactory.buildModelProvider(
            config: config, resolvedModels: ["kimi:k3.1-pro"], proxySession: URLSession(configuration: urlConfig)
        ))
        let modelID = "kimi:k3.1-pro"
        let model = try await provider.createLanguageModel(for: modelID)
        let session = LanguageModelSession(model: model, tools: [KimiEchoTool()])
        let options = provider.generationOptions(for: modelID, maxTokens: 1024, reasoningEffort: nil)
        let first = try await session.respond(to: "Use the tool", options: options)
        #expect(first.content == "Done")
        let second = try await session.respond(to: "Confirm the result", options: options)
        #expect(second.content == "Done")
    }
}

private struct KimiEchoTool: Tool {
    let name = "echo"
    let description = "Echoes its input."
    func call(arguments: String) async throws -> String { arguments }
}

private final class KimiToolURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://api.kimi.ai/coding/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-kimi-test")
            let body = try #require(request.httpBody ?? readBodyStream())
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try #require(json["messages"] as? [[String: Any]])
            #expect(json["model"] as? String == "k3.1-pro")
            #expect(json["max_tokens"] as? Int == 1024)
            #expect(json["max_completion_tokens"] == nil)

            let reply: String
            if let call = messages.first(where: { $0["tool_calls"] != nil }) {
                #expect(call["reasoning_content"] as? String == "Need to use the echo tool.")
                #expect(messages.contains { $0["role"] as? String == "tool" })
                reply = #"{"id":"done","choices":[{"message":{"role":"assistant","content":"Done"},"finish_reason":"stop"}]}"#
            } else {
                reply = #"{"id":"call","choices":[{"message":{"role":"assistant","reasoning_content":"Need to use the echo tool.","tool_calls":[{"id":"call_echo","type":"function","function":{"name":"echo","arguments":"\"test\""}}]},"finish_reason":"tool_calls"}]}"#
            }
            let response = try #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func readBodyStream() -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { return count == 0 ? data : nil }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
