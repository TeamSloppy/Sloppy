import Foundation
import Protocols

extension CoreService {
    public func listAgentPlugins() async -> [InstalledAgentPlugin] {
        await agentPluginManager.listInstalled()
    }

    public func getAgentPlugin(id: String) async throws -> InstalledAgentPlugin {
        guard let plugin = await agentPluginManager.installed(id: id) else {
            throw AgentPluginManagerError.notFound(id)
        }
        return plugin
    }

    public func uploadAgentPlugin(data: Data) async throws -> AgentPluginUpload {
        try await agentPluginManager.upload(data)
    }

    public func inspectAgentPlugin(_ request: AgentPluginInspectionRequest) async throws -> AgentPluginInspection {
        try await agentPluginManager.inspect(request)
    }

    public func planAgentPlugin(_ request: AgentPluginPlanRequest) async throws -> AgentPluginInstallPlan {
        let agentIDs = Set(try listAgents(includeSystem: true).map(\.id))
        return try await agentPluginManager.makePlan(request, availableAgentIDs: agentIDs)
    }

    public func installAgentPlugin(_ request: AgentPluginInstallRequest) async throws -> AgentPluginOperation {
        let context = try await agentPluginManager.consumePlan(request)
        let existing = await store.agentPlugin(id: context.plan.packageId)
        let operation = await agentPluginManager.beginOperation(
            packageId: context.plan.packageId,
            kind: existing == nil ? .install : .update,
            message: "Installing \(context.inspection.manifest.name)"
        )
        do {
            try await performAgentPluginInstall(context, existing: existing, operationID: operation.id)
            await agentPluginManager.updateOperation(id: operation.id, status: .completed, progress: 1, message: "Installed")
            await agentPluginManager.discardInspection(id: context.inspection.id)
        } catch {
            if let existing { try? await restoreAgentPluginComponents(existing) }
            let software = compatibleAgentPluginSoftware(context.inspection.manifest)
            var residuals = false
            for item in software.reversed() {
                do {
                    try await agentPluginManager.run(Array(item.rollback.reversed()), packageURL: context.packageURL, inputs: context.inputs, packageID: context.plan.packageId)
                } catch {
                    residuals = true
                }
            }
            await agentPluginManager.updateOperation(
                id: operation.id,
                status: residuals ? .failedWithResiduals : .failed,
                progress: 1,
                message: error.localizedDescription
            )
            await agentPluginManager.discardInspection(id: context.inspection.id)
            throw error
        }
        return await agentPluginManager.operation(id: operation.id) ?? operation
    }

    public func agentPluginOperation(id: String) async throws -> AgentPluginOperation {
        guard let operation = await agentPluginManager.operation(id: id) else {
            throw AgentPluginManagerError.notFound(id)
        }
        return operation
    }

    public func uninstallAgentPlugin(id: String, forceModifiedComponents: Bool) async throws -> AgentPluginOperation {
        guard let installed = await store.agentPlugin(id: id) else { throw AgentPluginManagerError.notFound(id) }
        let modified = try await modifiedAgentPluginComponents(installed)
        if !modified.isEmpty && !forceModifiedComponents {
            throw AgentPluginManagerError.conflict("Modified components require explicit removal confirmation: \(modified.joined(separator: ", "))")
        }
        let operation = await agentPluginManager.beginOperation(packageId: id, kind: .uninstall, message: "Uninstalling \(installed.name)")
        do {
            let packageURL = await agentPluginManager.packageInstallURL(installed.id, version: installed.version)
            for software in compatibleAgentPluginSoftware(installed.manifest).reversed() {
                try await agentPluginManager.run(software.uninstall, packageURL: packageURL, inputs: installed.configuration ?? [:], packageID: installed.id)
            }
            try await removeAgentPluginComponents(installed)
            if FileManager.default.fileExists(atPath: packageURL.deletingLastPathComponent().path) {
                try? FileManager.default.removeItem(at: packageURL.deletingLastPathComponent())
            }
            await store.deleteAgentPlugin(id: id)
            await agentPluginManager.updateOperation(id: operation.id, status: .completed, progress: 1, message: "Uninstalled")
        } catch {
            var failed = installed
            failed.status = .uninstallFailed
            failed.lastError = error.localizedDescription
            failed.updatedAt = Date()
            await store.saveAgentPlugin(failed)
            await agentPluginManager.updateOperation(id: operation.id, status: .failedWithResiduals, progress: 1, message: error.localizedDescription)
            throw error
        }
        return await agentPluginManager.operation(id: operation.id) ?? operation
    }

    public func listAgentPluginRegistries() async -> [AgentPluginRegistry] {
        await agentPluginManager.listRegistries()
    }

