import AnyLanguageModel
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PluginSDK
import Protocols

@Suite("OAuth stateless continuation", .serialized)
struct OpenAIOAuthContinuationTests {
    @Test(arguments: [false, true])
    func preservesWorkingStateAcrossToolRounds(streaming: Bool) async throws {
        OAuthContinuationURLProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OAuthContinuationURLProtocol.self]
        let http = URLSession(configuration: config)
        defer { http.invalidateAndCancel() }
        let model = OpenAIOAuthModel(bearerToken: "test", model: "gpt-6.1-sol", session: http)
        let session = LanguageModelSession(model: model)
        session.toolExecutionDelegate = SloppyToolExecutionDelegate { request in
            .init(tool: request.tool, ok: true, data: .string("checked"))
        }
        var options = GenerationOptions()
        options[custom: OpenAILanguageModel.self] = .init(reasoningEffort: .max)
        if streaming {
            var last = ""
            for try await snapshot in session.streamResponse(to: "Implement and verify", generating: String.self, options: options) {
                last = snapshot.content
            }
            #expect(last == "Verified and finished.")
        } else {
            let response = try await session.respond(to: "Implement and verify", generating: String.self, options: options)
            #expect(response.content == "Verified and finished.")
        }
        let requests = OAuthContinuationURLProtocol.requests
        #expect(requests.count == 3)
        for data in requests {
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect((body["reasoning"] as? [String: String])?["effort"] == "max")
            #expect(body["include"] as? [String] == ["reasoning.encrypted_content"])
        }
        let lastRequest = try #require(requests.last)
        let body = try #require(JSONSerialization.jsonObject(with: lastRequest) as? [String: Any])
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.compactMap { $0["type"] as? String } == [
            "message", "reasoning", "message", "function_call", "function_call_output",
            "reasoning", "message", "function_call", "function_call_output",
        ])
        #expect(input[1]["encrypted_content"] as? String == "opaque-0")
        #expect(input[2]["phase"] as? String == "commentary")
        #expect(input[5]["encrypted_content"] as? String == "opaque-1")
        #expect(input[6]["phase"] as? String == "commentary")
        #expect(input[3]["call_id"] as? String == input[4]["call_id"] as? String)
        #expect(input[7]["call_id"] as? String == input[8]["call_id"] as? String)
    }

    @Test(arguments: ["low", "medium", "high", "xhigh", "max"])
    func sendsSelectedEffortInInitialAndFollowUpRequests(effort: String) throws {
        let model = OpenAIOAuthModel(bearerToken: "test", model: "gpt-6.1-sol", reasoningCapture: ReasoningContentCapture())
        var options = GenerationOptions()
        let level = try #require(OpenAILanguageModel.CustomGenerationOptions.ReasoningEffort(rawValue: effort))
        options[custom: OpenAILanguageModel.self] = .init(reasoningEffort: level)
        let first = try model.buildRequestBodyForTesting(transcript: .init(entries: []), options: options)
        let next = try model.buildFollowUpRequestBodyForTesting(
            transcript: .init(entries: []), accumulatedEntries: [], functionCalls: [], toolOutputs: [], options: options
        )
        for data in [first, next] {
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let reasoning = try #require(body["reasoning"] as? [String: String])
            #expect(reasoning == ["effort": effort, "summary": "auto"])
        }
    }

    @Test func recoversCompletedOutputInOrderWithoutResponseEnvelope() throws {
        var accumulator = ResponsesOutputAccumulator()
        accumulator.consume(line: #"data: {"type":"response.output_item.done","output_index":1,"item":{"type":"message","phase":"commentary","content":[]}}"#)
        accumulator.consume(line: #"data: {"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","encrypted_content":"opaque","summary":[]}}"#)
        #expect(accumulator.items.compactMap { $0["type"] as? String } == ["reasoning", "message"])
        #expect(accumulator.items.first?["encrypted_content"] as? String == "opaque")
        accumulator.consume(line: #"data: {"type":"response.completed","response":{"output":[{"type":"message","phase":"final_answer","content":[]}]}}"#)
        #expect(accumulator.items.count == 1)
        #expect(accumulator.items.first?["phase"] as? String == "final_answer")
    }

    @Test func malformedArgumentsRemainReplayableForToolErrorRecovery() {
        var accumulator = ResponsesOutputAccumulator()
        accumulator.consume(line: #"data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","call_id":"broken","name":"files_read","arguments":""}}"#)
        #expect(accumulator.items.first?["arguments"] as? String == "{}")
    }

    @Test(arguments: [ReasoningEffort.high, .xhigh, .max])
    func providerPreservesEffortThroughOAuthWireRequest(effort: ReasoningEffort) throws {
        let provider = OpenAIModelProvider(supportedModels: ["openai-oauth:gpt-6.1-sol"],
            settings: .init(apiKey: { "test" }, useOpenAICodexOAuthPath: true))
        let options = provider.generationOptions(for: "openai-oauth:gpt-6.1-sol", maxTokens: 4096, reasoningEffort: effort)
        let model = OpenAIOAuthModel(bearerToken: "test", model: "gpt-6.1-sol")
        let data = try model.buildRequestBodyForTesting(transcript: .init(entries: []), options: options)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((body["reasoning"] as? [String: String])?["effort"] == effort.rawValue)
        #expect(try JSONDecoder().decode(ReasoningEffort.self, from: JSONEncoder().encode(effort)) == effort)
    }
}

private final class OAuthContinuationURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recordedRequests: [Data] = []
    static var requests: [Data] {
        get { lock.withLock { recordedRequests } }
        set { lock.withLock { recordedRequests = newValue } }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(buffer, count: count)
                }
            }
            let round = Self.lock.withLock { () -> Int in
                let index = Self.recordedRequests.count
                Self.recordedRequests.append(body)
                return index
            }
            let text = round < 2 ? "Progress \(round)." : "Verified and finished."
            var output: [[String: Any]] = []
            if round < 2 {
                output.append(["id": "rs_\(round)", "type": "reasoning", "encrypted_content": "opaque-\(round)", "summary": []])
            }
            output.append(["id": "msg_\(round)", "type": "message", "role": "assistant", "phase": round < 2 ? "commentary" : "final_answer",
                           "content": [["type": "output_text", "text": text, "annotations": []]]])
            if round < 2 {
                output.append(["id": "fc_\(round)", "type": "function_call", "call_id": "call_\(round)", "name": "files_read", "arguments": "{\"path\":\"source.swift\"}"])
            }
            var events: [[String: Any]] = [["type": "response.output_text.delta", "delta": text]]
            for (index, item) in output.enumerated() {
                events.append(["type": "response.output_item.done", "output_index": index, "item": item])
            }
            events.append(["type": "response.completed", "response": ["id": "resp_\(round)", "output": output]])
            let data = try events.reduce(into: Data()) { data, event in
                data.append(Data("data: ".utf8))
                data.append(try JSONSerialization.data(withJSONObject: event))
                data.append(Data("\n\n".utf8))
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
