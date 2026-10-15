import Foundation
#if os(Windows)
import WinSDK
import ucrt
#endif

enum PlatformProcess {
    static func setEnvironmentVariable(_ key: String, value: String, overwrite: Bool) {
        #if os(Windows)
        if !overwrite && ProcessInfo.processInfo.environment.keys.contains(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) { return }
        _ = key.withCString(encodedAs: UTF16.self) { name in
            value.withCString(encodedAs: UTF16.self) { _wputenv_s(name, $0) }
        }
        #else
        setenv(key, value, overwrite ? 1 : 0)
        #endif
    }

    static func isTerminal(input: Bool) -> Bool {
        #if os(Windows)
        var mode: DWORD = 0
        return GetConsoleMode(GetStdHandle(input ? STD_INPUT_HANDLE : STD_OUTPUT_HANDLE), &mode)
        #else
        return (input ? FileHandle.standardInput : FileHandle.standardOutput).fileDescriptor.withIsTTY
        #endif
    }

    static var userID: UInt32 {
        #if os(Windows)
        return 0 // Used only in launchd command construction on other platforms.
        #else
        return getuid()
        #endif
    }

    static func configure(_ process: Process, command: String, arguments: [String], environment: [String: String]) throws {
        #if os(Windows)
        let executable = try windowsExecutable(command, environment: environment)
        if ["cmd", "bat"].contains(executable.pathExtension.lowercased()) {
            let shellSyntax = CharacterSet(charactersIn: "\"&|<>^%\r\n()")
            guard ([executable.path] + arguments).allSatisfy({ $0.rangeOfCharacter(from: shellSyntax) == nil }) else {
                throw CocoaError(.executableNotLoadable, userInfo: [NSLocalizedDescriptionKey:
                    "Batch commands cannot accept shell metacharacters as arguments. Invoke a shell explicitly for shell expressions."])
            }
            // Batch shims (npm, npx, editor launchers) require cmd.exe.
            process.executableURL = URL(fileURLWithPath: environment["COMSPEC"] ?? environment["ComSpec"] ?? "C:\\Windows\\System32\\cmd.exe")
            process.arguments = ["/d", "/v:off", "/c", "call", executable.path] + arguments
        } else {
            process.executableURL = executable
            process.arguments = arguments
        }
        #else
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }
        #endif
        process.environment = environment
    }

    /// Preserve existing Unix launch sites while resolving their commands through Windows PATH.
    static func run(_ process: Process) throws {
        #if os(Windows)
        let path = process.executableURL?.path ?? ""
        let environment = process.environment ?? ProcessInfo.processInfo.environment
        if path.hasSuffix("/usr/bin/env"), let command = process.arguments?.first {
            try configure(process, command: command, arguments: Array((process.arguments ?? []).dropFirst()), environment: environment)
        } else if path.hasSuffix("/usr/bin/git") {
            try configure(process, command: "git", arguments: process.arguments ?? [], environment: environment)
        }
        #endif
        try process.run()
    }

    #if os(Windows)
    static func windowsExecutable(_ command: String, environment: [String: String], fileManager: FileManager = .default) throws -> URL {
        let path = environment.first { $0.key.caseInsensitiveCompare("PATH") == .orderedSame }?.value ?? ""
        let extensions = (environment.first { $0.key.caseInsensitiveCompare("PATHEXT") == .orderedSame }?.value
            ?? ".COM;.EXE;.BAT;.CMD").split(separator: ";").map(String.init)
        let names = URL(fileURLWithPath: command).pathExtension.isEmpty ? [command] + extensions.map { command + $0 } : [command]
        let directories = command.contains("/") || command.contains("\\") ? [""] : path.split(separator: ";").map(String.init)
        let candidates = directories.flatMap { directory in names.map {
            directory.isEmpty ? URL(fileURLWithPath: $0) : URL(fileURLWithPath: directory.trimmingCharacters(in: CharacterSet(charactersIn: "\""))).appendingPathComponent($0)
        } }
        guard let executable = candidates.first(where: {
            fileManager.fileExists(atPath: $0.path) && fileManager.isExecutableFile(atPath: $0.path)
        }) else {
            throw CocoaError(.executableNotLoadable, userInfo: [NSFilePathErrorKey: command])
        }
        return executable
    }
    #endif
}

#if !os(Windows)
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
private extension Int32 {
    var withIsTTY: Bool { isatty(self) != 0 }
}
#endif
