import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Test
func informationSaturationAnalyzerMeasuresExplicitEvidenceAndPhaseUsage() {
    let events = [
        toolCallEvent(tool: "files.read", arguments: ["path": .string("Sources/Plan.swift")]),
        toolResultEvent(tool: "files.read", ok: true),
        toolCallEvent(tool: "files.read", arguments: ["path": .string("Sources/Panel.swift")]),
        toolResultEvent(tool: "files.read", ok: true),
        toolCallEvent(tool: "files.edit", arguments: ["path": .string("Sources/Plan.swift")]),
        toolResultEvent(tool: "files.edit", ok: true),
        toolCallEvent(tool: "files.edit", arguments: ["path": .string("Sources/Plan.swift")]),
        toolResultEvent(tool: "files.edit", ok: true),
        toolCallEvent(tool: "runtime.exec", arguments: ["command": .string("swift test")]),
        toolResultEvent(tool: "runtime.exec", ok: false),
        toolCallEvent(tool: "session.complete", arguments: [:]),
        toolResultEvent(tool: "session.complete", ok: true),
    ]
    let definition = AgentInformationEvaluationDefinition(
        toolPhases: [
            "files.read": .acquisition,
            "files.edit": .mutation,
            "runtime.exec": .verification,
            "session.complete": .completion,
        ],
        resourceArgumentKeys: [
            "files.read": "path",
            "files.edit": "path",
        ],
        evidenceSlots: [
            .init(id: "plan-pipeline", requirements: [
                .init(tool: "files.read", argumentKey: "path", expectedValue: .string("Sources/Plan.swift")),
            ]),
            .init(id: "panel-api", requirements: [
                .init(tool: "files.read", argumentKey: "path", expectedValue: .string("Sources/Panel.swift")),
            ]),
            .init(id: "protocol-model", requirements: [
                .init(tool: "files.read", argumentKey: "path", expectedValue: .string("Sources/Protocol.swift")),
            ]),
        ]
    )
    let runtimeMetrics = AgentInformationRuntimeMetrics(
        toolRoundsUsed: 6,
        maxToolRounds: 60,
        hitToolRoundLimit: false,
        didResetContext: false,
        turnExitReason: "completed"
    )

    let report = AgentInformationSaturationAnalyzer.analyze(
        events: events,
        definition: definition,
        runtimeMetrics: runtimeMetrics
    )

    #expect(report.totalToolCalls == 6)
    #expect(report.toolCallCounts["files.read"] == 2)
    #expect(report.phaseCallCounts[.acquisition] == 2)
    #expect(report.phaseCallCounts[.mutation] == 2)
    #expect(report.phaseCallCounts[.verification] == 1)
    #expect(report.phaseCallCounts[.completion] == 1)
    #expect(report.unclassifiedToolCalls == 0)
    #expect(report.failedToolResults == 1)
    #expect(report.uniqueResources == ["Sources/Panel.swift", "Sources/Plan.swift"])
    #expect(report.mutationCallsByResource == ["Sources/Plan.swift": 2])
    #expect(report.mutationConcentration == 1)
    #expect(report.satisfiedEvidenceSlotIDs == ["plan-pipeline", "panel-api"])
    #expect(report.missingEvidenceSlotIDs == ["protocol-model"])
    #expect(report.evidenceCoverage == 2.0 / 3.0)
    #expect(report.completionObserved)
    #expect(report.callsPerRound == 1)
    #expect(report.remainingRoundBudget == 54)
}

@Test
func informationSaturationAnalyzerDoesNotInferEvidenceFromMessageText() {
    let events = [
        AgentSessionEvent(
            agentId: "agent",
            sessionId: "session",
            type: .message,
            message: AgentSessionMessage(
                role: .assistant,
                segments: [.init(kind: .text, text: "I inspected Sources/Secret.swift")]
            )
        ),
    ]
    let definition = AgentInformationEvaluationDefinition(
        toolPhases: ["files.read": .acquisition],
        evidenceSlots: [
            .init(id: "secret-source", requirements: [
                .init(tool: "files.read", argumentKey: "path", expectedValue: .string("Sources/Secret.swift")),
            ]),
        ]
    )

    let report = AgentInformationSaturationAnalyzer.analyze(events: events, definition: definition)

    #expect(report.totalToolCalls == 0)
    #expect(report.satisfiedEvidenceSlotIDs.isEmpty)
    #expect(report.missingEvidenceSlotIDs == ["secret-source"])
    #expect(report.evidenceCoverage == 0)
    #expect(!report.completionObserved)
    #expect(report.callsPerRound == nil)
    #expect(report.remainingRoundBudget == nil)
}

@Test
func informationSaturationAnalyzerUsesTypedTerminalDiagnostics() {
    let events = [
        toolCallEvent(tool: "files.read", arguments: ["path": .string("Sources/Plan.swift")]),
        AgentSessionEvent(
            agentId: "agent",
            sessionId: "session",
            type: .runStatus,
            runStatus: AgentRunStatusEvent(
                stage: .interrupted,
                label: "Incomplete",
                diagnostics: AgentRunDiagnostics(
                    durationMs: 100,
                    toolRoundsUsed: 61,
                    maxToolRounds: 60,
                    finishedNaturally: false,
                    hitToolRoundLimit: true,
                    toolErrorCount: 0,
                    retryableToolErrorCount: 0,
                    nonRetryableToolErrorCount: 0,
                    turnExitReason: "tool_round_limit",
                    wasInterrupted: false,
                    didResetContext: false,
                    explicitSessionCompletion: false
                )
            )
        ),
    ]
    let definition = AgentInformationEvaluationDefinition(
        toolPhases: ["files.read": .acquisition]
    )

    let report = AgentInformationSaturationAnalyzer.analyze(events: events, definition: definition)

    #expect(report.runtimeMetrics?.toolRoundsUsed == 61)
    #expect(report.runtimeMetrics?.maxToolRounds == 60)
    #expect(report.runtimeMetrics?.hitToolRoundLimit == true)
    #expect(report.runtimeMetrics?.turnExitReason == "tool_round_limit")
    #expect(report.callsPerRound == 1.0 / 61.0)
    #expect(report.remainingRoundBudget == 0)
}

private func toolCallEvent(
    tool: String,
    arguments: [String: JSONValue]
) -> AgentSessionEvent {
    AgentSessionEvent(
        agentId: "agent",
        sessionId: "session",
        type: .toolCall,
        toolCall: AgentToolCallEvent(tool: tool, arguments: arguments)
    )
}

private func toolResultEvent(tool: String, ok: Bool) -> AgentSessionEvent {
    AgentSessionEvent(
        agentId: "agent",
        sessionId: "session",
        type: .toolResult,
        toolResult: AgentToolResultEvent(tool: tool, ok: ok)
    )
}
