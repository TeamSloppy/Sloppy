import Foundation
import Logging
import Protocols
import PluginSDK

/// Meta-information parsed from a plugin's `plugin.json` file.
public struct PluginManifest: Codable, Sendable {
    public static let nodePluginAPIVersionV2 = "2026-05-plugins-v2"

    public enum Runtime: String, Codable, Sendable {
        case swift
        case nodejs

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            switch value {
            case "swift", "swift-dylib":
                self = .swift
            case "nodejs", "node":
                self = .nodejs
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported plugin runtime: \(value). Expected swift or nodejs."
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    /// Unique plugin identifier (e.g. `"telegram"`).
    public var name: String
    /// Protocol the plugin implements: `"gateway"`, `"task_sync"`, `"source_control"`, `"tool"`, `"memory"`, `"model_provider"`.
    public var `protocol`: String
    /// Optional semver string for display and diagnostics.
    public var version: String?
    /// Optional plugin API version. Missing values use the v1 compatibility protocol.
    public var apiVersion: String?
    /// Plugin runtime. Omitted manifests default to Swift dynamic libraries for compatibility.
    public var runtime: Runtime
    /// Runtime-specific entrypoint, for example a Node.js script path relative to the plugin directory.
    public var entrypoint: String?
    /// Declared host-managed capabilities the plugin wants to access.
    public var permissions: PluginManifestPermissions
    /// Runtime-specific configuration passed through to plugin implementations.
    public var config: [String: JSONValue]

    private enum CodingKeys: String, CodingKey {
        case name
        case `protocol`
        case version
        case apiVersion
        case runtime
        case entrypoint
        case permissions
        case config
    }

    public init(
        name: String,
        `protocol` pluginProtocol: String,
        version: String? = nil,
        apiVersion: String? = nil,
        runtime: Runtime = .swift,
        entrypoint: String? = nil,
        permissions: PluginManifestPermissions = .init(),
        config: [String: JSONValue] = [:]
    ) {
        self.name = name
        self.protocol = pluginProtocol
        self.version = version
        self.apiVersion = apiVersion
        self.runtime = runtime
        self.entrypoint = entrypoint
        self.permissions = permissions
        self.config = config
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        self.protocol = try container.decodeIfPresent(String.self, forKey: .protocol) ?? "plugin"
        version = try container.decodeIfPresent(String.self, forKey: .version)
        apiVersion = try container.decodeIfPresent(String.self, forKey: .apiVersion)
        runtime = try container.decodeIfPresent(Runtime.self, forKey: .runtime) ?? .swift
        entrypoint = try container.decodeIfPresent(String.self, forKey: .entrypoint)
        permissions = try container.decodeIfPresent(PluginManifestPermissions.self, forKey: .permissions) ?? .init()
        config = try container.decodeIfPresent([String: JSONValue].self, forKey: .config) ?? [:]
    }

    public var isNodePluginAPIV2: Bool {
        runtime == .nodejs && apiVersion == Self.nodePluginAPIVersionV2
    }

    func matches(protocol expectedProtocol: String) -> Bool {
        if self.protocol == expectedProtocol {
            return true
        }
        return isNodePluginAPIV2 && self.protocol == "plugin" && ["tool", "source_control"].contains(expectedProtocol)
    }
}

public struct PluginManifestPermissions: Codable, Sendable, Equatable {
    public var secrets: [String]
    public var network: [String]
    public var filesystem: [String]
    public var toolDispatch: [String]
    public var modelCalls: Bool
    public var projectContext: Bool
    public var channelSend: [String]
    public var channelInject: [String]

    private enum CodingKeys: String, CodingKey {
        case secrets
        case network
        case filesystem
        case toolDispatch = "tool_dispatch"
        case modelCalls = "model_calls"
        case projectContext = "project_context"
        case channelSend = "channel_send"
        case channelInject = "channel_inject"
    }

    public init(
        secrets: [String] = [],
        network: [String] = [],
        filesystem: [String] = [],
        toolDispatch: [String] = [],
        modelCalls: Bool = false,
        projectContext: Bool = false,
        channelSend: [String] = [],
        channelInject: [String] = []
    ) {
        self.secrets = secrets
        self.network = network
        self.filesystem = filesystem
        self.toolDispatch = toolDispatch
        self.modelCalls = modelCalls
        self.projectContext = projectContext
        self.channelSend = channelSend
        self.channelInject = channelInject
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        secrets = try container.decodeIfPresent([String].self, forKey: .secrets) ?? []
        network = try container.decodeIfPresent([String].self, forKey: .network) ?? []
        filesystem = try container.decodeIfPresent([String].self, forKey: .filesystem) ?? []
        toolDispatch = try container.decodeIfPresent([String].self, forKey: .toolDispatch) ?? []
        modelCalls = try container.decodeIfPresent(Bool.self, forKey: .modelCalls) ?? false
        projectContext = try container.decodeIfPresent(Bool.self, forKey: .projectContext) ?? false
        channelSend = try container.decodeIfPresent([String].self, forKey: .channelSend) ?? []
        channelInject = try container.decodeIfPresent([String].self, forKey: .channelInject) ?? []
    }
}

/// Scans a plugins directory and loads external plugins via dlopen.
/// Bundled plugins (e.g. Telegram) are created directly by CoreService and do NOT go through this loader.
public struct PluginLoader: Sendable {
    private let logger: Logger
    private let processRunner: any PluginProcessRunning

