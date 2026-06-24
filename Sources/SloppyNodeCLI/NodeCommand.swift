import ArgumentParser
import Foundation
import Logging
import Protocols
import SloppyNodeCore

public struct NodeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "node",
        abstract: "Runs the standalone Sloppy local executor.",
        subcommands: [
            Init.self,
            Status.self,
            Start.self,
            NetworkCreate.self,
            InviteCreate.self,
            Join.self,
            List.self,
            SharedProjectCreate.self,
            SharedProjectAttach.self,
            SharedProjectUpdate.self,
            SharedProjectRemoveMember.self,
            SharedProjectList.self,
            TaskCreate.self,
            TaskList.self,
            TaskStatus.self,
            RPCRequest.self,
            AuditLog.self,
            Invoke.self,
        ],
        defaultSubcommand: Bootstrap.self
    )

    public init() {}
}

public struct SloppyNodeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sloppy-node",
        abstract: "Runs the standalone Sloppy local executor.",
        subcommands: NodeCommand.configuration.subcommands,
        defaultSubcommand: NodeCommand.configuration.defaultSubcommand
    )

    public init() {}
}

public struct Init: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
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

    public init() {}

    public mutating func run() async throws {
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

public struct Status: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Prints local SloppyNode identity and runtime status."
    )

    @Option(name: .long, help: "Config path. Defaults to ~/.sloppy/node.json.")
    var configPath: String?

    public init() {}

    public mutating func run() async throws {
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

public struct Start: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Runs SloppyNode as a foreground daemon process."
    )

    @Option(name: .long, help: "Config path. Defaults to ~/.sloppy/node.json.")
    var configPath: String?

    @Option(name: .long, help: "Heartbeat interval in seconds.")
    var heartbeatInterval: Double = 15

    @Option(name: .long, help: "Relay URL. Overrides the relay in node config.")
    var relay: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let logger = Logger(label: "sloppy.node.start")
        let store = NodeConfigStore(configURL: configURL(from: configPath))
        let config = try store.load()
        let daemon = NodeDaemon(config: config)
        await daemon.connect()
        let relayURL = relay ?? config.relayURL
        logger.info("SloppyNode \(config.identity.nodeId) started name=\(config.identity.name) relay=\(relayURL ?? "none")")

        if let relayURL, !relayURL.isEmpty {
            let meshStore = NodeMeshStore(stateURL: meshURL(from: meshPath))
            let client = NodeMeshClient(
                config: config,
                daemon: daemon,
                meshStore: meshStore,
                heartbeatInterval: heartbeatInterval,
                onEnvelope: { envelope in
                    logger.info(
                        "Received mesh envelope",
                        metadata: [
                            "id": .string(envelope.id),
                            "type": .string(envelope.type.rawValue),
                            "from": .string(envelope.from),
                            "to": envelope.to.map(Logger.MetadataValue.string) ?? .string("-"),
                        ]
                    )
                    return []
                }
            )
            try await client.run(relayURL: relayURL)
            return
        }

        while !Task.isCancelled {
            await daemon.heartbeat()
            try await Task.sleep(nanoseconds: UInt64(max(1, heartbeatInterval) * 1_000_000_000))
        }
    }
}

public struct InviteCreate: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
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
    var ttlSeconds: Double = 86400

    @Option(name: .long, help: "Relay/coordinator URL to include in the bundled invite token.")
    var relay: String?

    @Option(name: .long, help: "Worker public key to include in the bundled invite token.")
    var publicKey: String?

    @Option(name: .long, help: "Worker node id to include in the bundled invite token.")
    var nodeId: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let store = NodeMeshStore(stateURL: meshURL(from: meshPath))
        let invite = try store.createInvite(
            networkId: network,
            name: name,
            roles: normalizeList(roles),
            capabilities: normalizeList(capabilities),
            ttlSeconds: ttlSeconds,
            relayURL: relay,
            nodeId: nodeId,
            publicKey: publicKey
        )
        print(invite.bundleToken ?? invite.token)
        print("  network: \(invite.networkId)")
        print("  roles: \(invite.roles.joined(separator: ","))")
        print("  capabilities: \(invite.capabilities.joined(separator: ","))")
        if let relayURL = invite.relayURL {
            print("  relay: \(relayURL)")
        }
        if let publicKey = invite.publicKey {
            print("  publicKey: \(publicKey)")
        }
        if let nodeId = invite.nodeId {
            print("  nodeId: \(nodeId)")
        }
        print("  expiresAt: \(ISO8601DateFormatter().string(from: invite.expiresAt))")
    }
}

