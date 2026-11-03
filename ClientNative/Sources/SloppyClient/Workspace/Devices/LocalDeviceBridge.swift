#if os(macOS)
import Foundation
import AppKit

enum DevicePlatform: String, CaseIterable, Identifiable {
    case iOS, android = "Android"
    var id: Self { self }
    var package: String { self == .iOS ? "serve-sim@0.1.46" : "serve-avd@0.1.3" }
    var executable: String { self == .iOS ? "serve-sim" : "serve-avd" }
}

/// Owns only the foreground Node process started by this tab. Never stops a simulator or ADB.
@MainActor
final class LocalDeviceBridge {
    private var process: Process?
    private var logURL: URL?
    private var logHandle: FileHandle?
    private var temporaryDirectory: URL?
    private var terminationObserver: NSObjectProtocol?

    init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    static var environment: [String: String] {
        var result = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        result["PATH"] = ([result["PATH"] ?? "", "/opt/homebrew/bin", "/opt/homebrew/opt/node@24/bin",
                           "/opt/homebrew/opt/node@22/bin", "/usr/local/bin", "/usr/bin", "/bin"])
            .joined(separator: ":")
        if result["ANDROID_HOME"] == nil && result["ANDROID_SDK_ROOT"] == nil {
            result["ANDROID_HOME"] = home + "/Library/Android/sdk"
        }
        return result
    }

    static func executable(_ name: String) throws -> URL {
        for directory in (environment["PATH"] ?? "").split(separator: ":") where directory.hasPrefix("/") {
            let url = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw failure("Install Node.js 20 or newer, then try again. Could not find \(name).")
    }

    static func adbExecutable() throws -> URL {
        let environment = environment
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = environment[key] {
                let url = URL(fileURLWithPath: root).appendingPathComponent("platform-tools/adb")
                if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            }
        }
        if let url = try? executable("adb") { return url }
        throw failure("Install Android SDK Platform-Tools, or set ANDROID_HOME to your Android SDK, then try again.")
    }

    nonisolated static func failure(_ message: String) -> NSError {
        NSError(domain: "SloppyDeviceBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func start(_ executable: URL, arguments: [String]) throws {
        stop()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sloppy-device-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        let log = directory.appendingPathComponent("bridge.log")
        guard FileManager.default.createFile(atPath: log.path, contents: nil) else {
            throw Self.failure("Could not create the device bridge log.")
        }
        logURL = log
        let handle = try FileHandle(forWritingTo: log)
        logHandle = handle
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        var environment = Self.environment
        // Bridge state files must not overwrite or remove another tool's device registrations.
        environment["TMPDIR"] = directory.path
        child.environment = environment
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = handle
        child.standardError = handle
        process = child
        do { try child.run() } catch { stop(); throw error }
    }

    var isRunning: Bool { process?.isRunning == true }

    func waitForInstallation() async throws {
        try await waitForExit(timeout: .seconds(180), timeoutMessage: "Installing the device bridge timed out. Try again.")
    }

    func run(_ executable: URL, arguments: [String], timeout: Duration) async throws -> String {
        try start(executable, arguments: arguments)
        try await waitForExit(timeout: timeout, timeoutMessage: "ADB timed out. Check the device's address, debugging port and network connection.")
        return diagnostics.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func waitForExit(timeout: Duration, timeoutMessage: String) async throws {
        let deadline = ContinuousClock.now + timeout
        while isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw Self.failure(timeoutMessage) }
            try await Task.sleep(for: .milliseconds(150))
        }
        try Task.checkCancellation()
        guard process?.terminationStatus == 0 else { throw Self.failure(diagnostics) }
    }

    var diagnostics: String {
        guard let logURL, let handle = try? FileHandle(forReadingFrom: logURL) else { return "Device bridge stopped." }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 6000 ? size - 6000 : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(data: data, encoding: .utf8) ?? "Device bridge stopped."
    }

    func stop() {
        if let process, process.isRunning { process.terminate() }
        process = nil
        try? logHandle?.close()
        logHandle = nil
        if let logURL { try? FileManager.default.removeItem(at: logURL) }
        logURL = nil
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
        temporaryDirectory = nil
    }

    isolated deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        stop()
    }
}
#endif
