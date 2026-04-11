import Foundation
import Testing
@testable import sloppy

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
}
