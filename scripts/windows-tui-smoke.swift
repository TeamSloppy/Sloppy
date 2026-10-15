import Foundation

// This driver is compiled with WindowsPseudoTerminal.swift, independently of the server module.
enum DashboardTerminalService {
    enum ServiceError: Error { case launchFailed, writeFailed, resizeFailed }
}

private final class Capture: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ chunk: String) { lock.withLock { text += chunk } }
    func contains(_ value: String) -> Bool { lock.withLock { text.contains(value) } }
    func save(to path: String) throws { try lock.withLock { try text.write(toFile: path, atomically: true, encoding: .utf8) } }
}

@main struct WindowsTUISmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else { throw CocoaError(.fileReadInvalidFileName) }
        let executable = CommandLine.arguments[1]
        let config = CommandLine.arguments[2]
        let log = CommandLine.arguments[3]
        for mode in ["root", "tui"] {
            let arguments = (mode == "root" ? [] : ["tui"]) + ["--config-path", config]
            try checkSession(executable: executable, arguments: arguments, text: "привет 👋 \(mode)", log: log)
        }
        print("Windows TUI: default and tui commands, Cyrillic, emoji, resize and Ctrl+C passed.")
    }

    private static func checkSession(executable: String, arguments: [String], text: String, log: String) throws {
        let terminal = try WindowsPseudoTerminal(shell: executable, arguments: arguments,
                                                 cwd: FileManager.default.currentDirectoryPath, cols: 100, rows: 32)
        let capture = Capture()
        let exited = DispatchSemaphore(value: 0)
        terminal.read(onOutput: { capture.append($0) }, onExit: { code in
            capture.append("\nPROCESS_EXIT=\(code)\n")
            exited.signal()
        })
        defer { terminal.close(); try? capture.save(to: log) }
        try waitUntil { capture.contains("Sloppy TUI") }
        try terminal.resize(cols: 120, rows: 40)
        try terminal.send(text)
        try waitUntil { capture.contains(text) }
        try terminal.send("\u{0003}")
        Thread.sleep(forTimeInterval: 0.2)
        try terminal.send("\u{0003}")
        guard exited.wait(timeout: .now() + 20) == .success, capture.contains("PROCESS_EXIT=0") else {
            throw NSError(domain: "TUI did not exit cleanly; see \(log)", code: 1)
        }
    }

    private static func waitUntil(_ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(30)
        while !condition() {
            guard Date() < deadline else { throw NSError(domain: "TUI output timed out", code: 1) }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
