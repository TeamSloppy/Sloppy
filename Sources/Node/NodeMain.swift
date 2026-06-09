import ArgumentParser
import Foundation
import Logging
import Protocols
import SloppyNodeCore

@main
struct NodeMain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sloppy-node",
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

    @Option(name: .long, help: "Relay URL. Overrides the relay in node config.")
    var relay: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let logger = Logger(label: "sloppy.node.start")
        let store = NodeConfigStore(configURL: configURL(from: configPath))
        let config = try store.load()
        let daemon = NodeDaemon(config: config)
        await daemon.connect()
        let relayURL = relay ?? config.relayURL
        logger.info("SloppyNode \(config.identity.nodeId) started name=\(config.identity.name) relay=\(relayURL ?? "none")")

        if let relayURL, !relayURL.isEmpty {
            let client = NodeMeshClient(
                config: config,
                daemon: daemon,
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
    var ttlSeconds: Double = 86400

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

struct NetworkCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "network-create",
        abstract: "Creates or updates local SloppyNode mesh network metadata."
    )

    @Option(name: .long, help: "Network id.")
    var id: String

    @Option(name: .long, help: "Human-readable network name. Defaults to id.")
    var name: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let state = try NodeMeshStore(stateURL: meshURL(from: meshPath)).createNetwork(id: id, name: name)
        print("Created mesh network")
        print("  id: \(state.networkId)")
        print("  name: \(state.networkName)")
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

struct SharedProjectUpdate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
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

    mutating func run() async throws {
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

struct SharedProjectRemoveMember: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
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

    mutating func run() async throws {
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

struct SharedProjectList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shared-project-list",
        abstract: "Lists shared project metadata records."
    )

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let projects = try NodeMeshStore(stateURL: meshURL(from: meshPath)).listSharedProjects()
        print("PROJECT ID\tNAME\tREPO\tDEFAULT BRANCH\tMEMBERS")
        for project in projects {
            print("\(project.id)\t\(project.name)\t\(project.repoUrl)\t\(project.defaultBranch)\t\(project.members.count)")
        }
    }
}

struct TaskCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
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

    mutating func run() async throws {
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

struct TaskList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "task-list",
        abstract: "Lists mesh task dispatch records."
    )

    @Option(name: .long, help: "Optional shared project id or name.")
    var project: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let tasks = try NodeMeshStore(stateURL: meshURL(from: meshPath)).listTasks(projectIdOrName: project)
        print("TASK ID\tPROJECT\tASSIGNED NODE\tSTATUS\tBRANCH\tCOMMIT\tTITLE")
        for task in tasks {
            print("\(task.id)\t\(task.projectId)\t\(task.assignedNodeId)\t\(task.status.rawValue)\t\(task.branch ?? "-")\t\(task.commit ?? "-")\t\(task.title)")
        }
    }
}

struct TaskStatus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "task-status",
        abstract: "Updates mesh task status and optional result metadata."
    )

    @Option(name: .long, help: "Mesh task id.")
    var task: String

    @Option(name: .long, help: "New status.")
    var status: String

    @Option(name: .long, help: "Actor node id.")
    var actor: String

    @Option(name: .long, help: "Result branch.")
    var branch: String?

    @Option(name: .long, help: "Result commit.")
    var commit: String?

    @Option(name: .long, help: "Result summary.")
    var summary: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        guard let parsedStatus = MeshTaskStatus(rawValue: status) else {
            throw ValidationError("Unknown task status '\(status)'.")
        }
        let task = try NodeMeshStore(stateURL: meshURL(from: meshPath)).updateTaskStatus(
            taskId: task,
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

struct RPCRequest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rpc-request",
        abstract: "Stores a mesh RPC request envelope for a target node."
    )

    @Option(name: .long, help: "Source node id.")
    var from: String

    @Option(name: .long, help: "Target node id.")
    var to: String

    @Option(name: .long, help: "RPC method name.")
    var method: String

    @Option(name: .long, help: "JSON params object/value.")
    var params: String?

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let parsedParams = try parseJSONValue(params) ?? .object([:])
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

struct AuditLog: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit-log",
        abstract: "Prints local mesh audit log entries."
    )

    @Option(name: .long, help: "Maximum number of entries to print.")
    var limit: Int = 50

    @Option(name: .long, help: "Mesh state path. Defaults to ~/.sloppy/mesh.json.")
    var meshPath: String?

    mutating func run() async throws {
        await LoggingBootstrapper.shared.bootstrapIfNeeded()
        let state = try NodeMeshStore(stateURL: meshURL(from: meshPath)).load()
        let entries = state.auditLog.suffix(max(0, limit))
        print("TIME\tACTOR\tTARGET\tACTION\tPROJECT\tTASK\tALLOWED\tMESSAGE")
        for entry in entries {
            print("\(formatDate(entry.time))\t\(entry.actor)\t\(entry.target ?? "-")\t\(entry.action)\t\(entry.project ?? "-")\t\(entry.task ?? "-")\t\(entry.allowed)\t\(entry.message ?? "-")")
        }
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