public struct NetworkCreate: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "network-create",
        abstract: "Creates or updates local SloppyNode mesh network metadata."
    )

    @Option(name: .long, help: "Network id.")
    var id: String

    @Option(name: .long, help: "Human-readable network name. Defaults to id.")
    var name: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let state = try NodeMeshStore(stateURL: meshURL(from: meshPath)).createNetwork(id: id, name: name)
        print("Created mesh network")
        print("  id: \(state.networkId)")
        print("  name: \(state.networkName)")
    }
}

public struct Join: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "join",
        abstract: "Joins a SloppyNode mesh using a one-time invite token."
    )

    @Option(name: .long, help: "Relay/coordinator URL, e.g. https://sloppy.example.com.")
    var relay: String?

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

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let bundle = try? MeshInviteBundle.parse(invite)
        let inviteToken = bundle?.inviteToken ?? invite
        let relayURL = relay ?? bundle?.relayURL
        guard let relayURL, !relayURL.isEmpty else {
            throw ValidationError("Provide --relay or use a bundled slp_mesh_ invite token.")
        }

        let meshStore = NodeMeshStore(stateURL: meshURL(from: meshPath))
        let state = try meshStore.load()
        let inviteRecord = state.invites.first(where: { $0.token == inviteToken })
        let nodeName = name ?? inviteRecord?.name ?? Host.current().localizedName ?? "joined-node"
        let roles = inviteRecord?.roles.isEmpty == false ? inviteRecord!.roles : ["worker"]
        let capabilities = inviteRecord?.capabilities.isEmpty == false ? inviteRecord!.capabilities : ["run_agent", "git"]

        let configStore = NodeConfigStore(configURL: configURL(from: configPath))
        let config: NodeConfig
        if !force, let existingConfig = try? configStore.load() {
            if let nodeId = bundle?.nodeId, existingConfig.identity.nodeId != nodeId {
                throw ValidationError("Bundled invite is bound to a different worker node id.")
            }
            if let publicKey = bundle?.publicKey, existingConfig.identity.publicKey != publicKey {
                throw ValidationError("Bundled invite is bound to a different worker public key.")
            }
            var updatedConfig = existingConfig
            updatedConfig.relayURL = relayURL
            try configStore.save(updatedConfig)
            config = updatedConfig
        } else {
            if bundle?.publicKey != nil {
                throw ValidationError("Bundled invite is bound to an existing worker public key. Run `sloppy-node init` first or pass --force with a legacy invite.")
            }
            config = try configStore.initialize(
                name: nodeName,
                roles: roles,
                capabilities: capabilities,
                relayURL: relayURL,
                force: force
            )
        }
        let record = try meshStore.consumeInvite(token: invite, identity: config.identity, endpoint: relayURL)

        print("Joined SloppyNode mesh")
        print("  id: \(record.id)")
        print("  name: \(record.name)")
        print("  relay: \(relayURL)")
        print("  config: \(configStore.configURL.path)")
    }
}

public struct List: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Lists known SloppyNodes in the mesh registry."
    )

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let state = try NodeMeshStore(stateURL: meshURL(from: meshPath)).load()
        print("NODE ID\tNAME\tSTATUS\tROLES\tCAPABILITIES")
        for node in state.nodes.sorted(by: { $0.name < $1.name }) {
            print("\(node.id)\t\(node.name)\t\(node.status.rawValue)\t\(node.roles.joined(separator: ","))\t\(node.capabilities.joined(separator: ","))")
        }
    }
}

public struct SharedProjectCreate: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
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

    public init() {}

    public mutating func run() async throws {
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

public struct SharedProjectAttach: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
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

    public init() {}

    public mutating func run() async throws {
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

public struct SharedProjectUpdate: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "shared-project-update",
        abstract: "Updates shared project metadata and policies."
    )

    @Option(name: .long, help: "Shared project id or name.")
    var project: String

    @Option(name: .long, help: "New shared project name.")
    var name: String?

    @Option(name: .long, help: "New Git repository URL.")
    var repo: String?

    @Option(name: .long, help: "New default Git branch.")
    var defaultBranch: String?

    @Option(name: .long, help: "Set branchPerTask policy (true/false).")
    var branchPerTask: String?

    @Option(name: .long, help: "Set directPushToMain policy (true/false).")
    var directPushToMain: String?

    @Option(name: .long, help: "Set requireCleanWorktree policy (true/false).")
    var requireCleanWorktree: String?

    @Option(name: .long, help: "Set requireTestsBeforeReady policy (true/false).")
    var requireTestsBeforeReady: String?

    @Option(name: .long, help: "Actor node id. Defaults to local.")
    var actor: String = "local"

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let store = NodeMeshStore(stateURL: meshURL(from: meshPath))
        let current = try store.listSharedProjects().first { $0.id == project || $0.name == project }
        let policies = try updatedPolicies(from: current?.policies)
        let updated = try store.updateSharedProject(
            projectIdOrName: project,
            name: name,
            repoUrl: repo,
            defaultBranch: defaultBranch,
            policies: policies,
            actor: actor
        )
        print("Updated shared project")
        print("  id: \(updated.id)")
        print("  name: \(updated.name)")
        print("  repo: \(updated.repoUrl)")
        print("  defaultBranch: \(updated.defaultBranch)")
    }

    private func updatedPolicies(from current: SharedProjectPolicies?) throws -> SharedProjectPolicies? {
        guard branchPerTask != nil || directPushToMain != nil || requireCleanWorktree != nil || requireTestsBeforeReady != nil else {
            return nil
        }
        let base = current ?? SharedProjectPolicies()
        return try SharedProjectPolicies(
            branchPerTask: parseBoolOption(branchPerTask, name: "branch-per-task") ?? base.branchPerTask,
            directPushToMain: parseBoolOption(directPushToMain, name: "direct-push-to-main") ?? base.directPushToMain,
            requireCleanWorktree: parseBoolOption(requireCleanWorktree, name: "require-clean-worktree") ?? base.requireCleanWorktree,
            requireTestsBeforeReady: parseBoolOption(requireTestsBeforeReady, name: "require-tests-before-ready") ?? base.requireTestsBeforeReady
        )
    }
}