    init(
        logger: Logger = Logger(label: "sloppy.plugin.loader"),
        processRunner: any PluginProcessRunning = LivePluginProcessRunner()
    ) {
        self.logger = logger
        self.processRunner = processRunner
    }

    /// Reads a `plugin.json` manifest from the given plugin directory.
    public func loadManifest(at pluginDirectory: URL) -> PluginManifest? {
        let manifestURL = pluginDirectory.appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }
        return try? JSONDecoder().decode(PluginManifest.self, from: data)
    }

    /// Loads all external gateway plugins found under `pluginsDirectory`.
    /// Each sub-directory must contain a `plugin.json` and either a prebuilt binary or a SwiftPM package.
    /// Returns only successfully loaded plugins; logs failures and continues.
    public func loadGatewayPlugins(
        from pluginsDirectory: URL,
        inboundReceiver: any InboundMessageReceiver
    ) async -> [any GatewayPlugin] {
        let cacheRootURL = pluginsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("plugin-cache", isDirectory: true)
        let loaded = await loadGatewayPluginBundles(
            from: pluginsDirectory,
            cacheRootURL: cacheRootURL,
            inboundReceiver: inboundReceiver
        )
        return loaded.map(\.plugin)
    }

    /// Loads all external task sync providers found under `pluginsDirectory`.
    /// Each sub-directory must contain a `plugin.json` with `"protocol": "task_sync"` and either a
    /// prebuilt binary or a SwiftPM package.
    public func loadTaskSyncPlugins(from pluginsDirectory: URL) async -> [any TaskSyncProvider] {
        let cacheRootURL = pluginsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("plugin-cache", isDirectory: true)
        let loaded = await loadTaskSyncPluginBundles(
            from: pluginsDirectory,
            cacheRootURL: cacheRootURL
        )
        return loaded.map(\.provider)
    }

    /// Loads all external source-control providers found under `pluginsDirectory`.
    /// Each sub-directory must contain a `plugin.json` with `"protocol": "source_control"` and either a
    /// prebuilt binary or a SwiftPM package.
    public func loadSourceControlPlugins(from pluginsDirectory: URL) async -> [any SourceControlProvider] {
        let cacheRootURL = pluginsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("plugin-cache", isDirectory: true)
        let loaded = await loadSourceControlPluginBundles(
            from: pluginsDirectory,
            cacheRootURL: cacheRootURL
        )
        return loaded.map(\.provider)
    }

    public func loadToolPlugins(from pluginsDirectory: URL) async -> [any ToolPlugin] {
        let cacheRootURL = pluginsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("plugin-cache", isDirectory: true)
        let loaded = await loadToolPluginBundles(
            from: pluginsDirectory,
            cacheRootURL: cacheRootURL
        )
        return loaded.map(\.plugin)
    }

    public func loadMemoryPlugins(from pluginsDirectory: URL) async -> [any MemoryPlugin] {
        let cacheRootURL = pluginsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("plugin-cache", isDirectory: true)
        let loaded = await loadMemoryPluginBundles(
            from: pluginsDirectory,
            cacheRootURL: cacheRootURL
        )
        return loaded.map(\.plugin)
    }

    public func loadModelProviders(from pluginsDirectory: URL) async -> [any ModelProvider] {
        let cacheRootURL = pluginsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("plugin-cache", isDirectory: true)
        let loaded = await loadModelProviderBundles(
            from: pluginsDirectory,
            cacheRootURL: cacheRootURL
        )
        return loaded.map(\.provider)
    }

    func loadGatewayPluginBundles(
        from pluginsDirectory: URL,
        cacheRootURL: URL,
        inboundReceiver: any InboundMessageReceiver,
        disabledPluginIDs: Set<String> = []
    ) async -> [LoadedGatewayPlugin] {
        await loadPluginBundles(
            from: pluginsDirectory,
            protocol: "gateway",
            disabledPluginIDs: disabledPluginIDs
        ) { entry, manifest in
            await loadGatewayPlugin(
                from: entry,
                cacheRootURL: cacheRootURL,
                manifest: manifest,
                inboundReceiver: inboundReceiver
            )
        }
    }

