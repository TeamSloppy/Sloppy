import ArgumentParser
import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct CoffeeCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "coffee",
        abstract: "Inspect and manage Coffee Mode power settings.",
        subcommands: [
            CoffeeStatusCommand.self,
            CoffeeApplyCommand.self,
            CoffeeRevertCommand.self,
        ]
    )
}

struct CoffeeStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show Coffee Mode config and macOS power status."
    )

    @Option(name: [.short, .long], help: "Path to JSON config file")
    var configPath: String?

    mutating func run() async throws {
        let context = CoffeeCommandContext.load(configPath: configPath)
        let service = CoffeeSystemService()
        do {
            let status = try service.status(config: context.config.coffeeMode, workspaceRoot: context.workspaceRoot)
            print("Coffee Mode: \(status.config.enabled ? "enabled" : "disabled")")
            print("Prevent display sleep: \(status.config.preventDisplaySleep ? "enabled" : "disabled")")
            print("Privileged lid mode required: \(status.config.privilegedLidModeRequired ? "yes" : "no")")
            print("Privileged lid mode active: \(status.privilegedLidModeActive ? "yes" : "no")")
            print("")
            print("pmset -g assertions")
            print(status.assertionsOutput.trimmingCharacters(in: .newlines))
            print("")
            print("pmset -g custom")
            print(status.customSettingsOutput.trimmingCharacters(in: .newlines))
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

struct CoffeeApplyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Apply experimental privileged lid/system sleep mode."
    )

    @Option(name: [.short, .long], help: "Path to JSON config file")
    var configPath: String?

    @Flag(name: .customLong("allow-unsupported-lid-mode"), help: "Acknowledge that this uses unsupported macOS pmset behavior.")
    var allowUnsupportedLidMode: Bool = false

    mutating func run() async throws {
        let context = CoffeeCommandContext.load(configPath: configPath)
        let service = CoffeeSystemService()
        do {
            try service.applyPrivilegedLidMode(
                allowUnsupportedLidMode: allowUnsupportedLidMode,
                workspaceRoot: context.workspaceRoot
            )
            CLIStyle.success("Privileged Coffee Mode applied.")
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

struct CoffeeRevertCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "revert",
        abstract: "Revert experimental privileged lid/system sleep mode."
    )

    @Option(name: [.short, .long], help: "Path to JSON config file")
    var configPath: String?

    mutating func run() async throws {
        let context = CoffeeCommandContext.load(configPath: configPath)
        let service = CoffeeSystemService()
        do {
            try service.revertPrivilegedLidMode(workspaceRoot: context.workspaceRoot)
            CLIStyle.success("Privileged Coffee Mode reverted.")
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

struct CoffeeCommandContext {
    let config: CoreConfig
    let workspaceRoot: URL

    static func load(configPath: String?) -> CoffeeCommandContext {
        let currentDirectory = CoreConfig.resolvedHomeDirectoryPath()
        let config = CoreConfig.load(
            from: normalizedServerConfigPath(configPath),
            currentDirectory: currentDirectory
        )
        return CoffeeCommandContext(
            config: config,
            workspaceRoot: config.resolvedWorkspaceRootURL(currentDirectory: currentDirectory)
        )
    }
}

struct CoffeeSystemCommandResult: Sendable, Equatable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

protocol CoffeeSystemCommandRunning {
    func run(_ command: [String]) throws -> CoffeeSystemCommandResult
}

struct LiveCoffeeSystemCommandRunner: CoffeeSystemCommandRunning {
    func run(_ command: [String]) throws -> CoffeeSystemCommandResult {
        guard let executable = command.first else {
            return .init(exitCode: 127, stdout: "", stderr: "Missing command.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return CoffeeSystemCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}

struct CoffeeSystemStatus: Sendable, Equatable {
    var config: CoreConfig.CoffeeMode
    var assertionsOutput: String
    var customSettingsOutput: String
    var privilegedLidModeActive: Bool
}

enum CoffeeSystemServiceError: Error, Equatable, LocalizedError {
    case unsupportedPlatform
    case unsupportedLidModeNotAllowed
    case requiresRoot
    case commandFailed([String], Int32, String)

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Privileged Coffee Mode is only available on macOS."
        case .unsupportedLidModeNotAllowed:
            return "This uses unsupported macOS pmset behavior. Re-run with --allow-unsupported-lid-mode to apply it explicitly."
        case .requiresRoot:
            return "This command must be run as root because pmset changes system power settings."
        case .commandFailed(let command, let exitCode, let stderr):
            let rendered = command.joined(separator: " ")
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return "\(rendered) failed with exit code \(exitCode)."
            }
            return "\(rendered) failed with exit code \(exitCode): \(details)"
        }
    }
}

struct CoffeeSystemService {
    var runner: CoffeeSystemCommandRunning
    var platform: CoffeeModePlatform
    var isRoot: () -> Bool
    var fileManager: FileManager

    init(
        runner: CoffeeSystemCommandRunning = LiveCoffeeSystemCommandRunner(),
        platform: CoffeeModePlatform = .current,
        isRoot: @escaping () -> Bool = {
            #if os(Linux)
            return Glibc.geteuid() == 0
            #else
            return Darwin.geteuid() == 0
            #endif
        },
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.platform = platform
        self.isRoot = isRoot
        self.fileManager = fileManager
    }

    func status(config: CoreConfig.CoffeeMode, workspaceRoot: URL) throws -> CoffeeSystemStatus {
        guard platform == .macOS else {
            return CoffeeSystemStatus(
                config: config,
                assertionsOutput: "Coffee Mode power inspection is only available on macOS.",
                customSettingsOutput: "",
                privilegedLidModeActive: false
            )
        }

        let assertions = try runPmset(["-g", "assertions"])
        let custom = try runPmset(["-g", "custom"])
        return CoffeeSystemStatus(
            config: config,
            assertionsOutput: assertions.stdout,
            customSettingsOutput: custom.stdout,
            privilegedLidModeActive: Self.detectPrivilegedLidModeActive(in: custom.stdout)
        )
    }

    func applyPrivilegedLidMode(allowUnsupportedLidMode: Bool, workspaceRoot: URL) throws {
        guard platform == .macOS else {
            throw CoffeeSystemServiceError.unsupportedPlatform
        }
        guard allowUnsupportedLidMode else {
            throw CoffeeSystemServiceError.unsupportedLidModeNotAllowed
        }
        guard isRoot() else {
            throw CoffeeSystemServiceError.requiresRoot
        }

        _ = try runPmset(["-a", "disablesleep", "1"])
        try writeState(applied: true, workspaceRoot: workspaceRoot)
    }

    func revertPrivilegedLidMode(workspaceRoot: URL) throws {
        guard platform == .macOS else {
            throw CoffeeSystemServiceError.unsupportedPlatform
        }
        guard isRoot() else {
            throw CoffeeSystemServiceError.requiresRoot
        }

        _ = try runPmset(["-a", "disablesleep", "0"])
        try writeState(applied: false, workspaceRoot: workspaceRoot)
    }

    static func detectPrivilegedLidModeActive(in output: String) -> Bool {
        output
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard parts.count >= 2 else { return false }
                let key = parts[0].lowercased()
                let value = parts[1].lowercased()
                return (key == "disablesleep" || key == "sleepdisabled") && ["1", "true", "yes"].contains(value)
            }
    }

    private func runPmset(_ arguments: [String]) throws -> CoffeeSystemCommandResult {
        let command = ["/usr/bin/pmset"] + arguments
        let result = try runner.run(command)
        guard result.exitCode == 0 else {
            throw CoffeeSystemServiceError.commandFailed(command, result.exitCode, result.stderr)
        }
        return result
    }

    private func writeState(applied: Bool, workspaceRoot: URL) throws {
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        let state = CoffeePrivilegedState(
            applied: applied,
            updatedAt: Date(),
            command: "/usr/bin/pmset -a disablesleep \(applied ? "1" : "0")",
            note: "Experimental unsupported lid/system sleep mode."
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state) + Data("\n".utf8)
        try data.write(to: workspaceRoot.appendingPathComponent("coffee-mode-state.json"), options: .atomic)
    }
}

private struct CoffeePrivilegedState: Codable {
    var applied: Bool
    var updatedAt: Date
    var command: String
    var note: String
}
