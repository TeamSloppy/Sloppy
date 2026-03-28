import ArgumentParser
import Foundation

struct ProvidersCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "providers",
        abstract: "Manage model providers and API keys.",
        subcommands: [
            ProvidersListCommand.self,
            ProvidersAddCommand.self,
            ProvidersRemoveCommand.self,
            ProvidersProbeCommand.self,
            ProvidersModelsCommand.self,
            ProvidersOpenAICommand.self,
            ProvidersSearchCommand.self,
        ]
    )
}

struct ProvidersListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List configured model providers.")

    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/config")
            if let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = cfg["models"],
               let modelsData = try? JSONSerialization.data(withJSONObject: models, options: .prettyPrinted),
               let str = String(data: modelsData, encoding: .utf8) {
                print(str)
            } else {
                CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
            }
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ProvidersAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add a model provider.")

    @Option(name: .long, help: "Display title") var title: String
    @Option(name: .long, help: "API URL") var apiUrl: String
    @Option(name: .long, help: "API key") var apiKey: String
    @Option(name: .long, help: "Model identifier") var model: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let configData = try await client.get("/v1/config")
            guard var cfg = try JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
                CLIStyle.error("Failed to parse config."); throw ExitCode.failure
            }
            var models = cfg["models"] as? [[String: Any]] ?? []
            let entry: [String: Any] = ["title": title, "apiUrl": apiUrl, "apiKey": apiKey, "model": model]
            models.append(entry)
            cfg["models"] = models
            let body = try JSONSerialization.data(withJSONObject: cfg)
            let data = try await client.put("/v1/config", body: body)
            CLIStyle.success("Provider '\(title)' added.")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ProvidersRemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a model provider by title.")

    @Argument(help: "Provider title") var title: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let configData = try await client.get("/v1/config")
            guard var cfg = try JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
                CLIStyle.error("Failed to parse config."); throw ExitCode.failure
            }
            var models = cfg["models"] as? [[String: Any]] ?? []
            let before = models.count
            models.removeAll { ($0["title"] as? String) == title }
            if models.count == before {
                CLIStyle.error("Provider '\(title)' not found."); throw ExitCode.failure
            }
            cfg["models"] = models
            let body = try JSONSerialization.data(withJSONObject: cfg)
            _ = try await client.put("/v1/config", body: body)
            CLIStyle.success("Provider '\(title)' removed.")
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ProvidersProbeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "probe", abstract: "Probe a provider connection.")

    @Option(name: .long, help: "Provider ID to probe") var providerId: String
    @Option(name: .long, help: "API key override") var apiKey: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        var payload: [String: Any] = ["providerId": providerId]
        if let apiKey { payload["apiKey"] = apiKey }
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.post("/v1/providers/probe", body: body)
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ProvidersModelsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "models", abstract: "List available models from an OpenAI-compatible endpoint.")

    @Option(name: .long, help: "API URL") var apiUrl: String
    @Option(name: .long, help: "API key") var apiKey: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let payload: [String: Any] = ["apiUrl": apiUrl, "apiKey": apiKey]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.post("/v1/providers/openai/models", body: body)
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ProvidersOpenAICommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "openai",
        abstract: "Manage OpenAI OAuth connection.",
        subcommands: [ProvidersOpenAIStatusCommand.self, ProvidersOpenAIDisconnectCommand.self]
    )
}

struct ProvidersOpenAIStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Get OpenAI OAuth status.")

    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/providers/openai/status")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ProvidersOpenAIDisconnectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "disconnect", abstract: "Disconnect OpenAI OAuth.")

    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            _ = try await client.post("/v1/providers/openai/oauth/disconnect")
            CLIStyle.success("OpenAI OAuth disconnected.")
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct ProvidersSearchCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "View search provider status.",
        subcommands: [ProvidersSearchStatusCommand.self]
    )
}

struct ProvidersSearchStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Get search provider status.")

    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/providers/search/status")
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}
