import Foundation
import Protocols
import Testing
@testable import sloppy

struct DevicePreviewToolTests {
    @Test func discoveryIncludesTheDeviceOperationSchema() async throws {
        let tools = await ToolCatalog.listToolsPayload(mcpRegistry: nil)
        let tool = try #require(tools.first { $0.asObject?["name"]?.asString == "devices.preview" }?.asObject)
        let schema = try #require(tool["parameters"]?.asObject)
        #expect(schema["required"]?.asArray?.contains(.string("operation")) == true)
        #expect(schema["properties"]?.asObject?["platform"] != nil)
        #expect(schema["properties"]?.asObject?["endX"]?.asObject?["type"] == .string("number"))
    }

    @Test func validatesAndRoutesDeviceInputOnlyToInteractiveClients() async throws {
        let bridge = WorkspaceBrowserBridgeService()
        var binding = WorkspaceBrowserBinding(bridgeId: UUID().uuidString, agentId: "agent", sessionId: "chat",
            capabilities: ["devices_v1"])
        try await bridge.register(binding)
        let directory = FileManager.default.temporaryDirectory
        let tool = DevicePreviewTool()
        let tap: [String: JSONValue] = ["operation": .string("tap"), "deviceId": .string("device"),
            "x": .number(0.2), "y": .number(1)]
        await #expect(throws: (any Error).self) {
            try await tool.run(arguments: tap, bridge: bridge, sessionID: "chat", captureDirectory: directory)
        }
        #expect(try await bridge.poll(binding).commands.isEmpty)
        await bridge.disconnect(binding)
        binding.capabilities?.append("devices_interaction_v1")
        try await bridge.register(binding)
        for invalid in [
            tap.merging(["x": .number(-1)], uniquingKeysWith: { _, new in new }),
            tap.merging(["x": .string("0.2")], uniquingKeysWith: { _, new in new }),
            ["operation": .string("type"), "deviceId": .string("device"), "text": .string("日本語")],
            ["operation": .string("swipe"), "deviceId": .string("device"), "x": .number(0), "y": .number(0),
             "endX": .number(1), "endY": .number(1), "durationMs": .number(55.5)],
        ] {
            await #expect(throws: (any Error).self) {
                try await tool.run(arguments: invalid, bridge: bridge, sessionID: "chat", captureDirectory: directory)
            }
        }
        #expect(try await bridge.poll(binding).commands.isEmpty)
        let request = Task {
            try await tool.run(arguments: tap, bridge: bridge, sessionID: "chat", captureDirectory: directory)
        }
        let command = try await next(bridge, binding)
        #expect(command.input == .object(tap))
        try await bridge.complete(.init(binding: binding, commandId: command.id, data: .object([:])))
        #expect(try await request.value.asObject?["surface"] == .string("devices_panel"))
    }

    @Test func oldOrDisconnectedClientsCannotStartSomethingOnCore() async throws {
        let bridge = WorkspaceBrowserBridgeService()
        let owner = WorkspaceBrowserBinding(bridgeId: UUID().uuidString, agentId: "agent", sessionId: "chat")
        try await bridge.register(owner)
        await #expect(throws: (any Error).self) {
            try await DevicePreviewTool().run(arguments: ["operation": .string("start"), "platform": .string("iOS")],
                bridge: bridge, sessionID: "chat", captureDirectory: FileManager.default.temporaryDirectory)
        }
        #expect(try await bridge.poll(owner).commands.isEmpty)
        await bridge.disconnect(owner)
        await #expect(throws: WorkspaceBrowserBridgeError.unavailable) {
            try await DevicePreviewTool().run(arguments: ["operation": .string("status")],
                bridge: bridge, sessionID: "chat", captureDirectory: FileManager.default.temporaryDirectory)
        }
    }

    @Test func routesDeviceCommandsAndStoresOnlyTheReturnedPNG() async throws {
        let bridge = WorkspaceBrowserBridgeService()
        let owner = WorkspaceBrowserBinding(bridgeId: UUID().uuidString, agentId: "agent", sessionId: "chat", capabilities: ["devices_v1"])
        try await bridge.register(owner)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("device-tool-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = Task {
            try await DevicePreviewTool().run(arguments: ["operation": .string("screenshot"), "deviceId": .string("fixture")],
                bridge: bridge, sessionID: "chat", captureDirectory: directory)
        }
        let command = try await next(bridge, owner)
        #expect(command.name == "devices")
        #expect(command.input.asObject?["deviceId"]?.asString == "fixture")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZlSAAAAAASUVORK5CYII=")!
        try await bridge.complete(.init(binding: owner, commandId: command.id,
            data: .object(["devicePreview": .object(["state": .string("ready")])]), imageBase64: png.base64EncodedString(), error: nil))
        let result = try await request.value.asObject
        let path = try #require(result?["path"]?.asString)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == png)
        #expect(result?["imageBase64"] == nil)
        #expect(result?["surface"]?.asString == "devices_panel")
        #expect(result?["mediaType"]?.asString == "image/png")
    }

    private func next(_ bridge: WorkspaceBrowserBridgeService, _ owner: WorkspaceBrowserBinding) async throws -> WorkspaceBrowserCommand {
        for _ in 0..<100 {
            if let command = try await bridge.poll(owner).commands.first { return command }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw WorkspaceBrowserBridgeError.timedOut
    }
}
