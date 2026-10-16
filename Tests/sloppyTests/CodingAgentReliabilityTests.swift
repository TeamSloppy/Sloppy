import Foundation
import Protocols
import Testing
@testable import sloppy

@Test
func turnGuardRejectsBlockedUntilCallRetriedAfterMalformedArguments() {
    var state = SessionTurnGuardState()
    #expect(state.blockedCompletionRejection == nil)
    state.recordMalformedCall()
    state.recordMalformedCall()
    #expect(state.blockedCompletionRejection != nil)
    state.recordWellFormedCall()
    #expect(state.blockedCompletionRejection == nil)
    state.recordMalformedCall()
    #expect(state.blockedCompletionRejection != nil)
}

@Test
func turnGuardTellsModelToChangeApproachAfterRepeatedSameFailure() {
    var state = SessionTurnGuardState()
    let failure = ToolInvocationResult(
        tool: "files.read", ok: false,
        error: ToolErrorPayload(code: "not_found", message: "missing", retryable: false)
    )
    let first = state.recordOutcome(tool: "files.read", result: failure)
    let second = state.recordOutcome(tool: "files.read", result: failure)
    let third = state.recordOutcome(tool: "files.read", result: failure)
    #expect(first == nil && second == nil)
    #expect(third?.contains("change the approach") == true)
    let afterSuccess = state.recordOutcome(tool: "files.read", result: ToolInvocationResult(tool: "files.read", ok: true))
    let afterReset = state.recordOutcome(tool: "files.read", result: failure)
    #expect(afterSuccess == nil && afterReset == nil)
}

@Test
func turnGuardFlagsOnlyRepeatedReads() {
    var state = SessionTurnGuardState()
    let first = state.isRepeatedRead(signature: "a")
    let again = state.isRepeatedRead(signature: "a")
    let other = state.isRepeatedRead(signature: "b")
    #expect(!first && again && !other)
}

@Test
func explicitSessionModelIsHonouredWhenRoutableEvenIfListIsStale() {
    #expect(AgentSessionOrchestrator.acceptsModelOverride(
        "openai-oauth:gpt-6.1-sol", availableModelIDs: ["openai-oauth:gpt-5.5"], isRoutable: { _ in true }))
    #expect(!AgentSessionOrchestrator.acceptsModelOverride(
        "bogus:model", availableModelIDs: ["openai-oauth:gpt-5.5"], isRoutable: { _ in false }))
    #expect(AgentSessionOrchestrator.acceptsModelOverride(
        "openai-oauth:gpt-5.5", availableModelIDs: ["openai-oauth:gpt-5.5"], isRoutable: { _ in false }))
}

@Test
func unsupportedOAuthModelFallsBackToLoadedModelNotAlreadyTried() {
    let cached = [
        ProviderModelOption(id: "gpt-6.1-sol", title: "6.1", capabilities: []),
        ProviderModelOption(id: "openai-oauth:gpt-6-sol", title: "6", capabilities: []),
    ]
    #expect(CoreService.alternativeOAuthModel(cached: cached, excluding: ["openai-oauth:gpt-5.5"]) == "openai-oauth:gpt-6-sol")
    #expect(CoreService.alternativeOAuthModel(cached: cached, excluding: ["openai-oauth:gpt-6-sol"]) == "openai-oauth:gpt-6.1-sol")
    #expect(CoreService.alternativeOAuthModel(cached: cached, excluding: ["openai-oauth:gpt-6-sol", "openai-oauth:gpt-6.1-sol"]) == nil)
}

@Test
func mcpToolsListedInConfigCountAsVerification() async {
    let registry = MCPClientRegistry(config: CoreConfig.MCP(
        servers: [],
        verificationTools: ["editor.build.start": "build", "studio:editor.play.start": "run", "x": "nonsense"]
    ))
    #expect(await registry.verificationKind(serverID: "acp.studio", tool: "editor.build.start") == "build")
    #expect(await registry.verificationKind(serverID: "studio", tool: "editor.play.start") == "run")
    #expect(await registry.verificationKind(serverID: "acp.studio", tool: "x") == nil)
}

@Test
func mcpVerificationToolsRoundTripThroughConfigJSON() throws {
    let json = #"{"servers":[],"verificationTools":{"editor.build.start":"build"}}"#
    let decoded = try JSONDecoder().decode(CoreConfig.MCP.self, from: Data(json.utf8))
    #expect(decoded.verificationTools["editor.build.start"] == "build")
    let legacy = try JSONDecoder().decode(CoreConfig.MCP.self, from: Data(#"{"servers":[]}"#.utf8))
    #expect(legacy.verificationTools.isEmpty)
}

@Test
func explorationBudgetNudgesOncePerBudgetAndProgressResetsIt() {
    var state = SessionTurnGuardState()
    for _ in 0..<(SessionTurnGuardState.explorationBudget - 1) {
        #expect(state.recordExploration(isProgress: false) == nil)
    }
    #expect(state.recordExploration(isProgress: false)?.contains("planning.progress_update") == true)
    #expect(state.recordExploration(isProgress: false) == nil)
    for _ in 0..<5 { _ = state.recordExploration(isProgress: false) }
    #expect(state.recordExploration(isProgress: true) == nil)
    #expect(state.explorationStreak == 0)
}

@Test
func mcpReadOnlyToolsFromConfigAreReportedAsReadOnly() async {
    let registry = MCPClientRegistry(config: CoreConfig.MCP(servers: [], readOnlyTools: ["editor.skills.read", "acp.studio:editor.docs.read"]))
    #expect(await registry.toolTraits(serverID: "acp.studio", tool: "editor.skills.read").readOnly == true)
    #expect(await registry.toolTraits(serverID: "acp.studio", tool: "editor.docs.read").readOnly == true)
    #expect(await registry.toolTraits(serverID: "other", tool: "editor.docs.read").readOnly == nil)
}
