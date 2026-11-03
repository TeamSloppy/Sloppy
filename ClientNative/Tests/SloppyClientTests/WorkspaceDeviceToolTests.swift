#if os(macOS)
import AppKit
import Foundation
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
import SwiftUI
import Testing
@testable import SloppyClient

@Suite("Agent device preview", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct WorkspaceDeviceToolTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_AGENT_DEVICE_BRIDGE_ROOT"] != nil))
    func launchesARealSimulatorThroughTheAgentCommand() async throws {
        let root = try #require(ProcessInfo.processInfo.environment["SLOPPY_AGENT_DEVICE_BRIDGE_ROOT"])
        let session = WorkspaceDeviceSession(installationRoot: URL(fileURLWithPath: root))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 480, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let runtime = WorkspaceDeviceToolRuntime(session: session) { device in
            window.contentView = NSHostingView(rootView: WorkspaceDevicePanelView(session: device)
                .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
            window.makeKeyAndOrderFront(nil)
        }
        let binding = WorkspaceBrowserBinding(bridgeId: UUID().uuidString, agentId: "agent", sessionId: "live-chat")
        defer { runtime.stop(); window.contentView = nil; window.close() }
        let start = await runtime.execute(try command(["operation": "start", "platform": "iOS"]), binding: binding)
        #expect(start.error == nil)
        for _ in 0..<900 where !session.isLoaded && session.errorMessage == nil {
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(session.errorMessage == nil)
        let status = await runtime.execute(try command(["operation": "status"]), binding: binding)
        #expect(status.data?.devicePreview?.state == .ready)
        let device = try #require(status.data?.devicePreview?.devices.first)
        let frame = await runtime.execute(try command(["operation": "screenshot", "deviceId": device.id]), binding: binding)
        let png = try #require(frame.imageBase64.flatMap { Data(base64Encoded: $0) })
        let captured = try #require(NSBitmapImageRep(data: png))
        #expect(captured.pixelsWide > 100)
        if let path = ProcessInfo.processInfo.environment["SLOPPY_AGENT_DEVICE_SCREENSHOT"] {
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    @Test func startsTheRequestedDeviceInItsOwnTabAndReturnsARealFrame() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("device-agent-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("node_modules/serve-sim/dist/serve-sim.js")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 32, height: 64), flipped: false) { rect in
            NSColor.systemGreen.setFill(); rect.fill(); return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let jpeg = try #require(bitmap.representation(using: .jpeg, properties: [:]))
        try """
        const fs = require('fs'), http = require('http');
        const args = process.argv.slice(2);
        fs.writeFileSync(__filename + '.arguments', JSON.stringify(args));
        const jpeg = Buffer.from('\(jpeg.base64EncodedString())', 'base64');
        http.createServer((req, res) => {
          if (req.url === '/grid/api') {
            res.end(JSON.stringify({devices:[{device:'fixture',name:'iPhone fixture',streamMjpegEndpoint:'/frame'}]}));
          } else if (req.url === '/frame') {
            res.end(Buffer.concat([Buffer.from('--frame\\r\\nContent-Type: image/jpeg\\r\\nContent-Length: '+jpeg.length+'\\r\\n\\r\\n'),jpeg]));
          } else { res.end('<html>Fixture simulator</html>'); }
        }).listen(Number(args[args.indexOf('--port') + 1]), '127.0.0.1');
        """.write(to: script, atomically: true, encoding: .utf8)

        let dock = WorkspaceDockState()
        let human = dock.open(.devices)
        let humanSession = WorkspaceDeviceSession()
        human.devices = humanSession
        let session = WorkspaceDeviceSession(installationRoot: root)
        let runtime = WorkspaceDeviceToolRuntime(session: session) { dock.presentDevice($0) }
        let browser = WorkspaceBrowserSession(apiClient: SloppyAPIClient(), agentID: "agent", sessionID: "chat",
            devices: runtime, present: {})
        defer { browser.stop(); humanSession.stop() }
        #expect(browser.binding.capabilities?.contains("devices_v1") == true)
        let target = UUID().uuidString
        let start = try command(["operation": "start", "platform": "iOS", "deviceId": target])
        let starting = await browser.execute(start)
        #expect(starting.error == nil)
        #expect(starting.data?.devicePreview?.state == .starting)
        #expect(dock.selectedTab?.devices === session)
        #expect(dock.tabs.count == 2)
        #expect(human.devices === humanSession)
        for _ in 0..<150 where !session.isLoaded && session.errorMessage == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(session.errorMessage == nil)
        #expect(session.isLoaded)
        let url = session.baseURL
        _ = await browser.execute(start)
        #expect(session.baseURL == url)
        #expect(dock.tabs.count == 2)
        let arguments = try JSONDecoder().decode([String].self, from: Data(contentsOf: script.appendingPathExtension("arguments")))
        #expect(arguments.first == target)
        let status = await browser.execute(try command(["operation": "status"]))
        #expect(status.data?.devicePreview?.state == .ready)
        #expect(status.data?.devicePreview?.devices.first?.id == "fixture")
        let captured = await browser.execute(try command(["operation": "screenshot", "deviceId": "fixture"]))
        #expect(captured.error == nil)
        let png = try #require(captured.imageBase64.flatMap { Data(base64Encoded: $0) })
        #expect(png.starts(with: [137, 80, 78, 71]))
        let capturedBitmap = try #require(NSBitmapImageRep(data: png))
        #expect(capturedBitmap.pixelsWide == 32)
        browser.stop()
        let stopped = await browser.execute(try command(["operation": "status"]))
        #expect(stopped.data?.devicePreview?.state == .stopped)
    }

    @Test func malformedTargetsNeverStartOrPresentADevice() async throws {
        let runtime = WorkspaceDeviceToolRuntime { _ in Issue.record("An invalid command presented Devices") }
        let binding = WorkspaceBrowserBinding(bridgeId: UUID().uuidString, agentId: "agent", sessionId: "chat")
        for input in [
            ["operation": "start", "platform": "iOS", "deviceId": "--host"],
            ["operation": "start", "platform": "iOS", "deviceId": "device;command"],
            ["operation": "start", "platform": "iOS", "androidAddress": "192.168.3.172:55555"],
            ["operation": "start", "platform": "Android", "androidAddress": "http://host:5555"],
            ["operation": "start", "platform": "unknown"],
        ] {
            let result = await runtime.execute(try command(input), binding: binding)
            #expect(result.error != nil)
            #expect(!runtime.session.isStarting)
        }
        runtime.stop()
    }

    @Test func unsupportedClientDoesNotFallBackToOpeningABrowser() async throws {
        let browser = WorkspaceBrowserSession(apiClient: SloppyAPIClient(), agentID: "agent", sessionID: "chat") {
            Issue.record("A device command opened the browser")
        }
        let result = await browser.execute(try command(["operation": "status"]))
        #expect(result.error != nil)
        #expect(browser.binding.capabilities?.contains("devices_v1") != true)
        browser.stop()
    }

    private func command(_ input: [String: String]) throws -> WorkspaceBrowserCommand {
        try JSONDecoder().decode(WorkspaceBrowserCommand.self, from: JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString, "name": "devices", "input": input,
        ]))
    }
}
#endif
