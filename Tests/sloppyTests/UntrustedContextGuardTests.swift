import Foundation
import Protocols
import Testing
@testable import sloppy

private func toolResultEvent(_ tool: String) -> AgentSessionEvent {
    AgentSessionEvent(
        agentId: "agent",
        sessionId: "session",
        type: .toolResult,
        toolResult: AgentToolResultEvent(tool: tool, ok: true)
    )
}

private func userMessageEvent() -> AgentSessionEvent {
    AgentSessionEvent(
        agentId: "agent",
        sessionId: "session",
        type: .message,
        message: AgentSessionMessage(
            role: .user,
            segments: [.init(kind: .text, text: "hello")]
        )
    )
}

@Test
func sessionWithoutUntrustedToolResultsIsNotTainted() {
    let events = [userMessageEvent(), toolResultEvent("files.read"), toolResultEvent("runtime.exec")]

    #expect(!UntrustedContextGuard.isTainted(events: events))
}

@Test
func webBrowserAndMCPToolResultsTaintSession() {
    for tool in ["web.fetch", "web.search", "browser.read", "safari.tabs", "mcp.call_tool", "channel.history"] {
        let events = [userMessageEvent(), toolResultEvent(tool)]

        #expect(UntrustedContextGuard.isTainted(events: events), "\(tool) should taint the session")
    }
}

@Test
func dynamicMCPToolOutsideBuiltInCatalogTaintsSession() {
    let events = [toolResultEvent("github__create_issue")]

    #expect(UntrustedContextGuard.isTainted(events: events))
}

@Test
func importedHistoryStillTaintsSessionBecauseItReachesModelContext() {
    var event = toolResultEvent("web.fetch")
    event.importOrigin = AgentSessionImportOrigin(source: .codex, sourceID: "s", externalID: "e", jobID: "j")

    #expect(UntrustedContextGuard.isTainted(events: [event]))
}

@Test
func taintedSessionForcesApprovalForRiskyCallsOnly() {
    let tainted = [toolResultEvent("web.fetch")]
    let clean = [toolResultEvent("files.read")]
    let settings = AgentToolApprovalSettings()

    #expect(UntrustedContextGuard.requiresPerInvocationApproval(
        sessionEvents: tainted, settings: settings, callRequiresHumanApproval: true
    ))
    #expect(!UntrustedContextGuard.requiresPerInvocationApproval(
        sessionEvents: tainted, settings: settings, callRequiresHumanApproval: false
    ))
    #expect(!UntrustedContextGuard.requiresPerInvocationApproval(
        sessionEvents: clean, settings: settings, callRequiresHumanApproval: true
    ))
}

@Test
func disabledGuardNeverForcesApproval() {
    let events = [toolResultEvent("web.fetch")]
    let settings = AgentToolApprovalSettings(untrustedContextGuard: .off)

    #expect(!UntrustedContextGuard.requiresPerInvocationApproval(
        sessionEvents: events, settings: settings, callRequiresHumanApproval: true
    ))
}

@Test
func approvalSettingsDefaultToGuardEnabledWhenFieldIsMissing() throws {
    let legacy = Data(#"{"policy":"on_request"}"#.utf8)

    let decoded = try JSONDecoder().decode(AgentToolApprovalSettings.self, from: legacy)

    #expect(decoded.untrustedContextGuard == .requireApproval)

    let encoded = try JSONEncoder().encode(AgentToolApprovalSettings(untrustedContextGuard: .off))
    let roundTripped = try JSONDecoder().decode(AgentToolApprovalSettings.self, from: encoded)
    #expect(roundTripped.untrustedContextGuard == .off)
}
