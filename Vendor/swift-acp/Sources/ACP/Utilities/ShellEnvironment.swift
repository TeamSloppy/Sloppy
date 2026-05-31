//
//  ShellEnvironment.swift
//  ACP
//
//  Shell environment loading utility
//

import Foundation

public enum ShellEnvironment: Sendable {
    private static let cacheLock = NSLock()
    private static let cacheCondition = NSCondition()
    private static var cachedEnvironment: [String: String]?
    private static var isLoading = false

    /// Get user's shell environment (cached after first load)
    /// Warning: On main thread, returns immediately with potentially incomplete environment.
    /// Use `loadUserShellEnvironmentAsync()` for guaranteed complete environment.
    public static func loadUserShellEnvironment() -> [String: String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cachedEnvironment {
            return cached
        }

        if Thread.isMainThread {
            DispatchQueue.global(qos: .utility).async {
                _ = loadUserShellEnvironment()
            }
            return ProcessInfo.processInfo.environment
        }

        let env = loadEnvironmentFromShell()
        cachedEnvironment = env

        cacheCondition.lock()
        cacheCondition.broadcast()
        cacheCondition.unlock()

        return env
    }

    /// Async version that guarantees the full user shell environment is loaded.
    /// Safe to call from any context (main thread, actors, etc.)
    public static func loadUserShellEnvironmentAsync() async -> [String: String] {
        if let cached = cachedEnvironmentSnapshot() {
            return cached
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let env = loadUserShellEnvironmentBlocking()
                continuation.resume(returning: env)
            }
        }
    }

    private static func cachedEnvironmentSnapshot() -> [String: String]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedEnvironment
    }

    /// Blocking version that waits for environment to be loaded.
    /// Do NOT call from main thread - use loadUserShellEnvironmentAsync() instead.
    public static func loadUserShellEnvironmentBlocking() -> [String: String] {
        cacheLock.lock()

        if let cached = cachedEnvironment {
            cacheLock.unlock()
            return cached
        }

        if isLoading {
            cacheLock.unlock()

            cacheCondition.lock()
            while cachedEnvironment == nil {
                cacheCondition.wait()
            }
            let env = cachedEnvironment!
            cacheCondition.unlock()
            return env
        }

        isLoading = true
        cacheLock.unlock()

        let env = loadEnvironmentFromShell()

        cacheLock.lock()
        cachedEnvironment = env
        isLoading = false
        cacheLock.unlock()

        cacheCondition.lock()
        cacheCondition.broadcast()
        cacheCondition.unlock()

        return env
    }

    /// Preload environment in background (call at app launch)
    public static func preloadEnvironment() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = loadUserShellEnvironment()
        }
    }

    /// Force reload of environment (e.g., after user changes shell config)
    public static func reloadEnvironment() {
        cacheLock.lock()
        cachedEnvironment = nil
        cacheLock.unlock()
        preloadEnvironment()
    }

    private static func loadEnvironmentFromShell() -> [String: String] {
        let shell = getLoginShell()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)

        let shellName = (shell as NSString).lastPathComponent
        let arguments: [String]
        switch shellName {
        case "fish":
            arguments = ["-l", "-c", "env"]
        case "zsh", "bash":
            arguments = ["-l", "-i", "-c", "env"]
        case "sh":
            arguments = ["-l", "-c", "env"]
        default:
            arguments = ["-c", "env"]
        }

        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: homeDir)

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        var shellEnv: [String: String] = [:]

        do {
            try process.run()
            process.waitUntilExit()

            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.split(separator: "\n") {
                    if let equalsIndex = line.firstIndex(of: "=") {
                        let key = String(line[..<equalsIndex])
                        let value = String(line[line.index(after: equalsIndex)...])
                        shellEnv[key] = value
                    }
                }
            }
        } catch {
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            return ProcessInfo.processInfo.environment
        }

        return shellEnv.isEmpty ? ProcessInfo.processInfo.environment : shellEnv
    }

    private static func getLoginShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }

        return "/bin/zsh"
    }
}
