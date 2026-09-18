import ArgumentParser
import Foundation
import Protocols

struct AgentPluginCommandGroup: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-plugin",
        abstract: "Manage Agent Plugin ZIP bundles.",
        subcommands: [
            AgentPluginListCommand.self,
            AgentPluginSearchCommand.self,
            AgentPluginInspectCommand.self,
            AgentPluginInstallCommand.self,
            AgentPluginUpdateCommand.self,
            AgentPluginReconfigureCommand.self,
            AgentPluginUninstallCommand.self,
            AgentPluginRegistryCommand.self,
        ]
    )
}

struct AgentPluginListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list")
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose = false
    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        CLIFormatters.output(try await client.get("/v1/agent-plugins"), format: .json)
    }
}

struct AgentPluginSearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "search")
    @Argument var query: String = ""
    @Option(name: .long) var registryId: String?
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose = false
    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        var params = ["search": query]
        if let registryId { params["registryId"] = registryId }
        CLIFormatters.output(try await client.get("/v1/agent-plugin-catalog", query: params), format: .json)
    }
}

struct AgentPluginInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install", abstract: "Inspect, approve, and install a ZIP or HTTPS URL.")
    @Argument var source: String
    @Option(name: .long, parsing: .upToNextOption) var agent: [String] = []
    @Option(name: .long, parsing: .upToNextOption) var input: [String] = []
    @Flag(name: .long) var trust = false
    @Flag(name: .long) var approveCommands = false
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose = false

    mutating func run() async throws {
        try await runAgentPluginInstall(source: source, agents: agent, inputPairs: input, trust: trust, approveCommands: approveCommands, url: url, token: token, verbose: verbose)
    }
}

struct AgentPluginInspectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "inspect")
    @Argument var source: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: false)
        let resolved = try await resolveAgentPluginSource(source, client: client)
        CLIFormatters.output(try await client.post("/v1/agent-plugins/inspections", body: client.encode(AgentPluginInspectionRequest(source: resolved))), format: .json)
    }
}

struct AgentPluginUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Install a reviewed replacement version.")
    @Argument var source: String
    @Option(name: .long, parsing: .upToNextOption) var agent: [String] = []
    @Option(name: .long, parsing: .upToNextOption) var input: [String] = []
    @Flag(name: .long) var trust = false
    @Flag(name: .long) var approveCommands = false
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    mutating func run() async throws {
        try await runAgentPluginInstall(source: source, agents: agent, inputPairs: input, trust: trust, approveCommands: approveCommands, url: url, token: token, verbose: false)
    }
}

struct AgentPluginReconfigureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reconfigure", abstract: "Reinstall a package with a new agent selection or inputs.")
    @Argument var source: String
    @Option(name: .long, parsing: .upToNextOption) var agent: [String] = []
    @Option(name: .long, parsing: .upToNextOption) var input: [String] = []
    @Flag(name: .long) var trust = false
    @Flag(name: .long) var approveCommands = false
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    mutating func run() async throws {
        try await runAgentPluginInstall(source: source, agents: agent, inputPairs: input, trust: trust, approveCommands: approveCommands, url: url, token: token, verbose: false)
    }
}

struct AgentPluginUninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall")
    @Argument var id: String
    @Flag(name: .long) var forceModified = false
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose = false
    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let request = AgentPluginUninstallPlanRequest(forceModifiedComponents: forceModified)
        CLIFormatters.output(try await client.post("/v1/agent-plugins/\(SloppyCLIClient.escape(id))/uninstall", body: client.encode(request)), format: .json)
    }
}

struct AgentPluginRegistryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "registry", subcommands: [AgentPluginRegistryListCommand.self, AgentPluginRegistryAddCommand.self, AgentPluginRegistryDeleteCommand.self])
}

struct AgentPluginRegistryListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list")
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: false)
        CLIFormatters.output(try await client.get("/v1/agent-plugin-registries"), format: .json)
    }
}

struct AgentPluginRegistryAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add")
    @Argument var name: String
    @Argument var registryURL: String
    @Flag(name: .long) var makeDefault = false
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: false)
        let request = AgentPluginRegistryWriteRequest(name: name, baseURL: registryURL, enabled: true, isDefault: makeDefault)
        CLIFormatters.output(try await client.post("/v1/agent-plugin-registries", body: client.encode(request)), format: .json)
    }
}

struct AgentPluginRegistryDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete")
    @Argument var id: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: false)
        _ = try await client.delete("/v1/agent-plugin-registries/\(SloppyCLIClient.escape(id))")
        CLIStyle.success("Registry removed.")
    }
}

private func resolveAgentPluginSource(_ source: String, client: SloppyCLIClient) async throws -> AgentPluginSource {
    if source.hasPrefix("https://") { return .init(kind: .url, url: source) }
    let data = try Data(contentsOf: URL(fileURLWithPath: source))
    let uploadedData = try await client.post("/v1/agent-plugins/uploads", body: data, contentType: "application/zip")
    let upload = try JSONDecoder().decode(AgentPluginUpload.self, from: uploadedData)
    return .init(kind: .upload, uploadId: upload.id)
}

private func runAgentPluginInstall(
    source: String,
    agents: [String],
    inputPairs: [String],
    trust: Bool,
    approveCommands: Bool,
    url: String?,
    token: String?,
    verbose: Bool
) async throws {
    let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
    let pluginSource = try await resolveAgentPluginSource(source, client: client)
    let inspectionData = try await client.post("/v1/agent-plugins/inspections", body: client.encode(AgentPluginInspectionRequest(source: pluginSource)))
    let inspection = try JSONDecoder().decode(AgentPluginInspection.self, from: inspectionData)
    let values = inputPairs.reduce(into: [String: String]()) { result, pair in
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2 { result[parts[0]] = parts[1] }
    }
    let planData = try await client.post("/v1/agent-plugins/plans", body: client.encode(AgentPluginPlanRequest(inspectionId: inspection.id, agentIds: agents, inputs: values)))
    let plan = try JSONDecoder().decode(AgentPluginInstallPlan.self, from: planData)
    guard (!plan.requiresTrustConfirmation || trust), (!plan.requiresCommandApproval || approveCommands) else {
        CLIFormatters.output(planData, format: .json)
        throw ValidationError("Review the plan, then pass --trust and/or --approve-commands as requested.")
    }
    let request = AgentPluginInstallRequest(planId: plan.id, approvalHash: plan.approvalHash, trustConfirmed: trust, commandsApproved: approveCommands)
    CLIFormatters.output(try await client.post("/v1/agent-plugins/install", body: client.encode(request)), format: .json)
}