public struct SharedProjectRemoveMember: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "shared-project-remove-member",
        abstract: "Removes a node from a shared project."
    )

    @Option(name: .long, help: "Shared project id or name.")
    var project: String

    @Option(name: .long, help: "Node id to remove.")
    var node: String

    @Option(name: .long, help: "Actor node id. Defaults to local.")
    var actor: String = "local"

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let updated = try NodeMeshStore(stateURL: meshURL(from: meshPath)).removeSharedProjectMember(
            projectIdOrName: project,
            nodeId: node,
            actor: actor
        )
        print("Removed shared project member")
        print("  project: \(updated.id)")
        print("  node: \(node)")
        print("  members: \(updated.members.count)")
    }
}

public struct SharedProjectList: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "shared-project-list",
        abstract: "Lists shared project metadata records."
    )

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let projects = try NodeMeshStore(stateURL: meshURL(from: meshPath)).listSharedProjects()
        print("PROJECT ID\tNAME\tREPO\tDEFAULT BRANCH\tMEMBERS")
        for project in projects {
            print("\(project.id)\t\(project.name)\t\(project.repoUrl)\t\(project.defaultBranch)\t\(project.members.count)")
        }
    }
}

public struct TaskCreate: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "task-create",
        abstract: "Creates a mesh task dispatch record for a target node."
    )

    @Option(name: .long, help: "Shared project id or name.")
    var project: String

    @Option(name: .long, help: "Task title.")
    var title: String

    @Option(name: .long, help: "Target node id.")
    var assign: String

    @Option(name: .long, help: "Actor node id. Defaults to local.")
    var actor: String = "local"

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let task = try NodeMeshStore(stateURL: meshURL(from: meshPath)).dispatchTask(
            projectIdOrName: project,
            title: title,
            assignedNodeId: assign,
            actor: actor
        )
        print("Created mesh task")
        print("  id: \(task.id)")
        print("  project: \(task.projectId)")
        print("  assignedNode: \(task.assignedNodeId)")
        print("  status: \(task.status.rawValue)")
    }
}

public struct TaskList: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "task-list",
        abstract: "Lists mesh task dispatch records."
    )

    @Option(name: .long, help: "Optional shared project id or name.")
    var project: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let tasks = try NodeMeshStore(stateURL: meshURL(from: meshPath)).listTasks(projectIdOrName: project)
        print("TASK ID\tPROJECT\tASSIGNED NODE\tSTATUS\tBRANCH\tCOMMIT\tTITLE")
        for task in tasks {
            print("\(task.id)\t\(task.projectId)\t\(task.assignedNodeId)\t\(task.status.rawValue)\t\(task.branch ?? "-")\t\(task.commit ?? "-")\t\(task.title)")
        }
    }
}

public struct TaskStatus: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "task-status",
        abstract: "Updates mesh task status and optional result metadata."
    )

    @Option(name: .long, help: "Mesh task id.")
    var task: String

    @Option(name: .long, help: "New status.")
    var status: String

    @Option(name: .long, help: "Actor node id.")
    var actor: String

    @Option(name: .long, help: "Project id or name when task id is not globally unique.")
    var project: String?

    @Option(name: .long, help: "Result branch.")
    var branch: String?

    @Option(name: .long, help: "Result commit.")
    var commit: String?

    @Option(name: .long, help: "Result summary.")
    var summary: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        guard let parsedStatus = MeshTaskStatus(rawValue: status) else {
            throw ValidationError("Unknown task status '\(status)'.")
        }
        let task = try NodeMeshStore(stateURL: meshURL(from: meshPath)).updateTaskStatus(
            taskId: task,
            projectIdOrName: project,
            status: parsedStatus,
            actor: actor,
            branch: branch,
            commit: commit,
            summary: summary
        )
        print("Updated mesh task")
        print("  id: \(task.id)")
        print("  status: \(task.status.rawValue)")
        if let branch = task.branch { print("  branch: \(branch)") }
        if let commit = task.commit { print("  commit: \(commit)") }
    }
}

