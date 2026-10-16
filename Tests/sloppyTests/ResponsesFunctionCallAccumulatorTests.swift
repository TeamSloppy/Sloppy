import AnyLanguageModel
import Foundation
import Testing
@testable import PluginSDK

private func sse(_ json: String) -> String { "data: \(json)" }

private func feed(_ lines: [String]) -> ResponsesFunctionCallAccumulator {
    var accumulator = ResponsesFunctionCallAccumulator()
    for line in lines { accumulator.consume(line: line) }
    return accumulator
}

private func added(_ index: Int, id: String, callId: String, name: String) -> String {
    sse(#"{"type":"response.output_item.added","output_index":\#(index),"item":{"type":"function_call","id":"\#(id)","call_id":"\#(callId)","name":"\#(name)","arguments":""}}"#)
}

private func delta(_ index: Int, id: String, _ text: String) -> String {
    let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    return sse(#"{"type":"response.function_call_arguments.delta","output_index":\#(index),"item_id":"\#(id)","delta":"\#(escaped)"}"#)
}

private func done(_ index: Int, id: String, arguments: String) -> String {
    let escaped = arguments.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    return sse(#"{"type":"response.function_call_arguments.done","output_index":\#(index),"item_id":"\#(id)","arguments":"\#(escaped)"}"#)
}

@Test
func accumulatorRestoresFourInterleavedParallelCalls() {
    let args = [
        #"{"path":"a.swift"}"#,
        #"{"server":"studio","tool":"editor.skills.read"}"#,
        #"{"query":"bird"}"#,
        #"{"command":"swift build"}"#,
    ]
    let names = ["files.read", "mcp.call", "files.grep", "runtime.exec"]
    var lines: [String] = []
    for i in 0..<4 { lines.append(added(i, id: "fc_\(i)", callId: "call_\(i)", name: names[i])) }
    // Deltas for different items arrive interleaved, split mid-token.
    for i in 0..<4 { lines.append(delta(i, id: "fc_\(i)", String(args[i].prefix(5)))) }
    for i in (0..<4).reversed() { lines.append(delta(i, id: "fc_\(i)", String(args[i].dropFirst(5)))) }
    for i in 0..<4 { lines.append(done(i, id: "fc_\(i)", arguments: args[i])) }
    lines.append(sse(#"{"type":"response.completed","response":{"id":"r"}}"#))

    let calls = feed(lines).calls
    #expect(calls.map(\.callId) == ["call_0", "call_1", "call_2", "call_3"])
    #expect(calls.map(\.name) == names)
    #expect(calls.map(\.arguments) == args)
}

@Test
func accumulatorHandlesSequentialCalls() {
    let lines = [
        added(0, id: "fc_0", callId: "call_0", name: "files.read"),
        delta(0, id: "fc_0", #"{"path":"x"}"#),
        done(0, id: "fc_0", arguments: #"{"path":"x"}"#),
        added(1, id: "fc_1", callId: "call_1", name: "files.read"),
        delta(1, id: "fc_1", #"{"path":"y"}"#),
        done(1, id: "fc_1", arguments: #"{"path":"y"}"#),
    ]
    let calls = feed(lines).calls
    #expect(calls.map(\.arguments) == [#"{"path":"x"}"#, #"{"path":"y"}"#])
}

@Test
func accumulatorPrefersDoneArgumentsOverLostDeltas() {
    let lines = [
        added(0, id: "fc_0", callId: "call_0", name: "files.read"),
        done(0, id: "fc_0", arguments: #"{"path":"x"}"#),
    ]
    #expect(feed(lines).calls.first?.arguments == #"{"path":"x"}"#)
}

@Test
func accumulatorRecoversArgumentsFromOutputItemDone() {
    let lines = [
        added(0, id: "fc_0", callId: "call_0", name: "files.read"),
        sse(#"{"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_0","call_id":"call_0","name":"files.read","arguments":"{\"path\":\"z\"}"}}"#),
    ]
    #expect(feed(lines).calls.first?.arguments == #"{"path":"z"}"#)
}

@Test
func accumulatorKeepsEmptyArgumentsVisibleAsInvalid() {
    let lines = [
        added(0, id: "fc_0", callId: "call_0", name: "files.read"),
        done(0, id: "fc_0", arguments: ""),
    ]
    let calls = feed(lines).calls
    #expect(calls.count == 1)
    #expect(!ResponsesFunctionCallAccumulator.isJSONObject(calls[0].arguments))
    #expect(ResponsesFunctionCallAccumulator.isJSONObject("{}"))
    #expect(!ResponsesFunctionCallAccumulator.isJSONObject("[1]"))
}

@Test
func accumulatorIgnoresNonFunctionItems() {
    let lines = [
        sse(#"{"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"m"}}"#),
        sse(#"{"type":"response.output_text.delta","delta":"hi"}"#),
    ]
    #expect(feed(lines).calls.isEmpty)
}

@Test
func oauthRequestAsksForParallelToolCallsUntilDisabled() throws {
    let control = ParallelToolCallsControl()
    let model = OpenAIOAuthModel(bearerToken: "t", model: "gpt-5", parallelToolCalls: control)
    let tool: [String: Any] = ["type": "function", "name": "files_read", "parameters": ["type": "object"]]
    func flag() throws -> Bool? {
        let data = try model.buildRequestBodyForTesting(transcript: Transcript(entries: []), options: GenerationOptions(), tools: [tool])
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["parallel_tool_calls"] as? Bool
    }
    #expect(try flag() == true)
    model.noteMalformedCallsForTesting([ResponsesFunctionCall(callId: "c", name: "files_read", arguments: "")])
    #expect(try flag() == false)
}

@Test
func oauthWellFormedCallsKeepParallelToolCalls() {
    let control = ParallelToolCallsControl()
    let model = OpenAIOAuthModel(bearerToken: "t", model: "gpt-5", parallelToolCalls: control)
    model.noteMalformedCallsForTesting([ResponsesFunctionCall(callId: "c", name: "n", arguments: "{}")])
    #expect(control.isEnabled)
}

@Test
func oauthClassifiesUnsupportedModelRejection() {
    let model = OpenAIOAuthModel(bearerToken: "t", model: "gpt-5.5")
    let body = #"{"detail":"The 'gpt-5.5' model is not supported when using Codex with a ChatGPT account."}"#
    let error = model.classifyHTTPErrorForTesting(statusCode: 400, body: body)
    #expect(error.surfaced is ProviderModelNotSupportedError)
    let other = model.classifyHTTPErrorForTesting(statusCode: 400, body: #"{"detail":"bad input"}"#)
    #expect(!(other.surfaced is ProviderModelNotSupportedError))
}

@Test
func followUpDoesNotReplayCurrentRoundTwice() throws {
    let model = OpenAIOAuthModel(bearerToken: "t", model: "gpt-5")
    let call = ResponsesFunctionCall(callId: "call_1", name: "files_read", arguments: #"{"path":"a"}"#)
    let toolCall = Transcript.ToolCall(id: "call_1", toolName: "files_read", arguments: GeneratedContent(properties: ["path": "a"]))
    let output = Transcript.ToolOutput(id: "call_1", toolName: "files_read", segments: [.text(.init(content: "ok"))])
    let data = try model.buildFollowUpRequestBodyForTesting(
        transcript: Transcript(entries: []),
        accumulatedEntries: [.toolCalls(Transcript.ToolCalls([toolCall])), .toolOutput(output)],
        functionCalls: [call],
        toolOutputs: [(callId: "call_1", output: "ok")]
    )
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let input = try #require(body["input"] as? [[String: Any]])
    #expect(input.filter { $0["type"] as? String == "function_call" }.count == 1)
    #expect(input.filter { $0["type"] as? String == "function_call_output" }.count == 1)
}