    public func saveAgentPluginRegistry(id: String?, request: AgentPluginRegistryWriteRequest) async throws -> AgentPluginRegistry {
        try await agentPluginManager.saveRegistry(id: id, request: request)
    }

    public func deleteAgentPluginRegistry(id: String) async throws {
        try await agentPluginManager.deleteRegistry(id: id)
    }

    public func searchAgentPluginCatalog(search: String, registryID: String?, cursor: String?, limit: Int) async -> AgentPluginCatalogResponse {
        await agentPluginManager.catalog(search: search, registryID: registryID, cursor: cursor, limit: limit)
    }

    private func performAgentPluginInstall(
        _ context: AgentPluginExecutionContext,
        existing: InstalledAgentPlugin?,
        operationID: String
    ) async throws {
        let manifest = context.inspection.manifest
        try preflightAgentPluginConflicts(manifest, existing: existing, agentIDs: context.plan.agentIds)
        let software = compatibleAgentPluginSoftware(manifest)
        for item in software {
            try await agentPluginManager.run(item.check, packageURL: context.packageURL, inputs: context.inputs, packageID: manifest.id)
            try await agentPluginManager.run(item.install, packageURL: context.packageURL, inputs: context.inputs, packageID: manifest.id)
        }
        await agentPluginManager.updateOperation(id: operationID, progress: 0.25, message: "Installing components")

        let destination = await agentPluginManager.packageInstallURL(manifest.id, version: manifest.version)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing, existing.version == manifest.version {
            guard existing.sha256 == context.inspection.sha256 else {
                throw AgentPluginManagerError.conflict("Version \(manifest.version) is immutable and is already installed with a different checksum.")
            }
        } else {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: context.packageURL, to: destination)
        }

        if let existing { try await removeAgentPluginComponents(existing) }
        var hashes: [String: String] = [:]
        let packageParts = manifest.id.split(separator: ".", maxSplits: 1).map(String.init)
        let owner = "agent-plugin-\(packageParts[0])"
        let packageName = packageParts[1]
        for agentID in context.plan.agentIds {
            for skill in manifest.components.skills {
                let source = try await agentPluginManager.safeComponentURL(skill.path, root: destination)
                let repo = "\(packageName)-\(skill.id)"
                _ = try agentSkillsStore.installManagedSkill(agentID: agentID, owner: owner, repo: repo, sourceURL: source, version: manifest.version, replaceExisting: true)
                if let path = try? agentSkillsStore.getSkillPath(agentID: agentID, skillID: "\(owner)/\(repo)") {
                    hashes["skill:\(agentID):\(owner)/\(repo)"] = try await agentPluginManager.hashTree(URL(fileURLWithPath: path))
                }
            }
            await sessionOrchestrator.notifySkillsChanged(agentID: agentID)
        }

        var nextConfig = currentConfig
        for mcp in manifest.components.mcpServers {
            let id = "\(manifest.id)/\(mcp.id)"
            let server = try await makeAgentPluginMCPServer(mcp, id: id, packageURL: destination, inputs: context.inputs, manifest: manifest)
            nextConfig.mcp.servers.removeAll { $0.id == id }
            nextConfig.mcp.servers.append(server)
            hashes["mcp:\(id)"] = try hashEncodable(server)
        }
        if nextConfig.mcp != currentConfig.mcp { _ = try await updateConfig(nextConfig) }

        for component in manifest.components.sloppyPlugins {
            let source = try await agentPluginManager.safeComponentURL(component.path, root: destination)
            let pluginManifest = PluginLoader(logger: logger).loadManifest(at: source)
            guard pluginManifest?.name == component.id else {
                throw AgentPluginManagerError.manifestInvalid("Sloppy component \(component.id) must match its plugin.json name")
            }
            _ = try await installSourceChannelPlugin(.init(sourceUrl: source.path, force: true, enabled: true, localDirectory: true))
            hashes["plugin:\(component.id)"] = try await agentPluginManager.hashTree(pluginsRootURL.appendingPathComponent(component.id, isDirectory: true))
        }

