import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite("SafariBridgeRouter")
struct SafariBridgeRouterTests {
    @Test("register endpoint exposes all tabs to safari.tabs tool")
    func registerEndpointExposesTabsToTool() async throws {
        let service = CoreService(config: .test)
        let router = CoreRouter(service: service)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let agentResponse = await router.handle(
            method: "POST",
            path: "/v1/agents",
            body: try encoder.encode(AgentCreateRequest(id: "sloppy", displayName: "Sloppy", role: "Use tools."))
        )
        #expect(agentResponse.status == 201)
        let sessionResponse = await router.handle(
            method: "POST",
            path: "/v1/agents/sloppy/sessions",
            body: try encoder.encode(AgentSessionCreateRequest(title: "Safari bridge"))
        )
        #expect(sessionResponse.status == 201)
        let session = try decoder.decode(AgentSessionSummary.self, from: sessionResponse.body)

        let register = SafariBridgeRegisterRequest(
            bridgeId: "safari-router",
            tabs: [
                SafariBridgeTab(id: 11, url: "https://one.example", title: "One", active: true, currentWindow: true),
                SafariBridgeTab(id: 12, url: "https://two.example", title: "Two", active: false, currentWindow: true),
            ],
            capabilities: ["tabs"]
        )
        let registerResponse = await router.handle(
            method: "POST",
            path: "/v1/safari-bridge/register",
            body: try encoder.encode(register)
        )
        #expect(registerResponse.status == 200)

        async let toolResponse = router.handle(
            method: "POST",
            path: "/v1/agents/sloppy/sessions/\(session.id)/tools/invoke",
            body: try encoder.encode(
                ToolInvocationRequest(tool: "safari.tabs", arguments: [:])
            )
        )

        let polled = await pollUntilCommandAvailable(service: service.safariBridgeService, bridgeId: "safari-router")
        let command = try #require(polled.commands.first)
        #expect(command.name == "safari.tabs")
        try await service.safariBridgeService.completeCommand(
            SafariBridgeCommandResultRequest(
                commandId: command.id,
                ok: true,
                data: .object([
                    "tabs": .array([
                        .object([
                            "id": .number(11),
                            "url": .string("https://one.example"),
                            "title": .string("One"),
                            "active": .bool(true),
                            "currentWindow": .bool(true),
                        ]),
                        .object([
                            "id": .number(12),
                            "url": .string("https://two.example"),
                            "title": .string("Two"),
                            "active": .bool(false),
                            "currentWindow": .bool(true),
                        ]),
                    ])
                ])
            )
        )

        let response = try await toolResponse
        #expect(response.status == 200)
        let result = try decoder.decode(ToolInvocationResult.self, from: response.body)
        #expect(result.ok == true)
        #expect(result.data?.asObject?["tabs"]?.asArray?.count == 2)
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
