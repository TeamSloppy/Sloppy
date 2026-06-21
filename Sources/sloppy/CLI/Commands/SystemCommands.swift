import ArgumentParser
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check server health."
    )

    @Option(name: .long, help: "Sloppy server URL") var url: String?
    @Option(name: .long, help: "Auth token") var token: String?
    @Flag(name: .long, help: "Show detailed HTTP info") var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/health")
            CLIStyle.success("Server is healthy at \(client.baseURL)")
            if verbose { CLIFormatters.printJSON(data) }
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

struct UpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Check for a newer version of Sloppy, or install source updates."
    )

    @Option(name: .long, help: "Sloppy server URL") var url: String?
    @Option(name: .long, help: "Auth token") var token: String?
    @Option(name: .long, help: "Output format: json, table") var format: String = "json"
    @Option(name: .long, help: "Source checkout to update. Defaults to the checkout that built this sloppy binary.")
    var dir: String?
    @Flag(name: .long, help: "Pull and reinstall from the source checkout without requiring a running server.")
    var install: Bool = false
    @Flag(name: .long, help: "Build only the server stack when installing.")
    var serverOnly: Bool = false
    @Flag(name: .long, help: "Do not pull the source checkout before rebuilding.")
    var noGitUpdate: Bool = false
    @Flag(name: .long, help: "Do not create or refresh the sloppy command symlink.")
    var noLink: Bool = false
    @Flag(name: .long, help: "Print installer actions without executing them.")
    var dryRun: Bool = false
    @Flag(name: .long, help: "Show detailed HTTP info") var verbose: Bool = false

    mutating func run() async throws {
        if install {
            try runInstall()
            return
        }

        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.post("/v1/updates/check")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let updateAvailable = json["updateAvailable"] as? Bool {
                if updateAvailable {
                    let latest = json["latestVersion"] as? String ?? "unknown"
                    let current = json["currentVersion"] as? String ?? SloppyVersion.current
                    let updateKind = json["updateKind"] as? String ?? "release"
                    if updateKind == "git" {
                        let branch = json["latestBranch"] as? String ?? json["currentBranch"] as? String ?? "upstream"
                        let commit = json["latestCommit"] as? String ?? latest
                        print(CLIStyle.yellow("Update available:") + " \(CLIStyle.whiteBold(commit)) on \(branch) (current: \(current))")
                        print(CLIStyle.dim("  Run: sloppy update --install"))
                    } else {
                        print(CLIStyle.yellow("Update available:") + " \(CLIStyle.whiteBold(latest)) (current: \(current))")
                        print(CLIStyle.dim("  Run: sloppy update --install"))
                    }
                    if let releaseUrl = json["releaseUrl"] as? String {
                        print(CLIStyle.dim("  Release: \(releaseUrl)"))
                    }
                } else {
                    CLIStyle.success("sloppy is up to date (\(json["currentVersion"] as? String ?? SloppyVersion.current))")
                }
            } else {
                CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
            }
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }

    private func runInstall() throws {
        let currentMetadata = BuildMetadataResolver().resolve()
        let repoURL: URL
        let metadata: BuildMetadata
        if currentMetadata.isReleaseBuild {
            repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            metadata = currentMetadata
        } else {
            repoURL = try resolveSourceCheckoutURL()
            metadata = BuildMetadataResolver(repositoryRootURL: repoURL).resolve()
        }
        let localScriptURL = repoURL
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("install.sh")
        let scriptURL = try installerScriptURL(localScriptURL: localScriptURL, metadata: metadata)

        if !metadata.isReleaseBuild && !FileManager.default.fileExists(atPath: scriptURL.path) {
            CLIStyle.error("Cannot find source installer at \(scriptURL.path).")
            throw ExitCode.failure
        }

        let plan = UpdateInstallerPlan(
            metadata: metadata,
            repoURL: repoURL,
            scriptURL: scriptURL,
            options: .init(
                serverOnly: serverOnly,
                noGitUpdate: noGitUpdate,
                noLink: noLink,
                dryRun: dryRun,
                verbose: verbose
            )
        )
        print(plan.summary)

        let status = runInstaller(arguments: plan.arguments)
        guard status == 0 else {
            CLIStyle.error("\(plan.failurePrefix) failed with exit code \(status).")
            throw ExitCode.failure
        }

        CLIStyle.success("\(plan.successPrefix) complete.")
    }

    private func resolveSourceCheckoutURL() throws -> URL {
        if let dir, !dir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: NSString(string: dir).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
        }

        let metadata = BuildMetadataResolver().resolve()
        if let path = metadata.git?.repositoryRootPath {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }

        if let executableURL = currentExecutableURL(),
           let repoURL = repoRootDerivedFromExecutable(executableURL: executableURL) {
            return repoURL
        }

        CLIStyle.error("Cannot determine the source checkout for this sloppy binary. Pass --dir /path/to/Sloppy.")
        throw ExitCode.failure
    }

    private func installerScriptURL(localScriptURL: URL, metadata: BuildMetadata) throws -> URL {
        if !metadata.isReleaseBuild || FileManager.default.fileExists(atPath: localScriptURL.path) {
            return localScriptURL
        }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-install-\(UUID().uuidString).sh")
        try downloadReleaseInstaller(to: temporaryURL)
        return temporaryURL
    }

    private func downloadReleaseInstaller(to destinationURL: URL) throws {
        guard let url = URL(string: "https://raw.githubusercontent.com/TeamSloppy/Sloppy/main/scripts/install.sh") else {
            throw ExitCode.failure
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "curl",
            "-fsSL",
            "-H",
            "User-Agent: sloppy-updater/1.0",
            "-o",
            destinationURL.path,
            url.absoluteString,
        ]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        process.environment = childProcessEnvironment()

        do {
            try process.run()
        } catch {
            CLIStyle.error("Failed to download release installer: \(error.localizedDescription)")
            throw ExitCode.failure
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            CLIStyle.error("Failed to download release installer.")
            throw ExitCode.failure
        }
    }

    private func runInstaller(arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        process.environment = childProcessEnvironment()

        do {
            try process.run()
        } catch {
            CLIStyle.error("Failed to start installer: \(error.localizedDescription)")
            return 127
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

struct UpdateInstallerPlan {
    enum Kind {
        case release
        case source
    }

    struct Options {
        var serverOnly: Bool
        var noGitUpdate: Bool
        var noLink: Bool
        var dryRun: Bool
        var verbose: Bool
    }

    let kind: Kind
    let arguments: [String]
    let summary: String
    let failurePrefix: String
    let successPrefix: String

    init(metadata: BuildMetadata, repoURL: URL, scriptURL: URL, options: Options) {
        if metadata.isReleaseBuild {
            kind = .release
            summary = CLIStyle.cyan("Installing latest release") + " from GitHub Releases"
            failurePrefix = "Release update"
            successPrefix = "Release update"
            var arguments = [
                "bash",
                scriptURL.path,
                "--release",
                "--no-prompt",
            ]
            if options.noLink {
                arguments.append("--no-link")
            }
            if options.dryRun {
                arguments.append("--dry-run")
            }
            if options.verbose {
                arguments.append("--verbose")
            }
            self.arguments = arguments
            return
        }

        kind = .source
        let branch = metadata.git?.currentBranch ?? metadata.git?.upstreamBranch ?? "current branch"
        summary = [
            CLIStyle.cyan("Updating source checkout:") + " \(repoURL.path)",
            CLIStyle.cyan("Branch:") + " \(branch)",
        ].joined(separator: "\n")
        failurePrefix = "Source update"
        successPrefix = "Source update"

        let mode = options.serverOnly ? "--server-only" : "--bundle"
        var arguments = [
            "bash",
            scriptURL.path,
            mode,
            "--dir",
            repoURL.path,
            "--no-prompt",
        ]
        if options.noGitUpdate {
            arguments.append("--no-git-update")
        }
        if options.noLink {
            arguments.append("--no-link")
        }
        if options.dryRun {
            arguments.append("--dry-run")
        }
        if options.verbose {
            arguments.append("--verbose")
        }
        self.arguments = arguments
    }
}

struct LogsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "View system logs."
    )

    @Option(name: .long, help: "Sloppy server URL") var url: String?
    @Option(name: .long, help: "Auth token") var token: String?
    @Option(name: .long, help: "Output format: json, table") var format: String = "json"
    @Flag(name: .long, help: "Show detailed HTTP info") var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/logs")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

struct WorkersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workers",
        abstract: "List active workers."
    )

    @Option(name: .long, help: "Sloppy server URL") var url: String?
    @Option(name: .long, help: "Auth token") var token: String?
    @Option(name: .long, help: "Output format: json, table") var format: String = "json"
    @Flag(name: .long, help: "Show detailed HTTP info") var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/workers")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

