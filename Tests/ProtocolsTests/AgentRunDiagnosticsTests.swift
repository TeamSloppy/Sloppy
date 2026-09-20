import Foundation
import Testing
@testable import Protocols

@Test
func runStatusDecodesLegacyPayloadWithoutDiagnostics() throws {
    let payload = Data(#"""
    {
        "id": "status-1",
        "stage": "done",
        "label": "Done",
        "createdAt": "2026-09-19T12:00:00Z"
    }
    """#.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let status = try decoder.decode(AgentRunStatusEvent.self, from: payload)

    #expect(status.id == "status-1")
    #expect(status.stage == .done)
    #expect(status.diagnostics == nil)
}

@Test
func runStatusRoundTripsTypedDiagnostics() throws {
    let diagnostics = AgentRunDiagnostics(
        durationMs: 988_072,
        toolRoundsUsed: 61,
        maxToolRounds: 60,
        finishedNaturally: false,
        hitToolRoundLimit: true,
        toolErrorCount: 1,
        retryableToolErrorCount: 1,
        nonRetryableToolErrorCount: 0,
        turnExitReason: "tool_round_limit",
        wasInterrupted: false,
        didResetContext: false,
        explicitSessionCompletion: false
    )
    let status = AgentRunStatusEvent(
        id: "status-2",
        stage: .interrupted,
        label: "Incomplete",
        diagnostics: diagnostics,
        createdAt: Date(timeIntervalSince1970: 1_758_276_000)
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let decoded = try decoder.decode(AgentRunStatusEvent.self, from: encoder.encode(status))

    #expect(decoded == status)
    #expect(decoded.diagnostics?.toolRoundsUsed == 61)
    #expect(decoded.diagnostics?.hitToolRoundLimit == true)
}
