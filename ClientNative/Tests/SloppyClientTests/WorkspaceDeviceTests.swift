#if os(macOS)
import AppKit
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyUITestSupport
import SwiftUI
import Testing
@testable import SloppyClient

@Suite("Workspace device state", .serialized)
@MainActor
struct WorkspaceDeviceStateTests {
    @Test func androidAddressesAreSeparateFromBridgeURLs() throws {
        for address in ["192.168.3.172:55555", "android.local:5555", "[::1]:5555"] {
            #expect(try AndroidDeviceEndpoint(" \(address)\n").address == address)
        }
        for address in ["", "192.168.3.172", "host:0", "host:65536", "host:-1", "host:+5555",
                        "http://192.168.3.172:55555", "host:5555/path", "user@host:5555",
                        "host:5555?x=1", "host:5555#x", "--help:5555", "host name:5555",
                        "host;whoami:5555", "host:5555\n--help"] {
            #expect(throws: (any Error).self) { try AndroidDeviceEndpoint(address) }
        }
    }

    @Test func invalidAndroidAddressPreservesAnExistingPreview() {
        let session = WorkspaceDeviceSession()
        defer { session.stop() }
        session.connect("http://127.0.0.1:3200")
        session.connectAndroid("http://192.168.3.172:55555")
        #expect(session.baseURL?.absoluteString == "http://127.0.0.1:3200")
        #expect(session.errorMessage != nil)
        #expect(!session.isStarting)
    }

    @Test func onlyLocalHTTPBridgesAreAccepted() throws {
        for url in ["http://localhost:3200", "http://127.0.0.1:43123/", "http://[::1]:3200"] {
            #expect(try WorkspaceDeviceSession.localURL(url).scheme == "http")
        }
        for url in ["https://example.com", "file:///tmp/bridge", "http://127.0.0.1.evil.com",
                    "http://user:password@localhost:3200", "http://localhost:3200/?token=secret",
                    "http://localhost:3200/other", "http://localhost:99999", "http://localhost:0"] {
            #expect(throws: (any Error).self) { try WorkspaceDeviceSession.localURL(url) }
        }
    }

    @Test func closingDeviceTabDisconnectsItsSessionAndPreservesOtherTabs() throws {
        let dock = WorkspaceDockState()
        let browser = dock.open(.browser)
        let tab = dock.open(.devices)
        let session = WorkspaceDeviceSession()
        tab.devices = session
        session.connect("http://127.0.0.1:3200")
        #expect(tab.title == "Devices")
        #expect(!WorkspaceSidePanelItem.devices.requiresProject)
        #expect(session.baseURL != nil)
        dock.close(tab.id)
        #expect(session.baseURL == nil)
        #expect(!session.isLoaded)
        #expect(dock.selectedTab === browser)
        #expect(dock.tabs.count == 1)
    }

    @Test func multipartFramesAreBoundedAndDeviceSourcesStayOnTheBridgeOrigin() throws {
        let jpeg = Data([255, 216, 1, 2, 255, 217])
        var parser = DeviceFrameCapture.Parser()
        let stream = Data("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: 6\r\n\r\n".utf8) + jpeg
        var result: Data?
        for byte in stream { result = try parser.append(byte) }
        #expect(result == jpeg)
        var invalid = DeviceFrameCapture.Parser()
        #expect(throws: (any Error).self) {
            for byte in Data("--frame\r\nContent-Length: 999999999\r\n\r\n".utf8) { _ = try invalid.append(byte) }
        }
        let base = try WorkspaceDeviceSession.localURL("http://127.0.0.1:3200")
        let grid = Data("""
        {"devices":[
          {"device":"iphone","name":"iPhone","helper":{"streamUrl":"http://127.0.0.1:3200/helper/iphone/stream.mjpeg"}},
          {"device":"emulator-5554","name":"Pixel","streamMjpegEndpoint":"/helper/emulator-5554/stream.mjpeg"},
          {"device":"offline","helper":null},
          {"device":"external","streamMjpegEndpoint":"https://example.com/frame"}]}
        """.utf8)
        #expect(try DeviceFrameSource.decode(grid, baseURL: base).map(\.id) == ["iphone", "emulator-5554"])
    }
}

