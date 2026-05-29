import Foundation
import Testing
@testable import sloppy
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite("SessionProcessRegistry")
struct SessionProcessRegistryTests {
    @Test("completed processes do not keep the active quota occupied")
    func completedProcessesReleaseQuota() async throws {
        let registry = SessionProcessRegistry()
        let sessionID = "quota-session"

        _ = try await registry.start(
            sessionID: sessionID,
            command: "/usr/bin/true",
            arguments: [],
            cwd: nil,
            maxProcesses: 2
        )
        _ = try await registry.start(
            sessionID: sessionID,
            command: "/usr/bin/true",
            arguments: [],
            cwd: nil,
            maxProcesses: 2
        )

        try await Task.sleep(for: .milliseconds(50))

        let activeCount = await registry.activeCount(sessionID: sessionID)
        #expect(activeCount == 0)

        let third = try await registry.start(
            sessionID: sessionID,
            command: "/usr/bin/true",
            arguments: [],
            cwd: nil,
            maxProcesses: 2
        )
        #expect(third.asObject?["running"]?.asBool == true)
    }

    @Test("list keeps completed processes visible with exit codes")
    func listIncludesCompletedProcesses() async throws {
        let registry = SessionProcessRegistry()
        let sessionID = "list-session"

        _ = try await registry.start(
            sessionID: sessionID,
            command: "/usr/bin/true",
            arguments: [],
            cwd: nil,
            maxProcesses: 2
        )

        try await Task.sleep(for: .milliseconds(50))

        let payload = await registry.list(sessionID: sessionID)
        let items = payload.asArray ?? []

        #expect(items.count == 1)
        #expect(items.first?.asObject?["running"]?.asBool == false)
        #expect(items.first?.asObject?["exitCode"]?.asInt == 0)
    }

    @Test("cleanup terminates processes that ignore SIGTERM")
    func cleanupTerminatesProcessesThatIgnoreSIGTERM() async throws {
        let registry = SessionProcessRegistry()
        let sessionID = "cleanup-session"
        let payload = try await registry.start(
            sessionID: sessionID,
            command: "/bin/sh",
            arguments: ["-c", "trap '' TERM; sleep 30"],
            cwd: nil,
            maxProcesses: 1
        )
        let pid = Int32(try #require(payload.asObject?["pid"]?.asInt))
        let completion = CompletionFlag()

        let cleanupTask = Task {
            await registry.cleanup(sessionID: sessionID)
            await completion.markComplete()
        }

        let finished = await waitForCompletion(completion, timeout: .seconds(5))
        if !finished {
            killProcess(pid)
        }
        await cleanupTask.value

        #expect(finished)
    }
}

private actor CompletionFlag {
    private var complete = false

    func markComplete() {
        complete = true
    }

    func isComplete() -> Bool {
        complete
    }
}

private func waitForCompletion(_ flag: CompletionFlag, timeout: Duration) async -> Bool {
    let start = ContinuousClock.now
    while ContinuousClock.now - start < timeout {
        if await flag.isComplete() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return await flag.isComplete()
}

private func killProcess(_ pid: Int32) {
    #if canImport(Darwin) || canImport(Glibc)
    kill(pid, SIGKILL)
    #else
    _ = pid
    #endif
}
