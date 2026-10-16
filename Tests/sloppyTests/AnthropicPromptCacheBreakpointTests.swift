import Foundation
import Testing
@testable import PluginSDK

private func rewritten(_ json: String) throws -> [String: Any] {
    let data = try #require(OAuthAnthropicURLProtocol.bodyByAddingPromptCacheControl(to: Data(json.utf8)))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func breakpointCount(_ value: Any) -> Int {
    if let dict = value as? [String: Any] {
        return (dict["cache_control"] != nil ? 1 : 0) + dict.values.reduce(0) { $0 + breakpointCount($1) }
    }
    if let array = value as? [Any] { return array.reduce(0) { $0 + breakpointCount($1) } }
    return 0
}

@Test
func toolLoopRequestCachesTheGrowingHistoryAndTheStablePrefix() throws {
    let object = try rewritten("""
    {
      "system": "You are an agent.",
      "tools": [{"name": "a", "input_schema": {}}, {"name": "b", "input_schema": {}}],
      "messages": [
        {"role": "user", "content": [{"type": "text", "text": "Fix the bug"}]},
        {"role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": "a", "input": {}}]},
        {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}
      ]
    }
    """)

    let messages = try #require(object["messages"] as? [[String: Any]])
    let first = try #require(messages[0]["content"] as? [[String: Any]])
    let last = try #require(messages[2]["content"] as? [[String: Any]])
    let system = try #require(object["system"] as? [[String: Any]])
    let tools = try #require(object["tools"] as? [[String: Any]])

    #expect(last[0]["cache_control"] != nil, "growing tool history")
    #expect(first[0]["cache_control"] != nil, "stable turn anchor")
    #expect(system.last?["cache_control"] != nil)
    #expect(system.last?["text"] as? String == "You are an agent.")
    #expect(tools.last?["cache_control"] != nil)
    #expect(tools.first?["cache_control"] == nil)
    #expect(breakpointCount(object) == 4)
}

@Test
func breakpointsNeverExceedTheProviderLimitAndKeepExistingOnes() throws {
    let object = try rewritten("""
    {
      "system": [{"type": "text", "text": "S", "cache_control": {"type": "ephemeral"}}],
      "tools": [{"name": "a", "input_schema": {}, "cache_control": {"type": "ephemeral"}}],
      "messages": [
        {"role": "user", "content": [{"type": "text", "text": "one"}]},
        {"role": "assistant", "content": [{"type": "text", "text": "two", "cache_control": {"type": "ephemeral"}}]},
        {"role": "user", "content": [{"type": "text", "text": "three"}]}
      ]
    }
    """)

    #expect(breakpointCount(object) == 4)
    let messages = try #require(object["messages"] as? [[String: Any]])
    let last = try #require(messages[2]["content"] as? [[String: Any]])
    #expect(last[0]["cache_control"] != nil)

    let full = """
    {"system":[{"type":"text","text":"S","cache_control":{"type":"ephemeral"}}],
     "messages":[{"role":"user","content":[{"type":"text","text":"a","cache_control":{"type":"ephemeral"}}]},
                 {"role":"assistant","content":[{"type":"text","text":"b","cache_control":{"type":"ephemeral"}}]},
                 {"role":"user","content":[{"type":"text","text":"c","cache_control":{"type":"ephemeral"}}]}]}
    """
    #expect(OAuthAnthropicURLProtocol.bodyByAddingPromptCacheControl(to: Data(full.utf8)) == nil)
}

@Test
func breakpointsSkipUncacheableBlocks() throws {
    let object = try rewritten("""
    {
      "messages": [
        {"role": "user", "content": [{"type": "text", "text": "ask"}]},
        {"role": "assistant", "content": [
          {"type": "text", "text": "answer"},
          {"type": "thinking", "thinking": "hmm", "signature": "s"}
        ]}
      ]
    }
    """)

    let messages = try #require(object["messages"] as? [[String: Any]])
    let assistant = try #require(messages[1]["content"] as? [[String: Any]])
    #expect(assistant[0]["cache_control"] != nil, "falls back to the last cacheable block")
    #expect(assistant[1]["cache_control"] == nil, "thinking blocks cannot carry cache_control")

    let empty = try rewritten(#"{"messages":[{"role":"user","content":[{"type":"text","text":""},{"type":"text","text":"x"}]}]}"#)
    let content = try #require((empty["messages"] as? [[String: Any]])?[0]["content"] as? [[String: Any]])
    #expect(content[0]["cache_control"] == nil)
    #expect(content[1]["cache_control"] != nil)
}

@Test
func requestsWithoutMessagesOrCacheableContentAreLeftUntouched() {
    #expect(OAuthAnthropicURLProtocol.bodyByAddingPromptCacheControl(to: Data("{}".utf8)) == nil)
    #expect(OAuthAnthropicURLProtocol.bodyByAddingPromptCacheControl(to: Data("not json".utf8)) == nil)
}
