import Foundation
import PackagePlugin

@main
struct SloppyRunPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let invocation = try Invocation(arguments: arguments)

        if !invocation.skipDashboard {
            try buildDashboard(
                packageDirectory: context.package.directoryURL,
                pluginWorkDirectory: context.pluginWorkDirectoryURL
            )
        } else {
            Diagnostics.remark("Skipping Dashboard build because --no-dashboard was provided.")
        }

        let buildResult = try packageManager.build(
            .product("sloppy"),
            parameters: .init(
                configuration: .release,
                logging: .concise,
                echoLogs: true
            )
        )

        guard buildResult.succeeded else {
            throw PluginError.message(buildResult.logText)
        }

        guard let executableURL = buildResult.builtArtifacts.first(where: {
            $0.kind == .executable && $0.url.lastPathComponent == "sloppy"
        })?.url else {
            throw PluginError.message("SwiftPM built sloppy, but the executable artifact could not be located.")
        }

        Diagnostics.remark("Launching sloppy from \(executableURL.path)")
        try runProcess(
            executableURL: executableURL,
            arguments: ["run"] + invocation.sloppyArguments,
            currentDirectoryURL: context.package.directoryURL,
            environment: ProcessInfo.processInfo.environment
        )
    }

    private func buildDashboard(packageDirectory: URL, pluginWorkDirectory: URL) throws {
        let dashboardDirectory = packageDirectory.appendingPathComponent("Dashboard", isDirectory: true)
        let packageJSONURL = dashboardDirectory.appendingPathComponent("package.json")
        let dashboardEnvironment = npmEnvironment(pluginWorkDirectory: pluginWorkDirectory)

        guard FileManager.default.fileExists(atPath: packageJSONURL.path) else {
            throw PluginError.message("Dashboard/package.json was not found. Cannot build Dashboard.")
        }

        let npmExecutable = try findExecutable(named: "npm")
        try normalizeDashboardToolPermissions(at: dashboardDirectory)
        if !dashboardDependenciesAreUsable(at: dashboardDirectory) {
            Diagnostics.remark("Dashboard dependencies are missing or unusable. Running npm install.")
            try runProcess(
                executableURL: npmExecutable,
                arguments: ["install"],
                currentDirectoryURL: dashboardDirectory,
                environment: dashboardEnvironment
            )
            try normalizeDashboardToolPermissions(at: dashboardDirectory)
        }

        Diagnostics.remark("Building Dashboard with npm run build.")
        try runProcess(
            executableURL: npmExecutable,
            arguments: ["run", "build"],
            currentDirectoryURL: dashboardDirectory,
            environment: dashboardEnvironment
        )
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String]
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            throw PluginError.message("Failed to launch \(executableURL.lastPathComponent): \(error.localizedDescription)")
        }

        process.waitUntilExit()

        guard process.terminationReason == .exit else {
            throw PluginError.message("\(executableURL.lastPathComponent) terminated unexpectedly.")
        }

        guard process.terminationStatus == 0 else {
            throw PluginError.message("\(executableURL.lastPathComponent) exited with status \(process.terminationStatus).")
        }
    }

    private func dashboardDependenciesAreUsable(at dashboardDirectory: URL) -> Bool {
        let nodeModulesDirectory = dashboardDirectory.appendingPathComponent("node_modules", isDirectory: true)
        guard FileManager.default.fileExists(atPath: nodeModulesDirectory.path) else {
            return false
        }

        let binDirectory = nodeModulesDirectory.appendingPathComponent(".bin", isDirectory: true)
        let viteCandidates = ["vite", "vite.cmd", "vite.ps1"]

        for candidate in viteCandidates {
            let viteURL = binDirectory.appendingPathComponent(candidate)
            guard FileManager.default.fileExists(atPath: viteURL.path) else {
                continue
            }

            if viteURL.pathExtension.isEmpty {
                return FileManager.default.isExecutableFile(atPath: viteURL.path)
            }

            return true
        }

        return false
    }

    private func normalizeDashboardToolPermissions(at dashboardDirectory: URL) throws {
        let candidateURLs = [
            dashboardDirectory
                .appendingPathComponent("node_modules", isDirectory: true)
                .appendingPathComponent(".bin", isDirectory: true)
                .appendingPathComponent("vite"),
            dashboardDirectory
                .appendingPathComponent("node_modules", isDirectory: true)
                .appendingPathComponent("vite", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("vite.js")
        ]

        for candidateURL in candidateURLs where FileManager.default.fileExists(atPath: candidateURL.path) {
            if !FileManager.default.isExecutableFile(atPath: candidateURL.path) {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: candidateURL.path
                )
            }
        }
    }

    private func npmEnvironment(pluginWorkDirectory: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let npmCacheDirectory = pluginWorkDirectory
            .appendingPathComponent("npm-cache", isDirectory: true)
            .path
        environment["NPM_CONFIG_CACHE"] = npmCacheDirectory
        environment["npm_config_cache"] = npmCacheDirectory
        return environment
    }

    private func findExecutable(named name: String) throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let pathVariable = environment["PATH"] ?? ""
        let pathSeparator = pathVariable.contains(";") ? ";" : ":"
        let searchPaths = pathVariable
            .split(separator: Character(pathSeparator))
            .map(String.init)
            .filter { !$0.isEmpty }

        let candidateNames = executableNames(for: name, environment: environment)

        for directory in searchPaths {
            for candidateName in candidateNames {
                let candidateURL = URL(fileURLWithPath: directory, isDirectory: true)
                    .appendingPathComponent(candidateName)
                if FileManager.default.isExecutableFile(atPath: candidateURL.path) {
                    return candidateURL
                }
            }
        }

        throw PluginError.message("Required executable '\(name)' was not found in PATH.")
    }

    private func executableNames(for baseName: String, environment: [String: String]) -> [String] {
        let pathExtensions = (environment["PATHEXT"] ?? ".COM;.EXE;.BAT;.CMD")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let hasExtension = URL(fileURLWithPath: baseName).pathExtension.isEmpty == false
        if hasExtension {
            return [baseName]
        }

        return [baseName] + pathExtensions.map { "\(baseName)\($0.lowercased())" }
    }
}

private struct Invocation {
    let skipDashboard: Bool
    let sloppyArguments: [String]

    init(arguments: [String]) throws {
        var skipDashboard = false
        var sloppyArguments: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                sloppyArguments = Array(arguments[(index + 1)...])
                break
            }

            switch argument {
            case "--no-dashboard":
                skipDashboard = true
            case "--config-path":
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw PluginError.message("Missing value for --config-path.")
                }
                sloppyArguments.append(argument)
                sloppyArguments.append(arguments[valueIndex])
                index = valueIndex
            default:
                if let value = Self.parseEqualsValue(argument, flag: "--config-path") {
                    sloppyArguments.append("--config-path")
                    sloppyArguments.append(value)
                } else {
                    throw PluginError.message(
                        "Unknown plugin argument '\(argument)'. Supported flags: --no-dashboard, --config-path <path>. Use '--' for any other sloppy run arguments."
                    )
                }
            }

            index += 1
        }

        self.skipDashboard = skipDashboard
        self.sloppyArguments = sloppyArguments
    }

    private static func parseEqualsValue(_ argument: String, flag: String) -> String? {
        let prefix = "\(flag)="
        guard argument.hasPrefix(prefix) else {
            return nil
        }
        let value = String(argument.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }
}

private enum PluginError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message):
            return message
        }
    }
}
