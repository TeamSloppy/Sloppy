import Foundation
import Testing
@testable import sloppy

@Test
func verificationKindRecognizesScriptAndTestRunners() {
    typealias Kind = SessionVerificationEvidenceKind
    func kind(_ command: String, _ args: [String]) -> Kind? {
        AgentSessionOrchestrator.verificationKind(command: command, arguments: args)
    }
    #expect(kind("node", ["test.js"]) == .run)
    #expect(kind("node", ["--test"]) == .test)
    #expect(kind("deno", ["test"]) == .test)
    #expect(kind("bun", ["test"]) == .test)
    #expect(kind("npx", ["vitest", "run"]) == .test)
    #expect(kind("npx", ["tsc", "--noEmit"]) == .lint)
    #expect(kind("rspec", []) == .test)
    #expect(kind("mvn", ["-q", "test"]) == .test)
    // Existing mappings stay intact.
    #expect(kind("swift", ["test"]) == .test)
    #expect(kind("npm", ["run", "build"]) == .build)
}

@Test
func verificationKindDoesNotTreatInspectionCommandsAsVerification() {
    func kind(_ command: String, _ args: [String]) -> SessionVerificationEvidenceKind? {
        AgentSessionOrchestrator.verificationKind(command: command, arguments: args)
    }
    #expect(kind("ls", ["-la"]) == nil)
    #expect(kind("cat", ["range.js"]) == nil)
    #expect(kind("node", ["--version"]) == nil)
    #expect(kind("bun", ["run"]) == nil)
    #expect(kind("bash", ["-lc", "pwd; ls -a; cat range.js"]) == nil)
}

@Test
func verificationKindClassifiesShellWrapperByItsLastCommand() {
    func kind(_ script: String) -> SessionVerificationEvidenceKind? {
        AgentSessionOrchestrator.verificationKind(command: "bash", arguments: ["-lc", script])
    }
    #expect(kind("pwd; ls -a; node test.js") == .run)
    #expect(kind("cd app && swift test") == .test)
    #expect(kind("node test.js && git diff --stat") == nil)
    // Pipes and `||` make the exit status ambiguous, so they never count as evidence.
    #expect(kind("node test.js | tee out.log") == nil)
    #expect(kind("node test.js || true") == nil)
}

@Test
func completionRecoveryPromptStatesRecordedFactsAndMissingEvidence() {
    let withoutEvidence = AgentSessionOrchestrator.completionRecoveryPrompt(
        mode: .debug, toolRoundsUsed: 2, verificationEvidenceCount: 0)
    #expect(withoutEvidence.contains("tool rounds used: 2"))
    #expect(withoutEvidence.contains("verification evidence recorded: 0"))
    #expect(withoutEvidence.contains("No successful build, test, or run is recorded"))
    #expect(withoutEvidence.contains("previous debug response"))

    let withEvidence = AgentSessionOrchestrator.completionRecoveryPrompt(
        mode: .build, toolRoundsUsed: 5, verificationEvidenceCount: 1)
    #expect(withEvidence.contains("verification evidence recorded: 1"))
    #expect(!withEvidence.contains("No successful build, test, or run is recorded"))
}

@Test
func completionRecoveryEscalatesAfterAnAttemptWithoutToolCalls() {
    let first = AgentSessionOrchestrator.completionRecoveryPrompt(
        mode: .debug, toolRoundsUsed: 2, verificationEvidenceCount: 0, attempt: 1, lastAttemptToolRounds: nil)
    let second = AgentSessionOrchestrator.completionRecoveryPrompt(
        mode: .debug, toolRoundsUsed: 2, verificationEvidenceCount: 0, attempt: 2, lastAttemptToolRounds: 0)
    let afterWork = AgentSessionOrchestrator.completionRecoveryPrompt(
        mode: .debug, toolRoundsUsed: 6, verificationEvidenceCount: 0, attempt: 2, lastAttemptToolRounds: 4)

    #expect(!first.contains("made no tool calls"))
    #expect(second.contains("recovery attempt 2 of \(AgentSessionOrchestrator.maxCompletionRecoveryAttempts)"))
    #expect(second.contains("made no tool calls"))
    #expect(!afterWork.contains("made no tool calls"))
}
