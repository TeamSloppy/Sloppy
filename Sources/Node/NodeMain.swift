import ArgumentParser
import Foundation
import Logging
import SloppyNodeCore
import Protocols

@main
struct NodeMain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sloppy-node",
        abstract: "Runs the standalone Sloppy local executor.",
        subcommands: [Init.self, Status.self, Start.self, InviteCreate.self, Join.self, List.self, SharedProjectCreate.self, SharedProjectAttach.self, Invoke.self],
        defaultSubcommand: Bootstrap.self
    )
}

struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initializes local SloppyNode identity and config."
    )

    @Option(name: .long, help: "Human-readable node name.")
    var name: String = Host.current().localizedName ?? "local-node"

    @Option(name: .long, parsing: .upToNextOption, help: "Node roles, comma-separated or repeated.")
    var roles: [String] = ["client", "worker"]

    @Option(name: .long, parsing: .upToNextOption, help: "Node capabilities, comma-separated or repeated.")
    var capabilities: [String] = ["run_shell", "local_files"]

    @Option(name: .long, help: "Optional relay URL for future persistent connections.")
    var relay: String?

    @Option(name: .long, help: "Config path. Defaults to ~/.sloppy/node.json.")
    var configPath: String?

    @Flag(name: .long, help: "Replace an existing config.")
    var force: Bool = false

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let store = NodeConfigStore(configURL: configURL(from: configPath))
        let config = try store.initialize(
            name: name,
            roles: normalizeList(roles),
            capabilities: normalizeList(capabilities),
            relayURL: relay,
            force: force
        )

        print("Initialized SloppyNode")
        print("  id: \(config.identity.nodeId)")
        print("  name: \(config.identity.name)")
        print("  roles: \(config.identity.roles.joined(separator: ","))")
        print("  capabilities: \(config.identity.capabilities.joined(separator: ","))")
        print("  publicKey: \(config.identity.publicKey)")
        print("  config: \(store.configURL.path)")
    }
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Prints local SloppyNode identity and runtime status."
    )

    @Option(name: .long, help: "Config path. Defaults to ~/.sloppy/node.json.")
    var configPath: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let store = NodeConfigStore(configURL: configURL(from: configPath))
        let config = try store.load()
        let daemon = NodeDaemon(config: config)
        await daemon.connect()
        let response = await daemon.invoke(NodeActionRequest(action: .status))
        let state = response.data?.asObject?["state"]?.asString ?? "unknown"

        print("SloppyNode status")
        print("  id: \(config.identity.nodeId)")
        print("  name: \(config.identity.name)")
        print("  state: \(state)")
        print("  roles: \(config.identity.roles.joined(separator: ","))")
        print("  capabilities: \(config.identity.capabilities.joined(separator: ","))")
        print("  relay: \(config.relayURL ?? "-")")
        print("  config: \(store.configURL.path)")
    }
}

struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Runs SloppyNode as a foreground daemon process."
    )

    @Option(name: .long, help: "Config path. Defaults to ~/.sloppy/node.json.")
    var configPath: String?

    @Option(name: .long, help: "Heartbeat interval in seconds.")
    var heartbeatInterval: Double = 15

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let logger = Logger(label: "sloppy.node.start")
        let store = NodeConfigStore(configURL: configURL(from: configPath))
        let config = try store.load()
        let daemon = NodeDaemon(config: config)
        await daemon.connect()
        logger.info("SloppyNode \(config.identity.nodeId) started name=\(config.identity.name) relay=\(config.relayURL ?? "none")")

        while !Task.isCancelled {
            await daemon.heartbeat()
            try await Task.sleep(nanoseconds: UInt64(max(1, heartbeatInterval) * 1_000_000_000))
        }
    }
}