struct BulletinsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bulletins",
        abstract: "View system bulletins."
    )

    @Option(name: .long, help: "Sloppy server URL") var url: String?
    @Option(name: .long, help: "Auth token") var token: String?
    @Option(name: .long, help: "Output format: json, table") var format: String = "json"
    @Flag(name: .long, help: "Show detailed HTTP info") var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/bulletins")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

struct TokenUsageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "token-usage",
        abstract: "View token usage statistics."
    )

    @Option(name: .long, help: "Sloppy server URL") var url: String?
    @Option(name: .long, help: "Auth token") var token: String?
    @Option(name: .long, help: "Output format: json, table") var format: String = "json"
    @Flag(name: .long, help: "Show detailed HTTP info") var verbose: Bool = false
    @Option(name: .long, help: "Filter by channel ID") var channelId: String?
    @Option(name: .long, help: "Filter by task ID") var taskId: String?
    @Option(name: .long, help: "Filter from date (ISO 8601)") var from: String?
    @Option(name: .long, help: "Filter to date (ISO 8601)") var to: String?

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        var query: [String: String] = [:]
        if let channelId { query["channelId"] = channelId }
        if let taskId { query["taskId"] = taskId }
        if let from { query["from"] = from }
        if let to { query["to"] = to }
        do {
            let data = try await client.get("/v1/token-usage", query: query)
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}
