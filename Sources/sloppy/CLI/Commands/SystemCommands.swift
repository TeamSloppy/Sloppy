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
        abstract: "Check for a newer version of Sloppy."
    )

    @Option(name: .long, help: "Sloppy server URL") var url: String?
    @Option(name: .long, help: "Auth token") var token: String?
    @Option(name: .long, help: "Output format: json, table") var format: String = "json"
    @Flag(name: .long, help: "Show detailed HTTP info") var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.post("/v1/updates/check")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let updateAvailable = json["updateAvailable"] as? Bool {
                if updateAvailable {
                    let latest = json["latestVersion"] as? String ?? "unknown"
                    let current = json["currentVersion"] as? String ?? SloppyVersion.current
                    print(CLIStyle.yellow("Update available:") + " \(CLIStyle.whiteBold(latest)) (current: \(current))")
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