struct InviteCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "invite-create",
        abstract: "Creates a one-time invite token for another SloppyNode."
    )

    @Option(name: .long, help: "Network id/name for this invite.")
    var network: String = "personal"

    @Option(name: .long, help: "Optional expected node name.")
    var name: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Roles granted to the joining node, comma-separated or repeated.")
    var roles: [String] = ["worker"]

    @Option(name: .long, parsing: .upToNextOption, help: "Capabilities granted to the joining node, comma-separated or repeated.")
    var capabilities: [String] = ["run_agent", "git"]

    @Option(name: .long, help: "Invite lifetime in seconds.")
    var ttlSeconds: Double = 86_400

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let store = NodeMeshStore(stateURL: meshURL(from: meshPath))
        let invite = try store.createInvite(
            networkId: network,
            name: name,
            roles: normalizeList(roles),
            capabilities: normalizeList(capabilities),
            ttlSeconds: ttlSeconds
        )
        print(invite.token)
        print("  network: \(invite.networkId)")
        print("  roles: \(invite.roles.joined(separator: ","))")
        print("  capabilities: \(invite.capabilities.joined(separator: ","))")
        print("  expiresAt: \(ISO8601DateFormatter().string(from: invite.expiresAt))")
    }
}

struct Join: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "join",
        abstract: "Joins a SloppyNode mesh using a one-time invite token."
    )

    @Option(name: .long, help: "Relay/coordinator URL, e.g. https://sloppy.example.com.")
    var relay: String

    @Option(name: .long, help: "Invite token created by the coordinator.")
    var invite: String

    @Option(name: .long, help: "Human-readable node name. Defaults to invite name or host name.")
    var name: String?

    @Option(name: .long, help: "Config path. Defaults to ~/.sloppy/node.json.")
    var configPath: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    @Flag(name: .long, help: "Replace an existing local node config.")
    var force: Bool = false

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let meshStore = NodeMeshStore(stateURL: meshURL(from: meshPath))
        let state = try meshStore.load()
        let inviteRecord = state.invites.first(where: { $0.token == invite })
        let nodeName = name ?? inviteRecord?.name ?? Host.current().localizedName ?? "joined-node"
        let roles = inviteRecord?.roles.isEmpty == false ? inviteRecord!.roles : ["worker"]
        let capabilities = inviteRecord?.capabilities.isEmpty == false ? inviteRecord!.capabilities : ["run_agent", "git"]

        let configStore = NodeConfigStore(configURL: configURL(from: configPath))
        let config = try configStore.initialize(
            name: nodeName,
            roles: roles,
            capabilities: capabilities,
            relayURL: relay,
            force: force
        )
        let record = try meshStore.consumeInvite(token: invite, identity: config.identity, endpoint: relay)

        print("Joined SloppyNode mesh")
        print("  id: \(record.id)")
        print("  name: \(record.name)")
        print("  relay: \(relay)")
        print("  config: \(configStore.configURL.path)")
    }
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Lists known SloppyNodes in the mesh registry."
    )

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let state = try NodeMeshStore(stateURL: meshURL(from: meshPath)).load()
        print("NODE ID\tNAME\tSTATUS\tROLES\tCAPABILITIES")
        for node in state.nodes.sorted(by: { $0.name < $1.name }) {
            print("\(node.id)\t\(node.name)\t\(node.status.rawValue)\t\(node.roles.joined(separator: ","))\t\(node.capabilities.joined(separator: ","))")
        }
    }
}

struct SharedProjectCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shared-project-create",
        abstract: "Creates a shared project metadata record."
    )

    @Option(name: .long, help: "Shared project name.")
    var name: String

    @Option(name: .long, help: "Git repository URL shared by all nodes.")
    var repo: String

    @Option(name: .long, help: "Default Git branch.")
    var defaultBranch: String = "main"

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let project = try NodeMeshStore(stateURL: meshURL(from: meshPath)).createSharedProject(
            name: name,
            repoUrl: repo,
            defaultBranch: defaultBranch
        )
        print("Created shared project")
        print("  id: \(project.id)")
        print("  name: \(project.name)")
        print("  repo: \(project.repoUrl)")
        print("  defaultBranch: \(project.defaultBranch)")
    }
}