    func loadTaskSyncPluginBundles(
        from pluginsDirectory: URL,
        cacheRootURL: URL,
        disabledPluginIDs: Set<String> = []
    ) async -> [LoadedTaskSyncPlugin] {
        await loadPluginBundles(
            from: pluginsDirectory,
            protocol: "task_sync",
            disabledPluginIDs: disabledPluginIDs
        ) { entry, manifest in
            await loadTaskSyncPlugin(
                from: entry,
                cacheRootURL: cacheRootURL,
                manifest: manifest
            )
        }
    }

    func loadSourceControlPluginBundles(
        from pluginsDirectory: URL,
        cacheRootURL: URL,
        disabledPluginIDs: Set<String> = []
    ) async -> [LoadedSourceControlPlugin] {
        await loadPluginBundles(
            from: pluginsDirectory,
            protocol: "source_control",
            disabledPluginIDs: disabledPluginIDs
        ) { entry, manifest in
            await loadSourceControlPlugin(
                from: entry,
                cacheRootURL: cacheRootURL,
                manifest: manifest
            )
        }
    }

    func loadToolPluginBundles(
        from pluginsDirectory: URL,
        cacheRootURL: URL,
        disabledPluginIDs: Set<String> = []
    ) async -> [LoadedToolPlugin] {
        await loadPluginBundles(
            from: pluginsDirectory,
            protocol: "tool",
            disabledPluginIDs: disabledPluginIDs
        ) { entry, manifest in
            await loadToolPlugin(from: entry, cacheRootURL: cacheRootURL, manifest: manifest)
        }
    }

    func loadMemoryPluginBundles(
        from pluginsDirectory: URL,
        cacheRootURL: URL,
        disabledPluginIDs: Set<String> = []
    ) async -> [LoadedMemoryPlugin] {
        await loadPluginBundles(
            from: pluginsDirectory,
            protocol: "memory",
            disabledPluginIDs: disabledPluginIDs
        ) { entry, manifest in
            await loadMemoryPlugin(from: entry, cacheRootURL: cacheRootURL, manifest: manifest)
        }
    }

    func loadModelProviderBundles(
        from pluginsDirectory: URL,
        cacheRootURL: URL,
        disabledPluginIDs: Set<String> = []
    ) async -> [LoadedModelProviderPlugin] {
        await loadPluginBundles(
            from: pluginsDirectory,
            protocol: "model_provider",
            disabledPluginIDs: disabledPluginIDs
        ) { entry, manifest in
            await loadModelProvider(from: entry, cacheRootURL: cacheRootURL, manifest: manifest)
        }
    }

    private func loadPluginBundles<Bundle>(
        from pluginsDirectory: URL,
        protocol expectedProtocol: String,
        disabledPluginIDs: Set<String>,
        load: (URL, PluginManifest) async -> Bundle?
    ) async -> [Bundle] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: pluginsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var plugins: [Bundle] = []

        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }

            guard let manifest = loadManifest(at: entry) else {
                logger.warning("No valid plugin.json in \(entry.lastPathComponent), skipping.")
                continue
            }

            guard manifest.matches(protocol: expectedProtocol) else {
                logger.debug("Plugin \(manifest.name) is not a \(expectedProtocol) plugin, skipping for now.")
                continue
            }

            if disabledPluginIDs.contains(manifest.name) {
                logger.info("Plugin \(manifest.name) is disabled, skipping.")
                continue
            }

