import AnyLanguageModel
import Foundation
import Protocols

struct DevicePreviewTool: CoreTool {
    let domain = "devices"
    let name = "devices.preview"
    let title = "Test a mobile app in Sloppy Devices"
    let status = "preview"
    let description = """
        Use this tool to interactively test mobile apps on the connected Sloppy macOS client, including with remote Core.
        Call list for the requested platform, pick an exact deviceId (ask if several match), then call start to open Devices.
        For a supplied network ADB address, call start with androidAddress instead. Poll status until devicePreview.state
        is ready or failed. Use the targetId returned by status for tap, swipe, type and screenshot. Coordinates are normalized
        to the device screen, with (0, 0) at the top left. Use images.inspect on the PNG path returned by screenshot to verify
        the result. Actions continue while Devices is hidden. If the target is lost, start it again. After an input error,
        inspect a screenshot before retrying. stop disconnects the preview and leaves the device running.
        """

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "operation", description: "list, start, status, tap, swipe, type, screenshot or stop.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "platform", description: "iOS or Android; required for list and start.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "deviceId", description: "UUID/AVD/serial from list for start. Pass the active targetId from status for input and screenshots.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "androidAddress", description: "Optional Android ADB host:port instead of deviceId.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "x", description: "Normalized X coordinate for tap or swipe start.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
            .init(name: "y", description: "Normalized Y coordinate for tap or swipe start.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
            .init(name: "endX", description: "Normalized swipe end X coordinate.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
            .init(name: "endY", description: "Normalized swipe end Y coordinate.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
            .init(name: "durationMs", description: "Optional swipe duration from 50 to 3000 milliseconds. Defaults to 300.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
            .init(name: "text", description: "Text for type, up to 512 ASCII characters, including space, tab and newline.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        await browserResult(tool: name) {
            try await run(arguments: arguments, bridge: context.browserService.workspaceBridge,
                sessionID: context.sessionID, captureDirectory: context.workspaceRootURL.appendingPathComponent("device-captures"))
        }
    }

    func run(arguments: [String: JSONValue], bridge: WorkspaceBrowserBridgeService,
             sessionID: String, captureDirectory: URL) async throws -> JSONValue {
        let interactive = ["list", "tap", "swipe", "type"]
        let operation = arguments["operation"]?.asString ?? ""
        guard (["start", "status", "screenshot", "stop"] + interactive).contains(operation) else {
            throw WorkspaceBrowserBridgeError.commandFailed("Choose a Devices operation: list, start, status, tap, swipe, type, screenshot or stop.")
        }
        let usesPlatform = operation == "start" || operation == "list"
        if usesPlatform, !["iOS", "Android"].contains(arguments["platform"]?.asString ?? "") {
            throw WorkspaceBrowserBridgeError.commandFailed("Choose platform iOS or Android.")
        }
        let sendsInput = ["tap", "swipe", "type"].contains(operation)
        let required = ["operation"] + (usesPlatform ? ["platform"] : []) + (sendsInput ? ["deviceId"] : [])
        let optional = operation == "start" ? ["deviceId", "androidAddress"] : operation == "screenshot" ? ["deviceId"] : []
        var input = try validatedBrowserWorkspaceInput(arguments, required: required, optional: optional).asObject ?? [:]
        if operation == "tap" || operation == "swipe" {
            let coordinateFields = operation == "tap" ? ["x", "y"] : ["x", "y", "endX", "endY"]
            for field in coordinateFields {
                guard let number = arguments[field]?.asNumber, (0...1).contains(number) else {
                    throw WorkspaceBrowserBridgeError.commandFailed("\(field) must be a number between 0 and 1.")
                }
                input[field] = .number(number)
            }
        }
        if operation == "swipe", let value = arguments["durationMs"], value != .null {
            guard let duration = value.asNumber, (50...3000).contains(duration), duration.rounded() == duration else {
                throw WorkspaceBrowserBridgeError.commandFailed("durationMs must be an integer between 50 and 3000.")
            }
            input["durationMs"] = .number(duration)
        }
        if operation == "type" {
            guard let value = arguments["text"]?.asString, (1...512).contains(value.utf8.count),
                  value.utf8.allSatisfy({ (32...126).contains($0) || $0 == 9 || $0 == 10 }) else {
                throw WorkspaceBrowserBridgeError.commandFailed("Use 1–512 ASCII characters for device keyboard input.")
            }
            input["text"] = .string(value)
        }
        let capability = interactive.contains(operation) ? "devices_interaction_v1" : "devices_v1"
        let result = try await bridge.run(sessionID: sessionID, name: "devices", input: .object(input), requiredCapability: capability)
        guard var data = result.asObject else { throw BrowserCDPError.invalidResponse }
        if operation == "screenshot" {
            guard let base64 = data.removeValue(forKey: "imageBase64")?.asString, base64.utf8.count <= 28 * 1024 * 1024,
                  let png = Data(base64Encoded: base64), png.count <= 20 * 1024 * 1024,
                  png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { throw BrowserCDPError.invalidResponse }
            try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
            let file = captureDirectory.appendingPathComponent(UUID().uuidString + ".png")
            try png.write(to: file, options: .atomic)
            data["path"] = .string(file.path)
            data["mediaType"] = .string("image/png")
            data["bytes"] = .number(Double(png.count))
        }
        data["surface"] = .string("devices_panel")
        return .object(data)
    }
}
