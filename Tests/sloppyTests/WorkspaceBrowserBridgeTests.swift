import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite("Workspace browser bridge")
struct WorkspaceBrowserBridgeTests {
    private func binding(_ session: String = "session") -> WorkspaceBrowserBinding {
        .init(bridgeId: UUID().uuidString, agentId: "agent", sessionId: session)
    }

    private func next(_ bridge: WorkspaceBrowserBridgeService, _ binding: WorkspaceBrowserBinding) async throws -> WorkspaceBrowserCommand {
        for _ in 0..<100 {
            if let command = try await bridge.poll(binding).commands.first { return command }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw WorkspaceBrowserBridgeError.timedOut
    }

    @Test func isolatesSessionsAndChecksResultOwner() async throws {
        let bridge = WorkspaceBrowserBridgeService()
        let first = binding("first"), second = binding("second")
        try await bridge.register(first)
        try await bridge.register(second)
        let task = Task { try await bridge.run(sessionID: "first", name: "click", input: .object(["selector": .string("#go")])) }
        let command = try await next(bridge, first)
        #expect(try await bridge.poll(second).commands.isEmpty)
        #expect(command.name == "click")
        #expect(command.input.asObject?["selector"]?.asString == "#go")
        await #expect(throws: WorkspaceBrowserBridgeError.unknownCommand) {
            try await bridge.complete(.init(binding: second, commandId: command.id, data: .object([:]), imageBase64: nil, error: nil))
        }
        try await bridge.complete(.init(binding: first, commandId: command.id, data: .object(["title": .string("Done")]), imageBase64: nil, error: nil))
        #expect(try await task.value.asObject?["title"]?.asString == "Done")
    }

    @Test func disconnectFailsPendingAndPreventsFallback() async throws {
        let bridge = WorkspaceBrowserBridgeService()
        let owner = binding()
        try await bridge.register(owner)
        let task = Task { try await bridge.run(sessionID: owner.sessionId, name: "read") }
        _ = try await next(bridge, owner)
        await bridge.disconnect(owner)
        await #expect(throws: WorkspaceBrowserBridgeError.unavailable) { try await task.value }
        #expect(await bridge.isAssigned(sessionID: owner.sessionId))
        await #expect(throws: WorkspaceBrowserBridgeError.unavailable) { try await bridge.run(sessionID: owner.sessionId, name: "open") }
    }

    @Test func evaluationUsesAssignedPageAndReturnsJSONWithoutFallback() async throws {
        let service = BrowserCDPService(workspaceRootURL: FileManager.default.temporaryDirectory)
        let owner = binding()
        try await service.workspaceBridge.register(owner)
        let expression = "Promise.resolve({price: 120})"
        let task = Task { try await service.evaluate(sessionID: owner.sessionId, pageID: "page", expression: expression) }
        let command = try await next(service.workspaceBridge, owner)
        #expect(command.name == "evaluate")
        #expect(command.input.asObject?["expression"]?.asString == expression)
        #expect(command.input.asObject?["pageId"]?.asString == "page")
        let evaluation: JSONValue = .object(["value": .object(["price": .number(120)])])
        try await service.workspaceBridge.complete(.init(binding: owner, commandId: command.id,
            data: .object(["pageId": .string("page"), "evaluation": evaluation]), imageBase64: nil, error: nil))
        let result = try await task.value
        #expect(result.asObject?["evaluation"] == evaluation)
        #expect(result.asObject?["surface"]?.asString == "in_app")
        await service.workspaceBridge.disconnect(owner)
        await #expect(throws: WorkspaceBrowserBridgeError.unavailable) {
            try await service.evaluate(sessionID: owner.sessionId, pageID: "page", expression: "42")
        }
    }

    @Test func cannotReplaceLiveBrowser() async throws {
        let bridge = WorkspaceBrowserBridgeService()
        try await bridge.register(binding())
        await #expect(throws: WorkspaceBrowserBridgeError.conflict) { try await bridge.register(binding()) }
    }

    @Test func expiredCommandsAreNotReplayed() async throws {
        let bridge = WorkspaceBrowserBridgeService(timeout: .milliseconds(20))
        let owner = binding()
        try await bridge.register(owner)
        await #expect(throws: WorkspaceBrowserBridgeError.timedOut) { try await bridge.run(sessionID: owner.sessionId, name: "click") }
        #expect(try await bridge.poll(owner).commands.isEmpty)
    }

    @Test func cancellationReleasesPendingCommand() async throws {
        let bridge = WorkspaceBrowserBridgeService()
        let owner = binding()
        try await bridge.register(owner)
        let task = Task { try await bridge.run(sessionID: owner.sessionId, name: "click") }
        _ = try await next(bridge, owner)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func servicePrefersInAppBrowserEvenWithoutChromium() async throws {
        let service = BrowserCDPService(workspaceRootURL: FileManager.default.temporaryDirectory)
        let owner = binding()
        try await service.workspaceBridge.register(owner)
        let task = Task { try await service.open(sessionID: owner.sessionId, url: "https://example.com") }
        let command = try await next(service.workspaceBridge, owner)
        #expect(command.name == "open")
        try await service.workspaceBridge.complete(.init(binding: owner, commandId: command.id,
            data: .object(["url": .string("https://example.com"), "pageId": .string("page")]), imageBase64: nil, error: nil))
        #expect(try await task.value.asObject?["surface"]?.asString == "in_app")
        #expect(await service.status(sessionID: owner.sessionId).asObject?["connected"]?.asBool == true)
    }
}

