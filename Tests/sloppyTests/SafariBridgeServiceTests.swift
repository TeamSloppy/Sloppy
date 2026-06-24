import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite("SafariBridgeService")
struct SafariBridgeServiceTests {
    @Test("register stores all Safari tabs for agent tools")
    func registerStoresAllTabs() async throws {
        let service = SafariBridgeService(commandTimeoutMs: 1_000)

        let response = await service.register(
            SafariBridgeRegisterRequest(
                bridgeId: "safari-test",
                tabs: [
                    SafariBridgeTab(id: 1, url: "https://example.com/one", title: "One", active: true, currentWindow: true),
                    SafariBridgeTab(id: 2, url: "https://example.com/two", title: "Two", active: false, currentWindow: true),
                ],
                capabilities: ["tabs"]
            )
        )

        #expect(response.bridgeId == "safari-test")
        let status = await service.statusPayload()
        let tabs = status.asObject?["tabs"]?.asArray ?? []
        #expect(tabs.count == 2)
        #expect(tabs[0].asObject?["url"]?.asString == "https://example.com/one")
        #expect(tabs[1].asObject?["url"]?.asString == "https://example.com/two")
    }

    @Test("command queue resolves when extension posts result")
    func commandQueueResolvesFromResult() async throws {
        let service = SafariBridgeService(commandTimeoutMs: 1_000)
        _ = await service.register(SafariBridgeRegisterRequest(bridgeId: "safari-test"))

        async let result = service.runCommand(
            name: "safari.scroll",
            input: .object(["y": .number(500)])
        )

        let polled = await pollUntilCommandAvailable(service: service, bridgeId: "safari-test")
        #expect(polled.commands.count == 1)
        #expect(polled.commands[0].name == "safari.scroll")

        try await service.completeCommand(
            SafariBridgeCommandResultRequest(
                commandId: polled.commands[0].id,
                ok: true,
                data: .object(["scrolled": .bool(true)])
            )
        )

        let payload = try await result
        #expect(payload.asObject?["scrolled"]?.asBool == true)
    }

    private func pollUntilCommandAvailable(
        service: SafariBridgeService,
        bridgeId: String
    ) async -> SafariBridgeCommandListResponse {
        for _ in 0..<20 {
            let response = await service.pollCommands(bridgeId: bridgeId, limit: 5)
            if !response.commands.isEmpty {
                return response
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return SafariBridgeCommandListResponse()
    }
}
