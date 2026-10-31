import Foundation
import ArgumentParser

/// Windows uses an interactive, per-user scheduled task, matching a macOS LaunchAgent.
enum WindowsServiceManager {
    enum Action: String {
        case install, uninstall, start, stop, restart, status, logs
    }

    static var scriptURL: URL? {
        Bundle.module.url(forResource: "service", withExtension: "ps1", subdirectory: "Windows")
    }

    static func arguments(
        action: Action,
        scriptPath: String,
        executablePath: String? = nil,
        configPath: String? = nil,
        lines: Int = 50
    ) -> [String] {
        var arguments = [
            "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
            "-File", scriptPath, "-Command", action.rawValue,
        ]
        if let executablePath { arguments += ["-ExecutablePath", executablePath] }
        if let configPath { arguments += ["-ConfigPath", configPath] }
        if action == .logs { arguments += ["-Lines", String(lines)] }
        return arguments
    }

    static func run(_ action: Action, executablePath: String? = nil, configPath: String? = nil, lines: Int = 50) throws {
        guard let scriptURL else {
            throw ValidationError("Windows service resources are missing. Reinstall Sloppy.")
        }
        let systemRoot = ProcessInfo.processInfo.environment.first {
            $0.key.caseInsensitiveCompare("SystemRoot") == .orderedSame
        }?.value ?? "C:\\Windows"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: systemRoot)
            .appendingPathComponent("System32/WindowsPowerShell/v1.0/powershell.exe")
        process.arguments = arguments(action: action, scriptPath: scriptURL.path,
                                      executablePath: executablePath, configPath: configPath, lines: lines)
        try PlatformProcess.run(process)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ExitCode.failure }
    }
}
