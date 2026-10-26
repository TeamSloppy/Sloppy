import Foundation
import Testing
@testable import sloppy

@Suite struct RemoteTransportRegressionTests {
    @Test func concurrentRelayStartsShareSetupBeforeItSuspends() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("relay-start-\(UUID())")
        var config = CoreConfig.test
        config.workspace.basePath = root.path
        let service = CoreService(config: config, currentDirectory: root.path,
            persistenceBuilder: InMemoryCorePersistenceBuilder(),
            nodeConfigStore: .init(configURL: root.appendingPathComponent("node.json")))
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = RelayStartupGate()
        let first = Task {
            await service.ensureConsoleRelayStarted {
                await gate.enter()
                await service.installRegressionRelayTask()
            }
        }
        await gate.waitUntilEntered()
        #expect(await service.hasRegressionRelayStartup())
        let second = Task {
            await service.ensureConsoleRelayStarted {
                Issue.record("A concurrent caller must join the reserved startup")
            }
        }
        await gate.release()
        await first.value
        await second.value
        #expect(await gate.calls == 1)
        #expect(!(await service.hasRegressionRelayStartup()))
        await service.stopConsoleRelay()
    }
}

private actor RelayStartupGate {
    var calls = 0
    private var entered: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    func enter() async {
        calls += 1
        entered?.resume(); entered = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }
    func waitUntilEntered() async {
        if calls > 0 { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release() { releaseContinuation?.resume(); releaseContinuation = nil }
}

private extension CoreService {
    func hasRegressionRelayStartup() -> Bool { consoleRelayStartupTask != nil }
    func installRegressionRelayTask() { consoleRelayTask = Task {} }
}