struct SharedProjectAttach: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shared-project-attach",
        abstract: "Attaches a node/local repo path to a shared project."
    )

    @Option(name: .long, help: "Shared project id or name.")
    var project: String

    @Option(name: .long, help: "Node id to attach.")
    var node: String

    @Option(name: .long, help: "Local repository path on that node.")
    var path: String

    @Option(name: .long, help: "Member role: owner, controller, worker, reviewer.")
    var role: String = "worker"

    @Option(name: .long, parsing: .upToNextOption, help: "Permissions, comma-separated or repeated.")
    var permissions: [String] = ["project.read", "task.update"]

    @Option(name: .long, help: "Optional actor id for this member.")
    var actorId: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let updated = try NodeMeshStore(stateURL: meshURL(from: meshPath)).attachMember(
            projectIdOrName: project,
            nodeId: node,
            localRepoPath: path,
            role: role,
            actorId: actorId,
            permissions: normalizeList(permissions)
        )
        print("Attached node to shared project")
        print("  project: \(updated.id)")
        print("  node: \(node)")
        print("  path: \(path)")
        print("  members: \(updated.members.count)")
    }
}

struct Bootstrap: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bootstrap",
        abstract: "Runs the legacy bootstrap command."
    )

    @Option(name: [.short, .long], help: "Node identifier")
    var nodeId: String = "node-local"

    @Option(name: .long, help: "Bootstrap command path")
    var command: String = "/bin/echo"

    @Option(name: .long, parsing: .upToNextOption, help: "Bootstrap command arguments")
    var arguments: [String] = ["Node daemon ready"]

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let logger = Logger(label: "sloppy.node.main")

        let daemon = NodeDaemon(nodeId: nodeId)
        await daemon.connect()
        await daemon.heartbeat()

        do {
            let result = try await daemon.spawnProcess(command: command, arguments: arguments)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("Node \(nodeId) process exit=\(result.exitCode) stdout=\(stdout)")
        } catch {
            logger.error("Node daemon failed to spawn process: \(String(describing: error))")
        }
    }
}

struct Invoke: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "invoke",
        abstract: "Runs one JSON node action request."
    )

    @Option(name: [.short, .long], help: "Node identifier")
    var nodeId: String = "node-local"

    @Flag(name: .long, help: "Read a NodeActionRequest JSON object from stdin.")
    var stdin: Bool = false

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let daemon = NodeDaemon(nodeId: nodeId)
        await daemon.connect()
        await daemon.heartbeat()

        let input: Data
        if stdin {
            input = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            throw ValidationError("Use --stdin to provide a JSON request.")
        }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let response: NodeActionResponse
        do {
            let request = try decoder.decode(NodeActionRequest.self, from: input)
            response = await daemon.invoke(request)
        } catch {
            response = .failure(action: .status, code: "invalid_json", message: error.localizedDescription)
        }

        let data = try encoder.encode(response)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private func meshURL(from path: String?) -> URL {
    guard let path, !path.isEmpty else {
        return NodeMeshStore.defaultStateURL()
    }
    if path.hasPrefix("~/") {
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(path.dropFirst(2)))
    }
    return URL(fileURLWithPath: path)
}

private func configURL(from path: String?) -> URL {
    guard let path, !path.isEmpty else {
        return NodeConfigStore.defaultConfigURL()
    }
    if path.hasPrefix("~/") {
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(path.dropFirst(2)))
    }
    return URL(fileURLWithPath: path)
}

private func normalizeList(_ values: [String]) -> [String] {
    values
        .flatMap { $0.split(separator: ",") }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private actor LoggingBootstrapper {
    static let shared = LoggingBootstrapper()

    private var isBootstrapped = false

    func bootstrapIfNeeded() {
        guard !isBootstrapped else {
            return
        }

        LoggingSystem.bootstrap(ColoredLogHandler.standardError)
        isBootstrapped = true
    }
}
