import Foundation
import SloppyClientCore
import Testing
@testable import SloppyFeatureChat

@Test
func turnDiffHasSameStandaloneRowInLiveAndSavedHistory() throws {
    let event = #"""
    {"id":"event-1","type":"run_status","runStatus":{"id":"run-1","stage":"done","label":"Done",
      "turnDiff":{"truncated":false,"files":[
        {"path":"/checkout/A.swift","attribution":"verified","additions":1,"deletions":0,"patch":"+let value = 1"},
        {"path":"/checkout/B.swift","attribution":"interleaved","additions":0,"deletions":0}
      ]}
    }}
    """#
    let decoder = JSONDecoder()
    let saved = try decoder.decode(ChatEventEnvelope.self, from: Data(event.utf8))
    let update = try decoder.decode(ChatStreamUpdate.self,
        from: Data("{\"kind\":\"session_event\",\"cursor\":1,\"event\":\(event)}".utf8))
    let message = try #require(saved.message)
    #expect(message.id == "turn-diff:run-1")
    #expect(update.message?.id == message.id)
    #expect(update.message?.turnDiff == message.turnDiff)
    #expect(message.turnDiff?.files.last?.attribution == .interleaved)
    #expect(ChatTranscriptGrouping.entries(from: [message]).first?.id == "message:turn-diff:run-1")
}
