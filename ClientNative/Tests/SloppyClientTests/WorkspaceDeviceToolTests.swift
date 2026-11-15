#if os(macOS)
import AppKit
import Foundation
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyUITestSupport
import SwiftUI
import Testing
@testable import SloppyClient

@Suite("Agent device preview", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct WorkspaceDeviceToolTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_AGENT_DEVICE_BRIDGE_ROOT"] != nil))
    func controlsARealDeviceThroughTheAgentCommands() async throws {
        let environment = ProcessInfo.processInfo.environment
        let root = try #require(environment["SLOPPY_AGENT_DEVICE_BRIDGE_ROOT"])
        let platform = environment["SLOPPY_AGENT_DEVICE_PLATFORM"] ?? "iOS"
        let session = WorkspaceDeviceSession(installationRoot: URL(fileURLWithPath: root))
        let dock = WorkspaceDockState()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 480, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        func show(_ device: WorkspaceDeviceSession) {
            dock.presentDevice(device)
            window.contentView = NSHostingView(rootView: WorkspaceDevicePanelView(session: device)
                .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
            window.makeKeyAndOrderFront(nil)
        }
        let runtime = WorkspaceDeviceToolRuntime(session: session, present: show)
        let binding = WorkspaceBrowserBinding(bridgeId: UUID().uuidString, agentId: "agent", sessionId: "live-chat")
        defer { runtime.stop(); window.contentView = nil; window.close() }
        func execute(_ input: [String: Any]) async throws -> WorkspaceBrowserCompletion {
            let result = await runtime.execute(try command(input), binding: binding)
            try #require(result.error == nil, "Device command failed: \(result.error ?? "")")
            return result
        }
        let inventory = try await execute(["operation": "list", "platform": platform])
        var startInput: [String: Any] = ["operation": "start", "platform": platform]
        if let target = environment["SLOPPY_AGENT_DEVICE_TARGET"] {
            #expect(inventory.data?.devicePreview?.devices.contains(where: { $0.id == target }) == true)
            startInput["deviceId"] = target
        }
        let start = try await execute(startInput)
        #expect(start.error == nil)
        let tab = try #require(dock.selectedTab)
        dock.hide()
        window.contentView = nil
        var status = start.data?.devicePreview
        let deadline = ContinuousClock.now + .seconds(325)
        while status?.state == .starting, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(500))
            status = try await execute(["operation": "status"]).data?.devicePreview
        }
        try #require(status?.state == .ready, "Device startup failed: \(status?.error ?? "timeout")")
        let target = try #require(status?.targetId)
        func screenshot() async throws -> Data {
            let frame = try await execute(["operation": "screenshot", "deviceId": target])
            return try #require(frame.imageBase64.flatMap { Data(base64Encoded: $0) })
        }
        let baseline = try await screenshot()
        let captured = try #require(NSBitmapImageRep(data: baseline))
        #expect(captured.pixelsWide > 100)
        let output = environment["SLOPPY_AGENT_DEVICE_SCREENSHOT"].map { URL(fileURLWithPath: $0) }
        if let output { try baseline.write(to: output) }
        if let input = environment["SLOPPY_AGENT_DEVICE_ACTIONS"] {
            let actions = try #require(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [[String: Any]])
            var previous = baseline
            for (index, action) in actions.enumerated() {
                if index == 1 { dock.close(tab.id) }
                var request = action
                request["deviceId"] = target
                _ = try await execute(request)
                try await Task.sleep(for: .milliseconds(600))
                var frame = try await screenshot()
                let settleDeadline = ContinuousClock.now + .seconds(5)
                while frame == previous, ContinuousClock.now < settleDeadline {
                    try await Task.sleep(for: .milliseconds(250))
                    frame = try await screenshot()
                }
                #expect(frame != previous, "Device screen did not change after action \(index + 1).")
                if let output {
                    try frame.write(to: output.deletingPathExtension().appendingPathExtension("\(index + 1).png"))
                }
                previous = frame
            }
        }
        #expect(!dock.isPresented)
        show(session)
        #expect(dock.selectedTab?.devices?.targetID == target)
        _ = try await execute(["operation": "stop"])
        #expect(session.baseURL == nil)
    }

    @Test func androidActionsStayOnTheVerifiedDeviceAfterClosingDevices() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("device-agent-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("node_modules/serve-avd/dist/serve-avd.js")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        let adb = root.appendingPathComponent("adb")
        try """
        #!/bin/sh
        if [ "$*" = '-s emulator-5554 emu avd name' ]; then
          printf 'Pixel_Fixture\\r\\nOK\\r\\n'
        else
          exit 1
        fi
        """.write(to: adb, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adb.path)
        let image = NSImage(size: NSSize(width: 32, height: 64), flipped: false) { rect in
            NSColor.systemGreen.setFill(); rect.fill(); return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try """
        const fs = require('fs'), http = require('http');
        const args = process.argv.slice(2);
        fs.writeFileSync(__filename + '.arguments', JSON.stringify(args));
        const png = Buffer.from('\(png.base64EncodedString())', 'base64');
        http.createServer((req, res) => {
          if (req.url === '/grid/api') {
            const serial = fs.existsSync(__filename + '.lost') ? 'emulator-5556' : 'emulator-5554';
            res.end(JSON.stringify({devices:[{device:serial,serial,state:'device',attached:true,name:'Pixel fixture',streamMjpegEndpoint:'/frame',screenshotEndpoint:'/helper/'+serial+'/screenshot.png'}]}));
          } else if (req.url === '/helper/emulator-5554/screenshot.png') {
            res.writeHead(200, {'Content-Type':'image/png', 'Content-Length':png.length});
            res.end(png);
          } else if (req.url === '/helper/emulator-5554/action' && req.method === 'POST') {
            let body = '';
            req.on('data', chunk => body += chunk);
            req.on('end', () => {
              fs.appendFileSync(__filename + '.actions', body + '\\n');
              res.end(JSON.stringify({ok:true}));
            });
          } else if (req.url === '/api') { res.end('{}'); }
          else if (req.url !== '/') { res.writeHead(404).end(); }
        }).listen(Number(args[args.indexOf('--port') + 1]), '127.0.0.1');
        """.write(to: script, atomically: true, encoding: .utf8)

        let api = SloppyAPIClient(baseURL: try #require(URL(string: "https://devices-test.invalid")))
        let main = MainViewModel(endpoint: api.endpoint, settings: ClientSettings(),
            connectionMonitor: ConnectionMonitor(baseURL: api.baseURL), cacheStore: ClientCacheStore(path: ":memory:"),
            apiClient: api, responseNotificationScheduler: DeviceTestNotifications(),
            onOpenSettings: { _ in }, onOpenWorkspace: {})
        main.createBlankChatTab()
        let ownerTabID = try #require(main.selectedTabID)
        let dock = main.workspaceDockState
        let human = dock.open(.devices)
        let humanSession = WorkspaceDeviceSession()
        human.devices = humanSession
        let session = WorkspaceDeviceSession(installationRoot: root, adbExecutable: adb)
        let runtime = WorkspaceDeviceToolRuntime(session: session) { dock.presentDevice($0) }
        let browser = WorkspaceBrowserSession(apiClient: api, agentID: "agent", sessionID: "chat",
            devices: runtime, present: {})
        main.browserSessions[ownerTabID] = browser
        defer { browser.stop(); humanSession.stop() }
        #expect(browser.binding.capabilities?.contains("devices_v1") == true)
        #expect(browser.binding.capabilities?.contains("devices_interaction_v1") == true)
        let target = "Pixel_Fixture"
        let start = try command(["operation": "start", "platform": "Android", "deviceId": target])
        let starting = await browser.execute(start)
        #expect(starting.error == nil)
        #expect(starting.data?.devicePreview?.state == .starting)
        #expect(dock.selectedTab?.devices === session)
        #expect(dock.tabs.count == 2)
        #expect(human.devices === humanSession)
        let agentTab = try #require(dock.selectedTab)
        dock.hide()
        for _ in 0..<150 where session.baseURL == nil && session.controlError == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(session.errorMessage == nil)
        #expect(!session.isLoaded)
        let url = session.baseURL
        _ = await browser.execute(start)
        #expect(session.baseURL == url)
        #expect(dock.tabs.count == 2)
        #expect(!dock.isPresented)
        let arguments = try JSONDecoder().decode([String].self, from: Data(contentsOf: script.appendingPathExtension("arguments")))
        #expect(arguments.first == target)
        let status = await browser.execute(try command(["operation": "status"]))
        #expect(status.data?.devicePreview?.state == .ready)
        let serial = try #require(status.data?.devicePreview?.targetId)
        #expect(serial == "emulator-5554")
        dock.close(agentTab.id)
        #expect(session.baseURL == url)
        #expect(dock.tabs.count == 1)
        let wrongTarget = await browser.execute(try command(["operation": "tap", "deviceId": "emulator-5556", "x": 0.25, "y": 0.75]))
        #expect(wrongTarget.error != nil)
        let tap = await browser.execute(try command(["operation": "tap", "deviceId": serial, "x": 0.25, "y": 0.75]))
        #expect(tap.error == nil)
        let swipe = await browser.execute(try command(["operation": "swipe", "deviceId": serial,
            "x": 0.25, "y": 0.75, "endX": 0.25, "endY": 0.25, "durationMs": 200]))
        #expect(swipe.error == nil)
        let typed = await browser.execute(try command(["operation": "type", "deviceId": serial, "text": "Sloppy"]))
        #expect(typed.error == nil)
        let actions = try String(contentsOf: script.appendingPathExtension("actions"), encoding: .utf8)
            .split(separator: "\n").map { line in
                try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            }
        #expect(actions.map { $0["action"] as? String } == ["tap", "swipe", "text"])
        #expect(actions.first?["x"] as? Double == 0.25)
        #expect(!dock.isPresented)
        let captured = await browser.execute(try command(["operation": "screenshot", "deviceId": serial]))
        #expect(captured.error == nil)
        let capturedPNG = try #require(captured.imageBase64.flatMap { Data(base64Encoded: $0) })
        #expect(capturedPNG.starts(with: [137, 80, 78, 71]))
        let capturedBitmap = try #require(NSBitmapImageRep(data: capturedPNG))
        #expect(capturedBitmap.pixelsWide == 32)
        let reopened = dock.presentDevice(session)
        #expect(reopened.devices?.targetID == serial)
        try Data().write(to: script.appendingPathExtension("lost"))
        let lost = await browser.execute(try command(["operation": "status"]))
        #expect(lost.data?.devicePreview?.state == .failed)
        #expect(lost.data?.devicePreview?.targetId == serial)
        let retargeted = await browser.execute(try command(["operation": "tap", "deviceId": "emulator-5556", "x": 0.25, "y": 0.75]))
        #expect(retargeted.error != nil)
        main.closeTab(ownerTabID)
        #expect(main.browserSessions[ownerTabID] == nil)
        #expect(dock.tabs.map(\.id) == [human.id])
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

    private func command(_ input: [String: Any]) throws -> WorkspaceBrowserCommand {
        try JSONDecoder().decode(WorkspaceBrowserCommand.self, from: JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString, "name": "devices", "input": input,
        ]))
    }
}

@MainActor
private final class DeviceTestNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