@Suite("Workspace devices", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct WorkspaceDeviceTests {

    @Test func setupExposesPlatformCardsAndNetworkConnectionAtNarrowWidths() async throws {
        AppKitTestAccessibility.enable()
        let session = WorkspaceDeviceSession()
        let host = NSHostingView(rootView: WorkspaceDevicePanelView(session: session)
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 480, height: 850),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { session.stop(); window.contentView = nil; window.close() }
        for width in [480.0, 360.0] {
            window.setContentSize(NSSize(width: width, height: 850))
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            let bounds = window.convertToScreen(host.convert(host.bounds, to: nil))
            for id in ["workspace.devices.start.iOS", "workspace.devices.start.android",
                       "workspace.devices.android.address", "workspace.devices.android.connect"] {
                let element = try #require(AppKitTestAccessibility.element(in: host, identifier: id))
                let frame = try #require(AppKitTestAccessibility.frame(of: element))
                #expect(frame.minX >= bounds.minX && frame.maxX <= bounds.maxX)
            }
            if let directory = ProcessInfo.processInfo.environment["SLOPPY_DEVICE_SCREENSHOTS"] {
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("device-setup-\(Int(width)).png"))
            }
        }
    }

    @Test func networkAndroidConnectsThroughADBAndTargetsOnlyThatDevice() async throws {
        let fixture = try makeNetworkFixture(state: "device")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = WorkspaceDeviceSession(installationRoot: fixture.root, adbExecutable: fixture.adb)
        defer { session.stop() }
        session.connectAndroid("192.168.3.172:55555")
        for _ in 0..<150 where session.isStarting { try await Task.sleep(for: .milliseconds(100)) }
        #expect(session.errorMessage == nil)
        #expect(session.baseURL?.host == "127.0.0.1")
        #expect(session.platform == .android)
        #expect(session.androidAddress == "192.168.3.172:55555")
        let calls = try String(contentsOf: fixture.adb.appendingPathExtension("arguments"), encoding: .utf8)
        #expect(calls == "connect 192.168.3.172:55555\n-s 192.168.3.172:55555 get-state\n")
        let arguments = try JSONDecoder().decode([String].self, from: Data(contentsOf: fixture.script.appendingPathExtension("arguments")))
        #expect(arguments.first == "192.168.3.172:55555")
        #expect(arguments.contains("127.0.0.1"))
        let url = try #require(session.baseURL)
        session.stop()
        #expect(session.androidAddress == nil)
        try await Task.sleep(for: .milliseconds(300))
        await #expect(throws: (any Error).self) {
            try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 1))
        }
    }

    @Test func adbConnectSuccessStillRequiresAnOnlineDevice() async throws {
        let fixture = try makeNetworkFixture(state: "unauthorized")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = WorkspaceDeviceSession(installationRoot: fixture.root, adbExecutable: fixture.adb)
        defer { session.stop() }
        session.connectAndroid("192.168.3.172:55555")
        for _ in 0..<150 where session.isStarting { try await Task.sleep(for: .milliseconds(100)) }
        #expect(session.baseURL == nil)
        #expect(session.errorMessage?.contains("unauthorized") == true)
        #expect(session.errorMessage?.contains("allow debugging") == true)
        #expect(!FileManager.default.fileExists(atPath: fixture.script.appendingPathExtension("arguments").path))
    }

    private func makeNetworkFixture(state: String) throws -> (root: URL, adb: URL, script: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sloppy-adb-test-\(UUID())")
        let script = root.appendingPathComponent("node_modules/serve-avd/dist/serve-avd.js")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        let adb = root.appendingPathComponent("fake-adb")
        try """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$0.arguments"
        if [ "$1" = connect ]; then
            printf 'connected\\n'
        else
            printf '%s\\n' '\(state)'
        fi
        """.write(to: adb, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adb.path)
        try """
        const fs = require('fs');
        const http = require('http');
        const args = process.argv.slice(2);
        fs.writeFileSync(__filename + '.arguments', JSON.stringify(args));
        http.createServer((req, res) => { res.end('<html>Android fixture</html>'); })
          .listen(Number(args[args.indexOf('--port') + 1]), '127.0.0.1');
        """.write(to: script, atomically: true, encoding: .utf8)
        return (root, adb, script)
    }

    @Test func screenshotCapturesInteractiveContentAndSurvivesDisconnect() async throws {
        let image = NSImage(size: NSSize(width: 128, height: 256), flipped: false) { rect in
            NSColor.systemGreen.setFill(); rect.fill(); return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let jpeg = try #require(bitmap.representation(using: .jpeg, properties: [:]))
        let multipart = Data("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".utf8) + jpeg
        let grid = Data("""
        {"devices":[{"device":"fixture","name":"Pixel fixture","streamMjpegEndpoint":"/stream.mjpeg"}]}
        """.utf8)
        let server = try BrowserHTTPFixture(responseDelay: 0, responses: [
            "/grid/api": ("application/json", grid),
            "/stream.mjpeg": ("multipart/x-mixed-replace; boundary=frame", multipart),
        ])
        let url = try await server.start()
        try await verifyScreen(url: url, name: "device-fixture")
        withExtendedLifetime(server) {}
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_DEVICE_PREVIEW_URL"] != nil))
    func liveDevicePreview() async throws {
        let url = try #require(URL(string: ProcessInfo.processInfo.environment["SLOPPY_DEVICE_PREVIEW_URL"] ?? ""))
        let platform = DevicePlatform(rawValue: ProcessInfo.processInfo.environment["SLOPPY_DEVICE_PREVIEW_PLATFORM"] ?? "iOS") ?? .iOS
        try await verifyScreen(url: url, name: "device-\(platform.rawValue.lowercased())-live", live: true, platform: platform)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_DEVICE_BRIDGE_ROOT"] != nil))
    func startsAndStopsItsOwnLocalBridge() async throws {
        let root = try #require(ProcessInfo.processInfo.environment["SLOPPY_DEVICE_BRIDGE_ROOT"])
        let session = WorkspaceDeviceSession(installationRoot: URL(fileURLWithPath: root))
        defer { session.stop() }
        session.start()
        for _ in 0..<600 where session.isStarting { try await Task.sleep(for: .milliseconds(200)) }
        #expect(session.errorMessage == nil)
        let url = try #require(session.baseURL)
        try await verifyScreen(url: url, name: "device-owned-bridge", live: true)
        session.stop()
        try await Task.sleep(for: .seconds(1))
        var request = URLRequest(url: url, timeoutInterval: 1)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        await #expect(throws: (any Error).self) { try await URLSession.shared.data(for: request) }
    }

    private func verifyScreen(url: URL, name: String, live: Bool = false, platform: DevicePlatform = .iOS) async throws {
        let session = WorkspaceDeviceSession()
        session.platform = platform
        var delivered: ChatComposerAttachment?
        AppKitTestAccessibility.enable()
        let host = NSHostingView(rootView: WorkspaceDevicePanelView(session: session, onAnnotate: {
            { delivered = $0; return true }
        })
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 850),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { session.stop(); window.orderOut(nil) }
        session.connect(url.absoluteString)
        for _ in 0..<300 where !session.isLoaded { try await Task.sleep(for: .milliseconds(30)) }
        #expect(session.errorMessage == nil)
        #expect(session.isLoaded)
        if live { try await Task.sleep(for: .seconds(4)) }
        else {
            _ = try await session.webView.evaluateJavaScript("document.querySelector('#name').value='Device input'; document.querySelector('#check').click()")
            #expect(try await session.webView.evaluateJavaScript("document.querySelector('#result').textContent") as? String == "Verified: Device input")
        }
        let source = try #require(try await session.captureSources().first)
        let captured = try await session.capture(source)
        #expect(captured.data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
        let bitmap = try #require(NSBitmapImageRep(data: captured.data))
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        #expect(captured.annotations.first?.comment.contains(source.id) == true)
        if !live {
            #expect(bitmap.pixelsWide == 128 && bitmap.pixelsHigh == 256)
            let color = try #require(bitmap.colorAt(x: 30, y: 30)?.usingColorSpace(.deviceRGB))
            #expect(color.greenComponent > 0.3)
            for _ in 0..<200 {
                host.layoutSubtreeIfNeeded()
                if AppKitTestAccessibility.element(in: host, identifier: "workspace.devices.annotate") != nil { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            let annotate = try #require(AppKitTestAccessibility.element(in: host, identifier: "workspace.devices.annotate"))
            #expect(AppKitTestAccessibility.press(annotate))
            for _ in 0..<200 where window.sheets.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
            let sheet = try #require(window.sheets.first?.contentView)
            let save = try #require(AppKitTestAccessibility.element(in: sheet, identifier: "chat.image.annotations.save"))
            #expect(AppKitTestAccessibility.press(save))
            for _ in 0..<100 where delivered == nil { try await Task.sleep(for: .milliseconds(20)) }
            #expect(delivered?.data == captured.data)
            #expect(delivered?.annotations.first?.comment.contains(source.id) == true)
            #expect(session.retainedCapture == nil)
        }
        if let directory = ProcessInfo.processInfo.environment["SLOPPY_DEVICE_SCREENSHOTS"] {
            try captured.data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
        session.stop()
        #expect(!captured.data.isEmpty)
        await #expect(throws: (any Error).self) { try await session.capture(source) }
    }
}
#endif
