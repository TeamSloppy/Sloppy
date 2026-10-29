import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WorkspaceBrowserError: Error, LocalizedError {
    case unavailable, disconnected, timeout, command(String), invalidURL
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Chromium was not found. Set a browser executable in Settings → Browser."
        case .disconnected: "The browser connection closed. Start the browser again."
        case .timeout: "The browser did not respond in time."
        case .command(let message): message
        case .invalidURL: "Enter an HTTP or HTTPS address."
        }
    }
}

/// An isolated Chromium page. The DevTools endpoint is loopback-only; no personal browser profile is used.
@MainActor public final class WorkspaceBrowserRuntime {
    private var socket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .ephemeral)
    private var reader: Task<Void, Never>?
    #if os(macOS) || os(Windows) || os(Linux)
    private var process: Process?
    #endif
    private var profile: URL?
    private var serial = 0
    private var pageSessionID: String?
    private var loadSequence = 0
    private var pending: [Int: CheckedContinuation<ConfigJSONValue, Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]

    public init() {}

    public static func address(_ text: String) throws -> URL {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = value.contains("://") ? value : "https://" + value
        guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { throw WorkspaceBrowserError.invalidURL }
        return url
    }

    public func start(executable: String = "") async throws {
        if socket != nil { return }
#if os(macOS) || os(Windows) || os(Linux)
        let candidates = [executable,
            "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
            "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
            "C:/Program Files/Google/Chrome/Application/chrome.exe",
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
            "/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome"]
        guard let executable = candidates.first(where: { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }) else { throw WorkspaceBrowserError.unavailable }
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("sloppy-browser-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        self.profile = profile
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--headless=new", "--remote-debugging-address=127.0.0.1", "--remote-debugging-port=0",
            "--user-data-dir=\(profile.path)", "--no-first-run", "--no-default-browser-check", "--disable-extensions", "about:blank"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        self.process = process
        do {
            try process.run()
            let portFile = profile.appendingPathComponent("DevToolsActivePort")
            var port: Int?
            var endpoint: String?
            for _ in 0..<100 {
                try Task.checkCancellation()
                if let content = try? String(contentsOf: portFile, encoding: .utf8),
                   let value = content.split(separator: "\n").first.flatMap({ Int($0) }), value > 0, value < 65536 {
                    port = value; endpoint = content.split(separator: "\n").dropFirst().first.map(String.init); break
                }
                if !process.isRunning { throw WorkspaceBrowserError.disconnected }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard let port, let endpoint, endpoint.hasPrefix("/devtools/browser/"),
                  let url = URL(string: "ws://127.0.0.1:\(port)\(endpoint)") else { throw WorkspaceBrowserError.timeout }
            let socket = session.webSocketTask(with: url)
            self.socket = socket; socket.resume()
            reader = Task { [weak self] in await self?.receive(socket) }
            let target = try await command("Target.createTarget", params: ["url": .string("about:blank")])
            guard let targetID = target["targetId"].string else { throw WorkspaceBrowserError.disconnected }
            let attached = try await command("Target.attachToTarget", params: ["targetId": .string(targetID), "flatten": .bool(true)])
            guard let sessionID = attached["sessionId"].string else { throw WorkspaceBrowserError.disconnected }
            pageSessionID = sessionID
            _ = try await command("Page.enable")
            _ = try await command("Emulation.setDeviceMetricsOverride", params: ["width": .number(800), "height": .number(900), "deviceScaleFactor": .number(1), "mobile": .bool(false)])
        } catch { stop(); throw error }
#else
        throw WorkspaceBrowserError.unavailable
#endif
    }

    public func stop() {
        reader?.cancel(); reader = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        pageSessionID = nil
        failPending(WorkspaceBrowserError.disconnected)
        #if os(macOS) || os(Windows) || os(Linux)
        if let process, process.isRunning { process.terminate() }
        process = nil
        #endif
        // Each profile is owned by this runtime. Chromium may still hold files during shutdown.
        if let profile, profile.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL,
           profile.lastPathComponent.hasPrefix("sloppy-browser-") { try? FileManager.default.removeItem(at: profile) }
        profile = nil
    }

    public func command(_ method: String, params: [String: ConfigJSONValue] = [:]) async throws -> ConfigJSONValue {
        guard let socket else { throw WorkspaceBrowserError.disconnected }
        serial += 1; let id = serial
        var payload: [String: ConfigJSONValue] = ["id": .number(Double(id)), "method": .string(method), "params": .object(params)]
        if let pageSessionID { payload["sessionId"] = .string(pageSessionID) }
        let bytes = try JSONEncoder().encode(ConfigJSONValue.object(payload))
        guard let message = String(data: bytes, encoding: .utf8) else { throw WorkspaceBrowserError.disconnected }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    self?.finish(id, result: .failure(WorkspaceBrowserError.timeout))
                }
                Task {
                    do { try await socket.send(.string(message)) }
                    catch { finish(id, result: .failure(error)) }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) } }
    }

    public func screenshot() async throws -> Data {
        let result = try await command("Page.captureScreenshot", params: ["format": .string("png"), "captureBeyondViewport": .bool(false)])
        guard let encoded = result["data"].string, let data = Data(base64Encoded: encoded) else { throw WorkspaceBrowserError.disconnected }
        return data
    }

    public func navigate(_ text: String) async throws {
        let url = try Self.address(text)
        let previousLoad = loadSequence
        let result = try await command("Page.navigate", params: ["url": .string(url.absoluteString)])
        if let error = result["errorText"].string { throw WorkspaceBrowserError.command(error) }
        guard result["loaderId"] != .null else { return }
        for _ in 0..<150 {
            try Task.checkCancellation()
            if loadSequence > previousLoad { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw WorkspaceBrowserError.timeout
    }

    private func receive(_ socket: URLSessionWebSocketTask) async {
        var buffer = BrowserMessageBuffer()
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message { case .string(let text): data = Data(text.utf8); case .data(let value): data = value; @unknown default: continue }
                for complete in try buffer.append(data) {
                    let payload = try JSONDecoder().decode(ConfigJSONValue.self, from: complete)
                    if payload["method"].string == "Page.loadEventFired", payload["sessionId"].string == pageSessionID { loadSequence += 1 }
                    guard case .number(let id) = payload["id"] else { continue }
                    if let message = payload["error"]["message"].string { finish(Int(id), result: .failure(WorkspaceBrowserError.command(message))) }
                    else { finish(Int(id), result: .success(payload["result"])) }
                }
            }
        } catch { if self.socket === socket { self.socket = nil; failPending(error) } }
    }

    private func finish(_ id: Int, result: Result<ConfigJSONValue, Error>) {
        deadlines.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }
    private func failPending(_ error: Error) { for id in Array(pending.keys) { finish(id, result: .failure(error)) } }
}

extension ConfigJSONValue {
    public subscript(_ key: String) -> Self { if case .object(let value) = self { value[key] ?? .null } else { .null } }
    public var string: String? { if case .string(let value) = self { value } else { nil } }
}