extension WorkspaceBrowserBridgeTests {
    @Test func routesDeliverCommandsAndRejectUnknownSessions() async throws {
        let service = CoreService(config: .test)
        let router = CoreRouter(service: service)
        let encoder = JSONEncoder()
        let agentID = "browser-route-\(UUID().uuidString.lowercased())"
        _ = try await service.createAgent(.init(id: agentID, displayName: "Browser test", role: "Testing"))
        let session = try await service.createAgentSession(agentID: agentID, request: .init(title: "Browser task"))
        let owner = WorkspaceBrowserBinding(bridgeId: UUID().uuidString, agentId: agentID, sessionId: session.id)
        let registered = await router.handle(method: "POST", path: "/v1/workspace-browser/register", body: try encoder.encode(owner))
        #expect(registered.status == 200)
        let browser = await service.toolExecution.browserService
        let commandTask = Task { try await browser.open(sessionID: session.id, url: "https://example.com") }
        var command: WorkspaceBrowserCommand?
        for _ in 0..<100 {
            let response = await router.handle(method: "POST", path: "/v1/workspace-browser/poll", body: try encoder.encode(owner))
            #expect(response.status == 200)
            command = try JSONDecoder().decode(WorkspaceBrowserCommands.self, from: response.body).commands.first
            if command != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let polled = try #require(command)
        let completed = await router.handle(method: "POST", path: "/v1/workspace-browser/complete", body: try encoder.encode(
            WorkspaceBrowserCompletion(binding: owner, commandId: polled.id, data: .object(["url": .string("https://example.com")]), imageBase64: nil, error: nil)
        ))
        #expect(completed.status == 200)
        #expect(try await commandTask.value.asObject?["url"]?.asString == "https://example.com")
        let disconnected = await router.handle(method: "POST", path: "/v1/workspace-browser/disconnect", body: try encoder.encode(owner))
        #expect(disconnected.status == 200)
        let unknown = WorkspaceBrowserBinding(bridgeId: UUID().uuidString, agentId: agentID, sessionId: "missing")
        let rejected = await router.handle(method: "POST", path: "/v1/workspace-browser/register", body: try encoder.encode(unknown))
        #expect(rejected.status == 400)
    }
}


extension WorkspaceBrowserBridgeTests {
    @Test func workspaceCommandsRequireAdvertisedCapability() async throws {
        let bridge = WorkspaceBrowserBridgeService()
        let legacy = binding("legacy")
        try await bridge.register(legacy)
        await #expect(throws: (any Error).self) {
            try await bridge.run(sessionID: "legacy", name: "tabs", requiredCapability: "tabs_v1")
        }
        #expect(try await bridge.poll(legacy).commands.isEmpty)
        let modern = WorkspaceBrowserBinding(bridgeId: UUID().uuidString, agentId: "agent", sessionId: "modern", capabilities: ["tabs_v1"])
        try await bridge.register(modern)
        let task = Task { try await bridge.run(sessionID: "modern", name: "tabs", input: .object(["operation": .string("list")]), requiredCapability: "tabs_v1") }
        let command = try await next(bridge, modern)
        #expect(command.name == "tabs")
        try await bridge.complete(.init(binding: modern, commandId: command.id, data: .object(["workspace": .object(["tabs": .array([])])]), imageBase64: nil, error: nil))
        #expect(try await task.value.asObject?["workspace"] != nil)
        let data = Data("{\"bridgeId\":\"x\",\"agentId\":\"a\",\"sessionId\":\"s\"}".utf8)
        #expect(try JSONDecoder().decode(WorkspaceBrowserBinding.self, from: data).capabilities == nil)
    }
}
