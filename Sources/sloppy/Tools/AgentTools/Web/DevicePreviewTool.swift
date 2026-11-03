import AnyLanguageModel
import Foundation
import Protocols

struct DevicePreviewTool: CoreTool {
    let domain = "devices"
    let name = "devices.preview"
    let title = "Open simulator in Sloppy"
    let status = "preview"
    let description = "Start an iOS simulator or Android emulator in the connected macOS client's Devices panel, without computer use. This runs on the client Mac, including with remote Core. Start returns immediately; poll status until devicePreview.state is ready or failed. Optional deviceId selects an iOS UUID, Android serial or AVD identifier; omission boots the bridge's default available device. screenshot captures a real device frame and returns a PNG path for images.inspect. stop disconnects only this conversation's preview and leaves the simulator running. Requires devices_v1; no desktop or server-side fallback."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "operation", description: "start, status, screenshot or stop.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "platform", description: "iOS or Android; required for start.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "deviceId", description: "Optional target UUID/AVD/serial for start; observed device ID from status for screenshot.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "androidAddress", description: "Optional Android ADB host:port instead of deviceId.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
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
        let input = try validatedBrowserWorkspaceInput(arguments, required: ["operation"], optional: ["platform", "deviceId", "androidAddress"])
        guard let operation = input.asObject?["operation"]?.asString,
              ["start", "status", "screenshot", "stop"].contains(operation),
              operation != "start" || ["iOS", "Android"].contains(input.asObject?["platform"]?.asString ?? "") else {
            throw WorkspaceBrowserBridgeError.commandFailed("Use start/status/screenshot/stop, with platform iOS or Android for start.")
        }
        let result = try await bridge.run(sessionID: sessionID, name: "devices", input: input, requiredCapability: "devices_v1")
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
