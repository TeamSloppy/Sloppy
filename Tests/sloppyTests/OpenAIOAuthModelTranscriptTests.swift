import Foundation
import Testing
import AnyLanguageModel
@testable import PluginSDK

@Test
func transcriptToResponsesInputConvertsPromptEntries() {
    let model = OpenAIOAuthModel(bearerToken: "test", model: "gpt-5")
    let transcript = Transcript(entries: [
        .prompt(Transcript.Prompt(segments: [.text(.init(content: "Hello"))]))
    ])

    let items = model.transcriptToResponsesInput(transcript)

    #expect(items.count == 1)
    let item = items[0]
    #expect(item["type"] as? String == "message")
    #expect(item["role"] as? String == "user")
    let content = item["content"] as? [[String: String]]
    #expect(content?.first?["type"] == "input_text")
    #expect(content?.first?["text"] == "Hello")
}

@Test
func transcriptToResponsesInputConvertsResponseEntries() {
    let model = OpenAIOAuthModel(bearerToken: "test", model: "gpt-5")
    let transcript = Transcript(entries: [
        .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Hi there!"))]))
    ])

    let items = model.transcriptToResponsesInput(transcript)

    #expect(items.count == 1)
    let item = items[0]
    #expect(item["type"] as? String == "message")
    #expect(item["role"] as? String == "assistant")
    let content = item["content"] as? [[String: String]]
    #expect(content?.first?["type"] == "output_text")
    #expect(content?.first?["text"] == "Hi there!")
}

@Test
func transcriptToResponsesInputConvertsToolCallEntries() {
    let model = OpenAIOAuthModel(bearerToken: "test", model: "gpt-5")
    let toolCall = Transcript.ToolCall(
        id: "call_123",
        toolName: "project.list",
        arguments: GeneratedContent("{}")
    )
    let transcript = Transcript(entries: [
        .toolCalls(Transcript.ToolCalls([toolCall]))
    ])

    let items = model.transcriptToResponsesInput(transcript)

    #expect(items.count == 1)
    let item = items[0]
    #expect(item["type"] as? String == "function_call")
    #expect(item["call_id"] as? String == "call_123")
    #expect(item["name"] as? String == "project_list")
}

@Test
func transcriptToResponsesInputConvertsToolOutputEntries() {
    let model = OpenAIOAuthModel(bearerToken: "test", model: "gpt-5")
    let output = Transcript.ToolOutput(
        id: "call_123",
        toolName: "project.list",
        segments: [.text(.init(content: "{\"projects\":[]}"))]
    )
    let transcript = Transcript(entries: [.toolOutput(output)])

    let items = model.transcriptToResponsesInput(transcript)

    #expect(items.count == 1)
    let item = items[0]
    #expect(item["type"] as? String == "function_call_output")
    #expect(item["call_id"] as? String == "call_123")
    #expect(item["output"] as? String == "{\"projects\":[]}")
}

@Test
func transcriptToResponsesInputSkipsInstructions() {
    let model = OpenAIOAuthModel(bearerToken: "test", model: "gpt-5")
    let transcript = Transcript(entries: [
        .instructions(Transcript.Instructions(
            segments: [.text(.init(content: "System instructions"))],
            toolDefinitions: []
        )),
        .prompt(Transcript.Prompt(segments: [.text(.init(content: "User message"))]))
    ])

    let items = model.transcriptToResponsesInput(transcript)

    #expect(items.count == 1)
    #expect(items[0]["role"] as? String == "user")
}

@Test
func transcriptToResponsesInputPreservesMultiTurnOrder() {
    let model = OpenAIOAuthModel(bearerToken: "test", model: "gpt-5")
    let transcript = Transcript(entries: [
        .instructions(Transcript.Instructions(
            segments: [.text(.init(content: "You are Sloppy"))],
            toolDefinitions: []
        )),
        .prompt(Transcript.Prompt(segments: [.text(.init(content: "Bootstrap prompt"))])),
        .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Bootstrap response"))])),
        .prompt(Transcript.Prompt(segments: [.text(.init(content: "Привет, поможешь?"))])),
        .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Конечно!"))])),
        .prompt(Transcript.Prompt(segments: [.text(.init(content: "Давай создадим проект"))]))
    ])

    let items = model.transcriptToResponsesInput(transcript)

    #expect(items.count == 5)
    #expect(items[0]["role"] as? String == "user")
    #expect(items[1]["role"] as? String == "assistant")
    #expect(items[2]["role"] as? String == "user")
    #expect(items[3]["role"] as? String == "assistant")
    #expect(items[4]["role"] as? String == "user")
}

@Test
func transcriptToResponsesInputSanitizesToolNames() {
    let model = OpenAIOAuthModel(bearerToken: "test", model: "gpt-5")
    let toolCall = Transcript.ToolCall(
        id: "call_456",
        toolName: "channel.history",
        arguments: GeneratedContent("{}")
    )
    let transcript = Transcript(entries: [
        .toolCalls(Transcript.ToolCalls([toolCall]))
    ])

    let items = model.transcriptToResponsesInput(transcript)

    #expect(items[0]["name"] as? String == "channel_history")
}

@Test
func transcriptToResponsesInputSkipsEmptyAssistantResponses() {
    let model = OpenAIOAuthModel(bearerToken: "test", model: "gpt-5")
    let transcript = Transcript(entries: [
        .response(Transcript.Response(assetIDs: [], segments: []))
    ])

    let items = model.transcriptToResponsesInput(transcript)

    #expect(items.count == 0)
}
