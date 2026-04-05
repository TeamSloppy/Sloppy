import Foundation
import Protocols

// MARK: - Channel Plugins

extension CoreService {
    // MARK: - Channel Plugins

    public func listChannelPlugins() async -> [ChannelPluginRecord] {
        await store.listChannelPlugins()
    }

    public func getChannelPlugin(id: String) async throws -> ChannelPluginRecord {
        guard let normalized = normalizedPluginID(id) else {
            throw ChannelPluginError.invalidID
        }
        guard let plugin = await store.channelPlugin(id: normalized) else {
            throw ChannelPluginError.notFound
        }
        return plugin
    }

    public func createChannelPlugin(_ request: ChannelPluginCreateRequest) async throws -> ChannelPluginRecord {
        let id: String
        if let requestID = request.id {
            guard let normalized = normalizedPluginID(requestID) else {
                throw ChannelPluginError.invalidID
            }
            if await store.channelPlugin(id: normalized) != nil {
                throw ChannelPluginError.conflict
            }
            id = normalized
        } else {
            id = UUID().uuidString.lowercased()
        }

        let type = request.type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty else {
            throw ChannelPluginError.invalidPayload
        }

        let baseUrl = request.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseUrl.isEmpty else {
            throw ChannelPluginError.invalidPayload
        }

        let now = Date()
        let plugin = ChannelPluginRecord(
            id: id,
            type: type,
            baseUrl: baseUrl,
            channelIds: request.channelIds ?? [],
            config: request.config ?? [:],
            enabled: request.enabled ?? true,
            createdAt: now,
            updatedAt: now
        )
        await store.saveChannelPlugin(plugin)
        return plugin
    }

    public func updateChannelPlugin(id: String, request: ChannelPluginUpdateRequest) async throws -> ChannelPluginRecord {
        guard let normalized = normalizedPluginID(id) else {
            throw ChannelPluginError.invalidID
        }
        guard var plugin = await store.channelPlugin(id: normalized) else {
            throw ChannelPluginError.notFound
        }
        if let type = request.type {
            let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ChannelPluginError.invalidPayload }
            plugin.type = trimmed
        }
        if let baseUrl = request.baseUrl {
            let trimmed = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ChannelPluginError.invalidPayload }
            plugin.baseUrl = trimmed
        }
        if let channelIds = request.channelIds {
            plugin.channelIds = channelIds
        }
        if let config = request.config {
            plugin.config = config
        }
        if let enabled = request.enabled {
            plugin.enabled = enabled
        }
        plugin.updatedAt = Date()
        await store.saveChannelPlugin(plugin)
        return plugin
    }

    public func deleteChannelPlugin(id: String) async throws {
        guard let normalized = normalizedPluginID(id) else {
            throw ChannelPluginError.invalidID
        }
        guard await store.channelPlugin(id: normalized) != nil else {
            throw ChannelPluginError.notFound
        }
        await store.deleteChannelPlugin(id: normalized)
    }

    /// Finds the enabled plugin responsible for a given channel ID.
    public func channelPluginForChannel(channelId: String) async -> ChannelPluginRecord? {
        let plugins = await store.listChannelPlugins()
        return plugins.first { $0.enabled && $0.channelIds.contains(channelId) }
    }

    func normalizedPluginID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return nil }
        return trimmed
    }

    /// Returns actor graph snapshot used by visual canvas board.
}
