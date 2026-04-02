import ArgumentParser
import Foundation
import Protocols

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
        abstract: "Manage OpenAI authentication.",
        subcommands: [
            ProvidersOpenAIStatusCommand.self,
            ProvidersOpenAIConnectCommand.self,
            ProvidersOpenAIDisconnectCommand.self
        ]
    )
}

enum OpenAIDeviceAuthorizationFlow {
    enum FlowError: LocalizedError {
        case timedOut(Int)
        case authorizationFailed(String)

        var errorDescription: String? {
            switch self {
            case let .timedOut(seconds):
                return "Timed out waiting for OpenAI device authorization after \(seconds)s."
            case let .authorizationFailed(message):
                return message
            }
        }
    }

    static func effectiveTimeout(serverExpiresIn: Int, requestedTimeout: Int?) -> Int {
        let normalizedServerTimeout = max(1, serverExpiresIn)
        guard let requestedTimeout, requestedTimeout > 0 else {
            return normalizedServerTimeout
        }
        return min(requestedTimeout, normalizedServerTimeout)
    }

    static func pollUntilApproved(
        request: OpenAIDeviceCodePollRequest,
        initialInterval: Int,
        timeoutSeconds: Int,
        poll: @escaping @Sendable (OpenAIDeviceCodePollRequest) async throws -> OpenAIDeviceCodePollResponse,
        sleep: @escaping @Sendable (Int) async throws -> Void,
        now: @escaping @Sendable () -> Date = Date.init,
        onStatus: (@Sendable (OpenAIDeviceCodePollResponse, Int) -> Void)? = nil
    ) async throws -> OpenAIDeviceCodePollResponse {
        let startedAt = now()
        let deadline = startedAt.addingTimeInterval(TimeInterval(max(1, timeoutSeconds)))
        var currentInterval = max(1, initialInterval)

        while true {
            if now() >= deadline {
                throw FlowError.timedOut(Int(deadline.timeIntervalSince(startedAt)))
            }

            let response = try await poll(request)
            switch response.status {
            case "approved":
                guard response.ok else {
                    throw FlowError.authorizationFailed(response.message)
                }
                return response
            case "pending":
                onStatus?(response, currentInterval)
                try await sleep(currentInterval)
            case "slow_down":
                currentInterval += 5
                onStatus?(response, currentInterval)
                try await sleep(currentInterval)
            default:
                if response.ok {
                    return response
                }
                throw FlowError.authorizationFailed(response.message)
            }
        }
    }
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

struct ProvidersOpenAIConnectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect",
        abstract: "Connect OpenAI OAuth using device authorization."
    )

    @Option(name: .long, help: "Maximum seconds to wait for approval. Defaults to the server-provided expiration.")
    var timeout: Int?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let verboseEnabled = verbose

        do {
            let startData = try await client.post("/v1/providers/openai/oauth/device-code/start")
            let startResponse = try JSONDecoder().decode(OpenAIDeviceCodeStartResponse.self, from: startData)
            let timeoutSeconds = OpenAIDeviceAuthorizationFlow.effectiveTimeout(
                serverExpiresIn: startResponse.expiresIn,
                requestedTimeout: timeout
            )

            CLIStyle.success("OpenAI device authorization started.")
            print("Open this URL in your browser:")
            print(startResponse.verificationURL)
            print("")
            print("Enter this code:")
            print(CLIStyle.bold(startResponse.userCode))
            print("")
            print("Waiting for approval for up to \(timeoutSeconds)s...")

            let pollRequest = OpenAIDeviceCodePollRequest(
                deviceAuthId: startResponse.deviceAuthId,
                userCode: startResponse.userCode
            )

            let finalResponse = try await OpenAIDeviceAuthorizationFlow.pollUntilApproved(
                request: pollRequest,
                initialInterval: startResponse.interval,
                timeoutSeconds: timeoutSeconds,
                poll: { request in
                    let body = try client.encode(request)
                    let data = try await client.post("/v1/providers/openai/oauth/device-code/poll", body: body)
                    return try JSONDecoder().decode(OpenAIDeviceCodePollResponse.self, from: data)
                },
                sleep: { seconds in
                    try await Task.sleep(nanoseconds: UInt64(max(1, seconds)) * 1_000_000_000)
                },
                onStatus: { response, interval in
                    switch response.status {
                    case "pending":
                        CLIStyle.verbose("Still waiting for OpenAI authorization...", enabled: verboseEnabled)
                    case "slow_down":
                        CLIStyle.verbose(
                            "OpenAI requested slower polling. Retrying in \(interval)s.",
                            enabled: true
                        )
                    default:
                        break
                    }
                }
            )

            CLIStyle.success(finalResponse.message)
            if let accountId = finalResponse.accountId, !accountId.isEmpty {
                print("Account ID: \(accountId)")
            }
            if let planType = finalResponse.planType, !planType.isEmpty {
                print("Plan: \(planType)")
            }
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
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
