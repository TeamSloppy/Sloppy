#if os(macOS)
import AppKit
import Foundation
import Observation
import SloppyFeatureChat
import WebKit

@Observable
@MainActor
final class WorkspaceDeviceSession: NSObject, WKNavigationDelegate {
    var platform: DevicePlatform = .iOS
    private(set) var baseURL: URL?
    private(set) var isStarting = false
    private(set) var isLoaded = false
    private(set) var androidAddress: String?
    private(set) var startupMessage = ""
    var errorMessage: String?
    var retainedCapture: ChatComposerAttachment?
    let webView: WKWebView
    private let bridge = LocalDeviceBridge()
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var navigation: WKNavigation?
    private let installationRoot: URL?
    private let adbExecutable: URL?

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
        !value.isEmpty && value.utf8.count <= 200 && !value.hasPrefix("-")
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_.:-".contains($0)) }
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
                    var connectionOutput = ""
                    do {
                        connectionOutput = try await bridge.run(adb, arguments: ["connect", androidDevice.address], timeout: .seconds(20))
                        let state = try await bridge.run(adb, arguments: ["-s", androidDevice.address, "get-state"], timeout: .seconds(10))
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
                let deadline = ContinuousClock.now + .seconds(120)
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
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
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
    }

    func captureSources() async throws -> [DeviceFrameSource] {
        guard let baseURL, isLoaded else { throw LocalDeviceBridge.failure("Wait for the device screen to load.") }
        let token = generation
        let request = URLRequest(url: baseURL.appendingPathComponent("grid/api"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard generation == token else { throw CancellationError() }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LocalDeviceBridge.failure("Could not list the connected devices.")
        }
        return try DeviceFrameSource.decode(data, baseURL: baseURL)
    }

    func capture(_ source: DeviceFrameSource) async throws -> ChatComposerAttachment {
        guard let baseURL, isLoaded,
              source.url.scheme == baseURL.scheme, source.url.host == baseURL.host, source.url.port == baseURL.port else {
            throw LocalDeviceBridge.failure("Wait for the device screen to load and select a connected device.")
        }
        let token = generation
        let platform = platform
        let jpeg = try await DeviceFrameCapture.jpeg(from: source.url)
        guard generation == token else { throw CancellationError() }
        guard let bitmap = NSBitmapImageRep(data: jpeg),
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
