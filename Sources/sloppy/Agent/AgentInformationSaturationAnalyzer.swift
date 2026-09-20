import Foundation
import Protocols

enum AgentInformationEvaluationPhase: String, Sendable, Equatable, Hashable {
    case acquisition
    case mutation
    case verification
    case coordination
    case completion
}

struct AgentInformationEvidenceRequirement: Sendable, Equatable {
    var tool: String
    var argumentKey: String
    var expectedValue: JSONValue

    init(tool: String, argumentKey: String, expectedValue: JSONValue) {
        self.tool = tool
        self.argumentKey = argumentKey
        self.expectedValue = expectedValue
    }
}

struct AgentInformationEvidenceSlot: Sendable, Equatable {
    var id: String
    var requirements: [AgentInformationEvidenceRequirement]

    init(id: String, requirements: [AgentInformationEvidenceRequirement]) {
        self.id = id
        self.requirements = requirements
    }
}

struct AgentInformationEvaluationDefinition: Sendable, Equatable {
    var toolPhases: [String: AgentInformationEvaluationPhase]
    var resourceArgumentKeys: [String: String]
    var completionTools: Set<String>
    var evidenceSlots: [AgentInformationEvidenceSlot]

    init(
        toolPhases: [String: AgentInformationEvaluationPhase],
        resourceArgumentKeys: [String: String] = [:],
        completionTools: Set<String> = ["session.complete"],
        evidenceSlots: [AgentInformationEvidenceSlot] = []
    ) {
        self.toolPhases = toolPhases
        self.resourceArgumentKeys = resourceArgumentKeys
        self.completionTools = completionTools
        self.evidenceSlots = evidenceSlots
    }
}

struct AgentInformationRuntimeMetrics: Sendable, Equatable {
    var toolRoundsUsed: Int
    var maxToolRounds: Int
    var hitToolRoundLimit: Bool
    var didResetContext: Bool
    var turnExitReason: String

    init(
        toolRoundsUsed: Int,
        maxToolRounds: Int,
        hitToolRoundLimit: Bool,
        didResetContext: Bool,
        turnExitReason: String
    ) {
        self.toolRoundsUsed = max(0, toolRoundsUsed)
        self.maxToolRounds = max(0, maxToolRounds)
        self.hitToolRoundLimit = hitToolRoundLimit
        self.didResetContext = didResetContext
        self.turnExitReason = turnExitReason
    }
}

struct AgentInformationEvaluationReport: Sendable, Equatable {
    var totalToolCalls: Int
    var toolCallCounts: [String: Int]
    var phaseCallCounts: [AgentInformationEvaluationPhase: Int]
    var unclassifiedToolCalls: Int
    var failedToolResults: Int
    var uniqueResources: [String]
    var mutationCallsByResource: [String: Int]
    var mutationConcentration: Double
    var satisfiedEvidenceSlotIDs: [String]
    var missingEvidenceSlotIDs: [String]
    var evidenceCoverage: Double
    var completionObserved: Bool
    var runtimeMetrics: AgentInformationRuntimeMetrics?

    var callsPerRound: Double? {
        guard let runtimeMetrics, runtimeMetrics.toolRoundsUsed > 0 else {
            return nil
        }
        return Double(totalToolCalls) / Double(runtimeMetrics.toolRoundsUsed)
    }

    var remainingRoundBudget: Int? {
        guard let runtimeMetrics, runtimeMetrics.maxToolRounds > 0 else {
            return nil
        }
        return max(0, runtimeMetrics.maxToolRounds - runtimeMetrics.toolRoundsUsed)
    }
}

