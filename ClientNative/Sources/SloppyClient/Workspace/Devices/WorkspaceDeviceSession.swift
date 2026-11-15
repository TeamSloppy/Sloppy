#if os(macOS)
import AppKit
import Foundation
import Observation
import SloppyClientCore
import SloppyFeatureChat
import WebKit

@Observable
@MainActor
final class WorkspaceDeviceSession: NSObject, WKNavigationDelegate {
    var platform: DevicePlatform = .iOS
    private(set) var baseURL: URL?
    private(set) var isStarting = false
    private(set) var isLoaded = false
    private(set) var targetID: String?
    private(set) var controlError: String?
    private(set) var androidAddress: String?
    private(set) var startupMessage = ""
    var errorMessage: String?
    var retainedCapture: ChatComposerAttachment?
    let webView: WKWebView
    private let bridge = LocalDeviceBridge()
    private var operation: Task<Void, Never>?
    private var inputOperation: Task<Void, Error>?
    private var generation = UUID()
    private var navigation: WKNavigation?
    private let installationRoot: URL?
    private let adbExecutable: URL?
    private var controlScript: URL?

    init(installationRoot: URL? = nil, adbExecutable: URL? = nil) {
        self.installationRoot = installationRoot
        self.adbExecutable = adbExecutable
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
    }

    static func localURL(_ text: String) throws -> URL {
        guard let url = URL(string: text), url.scheme == "http",
              ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              url.port.map({ (1...65535).contains($0) }) ?? true else {
            throw LocalDeviceBridge.failure("Enter a local bridge URL, such as http://127.0.0.1:3200.")
        }
        return url
    }

    func start() {
        start(androidDevice: nil, deviceID: nil)
    }

    func start(deviceID: String) throws {
        guard Self.validDeviceID(deviceID) else {
            throw LocalDeviceBridge.failure("Use a simulator UUID, Android serial or AVD identifier from your device configuration.")
        }
        start(androidDevice: nil, deviceID: deviceID)
    }