public struct RPCRequest: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rpc-request",
        abstract: "Creates a mesh RPC request envelope or sends it over a live relay."
    )

    @Option(name: .long, help: "Source node id for local envelope mode.")
    var from: String?

    @Option(name: .long, help: "Target node id.")
    var to: String

    @Option(name: .long, help: "RPC method name.")
    var method: String

    @Option(name: .long, help: "JSON params object/value.")
    var params: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    @Flag(name: .long, help: "Send the RPC request over the configured relay and print the response JSON.")
    var live: Bool = false

    @Option(name: .long, help: "Relay URL for live mode. Overrides node config.")
    var relay: String?

    @Option(name: .long, help: "Config path for live mode. Defaults to ~/.sloppy/node.json.")
    var configPath: String?

    @Option(name: .long, help: "Live RPC timeout in seconds.")
    var timeout: Double = 30

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let parsedParams = try parseJSONValue(params) ?? .object([:])

        if live {
            let store = NodeConfigStore(configURL: configURL(from: configPath))
            let config = try store.load()
            let daemon = NodeDaemon(config: config)
            let client = NodeMeshClient(config: config, daemon: daemon)
            let response = try await client.sendRPCRequest(
                relayURL: relay,
                to: to,
                method: method,
                params: parsedParams,
                timeout: timeout
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(response)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        guard let from, !from.isEmpty else {
            throw ValidationError("--from is required unless --live is set.")
        }
        let envelope = try NodeMeshStore(stateURL: meshURL(from: meshPath)).rpcRequest(
            from: from,
            to: to,
            method: method,
            params: parsedParams
        )
        print("Created mesh RPC request")
        print("  id: \(envelope.id)")
        print("  from: \(envelope.from)")
        print("  to: \(envelope.to ?? "-")")
        print("  method: \(method)")
    }
}

public struct AuditLog: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "audit-log",
        abstract: "Prints local mesh audit log entries."
    )

    @Option(name: .long, help: "Maximum number of entries to print.")
    var limit: Int = 50

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    public init() {}

    public mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let state = try NodeMeshStore(stateURL: meshURL(from: meshPath)).load()
        let entries = state.auditLog.suffix(max(0, limit))
        print("TIME\tACTOR\tTARGET\tACTION\tPROJECT\tTASK\tALLOWED\tMESSAGE")
        for entry in entries {
            print("\(formatDate(entry.time))\t\(entry.actor)\t\(entry.target ?? "-")\t\(entry.action)\t\(entry.project ?? "-")\t\(entry.task ?? "-")\t\(entry.allowed)\t\(entry.message ?? "-")")
        }
    }
}

public struct Bootstrap: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "bootstrap",
        abstract: "Runs the legacy bootstrap command."
    )

    @Option(name: [.short, .long], help: "Node identifier")
    var nodeId: String = "node-local"

    @Option(name: .long, help: "Bootstrap command path")
    var command: String = "/bin/echo"

    @Option(name: .long, parsing: .upToNextOption, help: "Bootstrap command arguments")
    var arguments: [String] = ["Node daemon ready"]

    public init() {}

    public mutating func run() async throws {
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

public struct Invoke: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "invoke",
        abstract: "Runs one JSON node action request."
    )

    @Option(name: [.short, .long], help: "Node identifier")
    var nodeId: String = "node-local"

    @Flag(name: .long, help: "Read a NodeActionRequest JSON object from stdin.")
    var stdin: Bool = false

    public init() {}

    public mutating func run() async throws {
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

private func parseBoolOption(_ value: String?, name: String) throws -> Bool? {
    guard let value else { return nil }
    switch value.lowercased() {
    case "true", "yes", "1": return true
    case "false", "no", "0": return false
    default: throw ValidationError("Invalid boolean for --\(name): \(value)")
    }
}

private func parseJSONValue(_ text: String?) throws -> JSONValue? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    guard let data = text.data(using: .utf8) else {
        throw ValidationError("Params must be valid UTF-8 JSON.")
    }
    do {
        return try JSONDecoder().decode(JSONValue.self, from: data)
    } catch {
        throw ValidationError("Params must be valid JSON: \(error.localizedDescription)")
    }
}

private func formatDate(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
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