enum AgentInformationSaturationAnalyzer {
    static func analyze(
        events: [AgentSessionEvent],
        definition: AgentInformationEvaluationDefinition,
        runtimeMetrics: AgentInformationRuntimeMetrics? = nil
    ) -> AgentInformationEvaluationReport {
        let latestEventRuntimeMetrics: AgentInformationRuntimeMetrics? = events.reversed().compactMap {
            event -> AgentInformationRuntimeMetrics? in
            guard let diagnostics = event.runStatus?.diagnostics else {
                return nil
            }
            return AgentInformationRuntimeMetrics(diagnostics)
        }.first
        let effectiveRuntimeMetrics = runtimeMetrics ?? latestEventRuntimeMetrics
        let toolCalls = events.compactMap(\.toolCall)
        var toolCallCounts: [String: Int] = [:]
        var phaseCallCounts: [AgentInformationEvaluationPhase: Int] = [:]
        var unclassifiedToolCalls = 0
        var resources = Set<String>()
        var mutationCallsByResource: [String: Int] = [:]

        for call in toolCalls {
            toolCallCounts[call.tool, default: 0] += 1

            let phase = definition.toolPhases[call.tool]
            if let phase {
                phaseCallCounts[phase, default: 0] += 1
            } else {
                unclassifiedToolCalls += 1
            }

            guard let argumentKey = definition.resourceArgumentKeys[call.tool],
                  let resource = call.arguments[argumentKey]?.asString else {
                continue
            }
            resources.insert(resource)
            if phase == .mutation {
                mutationCallsByResource[resource, default: 0] += 1
            }
        }

        let failedToolResults = events.reduce(into: 0) { count, event in
            if event.toolResult?.ok == false {
                count += 1
            }
        }

        let satisfiedEvidenceSlotIDs = definition.evidenceSlots.compactMap { slot -> String? in
            guard !slot.requirements.isEmpty else {
                return nil
            }
            let isSatisfied = slot.requirements.allSatisfy { requirement in
                toolCalls.contains { call in
                    call.tool == requirement.tool
                        && call.arguments[requirement.argumentKey] == requirement.expectedValue
                }
            }
            return isSatisfied ? slot.id : nil
        }
        let satisfiedEvidenceSlotIDSet = Set(satisfiedEvidenceSlotIDs)
        let missingEvidenceSlotIDs = definition.evidenceSlots
            .map(\.id)
            .filter { !satisfiedEvidenceSlotIDSet.contains($0) }

        let evidenceCoverage: Double
        if definition.evidenceSlots.isEmpty {
            evidenceCoverage = 1
        } else {
            evidenceCoverage = Double(satisfiedEvidenceSlotIDs.count)
                / Double(definition.evidenceSlots.count)
        }

        let mutationCallCount = phaseCallCounts[.mutation, default: 0]
        let largestMutationCount = mutationCallsByResource.values.max() ?? 0
        let mutationConcentration = mutationCallCount > 0
            ? Double(largestMutationCount) / Double(mutationCallCount)
            : 0

        return AgentInformationEvaluationReport(
            totalToolCalls: toolCalls.count,
            toolCallCounts: toolCallCounts,
            phaseCallCounts: phaseCallCounts,
            unclassifiedToolCalls: unclassifiedToolCalls,
            failedToolResults: failedToolResults,
            uniqueResources: resources.sorted(),
            mutationCallsByResource: mutationCallsByResource,
            mutationConcentration: mutationConcentration,
            satisfiedEvidenceSlotIDs: satisfiedEvidenceSlotIDs,
            missingEvidenceSlotIDs: missingEvidenceSlotIDs,
            evidenceCoverage: evidenceCoverage,
            completionObserved: toolCalls.contains { definition.completionTools.contains($0.tool) },
            runtimeMetrics: effectiveRuntimeMetrics
        )
    }
}

private extension AgentInformationRuntimeMetrics {
    init(_ diagnostics: AgentRunDiagnostics) {
        self.init(
            toolRoundsUsed: diagnostics.toolRoundsUsed,
            maxToolRounds: diagnostics.maxToolRounds,
            hitToolRoundLimit: diagnostics.hitToolRoundLimit,
            didResetContext: diagnostics.didResetContext,
            turnExitReason: diagnostics.turnExitReason
        )
    }
}