        let now = Date()
        let secretIDs = Set(manifest.inputs.filter { $0.kind == .secret }.map(\.id))
        let persistedInputs = context.inputs.filter { !secretIDs.contains($0.key) }
        let record = InstalledAgentPlugin(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            source: context.inspection.source,
            sha256: context.inspection.sha256,
            status: .installed,
            agentIds: context.plan.agentIds,
            manifest: manifest,
            componentHashes: hashes,
            configuration: persistedInputs,
            installedAt: existing?.installedAt ?? now,
            updatedAt: now,
            lastError: nil
        )
        await store.saveAgentPlugin(record)
        if let existing, existing.version != manifest.version {
            let old = await agentPluginManager.packageInstallURL(existing.id, version: existing.version)
            try? FileManager.default.removeItem(at: old)
        }
    }

    private func preflightAgentPluginConflicts(_ manifest: AgentPluginManifest, existing: InstalledAgentPlugin?, agentIDs: [String]) throws {
        let parts = manifest.id.split(separator: ".", maxSplits: 1).map(String.init)
        let skillOwner = "agent-plugin-\(parts[0])"
        for agentID in agentIDs {
            for skill in manifest.components.skills {
                let skillID = "\(skillOwner)/\(parts[1])-\(skill.id)"
                if (try? agentSkillsStore.getSkill(agentID: agentID, skillID: skillID)) != nil,
                   existing?.agentIds.contains(agentID) != true {
                    throw AgentPluginManagerError.conflict("Skill \(skillID) already exists for agent \(agentID) and is unmanaged.")
                }
            }
        }
        let owned = Set(existing?.manifest.components.sloppyPlugins.map(\.id) ?? [])
        for component in manifest.components.sloppyPlugins {
            if FileManager.default.fileExists(atPath: pluginsRootURL.appendingPathComponent(component.id).path), !owned.contains(component.id) {
                throw AgentPluginManagerError.conflict("Sloppy plugin \(component.id) already exists and is not owned by \(manifest.id).")
            }
        }
        let existingMCP = Set(currentConfig.mcp.servers.map(\.id))
        let oldMCP = Set(existing?.manifest.components.mcpServers.map { "\(manifest.id)/\($0.id)" } ?? [])
        for mcp in manifest.components.mcpServers where existingMCP.contains("\(manifest.id)/\(mcp.id)") && !oldMCP.contains("\(manifest.id)/\(mcp.id)") {
            throw AgentPluginManagerError.conflict("MCP server \(manifest.id)/\(mcp.id) already exists and is unmanaged.")
        }
    }

    private func makeAgentPluginMCPServer(
        _ component: AgentPluginMCPComponent,
        id: String,
        packageURL: URL,
        inputs: [String: String],
        manifest: AgentPluginManifest
    ) async throws -> CoreConfig.MCP.Server {
        let secretIDs = Set(manifest.inputs.filter { $0.kind == .secret }.map(\.id))
        let persistentValues = component.arguments + Array(component.headers.values) + Array(component.environment.values) + [component.command, component.endpoint, component.cwd].compactMap { $0 }
        for secretID in secretIDs where persistentValues.contains(where: { $0.contains("${secret.\(secretID)}") }) {
            throw AgentPluginManagerError.manifestInvalid("Secret input \(secretID) cannot be persisted in MCP configuration; reference a Core environment variable instead")
        }
        let render: (String) async throws -> String = { value in
            try await self.agentPluginManager.render(value, inputs: inputs, packageID: manifest.id)
        }
        let transport = CoreConfig.MCP.Server.Transport(rawValue: component.transport) ?? .stdio
        let cwdValue: String?
        if let rawCWD = component.cwd { cwdValue = try await render(rawCWD) }
        else { cwdValue = nil }
        let resolvedCWD: String?
        if let cwdValue, cwdValue.hasPrefix("/") { resolvedCWD = cwdValue }
        else if let cwdValue { resolvedCWD = packageURL.appendingPathComponent(cwdValue).standardizedFileURL.path }
        else { resolvedCWD = packageURL.path }
        var headers: [String: String] = [:]
        for pair in component.headers { headers[pair.key] = try await render(pair.value) }
        var environment: [String: String] = [:]
        for pair in component.environment { environment[pair.key] = try await render(pair.value) }
        let command: String?
        if let rawCommand = component.command { command = try await render(rawCommand) }
        else { command = nil }
        let endpoint: String?
        if let rawEndpoint = component.endpoint { endpoint = try await render(rawEndpoint) }
        else { endpoint = nil }
        var arguments: [String] = []
        arguments.reserveCapacity(component.arguments.count)
        for argument in component.arguments { arguments.append(try await render(argument)) }
        return CoreConfig.MCP.Server(
            id: id,
            transport: transport,
            command: command,
            arguments: arguments,
            cwd: resolvedCWD,
            endpoint: endpoint,
            headers: headers,
            environment: environment,
            timeoutMs: component.timeoutMs,
            enabled: component.enabled,
            exposeTools: component.exposeTools,
            exposeResources: component.exposeResources,
            exposePrompts: component.exposePrompts,
            toolPrefix: component.toolPrefix
        )
    }

    private func removeAgentPluginComponents(_ installed: InstalledAgentPlugin) async throws {
        let parts = installed.id.split(separator: ".", maxSplits: 1).map(String.init)
        let owner = "agent-plugin-\(parts[0])"
        let packageName = parts[1]
        for agentID in installed.agentIds {
            for skill in installed.manifest.components.skills {
                try? agentSkillsStore.uninstallSkill(agentID: agentID, skillID: "\(owner)/\(packageName)-\(skill.id)")
            }
            await sessionOrchestrator.notifySkillsChanged(agentID: agentID)
        }
        var nextConfig = currentConfig
        let mcpIDs = Set(installed.manifest.components.mcpServers.map { "\(installed.id)/\($0.id)" })
        nextConfig.mcp.servers.removeAll { mcpIDs.contains($0.id) }
        if nextConfig.mcp != currentConfig.mcp { _ = try await updateConfig(nextConfig) }
        for plugin in installed.manifest.components.sloppyPlugins {
            try? await deleteChannelPlugin(id: plugin.id)
            let source = pluginsRootURL.appendingPathComponent(plugin.id, isDirectory: true)
            if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.removeItem(at: source) }
        }
    }

    private func restoreAgentPluginComponents(_ installed: InstalledAgentPlugin) async throws {
        let packageURL = await agentPluginManager.packageInstallURL(installed.id, version: installed.version)
        guard FileManager.default.fileExists(atPath: packageURL.path) else { return }
        let parts = installed.id.split(separator: ".", maxSplits: 1).map(String.init)
        let owner = "agent-plugin-\(parts[0])"
        let packageName = parts[1]
        for agentID in installed.agentIds {
            for skill in installed.manifest.components.skills {
                let source = try await agentPluginManager.safeComponentURL(skill.path, root: packageURL)
                _ = try agentSkillsStore.installManagedSkill(
                    agentID: agentID,
                    owner: owner,
                    repo: "\(packageName)-\(skill.id)",
                    sourceURL: source,
                    version: installed.version,
                    replaceExisting: true
                )
            }
            await sessionOrchestrator.notifySkillsChanged(agentID: agentID)
        }
        var config = currentConfig
        for component in installed.manifest.components.mcpServers {
            let id = "\(installed.id)/\(component.id)"
            config.mcp.servers.removeAll { $0.id == id }
            config.mcp.servers.append(
                try await makeAgentPluginMCPServer(
                    component,
                    id: id,
                    packageURL: packageURL,
                    inputs: installed.configuration ?? [:],
                    manifest: installed.manifest
                )
            )
        }
        if config.mcp != currentConfig.mcp { _ = try await updateConfig(config) }
        for component in installed.manifest.components.sloppyPlugins {
            let source = try await agentPluginManager.safeComponentURL(component.path, root: packageURL)
            _ = try await installSourceChannelPlugin(.init(sourceUrl: source.path, force: true, enabled: true, localDirectory: true))
        }
        await store.saveAgentPlugin(installed)
    }

    private func modifiedAgentPluginComponents(_ installed: InstalledAgentPlugin) async throws -> [String] {
        var modified: [String] = []
        for (key, expected) in installed.componentHashes {
            if key.hasPrefix("skill:"), let path = key.split(separator: ":", maxSplits: 2).last {
                let values = key.split(separator: ":", maxSplits: 2).map(String.init)
                if values.count == 3, let skillPath = try? agentSkillsStore.getSkillPath(agentID: values[1], skillID: String(path)) {
                    if try await agentPluginManager.hashTree(URL(fileURLWithPath: skillPath)) != expected { modified.append(key) }
                }
            } else if key.hasPrefix("plugin:") {
                let id = String(key.dropFirst("plugin:".count))
                let url = pluginsRootURL.appendingPathComponent(id, isDirectory: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    modified.append(key)
                } else {
                    let currentHash = try await agentPluginManager.hashTree(url)
                    if currentHash != expected { modified.append(key) }
                }
            } else if key.hasPrefix("mcp:") {
                let id = String(key.dropFirst("mcp:".count))
                guard let server = currentConfig.mcp.servers.first(where: { $0.id == id }), try hashEncodable(server) == expected else { modified.append(key); continue }
            }
        }
        return modified
    }

    private func compatibleAgentPluginSoftware(_ manifest: AgentPluginManifest) -> [AgentPluginSoftwareComponent] {
        manifest.components.software.filter { component in
            if component.platforms.isEmpty { return true }
#if os(macOS)
            return component.platforms.contains { $0.os.lowercased() == "macos" }
#elseif os(Linux)
            return component.platforms.contains { $0.os.lowercased() == "linux" }
#else
            return false
#endif
        }
    }

    private func hashEncodable<T: Encodable>(_ value: T) throws -> String {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: temp)
        return try awaitHashTree(temp)
    }

    private func awaitHashTree(_ url: URL) throws -> String {
        // Stable non-cryptographic drift marker for in-memory configuration values.
        let data = (try? Data(contentsOf: url)) ?? Data()
        return String(data.reduce(into: UInt64(1_469_598_103_934_665_603)) { value, byte in value = (value ^ UInt64(byte)) &* 1_099_511_628_211 }, radix: 16)
    }
}