            if let plugin = await load(entry, manifest) {
                plugins.append(plugin)
            }
        }

        return plugins
    }

    func loadGatewayPlugin(
        from directory: URL,
        cacheRootURL: URL,
        manifest: PluginManifest,
        inboundReceiver: any InboundMessageReceiver
    ) async -> LoadedGatewayPlugin? {
        switch manifest.runtime {
        case .nodejs:
            guard await nodeRuntimeIsAvailable() else {
                logger.error("Node.js runtime is not available; gateway plugin \(manifest.name) was not registered.")
                return nil
            }
            do {
                let descriptor = try await describeNodePluginIfNeeded(manifest: manifest, pluginDirectory: directory)
                let plugin: any GatewayPlugin
                if manifest.isNodePluginAPIV2 {
                    let capabilities = NodePersistentGatewayPlugin.capabilities(descriptor: descriptor)
                    let interactiveCapabilities: Set<String> = ["streaming", "tool_approval", "plan_input"]
                    if !capabilities.isDisjoint(with: interactiveCapabilities) {
                        plugin = try NodeInteractiveGatewayPlugin(
                            manifest: manifest,
                            pluginDirectory: directory,
                            descriptor: descriptor,
                            inboundReceiver: inboundReceiver,
                            logger: logger
                        )
                    } else {
                        plugin = try NodePersistentGatewayPlugin(
                            manifest: manifest,
                            pluginDirectory: directory,
                            descriptor: descriptor,
                            inboundReceiver: inboundReceiver,
                            logger: logger
                        )
                    }
                } else {
                    plugin = try NodeGatewayPlugin(manifest: manifest, pluginDirectory: directory, logger: logger)
                }
                return LoadedGatewayPlugin(
                    manifest: manifest,
                    plugin: plugin,
                    sourceURL: directory,
                    binaryURL: nil,
                    rebuilt: false
                )
            } catch {
                logger.error("Failed to initialize Node gateway plugin \(manifest.name): \(error)")
                return nil
            }
        case .swift:
            guard let binary = await loadSwiftPluginBinary(
                from: directory,
                cacheRootURL: cacheRootURL,
                manifest: manifest,
                build: { builder in
                    try await builder.buildGatewayPlugin(at: directory, manifest: manifest)
                }
            ) else {
                return nil
            }
            guard let plugin = loadDylibGatewayPlugin(
                binaryURL: binary.binaryURL,
                manifest: manifest,
                inboundReceiver: inboundReceiver
            ) else {
                return nil
            }
            return LoadedGatewayPlugin(
                manifest: manifest,
                plugin: plugin,
                sourceURL: directory,
                binaryURL: binary.binaryURL,
                rebuilt: binary.rebuilt
            )
        }
    }

    func loadTaskSyncPlugin(
        from directory: URL,
        cacheRootURL: URL,
        manifest: PluginManifest
    ) async -> LoadedTaskSyncPlugin? {
        switch manifest.runtime {
        case .nodejs:
            guard await nodeRuntimeIsAvailable() else {
                logger.error("Node.js runtime is not available; task-sync plugin \(manifest.name) was not registered.")
                return nil
            }
            do {
                let provider = try NodeTaskSyncProvider(manifest: manifest, pluginDirectory: directory, logger: logger)
                return LoadedTaskSyncPlugin(
                    manifest: manifest,
                    provider: provider,
                    sourceURL: directory,
                    binaryURL: nil,
                    rebuilt: false
                )
            } catch {
                logger.error("Failed to initialize Node task-sync plugin \(manifest.name): \(error)")
                return nil
            }
        case .swift:
            guard let binary = await loadSwiftPluginBinary(
                from: directory,
                cacheRootURL: cacheRootURL,
                manifest: manifest,
                build: { builder in
                    try await builder.buildTaskSyncPlugin(at: directory, manifest: manifest)
                }
            ) else {
                return nil
            }
            guard let provider = loadDylibTaskSyncProvider(
                binaryURL: binary.binaryURL,
                manifest: manifest
            ) else {
                return nil
            }
            return LoadedTaskSyncPlugin(
                manifest: manifest,
                provider: provider,
                sourceURL: directory,
                binaryURL: binary.binaryURL,
                rebuilt: binary.rebuilt
            )
        }
    }

    func loadSourceControlPlugin(
        from directory: URL,
        cacheRootURL: URL,
        manifest: PluginManifest
    ) async -> LoadedSourceControlPlugin? {
        switch manifest.runtime {
        case .nodejs:
            guard await nodeRuntimeIsAvailable() else {
                logger.error("Node.js runtime is not available; source-control plugin \(manifest.name) was not registered.")
                return nil
            }
            do {
                let descriptor = try await describeNodePluginIfNeeded(manifest: manifest, pluginDirectory: directory)
                guard !manifest.isNodePluginAPIV2 || manifest.protocol == "source_control" || descriptor?.sourceControls.isEmpty == false else {
                    return nil
                }
                let provider = try NodeSourceControlProvider(
                    manifest: manifest,
                    pluginDirectory: directory,
                    descriptor: descriptor,
                    logger: logger
                )
                return LoadedSourceControlPlugin(
                    manifest: manifest,
                    provider: provider,
                    sourceURL: directory,
                    binaryURL: nil,
                    rebuilt: false
                )
            } catch {
                logger.error("Failed to initialize Node source-control plugin \(manifest.name): \(error)")
                return nil
            }
        case .swift:
            guard let binary = await loadSwiftPluginBinary(
                from: directory,
                cacheRootURL: cacheRootURL,
                manifest: manifest,
                build: { builder in
                    try await builder.buildSourceControlPlugin(at: directory, manifest: manifest)
                }
            ) else {
                return nil
            }
            guard let provider = loadDylibSourceControlProvider(
                binaryURL: binary.binaryURL,
                manifest: manifest
            ) else {
                return nil
            }
            return LoadedSourceControlPlugin(
                manifest: manifest,
                provider: provider,
                sourceURL: directory,
                binaryURL: binary.binaryURL,
                rebuilt: binary.rebuilt
            )
        }
    }

    func loadToolPlugin(
        from directory: URL,
        cacheRootURL: URL,
        manifest: PluginManifest
    ) async -> LoadedToolPlugin? {
        switch manifest.runtime {
        case .nodejs:
            guard await nodeRuntimeIsAvailable() else {
                logger.error("Node.js runtime is not available; tool plugin \(manifest.name) was not registered.")
                return nil
            }
            do {
                let descriptor = try await describeNodePluginIfNeeded(manifest: manifest, pluginDirectory: directory)
                guard !manifest.isNodePluginAPIV2 || manifest.protocol == "tool" || descriptor?.tools.isEmpty == false else {
                    return nil
                }
                let plugin = try NodeToolPlugin(
                    manifest: manifest,
                    pluginDirectory: directory,
                    descriptor: descriptor,
                    logger: logger
                )
                return LoadedToolPlugin(manifest: manifest, plugin: plugin, sourceURL: directory, binaryURL: nil, rebuilt: false)
            } catch {
                logger.error("Failed to initialize Node tool plugin \(manifest.name): \(error)")
                return nil
            }
        case .swift:
            guard let binary = await loadSwiftPluginBinary(
                from: directory,
                cacheRootURL: cacheRootURL,
                manifest: manifest,
                build: { builder in
                    try await builder.buildPlugin(at: directory, manifest: manifest)
                }
            ) else {
                return nil
            }
            guard let plugin = loadDylibToolPlugin(binaryURL: binary.binaryURL, manifest: manifest) else {
                return nil
            }
            return LoadedToolPlugin(manifest: manifest, plugin: plugin, sourceURL: directory, binaryURL: binary.binaryURL, rebuilt: binary.rebuilt)
        }
    }

    func loadMemoryPlugin(
        from directory: URL,
        cacheRootURL: URL,
        manifest: PluginManifest
    ) async -> LoadedMemoryPlugin? {
        switch manifest.runtime {
        case .nodejs:
            guard await nodeRuntimeIsAvailable() else {
                logger.error("Node.js runtime is not available; memory plugin \(manifest.name) was not registered.")
                return nil
            }
            do {
                let plugin = try NodeMemoryPlugin(manifest: manifest, pluginDirectory: directory, logger: logger)
                return LoadedMemoryPlugin(manifest: manifest, plugin: plugin, sourceURL: directory, binaryURL: nil, rebuilt: false)
            } catch {
                logger.error("Failed to initialize Node memory plugin \(manifest.name): \(error)")
                return nil
            }
        case .swift:
            guard let binary = await loadSwiftPluginBinary(
                from: directory,
                cacheRootURL: cacheRootURL,
                manifest: manifest,
                build: { builder in
                    try await builder.buildPlugin(at: directory, manifest: manifest)
                }
            ) else {
                return nil
            }
            guard let plugin = loadDylibMemoryPlugin(binaryURL: binary.binaryURL, manifest: manifest) else {
                return nil
            }
            return LoadedMemoryPlugin(manifest: manifest, plugin: plugin, sourceURL: directory, binaryURL: binary.binaryURL, rebuilt: binary.rebuilt)
        }
    }

    func loadModelProvider(
        from directory: URL,
        cacheRootURL: URL,
        manifest: PluginManifest
    ) async -> LoadedModelProviderPlugin? {
        switch manifest.runtime {
        case .nodejs:
            guard await nodeRuntimeIsAvailable() else {
                logger.error("Node.js runtime is not available; model-provider plugin \(manifest.name) was not registered.")
                return nil
            }
            do {
                let provider = try NodeModelProvider(manifest: manifest, pluginDirectory: directory, logger: logger)
                return LoadedModelProviderPlugin(manifest: manifest, provider: provider, sourceURL: directory, binaryURL: nil, rebuilt: false)
            } catch {
                logger.error("Failed to initialize Node model-provider plugin \(manifest.name): \(error)")
                return nil
            }
        case .swift:
            guard let binary = await loadSwiftPluginBinary(
                from: directory,
                cacheRootURL: cacheRootURL,
                manifest: manifest,
                build: { builder in
                    try await builder.buildPlugin(at: directory, manifest: manifest)
                }
            ) else {
                return nil
            }
            guard let provider = loadDylibModelProvider(binaryURL: binary.binaryURL, manifest: manifest) else {
                return nil
            }
            return LoadedModelProviderPlugin(manifest: manifest, provider: provider, sourceURL: directory, binaryURL: binary.binaryURL, rebuilt: binary.rebuilt)
        }
    }

    private func loadSwiftPluginBinary(
        from directory: URL,
        cacheRootURL: URL,
        manifest: PluginManifest,
        build: (PluginPackageBuilder) async throws -> PluginPackageBuildResult
    ) async -> PluginBinaryLoad? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
            do {
                let builder = PluginPackageBuilder(
                    cacheRootURL: cacheRootURL,
                    processRunner: processRunner,
                    fileManager: fileManager,
                    logger: Logger(label: "sloppy.plugin.builder")
                )
                let build = try await build(builder)
                return PluginBinaryLoad(binaryURL: build.binaryURL, rebuilt: build.rebuilt)
            } catch {
                logger.error("Failed to build Swift plugin \(manifest.name): \(error)")
                return nil
            }
        }
        guard let found = findBinary(in: directory, name: manifest.name) else {
            logger.warning("No dynamic library binary found for plugin \(manifest.name) in \(directory.lastPathComponent).")
            return nil
        }
        return PluginBinaryLoad(binaryURL: found, rebuilt: false)
    }

    private func describeNodePluginIfNeeded(
        manifest: PluginManifest,
        pluginDirectory: URL
    ) async throws -> NodePluginDescriptor? {
        guard manifest.isNodePluginAPIV2 else {
            return nil
        }
        logDeclaredPermissions(manifest)
        let runtime = try NodePluginRuntime(manifest: manifest, pluginDirectory: pluginDirectory, logger: logger)
        return try await runtime.describe()
    }

    private func logDeclaredPermissions(_ manifest: PluginManifest) {
        let permissions = manifest.permissions
        let requested = [
            permissions.secrets.isEmpty ? nil : "secrets=\(permissions.secrets.joined(separator: ","))",
            permissions.network.isEmpty ? nil : "network=\(permissions.network.joined(separator: ","))",
            permissions.filesystem.isEmpty ? nil : "filesystem=\(permissions.filesystem.joined(separator: ","))",
            permissions.toolDispatch.isEmpty ? nil : "tool_dispatch=\(permissions.toolDispatch.joined(separator: ","))",
            permissions.modelCalls ? "model_calls=true" : nil,
            permissions.projectContext ? "project_context=true" : nil,
            permissions.channelSend.isEmpty ? nil : "channel_send=\(permissions.channelSend.joined(separator: ","))",
            permissions.channelInject.isEmpty ? nil : "channel_inject=\(permissions.channelInject.joined(separator: ","))",
        ].compactMap { $0 }
        guard !requested.isEmpty else { return }
        logger.info("Node plugin \(manifest.name) declares v2 permissions: \(requested.joined(separator: " "))")
    }

    private func nodeRuntimeIsAvailable() async -> Bool {
        guard let result = try? await processRunner.run("node", arguments: ["--version"], cwd: nil) else {
            return false
        }
        return result.exitCode == 0
    }

    // MARK: - dlopen

    func loadDylibGatewayPlugin(
        binaryURL: URL,
        manifest: PluginManifest,
        inboundReceiver: any InboundMessageReceiver
    ) -> (any GatewayPlugin)? {
        guard let handle = dlopen(binaryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let error = String(cString: dlerror())
            logger.error("dlopen failed for plugin \(manifest.name): \(error)")
            return nil
        }

        guard let sym = dlsym(handle, "sloppy_gateway_create") else {
            let error = String(cString: dlerror())
            logger.error("dlsym(sloppy_gateway_create) failed for plugin \(manifest.name): \(error)")
            dlclose(handle)
            return nil
        }

        // C ABI: void* sloppy_gateway_create(const char* manifest_json, void* inbound_receiver_opaque)
        // The opaque pointer is an Unmanaged reference to the InboundMessageReceiver existential box.
        typealias CreateFn = @convention(c) (
            UnsafePointer<CChar>,
            UnsafeMutableRawPointer
        ) -> UnsafeMutableRawPointer?

        let createFn = unsafeBitCast(sym, to: CreateFn.self)

        let manifestJSON = (try? String(data: JSONEncoder().encode(manifest), encoding: .utf8)) ?? "{}"
        let receiverBox = GatewayPluginReceiverBox(receiver: inboundReceiver)
        let boxPtr = Unmanaged.passRetained(receiverBox).toOpaque()

        guard let rawPlugin = manifestJSON.withCString({ createFn($0, boxPtr) }) else {
            logger.error("sloppy_gateway_create returned nil for plugin \(manifest.name).")
            Unmanaged<GatewayPluginReceiverBox>.fromOpaque(boxPtr).release()
            dlclose(handle)
            return nil
        }

        let plugin = Unmanaged<AnyGatewayPluginBox>.fromOpaque(rawPlugin).takeRetainedValue()
        guard plugin.id == manifest.name else {
            logger.error("Plugin id mismatch for \(manifest.name): dylib returned \(plugin.id).")
            Unmanaged<GatewayPluginReceiverBox>.fromOpaque(boxPtr).release()
            dlclose(handle)
            return nil
        }
        logger.info("Loaded external gateway plugin \(manifest.name) v\(manifest.version ?? "unknown").")
        return plugin
    }

    func loadDylibTaskSyncProvider(
        binaryURL: URL,
        manifest: PluginManifest
    ) -> (any TaskSyncProvider)? {
        guard let handle = dlopen(binaryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let error = String(cString: dlerror())
            logger.error("dlopen failed for task sync plugin \(manifest.name): \(error)")
            return nil
        }

        guard let sym = dlsym(handle, "sloppy_task_sync_create") else {
            let error = String(cString: dlerror())
            logger.error("dlsym(sloppy_task_sync_create) failed for plugin \(manifest.name): \(error)")
            dlclose(handle)
            return nil
        }

        // C ABI: void* sloppy_task_sync_create(const char* manifest_json)
        typealias CreateFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
        let createFn = unsafeBitCast(sym, to: CreateFn.self)
        let manifestJSON = (try? String(data: JSONEncoder().encode(manifest), encoding: .utf8)) ?? "{}"

        guard let rawProvider = manifestJSON.withCString({ createFn($0) }) else {
            logger.error("sloppy_task_sync_create returned nil for plugin \(manifest.name).")
            dlclose(handle)
            return nil
        }

        let provider = Unmanaged<AnyTaskSyncProviderBox>.fromOpaque(rawProvider).takeRetainedValue()
        guard provider.id == manifest.name else {
            logger.error("Task sync provider id mismatch for \(manifest.name): dylib returned \(provider.id).")
            dlclose(handle)
            return nil
        }
        logger.info("Loaded external task sync plugin \(manifest.name) v\(manifest.version ?? "unknown").")
        return provider
    }

    func loadDylibSourceControlProvider(
        binaryURL: URL,
        manifest: PluginManifest
    ) -> (any SourceControlProvider)? {
        guard let handle = dlopen(binaryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let error = String(cString: dlerror())
            logger.error("dlopen failed for source-control plugin \(manifest.name): \(error)")
            return nil
        }

        guard let sym = dlsym(handle, "sloppy_source_control_create") else {
            let error = String(cString: dlerror())
            logger.error("dlsym(sloppy_source_control_create) failed for plugin \(manifest.name): \(error)")
            dlclose(handle)
            return nil
        }

        // C ABI: void* sloppy_source_control_create(const char* manifest_json)
        typealias CreateFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
        let createFn = unsafeBitCast(sym, to: CreateFn.self)
        let manifestJSON = (try? String(data: JSONEncoder().encode(manifest), encoding: .utf8)) ?? "{}"

        guard let rawProvider = manifestJSON.withCString({ createFn($0) }) else {
            logger.error("sloppy_source_control_create returned nil for plugin \(manifest.name).")
            dlclose(handle)
            return nil
        }

        let provider = Unmanaged<AnySourceControlProviderBox>.fromOpaque(rawProvider).takeRetainedValue()
        guard provider.id == manifest.name else {
            logger.error("Source-control provider id mismatch for \(manifest.name): dylib returned \(provider.id).")
            dlclose(handle)
            return nil
        }
        logger.info("Loaded external source-control plugin \(manifest.name) v\(manifest.version ?? "unknown").")
        return provider
    }

    func loadDylibToolPlugin(
        binaryURL: URL,
        manifest: PluginManifest
    ) -> (any ToolPlugin)? {
        guard let handle = dlopen(binaryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let error = String(cString: dlerror())
            logger.error("dlopen failed for tool plugin \(manifest.name): \(error)")
            return nil
        }

        guard let sym = dlsym(handle, "sloppy_tool_create") else {
            let error = String(cString: dlerror())
            logger.error("dlsym(sloppy_tool_create) failed for plugin \(manifest.name): \(error)")
            dlclose(handle)
            return nil
        }

        typealias CreateFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
        let createFn = unsafeBitCast(sym, to: CreateFn.self)
        let manifestJSON = (try? String(data: JSONEncoder().encode(manifest), encoding: .utf8)) ?? "{}"

        guard let rawPlugin = manifestJSON.withCString({ createFn($0) }) else {
            logger.error("sloppy_tool_create returned nil for plugin \(manifest.name).")
            dlclose(handle)
            return nil
        }

        let plugin = Unmanaged<AnyToolPluginBox>.fromOpaque(rawPlugin).takeRetainedValue()
        guard plugin.id == manifest.name else {
            logger.error("Tool plugin id mismatch for \(manifest.name): dylib returned \(plugin.id).")
            dlclose(handle)
            return nil
        }
        logger.info("Loaded external tool plugin \(manifest.name) v\(manifest.version ?? "unknown").")
        return plugin
    }

    func loadDylibMemoryPlugin(
        binaryURL: URL,
        manifest: PluginManifest
    ) -> (any MemoryPlugin)? {
        guard let handle = dlopen(binaryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let error = String(cString: dlerror())
            logger.error("dlopen failed for memory plugin \(manifest.name): \(error)")
            return nil
        }

        guard let sym = dlsym(handle, "sloppy_memory_create") else {
            let error = String(cString: dlerror())
            logger.error("dlsym(sloppy_memory_create) failed for plugin \(manifest.name): \(error)")
            dlclose(handle)
            return nil
        }

        typealias CreateFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
        let createFn = unsafeBitCast(sym, to: CreateFn.self)
        let manifestJSON = (try? String(data: JSONEncoder().encode(manifest), encoding: .utf8)) ?? "{}"

        guard let rawPlugin = manifestJSON.withCString({ createFn($0) }) else {
            logger.error("sloppy_memory_create returned nil for plugin \(manifest.name).")
            dlclose(handle)
            return nil
        }

        let plugin = Unmanaged<AnyMemoryPluginBox>.fromOpaque(rawPlugin).takeRetainedValue()
        guard plugin.id == manifest.name else {
            logger.error("Memory plugin id mismatch for \(manifest.name): dylib returned \(plugin.id).")
            dlclose(handle)
            return nil
        }
        logger.info("Loaded external memory plugin \(manifest.name) v\(manifest.version ?? "unknown").")
        return plugin
    }

    func loadDylibModelProvider(
        binaryURL: URL,
        manifest: PluginManifest
    ) -> (any ModelProvider)? {
        guard let handle = dlopen(binaryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let error = String(cString: dlerror())
            logger.error("dlopen failed for model-provider plugin \(manifest.name): \(error)")
            return nil
        }

        guard let sym = dlsym(handle, "sloppy_model_provider_create") else {
            let error = String(cString: dlerror())
            logger.error("dlsym(sloppy_model_provider_create) failed for plugin \(manifest.name): \(error)")
            dlclose(handle)
            return nil
        }

        typealias CreateFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
        let createFn = unsafeBitCast(sym, to: CreateFn.self)
        let manifestJSON = (try? String(data: JSONEncoder().encode(manifest), encoding: .utf8)) ?? "{}"

        guard let rawProvider = manifestJSON.withCString({ createFn($0) }) else {
            logger.error("sloppy_model_provider_create returned nil for plugin \(manifest.name).")
            dlclose(handle)
            return nil
        }

        let provider = Unmanaged<AnyModelProviderBox>.fromOpaque(rawProvider).takeRetainedValue()
        guard provider.id == manifest.name else {
            logger.error("Model provider id mismatch for \(manifest.name): dylib returned \(provider.id).")
            dlclose(handle)
            return nil
        }
        logger.info("Loaded external model-provider plugin \(manifest.name) v\(manifest.version ?? "unknown").")
        return provider
    }

    private func findBinary(in directory: URL, name: String) -> URL? {
        let candidates = [
            directory.appendingPathComponent("plugin.dylib"),
            directory.appendingPathComponent("\(name).dylib"),
            directory.appendingPathComponent("lib\(name).dylib"),
            directory.appendingPathComponent("plugin.so"),
            directory.appendingPathComponent("\(name).so"),
            directory.appendingPathComponent("lib\(name).so"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private struct PluginBinaryLoad: Sendable {
    var binaryURL: URL
    var rebuilt: Bool
}

struct LoadedGatewayPlugin: Sendable {
    var manifest: PluginManifest
    var plugin: any GatewayPlugin
    var sourceURL: URL
    var binaryURL: URL?
    var rebuilt: Bool
}

struct LoadedTaskSyncPlugin: Sendable {
    var manifest: PluginManifest
    var provider: any TaskSyncProvider
    var sourceURL: URL
    var binaryURL: URL?
    var rebuilt: Bool
}

struct LoadedSourceControlPlugin: Sendable {
    var manifest: PluginManifest
    var provider: any SourceControlProvider
    var sourceURL: URL
    var binaryURL: URL?
    var rebuilt: Bool
}

struct LoadedToolPlugin: Sendable {
    var manifest: PluginManifest
    var plugin: any ToolPlugin
    var sourceURL: URL
    var binaryURL: URL?
    var rebuilt: Bool
}

struct LoadedMemoryPlugin: Sendable {
    var manifest: PluginManifest
    var plugin: any MemoryPlugin
    var sourceURL: URL
    var binaryURL: URL?
    var rebuilt: Bool
}

struct LoadedModelProviderPlugin: Sendable {
    var manifest: PluginManifest
    var provider: any ModelProvider
    var sourceURL: URL
    var binaryURL: URL?
    var rebuilt: Bool
}
