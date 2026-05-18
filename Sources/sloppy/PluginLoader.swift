import Foundation
import Logging
import Protocols
import PluginSDK

/// Meta-information parsed from a plugin's `plugin.json` file.
public struct PluginManifest: Codable, Sendable {
    public enum Runtime: String, Codable, Sendable {
        case swiftDylib = "swift-dylib"
        case node
    }

    /// Unique plugin identifier (e.g. `"telegram"`).
    public var name: String
    /// Protocol the plugin implements: `"gateway"`, `"task_sync"`, `"source_control"`, `"tool"`, `"memory"`, `"model_provider"`.
    public var `protocol`: String
    /// Optional semver string for display and diagnostics.
    public var version: String?
    /// Plugin runtime. Omitted manifests default to Swift dynamic libraries for compatibility.
    public var runtime: Runtime
    /// Runtime-specific entrypoint, for example a Node.js script path relative to the plugin directory.
    public var entrypoint: String?
    /// Runtime-specific configuration passed through to plugin implementations.
    public var config: [String: JSONValue]

    private enum CodingKeys: String, CodingKey {
        case name
        case `protocol`
        case version
        case runtime
        case entrypoint
        case config
    }

    public init(
        name: String,
        `protocol` pluginProtocol: String,
        version: String? = nil,
        runtime: Runtime = .swiftDylib,
        entrypoint: String? = nil,
        config: [String: JSONValue] = [:]
    ) {
        self.name = name
        self.protocol = pluginProtocol
        self.version = version
        self.runtime = runtime
        self.entrypoint = entrypoint
        self.config = config
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        self.protocol = try container.decode(String.self, forKey: .protocol)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        runtime = try container.decodeIfPresent(Runtime.self, forKey: .runtime) ?? .swiftDylib
        entrypoint = try container.decodeIfPresent(String.self, forKey: .entrypoint)
        config = try container.decodeIfPresent([String: JSONValue].self, forKey: .config) ?? [:]
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

            guard manifest.protocol == expectedProtocol else {
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
        let fileManager = FileManager.default
        let binary: PluginBinaryLoad

        if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
            do {
                let builder = PluginPackageBuilder(
                    cacheRootURL: cacheRootURL,
                    processRunner: processRunner,
                    fileManager: fileManager,
                    logger: Logger(label: "sloppy.plugin.builder")
                )
                let build = try await builder.buildGatewayPlugin(at: directory, manifest: manifest)
                binary = PluginBinaryLoad(binaryURL: build.binaryURL, rebuilt: build.rebuilt)
            } catch {
                logger.error("Failed to build source plugin \(manifest.name): \(error)")
                return nil
            }
        } else {
            guard let found = findBinary(in: directory, name: manifest.name) else {
                logger.warning("No dynamic library binary found for plugin \(manifest.name) in \(directory.lastPathComponent).")
                return nil
            }
            binary = PluginBinaryLoad(binaryURL: found, rebuilt: false)
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

    func loadTaskSyncPlugin(
        from directory: URL,
        cacheRootURL: URL,
        manifest: PluginManifest
    ) async -> LoadedTaskSyncPlugin? {
        let fileManager = FileManager.default
        let binary: PluginBinaryLoad

        if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
            do {
                let builder = PluginPackageBuilder(
                    cacheRootURL: cacheRootURL,
                    processRunner: processRunner,
                    fileManager: fileManager,
                    logger: Logger(label: "sloppy.plugin.builder")
                )
                let build = try await builder.buildTaskSyncPlugin(at: directory, manifest: manifest)
                binary = PluginBinaryLoad(binaryURL: build.binaryURL, rebuilt: build.rebuilt)
            } catch {
                logger.error("Failed to build source plugin \(manifest.name): \(error)")
                return nil
            }
        } else {
            guard let found = findBinary(in: directory, name: manifest.name) else {
                logger.warning("No dynamic library binary found for plugin \(manifest.name) in \(directory.lastPathComponent).")
                return nil
            }
            binary = PluginBinaryLoad(binaryURL: found, rebuilt: false)
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

    func loadSourceControlPlugin(
        from directory: URL,
        cacheRootURL: URL,
        manifest: PluginManifest
    ) async -> LoadedSourceControlPlugin? {
        if manifest.runtime == .node {
            guard await nodeRuntimeIsAvailable() else {
                logger.error("Node.js runtime is not available; source-control plugin \(manifest.name) was not registered.")
                return nil
            }
            do {
                let provider = try NodeSourceControlProvider(manifest: manifest, pluginDirectory: directory, logger: logger)
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
        }

        let fileManager = FileManager.default
        let binary: PluginBinaryLoad

        if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
            do {
                let builder = PluginPackageBuilder(
                    cacheRootURL: cacheRootURL,
                    processRunner: processRunner,
                    fileManager: fileManager,
                    logger: Logger(label: "sloppy.plugin.builder")
                )
                let build = try await builder.buildSourceControlPlugin(at: directory, manifest: manifest)
                binary = PluginBinaryLoad(binaryURL: build.binaryURL, rebuilt: build.rebuilt)
            } catch {
                logger.error("Failed to build source-control plugin \(manifest.name): \(error)")
                return nil
            }
        } else {
            guard let found = findBinary(in: directory, name: manifest.name) else {
                logger.warning("No dynamic library binary found for plugin \(manifest.name) in \(directory.lastPathComponent).")
                return nil
            }
            binary = PluginBinaryLoad(binaryURL: found, rebuilt: false)
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
    var binaryURL: URL
    var rebuilt: Bool
}

struct LoadedTaskSyncPlugin: Sendable {
    var manifest: PluginManifest
    var provider: any TaskSyncProvider
    var sourceURL: URL
    var binaryURL: URL
    var rebuilt: Bool
}

struct LoadedSourceControlPlugin: Sendable {
    var manifest: PluginManifest
    var provider: any SourceControlProvider
    var sourceURL: URL
    var binaryURL: URL?
    var rebuilt: Bool
}
