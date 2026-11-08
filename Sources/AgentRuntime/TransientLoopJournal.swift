import Foundation
import PluginSDK
import Protocols

/// Low-level RuntimeSystem callers historically own only in-memory channel history. Core and embedded
/// hosts supply their durable journals. Both use this same AgentLoop/ToolPipeline, with no provider loop.
actor TransientLoopJournal: AgentLoopStateJournal, AgentLoopOutcomeJournal, AgentLoopInstructionJournal, AgentLoopUsageJournal {
    private var history: [ModelStepMessage]
    private var responses: [(ModelStepRequest, ModelStepResponse)] = []
    private var calls: [String: AgentLoopCall] = [:]
    private var results: [String: ToolInvocationResult] = [:]
    private var instructions: [ModelStepMessage] = []
    private var snapshot: RunStateSnapshot?
    init(history: [ModelStepMessage]) { self.history = history }

    func messages(includeInstructions: Bool = false) throws -> [ModelStepMessage] {
        var messages = history
        for (request, response) in responses {
            messages.append(.init(id: request.stepId, role: .assistant, text: response.text,
                toolCalls: response.toolCalls, continuation: response.continuation))
            for call in response.toolCalls {
                let key = request.stepId + "/" + call.id
                if let original = calls[key], let result = results[original.eventID] {
                    messages.append(.init(id: original.eventID, role: .tool, toolOutput: .init(callId: call.id,
                        name: call.name, content: String(decoding: try JSONEncoder().encode(result), as: UTF8.self), isError: !result.ok)))
                }
            }
        }
        return messages + (includeInstructions ? instructions : [])
    }
    func prepareRequest(_ request: ModelStepRequest) throws -> ModelStepRequest {
        var request = request; request.messages = try messages(includeInstructions: true); return request
    }
    func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest) { responses.append((request, response)) }
    func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest, usageRequest: UsageRequestRecord) {
        appendResponse(response, request: request)
    }
    func appendRequested(_ values: [AgentLoopCall], request: ModelStepRequest) {
        for call in values { calls[request.stepId + "/" + call.call.id] = call }
    }
    func appendStarted(_ call: AgentLoopCall, request: ModelStepRequest) {}
    func appendResult(_ result: ToolInvocationResult, call: AgentLoopCall, request: ModelStepRequest) {
        if result.error?.code == "tool_execution_interrupted", let known = results[call.eventID], known.error?.code != "tool_execution_interrupted" { return }
        results[call.eventID] = result
    }
    func appendOutcome(_ outcome: AgentLoopToolOutcome, call: AgentLoopCall, request: ModelStepRequest) {
        appendResult(outcome.result, call: call, request: request)
    }
    func appendInstruction(_ instruction: AgentRunInstruction, request: ModelStepRequest) {
        instructions.append(.init(id: instruction.id, role: .user, text: instruction.text))
    }
    func appendRunState(_ snapshot: RunStateSnapshot, request: ModelStepRequest) { self.snapshot = snapshot }
    func restoreRunState(userTurnID: String?) throws -> RunState? { try snapshot.map { try RunState(snapshot: $0) } }
}
