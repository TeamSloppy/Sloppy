import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AnyLanguageModel
import PluginSDK
import Protocols

struct SloppyModelProviderFactory: ModelProviderFactory {
    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let entries = config.modelConfigs.filter {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("sloppy:") == true
        }
        let models = config.resolvedModels.filter { $0.hasPrefix("sloppy:") }
        guard !models.isEmpty else { return nil }
        let singleServer = entries.first.flatMap { first in
            entries.allSatisfy { $0.apiUrl == first.apiUrl && $0.apiKey == first.apiKey } ? first : nil
        }
        let catalogLimits = RemoteModelContextLimits()
        let base = AnyModelProviderBox(
            id: "sloppy", supportedModels: models, systemInstructions: config.systemInstructions, tools: config.tools,
            createLanguageModel: { name in
                guard let entry = entries.first(where: { CoreModelProviderFactory.resolvedIdentifier(for: $0) == name }) ?? singleServer else {
                    throw SloppyRemoteError.unknownModel
                }
                // Resolve metadata before RuntimeSystem creates its session/tool budget.
                // Catalog failure must not turn a working inference endpoint into a failure.
                if catalogLimits.value(for: name) == nil {
                    let catalog: [ProviderModelOption]?
                    if ConsoleModelEndpoint.isConsole(entry.apiUrl), let bridge = config.consoleModelBridge,
                       let instanceID = try? ConsoleModelEndpoint.instanceID(entry.apiUrl) {
                        catalog = try? await bridge.catalog(instanceID: instanceID)
                    } else if SloppyRelayEndpoint.isRelay(entry.apiUrl), let bridge = config.meshModelBridge,
                              let nodeID = try? SloppyRelayEndpoint.nodeID(entry.apiUrl) {
                        catalog = try? await bridge.catalog(nodeID: nodeID)
                    } else if let url = try? SloppyRemoteEndpoint.url(base: entry.apiUrl, path: "providers/models") {
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 10
                        let token = entry.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        request.setValue(token.isEmpty ? "" : "Bearer \(token)", forHTTPHeaderField: "Authorization")
                        if let (data, response) = try? await (config.proxySession ?? SloppyURLSessionFactory.shared).data(for: request),
                           (response as? HTTPURLResponse)?.statusCode == 200 {
                            catalog = try? JSONDecoder().decode([ProviderModelOption].self, from: data)
                        } else { catalog = nil }
                    } else { catalog = nil }
                    // Store only the requested model: catalogs from different endpoints can reuse IDs.
                    if let option = catalog?.first(where: { "sloppy:" + $0.id == name }) {
                        catalogLimits.store(option, for: name)
                    }
                }
                if ConsoleModelEndpoint.isConsole(entry.apiUrl) {
                    let instanceID = try ConsoleModelEndpoint.instanceID(entry.apiUrl)
                    guard entry.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          let bridge = config.consoleModelBridge else { throw ConsoleModelBridge.BridgeError.notBound }
                    return SloppyRemoteModel(baseURL: entry.apiUrl, accessToken: "", model: String(name.dropFirst("sloppy:".count)),
                        inferenceTransport: { request, onSnapshot in
                            try await bridge.infer(instanceID: instanceID, request: request, onSnapshot: onSnapshot)
                        })
                }
                if SloppyRelayEndpoint.isRelay(entry.apiUrl) {
                    let nodeID = try SloppyRelayEndpoint.nodeID(entry.apiUrl)
                    guard entry.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          let bridge = config.meshModelBridge else { throw MeshModelBridge.BridgeError.notConnected }
                    return SloppyRemoteModel(baseURL: entry.apiUrl, accessToken: "", model: String(name.dropFirst("sloppy:".count)),
                        inferenceTransport: { request, onSnapshot in
                            try await bridge.infer(nodeID: nodeID, request: request, onSnapshot: onSnapshot)
                        })
                }
                _ = try SloppyRemoteEndpoint.url(base: entry.apiUrl, path: "providers/inference")
                return SloppyRemoteModel(
                    baseURL: entry.apiUrl,
                    accessToken: entry.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: String(name.dropFirst("sloppy:".count)),
                    session: config.proxySession ?? SloppyURLSessionFactory.shared
                )
            },
            generationOptions: { name, maxTokens, effort in
                var options = GenerationOptions(maximumResponseTokens: catalogLimits.value(for: name)?.outputReserve(maxTokens) ?? maxTokens)
                options[custom: SloppyRemoteModel.self] = .init(reasoningEffort: effort)
                return options
            },
            contextLimits: { catalogLimits.value(for: $0) },
            supports: { models.contains($0) || (singleServer != nil && $0.hasPrefix("sloppy:")) }
        )
        return NativeSloppyModelProvider(base: base, prepareStep: { name in
            guard let entry = entries.first(where: { CoreModelProviderFactory.resolvedIdentifier(for: $0) == name }) ?? singleServer else {
                throw SloppyRemoteError.unknownModel
            }
            let catalog: [ProviderModelOption]
            let transport: SloppyModelStepTransport?
            let scope: String
            if ConsoleModelEndpoint.isConsole(entry.apiUrl), let bridge = config.consoleModelBridge {
                guard entry.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SloppyRemoteError.invalidURL }
                let instance = try ConsoleModelEndpoint.instanceID(entry.apiUrl)
                catalog = try await bridge.catalog(instanceID: instance)
                transport = { try await bridge.inferStep(instanceID: instance, request: $0) }
                scope = "console:" + instance.uuidString
            } else if SloppyRelayEndpoint.isRelay(entry.apiUrl), let bridge = config.meshModelBridge {
                guard entry.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SloppyRemoteError.invalidURL }
                let node = try SloppyRelayEndpoint.nodeID(entry.apiUrl)
                catalog = try await bridge.catalog(nodeID: node)
                transport = { try await bridge.inferStep(nodeID: node, request: $0) }
                scope = "mesh:" + node
            } else {
                var request = URLRequest(url: try SloppyRemoteEndpoint.url(base: entry.apiUrl, path: "providers/models"))
                request.timeoutInterval = 10
                let token = entry.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                request.setValue(token.isEmpty ? "" : "Bearer " + token, forHTTPHeaderField: "Authorization")
                let (data, response) = try await (config.proxySession ?? SloppyURLSessionFactory.shared).data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SloppyRemoteError.unknownModel }
                catalog = try JSONDecoder().decode([ProviderModelOption].self, from: data)
                transport = nil; scope = ""
            }
            let nativeModel = String(name.dropFirst("sloppy:".count))
            guard let option = catalog.first(where: { $0.id == nativeModel }), option.capabilities.contains("model_step_v1") else {
                throw ModelStepFailure(category: .unavailable, code: "remote_step_version_unavailable",
                    message: "The remote model does not advertise the single-step protocol.", stage: .preparation)
            }
            catalogLimits.store(option, for: name)
            if let transport { return SloppyModelStepProvider(model: name, scope: scope, transport: transport) }
            return try SloppyModelStepProvider(baseURL: entry.apiUrl,
                accessToken: entry.apiKey.trimmingCharacters(in: .whitespacesAndNewlines), model: name,
                session: config.proxySession ?? SloppyURLSessionFactory.shared)
        })
    }
}

/// Synchronous ModelProvider metadata queried after asynchronous catalog discovery.
/// The lock protects the small immutable-value map; no network work occurs under it.
final class RemoteModelContextLimits: @unchecked Sendable {
    private let lock = NSLock()
    private var limits: [String: ModelContextLimits] = [:]

    func value(for name: String) -> ModelContextLimits? {
        lock.lock()
        defer { lock.unlock() }
        return limits[name]
    }

    func store(_ option: ProviderModelOption, for name: String) {
        guard let window = option.contextWindowTokens, window > 0 else { return }
        let value = ModelContextLimits(contextWindowTokens: window,
            maxInputTokens: option.maxInputTokens.flatMap { $0 > 0 ? $0 : nil },
            maxOutputTokens: option.maxOutputTokens.flatMap { $0 > 0 ? $0 : nil })
        lock.lock()
        defer { lock.unlock() }
        limits[name] = value
    }
}