    static func validDeviceID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 200, !value.hasPrefix("-") else { return false }
        if value.hasPrefix("[") { return (try? AndroidDeviceEndpoint(value).address) == value }
        return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_.:-".contains($0)) }
    }

    func inventory(_ platform: DevicePlatform) async throws -> [WorkspaceDevicePreview.Device] {
        try await WorkspaceDeviceInventory.list(platform, adbExecutable: adbExecutable)
    }

    func connectAndroid(_ address: String) {
        do {
            let endpoint = try AndroidDeviceEndpoint(address)
            platform = .android
            start(androidDevice: endpoint, deviceID: nil)
        } catch { errorMessage = error.localizedDescription }
    }

    private func start(androidDevice: AndroidDeviceEndpoint?, deviceID: String?) {
        stop()
        androidAddress = androidDevice?.address
        isStarting = true
        startupMessage = androidDevice.map { "Connecting to \($0.address)…" } ?? "Preparing the device bridge…"
        let token = generation
        let platform = platform
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil else {
                    throw LocalDeviceBridge.failure("This build uses App Sandbox. Start a bridge in Terminal and use Existing local bridge.")
                }
                if let androidDevice {
                    let adb = try adbExecutable ?? LocalDeviceBridge.adbExecutable()
                    let adbCommand = LocalDeviceBridge()
                    defer { adbCommand.stop() }
                    var connectionOutput = ""
                    do {
                        connectionOutput = try await adbCommand.run(adb, arguments: ["connect", androidDevice.address], timeout: .seconds(20))
                        let state = try await adbCommand.run(adb, arguments: ["-s", androidDevice.address, "get-state"], timeout: .seconds(10))
                        guard state == "device" else { throw LocalDeviceBridge.failure("ADB device state: \(state)") }
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        throw LocalDeviceBridge.failure("Could not connect to \(androidDevice.address). Check the ADB port and allow debugging on the device. Wireless debugging may require adb pair in Terminal first.\n\(connectionOutput)\n\(error.localizedDescription)")
                    }
                }
                let node = try LocalDeviceBridge.executable("node")
                let root = try installationRoot ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
                    .appendingPathComponent("Sloppy/DeviceBridges/\(platform.package)")
                let script = root.appendingPathComponent("node_modules/\(platform.executable)/dist/\(platform.executable).js")
                let installed = root.appendingPathComponent(".sloppy-installed")
                if !FileManager.default.fileExists(atPath: script.path)
                    || (installationRoot == nil && !FileManager.default.fileExists(atPath: installed.path)) {
                    startupMessage = "Installing the \(platform.rawValue) preview bridge…"
                    try bridge.start(try LocalDeviceBridge.executable("npm"), arguments: ["install", "--prefix", root.path,
                        "--no-audit", "--no-fund", platform.package])
                    try await bridge.waitForInstallation()
                    try Data(platform.package.utf8).write(to: installed, options: .atomic)
                }
                try Task.checkCancellation()
                let port = Int.random(in: 43000...59000)
                let url = try Self.localURL("http://127.0.0.1:\(port)")
                startupMessage = "Opening the \(platform.rawValue) preview…"
                var arguments = [script.path]
                if let androidDevice { arguments.append(androidDevice.address) }
                else if let deviceID { arguments.append(deviceID) }
                arguments += ["--port", String(port), "--host", "127.0.0.1", "--panes", "none", "--codec", "auto"]
                try bridge.start(node, arguments: arguments)
                let deadline = ContinuousClock.now + .seconds(platform == .android && deviceID != nil ? 315 : 120)
                var ready = false
                while ContinuousClock.now < deadline {
                    try Task.checkCancellation()
                    guard bridge.isRunning else { throw LocalDeviceBridge.failure(bridge.diagnostics) }
                    var request = URLRequest(url: url.appendingPathComponent("api"), cachePolicy: .reloadIgnoringLocalCacheData,
                                             timeoutInterval: 1)
                    request.httpMethod = "GET"
                    if let (_, response) = try? await URLSession.shared.data(for: request),
                       (response as? HTTPURLResponse)?.statusCode == 200 { ready = true; break }
                    try await Task.sleep(for: .milliseconds(300))
                }
                guard ready else { throw LocalDeviceBridge.failure("The device bridge did not become ready. Check Xcode or Android SDK and try again.") }
                guard generation == token else { return }
                controlScript = script
                present(url)
                while generation == token {
                    try await Task.sleep(for: .seconds(1))
                    guard bridge.isRunning else { throw LocalDeviceBridge.failure(bridge.diagnostics) }
                }
            } catch {
                guard generation == token else { return }
                bridge.stop()
                baseURL = nil
                isLoaded = false
                webView.stopLoading()
                isStarting = false
                if !(error is CancellationError) {
                    controlError = error.localizedDescription
                    errorMessage = controlError
                }
            }
        }
    }

    func connect(_ address: String) {
        do {
            let url = try Self.localURL(address.trimmingCharacters(in: .whitespacesAndNewlines))
            stop()
            present(url)
        } catch { errorMessage = error.localizedDescription }
    }

    private func present(_ url: URL) {
        baseURL = url
        isStarting = false
        navigation = webView.load(URLRequest(url: url))
    }

    func stop() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        inputOperation?.cancel()
        inputOperation = nil
        bridge.stop()
        webView.stopLoading()
        navigation = nil
        webView.loadHTMLString("", baseURL: nil)
        baseURL = nil
        isStarting = false
        isLoaded = false
        androidAddress = nil
        startupMessage = ""
        errorMessage = nil
        targetID = nil
        controlError = nil
        controlScript = nil
    }

    func captureSources() async throws -> [DeviceFrameSource] {
        guard let baseURL else { throw LocalDeviceBridge.failure("Wait for the device bridge to start.") }
        let token = generation
        let request = URLRequest(url: baseURL.appendingPathComponent("grid/api"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let (data, response) = try await URLSession.shared.data(for: request, delegate: DeviceBridgeNoRedirect())
        guard generation == token else { throw CancellationError() }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LocalDeviceBridge.failure("Could not list the connected devices.")
        }
        return try DeviceFrameSource.decode(data, baseURL: baseURL)
    }

    func resolveTarget(in sources: [DeviceFrameSource], requestedID: String?) async throws -> DeviceFrameSource? {
        let token = generation
        if let targetID {
            if let source = sources.first(where: { $0.id == targetID }) { return source }
            throw failControl("Device \(targetID) disconnected. Start it again in Devices.")
        }
        let source: DeviceFrameSource?
        if let requestedID {
            source = sources.first {
                platform == .iOS ? $0.id.caseInsensitiveCompare(requestedID) == .orderedSame : $0.id == requestedID
            }
            if source == nil, platform == .android, sources.count == 1, let candidate = sources.first {
                let adb = try adbExecutable ?? LocalDeviceBridge.adbExecutable()
                let avd = try await WorkspaceDeviceInventory.avdName(serial: candidate.id, adb: adb)
                guard generation == token else { throw CancellationError() }
                guard avd?.caseInsensitiveCompare(requestedID) == .orderedSame else {
                    throw failControl("The Android bridge did not attach the requested device \(requestedID). Start it again in Devices.")
                }
                targetID = candidate.id
                return candidate
            }
        } else {
            guard sources.count <= 1 else {
                throw failControl("Several devices are attached. Start Devices again with an explicit device ID.")
            }
            source = sources.first
        }
        targetID = source?.id
        return source
    }

    func failControl(_ message: String) -> NSError {
        controlError = message
        errorMessage = message
        return LocalDeviceBridge.failure(message)
    }

    func perform(_ input: WorkspaceDeviceInput, target: DeviceFrameSource) async throws {
        guard controlError == nil, let baseURL, targetID == target.id, Self.validDeviceID(target.id) else {
            throw LocalDeviceBridge.failure("Start the target device in Devices before sending input.")
        }
        guard inputOperation == nil else { throw LocalDeviceBridge.failure("Wait for the current device input to finish.") }
        let token = generation
        let platform = platform
        let script = controlScript
        let stateDirectory = bridge.stateDirectory
        let command = Task {
            let helper = baseURL.appendingPathComponent("helper").appendingPathComponent(target.id)
            switch platform {
            case .android:
                try await input.sendToAndroid(at: helper.appendingPathComponent("action"))
            case .iOS:
                if case .text(let text) = input {
                    guard let script, let stateDirectory else {
                        throw LocalDeviceBridge.failure("The simulator keyboard requires a bridge started from Devices.")
                    }
                    if Self.simulatorHardwareKeyboardDisabled(deviceID: target.id) {
                        throw LocalDeviceBridge.failure("Connect the hardware keyboard for this simulator in Simulator → I/O → Keyboard → Connect Hardware Keyboard, then try again.")
                    }
                    let file = stateDirectory.appendingPathComponent("keyboard-\(UUID()).txt")
                    try Data(text.utf8).write(to: file, options: .atomic)
                    defer { try? FileManager.default.removeItem(at: file) }
                    let keyboard = LocalDeviceBridge()
                    defer { keyboard.stop() }
                    _ = try await keyboard.run(try LocalDeviceBridge.executable("node"),
                        arguments: [script.path, "type", "-d", target.id, "--file", file.path],
                        timeout: .seconds(12), bridgeStateDirectory: stateDirectory)
                } else {
                    guard var address = URLComponents(url: helper.appendingPathComponent("ws"), resolvingAgainstBaseURL: false) else {
                        throw LocalDeviceBridge.failure("The simulator input endpoint is invalid.")
                    }
                    address.scheme = "ws"
                    guard let url = address.url else { throw LocalDeviceBridge.failure("The simulator input endpoint is invalid.") }
                    try await input.sendIOSGesture(to: url)
                }
            }
        }
        inputOperation = command
        defer { if generation == token { inputOperation = nil } }
        try await withTaskCancellationHandler { try await command.value } onCancel: { command.cancel() }
        guard generation == token else { throw CancellationError() }
    }

    private static func simulatorHardwareKeyboardDisabled(deviceID: String) -> Bool {
        guard let preferences = UserDefaults(suiteName: "com.apple.iphonesimulator") else { return false }
        let key = "ConnectHardwareKeyboard"
        if let device = preferences.dictionary(forKey: "DevicePreferences")?[deviceID] as? [String: Any],
           let connected = device[key] as? Bool {
            return !connected
        }
        return preferences.string(forKey: "CurrentDeviceUDID") == deviceID
            && preferences.object(forKey: key) != nil && !preferences.bool(forKey: key)
    }

    func capture(_ source: DeviceFrameSource) async throws -> ChatComposerAttachment {
        let url = source.screenshotURL ?? source.url
        guard let baseURL,
              url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port else {
            throw LocalDeviceBridge.failure("Wait for the device screen to load and select a connected device.")
        }
        let token = generation
        let platform = platform
        let frame = try await DeviceFrameCapture.image(from: url)
        guard generation == token else { throw CancellationError() }
        guard let bitmap = NSBitmapImageRep(data: frame),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw LocalDeviceBridge.failure("Could not capture the device screen.")
        }
        let context = "Device: \(source.name)\nPlatform: \(platform.rawValue)\nDevice ID: \(source.id)\nCaptured: \(Date().formatted(.iso8601))"
        return ChatComposerAttachment(name: "\(source.name).png", mimeType: "image/png", data: data,
            annotations: [.init(region: .init(x: 0, y: 0, width: 1, height: 1), comment: context)])
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === self.navigation else { return }
        isLoaded = baseURL != nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === self.navigation, (error as NSError).code != NSURLErrorCancelled else { return }
        isLoaded = false
        errorMessage = error.localizedDescription
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let local = url?.scheme == baseURL?.scheme && url?.host == baseURL?.host && url?.port == baseURL?.port
        decisionHandler(url?.absoluteString == "about:blank" || (baseURL != nil && local) ? .allow : .cancel)
    }
}
#endif
