import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols
import Testing
@testable import sloppy

private final class JevMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
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

private struct FixedSemanticDecisionProvider: SemanticDecisionProvider {
    var response: SemanticChoiceResponse

    func choose(_ request: SemanticChoiceRequest) async throws -> SemanticChoiceResponse {
        response
    }
}

private func jevTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [JevMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func jevRequestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data.isEmpty ? nil : data
}

@Suite("Semantic decisions", .serialized)
struct SemanticDecisionTests {
    @Test("legacy configs keep semantic decisions disabled")
    func legacyConfigDefaults() throws {
        let encoded = try JSONEncoder().encode(CoreConfig.test)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "semanticDecisions")

        let decoded = try JSONDecoder().decode(
            CoreConfig.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.semanticDecisions.provider == nil)
        #expect(decoded.semanticDecisions.executorModelRouting == .disabled)
        #expect(decoded.semanticDecisions.modelProfiles.isEmpty)
    }

    @Test("semantic decision config accepts a Dashboard API key and older payloads without it")
    func configAPIKeyRoundTripAndCompatibility() throws {
        let configured = CoreConfig.SemanticDecisions(
            provider: .typeSafe,
            apiKey: "dashboard-key",
            executorModelRouting: .shadow,
            modelProfiles: [
                "fast": .init(model: "mock:fast", description: "Routine"),
                "senior": .init(model: "mock:senior", description: "Complex"),
            ]
        )
        let encoded = try JSONEncoder().encode(configured)
        let decoded = try JSONDecoder().decode(CoreConfig.SemanticDecisions.self, from: encoded)
        #expect(decoded.apiKey == "dashboard-key")
        #expect(SemanticModelRouter.defaultProvider(config: decoded) != nil)

        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "apiKey")
        let legacy = try JSONDecoder().decode(
            CoreConfig.SemanticDecisions.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(legacy.apiKey.isEmpty)
        #expect(legacy.executorModelRouting == .shadow)
    }

    @Test("JEV adapter reads a typed choice and provider-reported Vercel cost")
    func jevChoiceAndReportedCost() async throws {
        JevMockURLProtocol.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            let body = try #require(jevRequestBody(request))
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["model"] as? String == "typesafe-ai/jev")
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ))
            let data = Data(
                """
                {
                  "model": "typesafe-ai/jev",
                  "answers": {
                    "executor_profile": {
                      "type": "choice",
                      "choice": "senior",
                      "confidence": 0.91,
                      "probabilities": { "fast": 0.09, "senior": 0.91 }
                    }
                  },
                  "usage": { "input_tokens": 275, "output_tokens": 20 },
                  "provider_metadata": { "gateway": { "cost": "0.00001155" } }
                }
                """.utf8
            )
            return (response, data)
        }
        defer { JevMockURLProtocol.requestHandler = nil }

        let provider = JevSemanticDecisionProvider(
            endpoint: try #require(URL(string: "https://example.test/typesafe/v1/systemone")),
            apiKey: "test-key",
            model: "typesafe-ai/jev",
            timeoutMs: 1_000,
            inputCostPerMillionTokensUSD: 0.042,
            session: jevTestSession()
        )
        let result = try await provider.choose(
            SemanticChoiceRequest(
                state: "{}",
                questionID: "executor_profile",
                instructions: "Choose a profile.",
                choices: ["fast": "Routine", "senior": "Complex"]
            )
        )

        #expect(result.choice == "senior")
        #expect(result.confidence == 0.91)
        #expect(result.usage.inputTokens == 275)
        #expect(result.usage.costUSD == 0.00001155)
        #expect(result.usage.costIsEstimated == false)
    }

    @Test("direct JEV cost is estimated from input tokens")
    func directCostEstimate() async throws {
        JevMockURLProtocol.requestHandler = { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ))
            return (
                response,
                Data("""
                {
                  "answers": {
                    "executor_profile": {
                      "choice": "fast",
                      "confidence": 0.8,
                      "probabilities": { "fast": 0.8, "senior": 0.2 }
                    }
                  },
                  "usage": { "input_tokens": 1000000, "output_tokens": 10 }
                }
                """.utf8)
            )
        }
        defer { JevMockURLProtocol.requestHandler = nil }

        let provider = JevSemanticDecisionProvider(
            endpoint: try #require(URL(string: "https://example.test/v1/systemone")),
            apiKey: "test-key",
            model: "jev-latest",
            timeoutMs: 1_000,
            inputCostPerMillionTokensUSD: 0.042,
            session: jevTestSession()
        )
        let result = try await provider.choose(
            SemanticChoiceRequest(
                state: "{}",
                questionID: "executor_profile",
                instructions: "Choose a profile.",
                choices: ["fast": "Routine", "senior": "Complex"]
            )
        )

        #expect(result.usage.costUSD == 0.042)
        #expect(result.usage.costIsEstimated)
    }

    @Test("active routing applies an eligible confident profile and meters usage")
    func activeModelRouting() async throws {
        let usageMeter = SemanticDecisionUsageMeter()
        let fixed = FixedSemanticDecisionProvider(
            response: SemanticChoiceResponse(
                choice: "senior",
                confidence: 0.92,
                probabilities: ["fast": 0.08, "senior": 0.92],
                usage: .init(inputTokens: 300, outputTokens: 15, costUSD: 0.0000126, costIsEstimated: true)
            )
        )
        let config = CoreConfig.SemanticDecisions(
            provider: .typeSafe,
            executorModelRouting: .active,
            minimumConfidence: 0.75,
            modelProfiles: [
                "fast": .init(model: "mock:fast", description: "Routine work"),
                "senior": .init(model: "mock:senior", description: "Complex work"),
            ]
        )
        let router = SemanticModelRouter(
            config: config,
            usageMeter: usageMeter,
            providerFactory: { _ in fixed }
        )

        let route = await router.route(
            channelID: "agent:a:session:s",
            userRequest: "Diagnose a concurrency crash",
            chatMode: .debug,
            attachmentTypes: ["text/plain"],
            availableModelIDs: ["mock:fast", "mock:senior"]
        )
        let usage = await usageMeter.snapshot(channelID: "agent:a:session:s")

        #expect(route?.profile == "senior")
        #expect(route?.model == "mock:senior")
        #expect(route?.shouldApply == true)
        #expect(usage?.requestCount == 1)
        #expect(usage?.totalCostUSD == 0.0000126)
        #expect(usage?.includesEstimatedCost == true)
    }

    @Test("shadow routing records spend without applying the selected model")
    func shadowModelRouting() async {
        let usageMeter = SemanticDecisionUsageMeter()
        let fixed = FixedSemanticDecisionProvider(
            response: .init(
                choice: "fast",
                confidence: 0.99,
                probabilities: ["fast": 0.99, "senior": 0.01],
                usage: .init(inputTokens: 50, outputTokens: 5, costUSD: 0.0000021, costIsEstimated: true)
            )
        )
        let router = SemanticModelRouter(
            config: .init(
                provider: .typeSafe,
                executorModelRouting: .shadow,
                modelProfiles: [
                    "fast": .init(model: "mock:fast", description: "Routine work"),
                    "senior": .init(model: "mock:senior", description: "Complex work"),
                ]
            ),
            usageMeter: usageMeter,
            providerFactory: { _ in fixed }
        )

        let route = await router.route(
            channelID: "agent:a:session:shadow",
            userRequest: "Answer a simple question",
            chatMode: .ask,
            attachmentTypes: [],
            availableModelIDs: ["mock:fast", "mock:senior"]
        )

        #expect(route?.profile == "fast")
        #expect(route?.shouldApply == false)
        #expect(await usageMeter.snapshot(channelID: "agent:a:session:shadow")?.requestCount == 1)
    }

    @Test("context status shows JEV calls and estimated spend")
    func contextStatusShowsJevSpend() {
        let summary = SloppyTUIContextUsageSummary(
            modelTitle: "Test model",
            modelID: "mock:test",
            contextWindowLabel: "32K",
            promptTokens: 1_000,
            completionTokens: 100,
            totalTokens: 1_100,
            contextWindowTokens: 32_000,
            pendingContextAttached: false,
            pendingUploadCount: 0,
            semanticDecisionUsage: SemanticDecisionUsage(
                requestCount: 3,
                inputTokens: 1_200,
                outputTokens: 60,
                totalCostUSD: 0.0042,
                estimatedCostUSD: 0.0042
            )
        )

        let markdown = SloppyTUITheme.contextUsageMarkdown(summary)

        #expect(markdown.contains("JEV decisions:"))
        #expect(markdown.contains("3 calls"))
        #expect(markdown.contains("1.2K input tokens"))
        #expect(markdown.contains("~$0.0042"))
    }
}
