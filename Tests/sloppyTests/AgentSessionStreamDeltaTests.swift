import Testing
@testable import sloppy

@Test
func sessionStreamExtractsOnlyNewTextFromCumulativeSnapshots() {
    #expect(AgentSessionStreamDelta.extract(previous: "", snapshot: "Пр") == "Пр")
    #expect(AgentSessionStreamDelta.extract(previous: "Пр", snapshot: "Привет") == "ивет")
    #expect(AgentSessionStreamDelta.extract(previous: "Привет", snapshot: "Привет мир") == " мир")
    #expect(AgentSessionStreamDelta.extract(previous: "Привет мир", snapshot: "Привет мир") == "")
}

@Test
func sessionStreamPreservesNonCumulativeChunkAndWhitespace() {
    #expect(AgentSessionStreamDelta.extract(previous: "Привет", snapshot: "!") == "!")
    #expect(AgentSessionStreamDelta.extract(previous: "Привет", snapshot: " ") == " ")
}
