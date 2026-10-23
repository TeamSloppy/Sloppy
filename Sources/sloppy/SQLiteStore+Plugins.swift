import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
#endif

extension SQLiteStore {
    public func listChannelPlugins() async -> [ChannelPluginRecord] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackPlugins.values.sorted { $0.createdAt < $1.createdAt }
        }
        let result = loadChannelPlugins(db: db)
        if result.isEmpty && !fallbackPlugins.isEmpty {
            return fallbackPlugins.values.sorted { $0.createdAt < $1.createdAt }
        }
        return result
#else
        return fallbackPlugins.values.sorted { $0.createdAt < $1.createdAt }
#endif
    }

    public func channelPlugin(id: String) async -> ChannelPluginRecord? {
#if canImport(CSQLite3)
        if let db {
            let sql =
                """
                SELECT id, type, base_url, channel_ids_json, config_json, enabled, delivery_mode, created_at, updated_at
                FROM channel_plugins
                WHERE id = ?
                LIMIT 1;
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return fallbackPlugins[id]
            }
            defer { sqlite3_finalize(statement) }
            bindText(id, at: 1, statement: statement)
            if sqlite3_step(statement) == SQLITE_ROW {
                return decodePluginRow(statement: statement)
            }
            return nil
        }
#endif
        return fallbackPlugins[id]
    }

    public func saveChannelPlugin(_ plugin: ChannelPluginRecord) async {
        fallbackPlugins[plugin.id] = plugin
#if canImport(CSQLite3)
        guard let db else { return }

        let sql =
            """
            INSERT OR REPLACE INTO channel_plugins(
                id, type, base_url, channel_ids_json, config_json, enabled, delivery_mode, created_at, updated_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        let channelIdsJSON = (try? String(data: JSONEncoder().encode(plugin.channelIds), encoding: .utf8)) ?? "[]"
        let configJSON = (try? String(data: JSONEncoder().encode(plugin.config), encoding: .utf8)) ?? "{}"

        bindText(plugin.id, at: 1, statement: statement)
        bindText(plugin.type, at: 2, statement: statement)
        bindText(plugin.baseUrl, at: 3, statement: statement)
        bindText(channelIdsJSON, at: 4, statement: statement)
        bindText(configJSON, at: 5, statement: statement)
        sqlite3_bind_int(statement, 6, plugin.enabled ? 1 : 0)
        bindText(plugin.deliveryMode, at: 7, statement: statement)
        bindText(isoFormatter.string(from: plugin.createdAt), at: 8, statement: statement)
        bindText(isoFormatter.string(from: plugin.updatedAt), at: 9, statement: statement)

        _ = sqlite3_step(statement)
#endif
    }

    public func deleteChannelPlugin(id: String) async {
        fallbackPlugins[id] = nil
#if canImport(CSQLite3)
        guard let db else { return }

        let sql = "DELETE FROM channel_plugins WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

    public func listAgentPlugins() async -> [InstalledAgentPlugin] {
#if canImport(CSQLite3)
        if let db {
            return loadAgentPluginJSONRows(db: db, table: "agent_plugins", as: InstalledAgentPlugin.self)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
#endif
        return fallbackAgentPlugins.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func agentPlugin(id: String) async -> InstalledAgentPlugin? {
#if canImport(CSQLite3)
        if let db {
            return loadAgentPluginJSONRow(db: db, table: "agent_plugins", id: id, as: InstalledAgentPlugin.self)
        }
#endif
        return fallbackAgentPlugins[id]
    }

    public func saveAgentPlugin(_ plugin: InstalledAgentPlugin) async {
        fallbackAgentPlugins[plugin.id] = plugin
#if canImport(CSQLite3)
        if let db { saveAgentPluginJSONRow(db: db, table: "agent_plugins", id: plugin.id, value: plugin) }
#endif
    }

    public func deleteAgentPlugin(id: String) async {
        fallbackAgentPlugins[id] = nil
#if canImport(CSQLite3)
        if let db { deleteAgentPluginJSONRow(db: db, table: "agent_plugins", id: id) }
#endif
    }

    public func listAgentPluginRegistries() async -> [AgentPluginRegistry] {
#if canImport(CSQLite3)
        let values: [AgentPluginRegistry]
        if let db {
            values = loadAgentPluginJSONRows(db: db, table: "agent_plugin_registries", as: AgentPluginRegistry.self)
        } else {
            values = Array(fallbackAgentPluginRegistries.values)
        }
#else
        let values = Array(fallbackAgentPluginRegistries.values)
#endif
        return values.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func saveAgentPluginRegistry(_ registry: AgentPluginRegistry) async {
        if registry.isDefault {
            for key in fallbackAgentPluginRegistries.keys { fallbackAgentPluginRegistries[key]?.isDefault = false }
            for existing in await listAgentPluginRegistries() where existing.id != registry.id && existing.isDefault {
                var updated = existing
                updated.isDefault = false
                fallbackAgentPluginRegistries[updated.id] = updated
#if canImport(CSQLite3)
                if let db { saveAgentPluginJSONRow(db: db, table: "agent_plugin_registries", id: updated.id, value: updated) }
#endif
            }
        }
        fallbackAgentPluginRegistries[registry.id] = registry
#if canImport(CSQLite3)
        if let db { saveAgentPluginJSONRow(db: db, table: "agent_plugin_registries", id: registry.id, value: registry) }
#endif
    }

    public func deleteAgentPluginRegistry(id: String) async {
        fallbackAgentPluginRegistries[id] = nil
#if canImport(CSQLite3)
        if let db { deleteAgentPluginJSONRow(db: db, table: "agent_plugin_registries", id: id) }
#endif
    }

#if canImport(CSQLite3)
    func loadAgentPluginJSONRows<T: Decodable>(db: OpaquePointer, table: String, as type: T.Type) -> [T] {
        let allowedTables = ["agent_plugins", "agent_plugin_registries"]
        guard allowedTables.contains(table) else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT record_json FROM \(table);", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pointer = sqlite3_column_text(statement, 0),
                  let data = String(cString: pointer).data(using: .utf8),
                  let value = try? JSONDecoder().decode(T.self, from: data)
            else { continue }
            result.append(value)
        }
        return result
    }
#endif

#if canImport(CSQLite3)
    func loadAgentPluginJSONRow<T: Decodable>(db: OpaquePointer, table: String, id: String, as type: T.Type) -> T? {
        let allowedTables = ["agent_plugins", "agent_plugin_registries"]
        guard allowedTables.contains(table) else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT record_json FROM \(table) WHERE id = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let pointer = sqlite3_column_text(statement, 0),
              let data = String(cString: pointer).data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
#endif

#if canImport(CSQLite3)
    func saveAgentPluginJSONRow<T: Encodable>(db: OpaquePointer, table: String, id: String, value: T) {
        let allowedTables = ["agent_plugins", "agent_plugin_registries"]
        guard allowedTables.contains(table),
              let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8)
        else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO \(table)(id, record_json, updated_at) VALUES(?, ?, ?);", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        bindText(json, at: 2, statement: statement)
        bindText(isoFormatter.string(from: Date()), at: 3, statement: statement)
        _ = sqlite3_step(statement)
    }
#endif

#if canImport(CSQLite3)
    func deleteAgentPluginJSONRow(db: OpaquePointer, table: String, id: String) {
        let allowedTables = ["agent_plugins", "agent_plugin_registries"]
        guard allowedTables.contains(table) else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM \(table) WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        _ = sqlite3_step(statement)
    }
#endif

#if canImport(CSQLite3)
    func loadChannelPlugins(db: OpaquePointer) -> [ChannelPluginRecord] {
        let sql =
            """
            SELECT id, type, base_url, channel_ids_json, config_json, enabled, delivery_mode, created_at, updated_at
            FROM channel_plugins
            ORDER BY created_at ASC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var result: [ChannelPluginRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let record = decodePluginRow(statement: statement) {
                result.append(record)
            }
        }
        return result
    }
#endif

#if canImport(CSQLite3)
    func decodePluginRow(statement: OpaquePointer?) -> ChannelPluginRecord? {
        guard
            let idPtr = sqlite3_column_text(statement, 0),
            let typePtr = sqlite3_column_text(statement, 1),
            let baseUrlPtr = sqlite3_column_text(statement, 2),
            let channelIdsPtr = sqlite3_column_text(statement, 3),
            let configPtr = sqlite3_column_text(statement, 4),
            let createdAtPtr = sqlite3_column_text(statement, 7),
            let updatedAtPtr = sqlite3_column_text(statement, 8)
        else {
            return nil
        }

        let enabled = sqlite3_column_int(statement, 5) != 0
        let deliveryModePtr = sqlite3_column_text(statement, 6)
        let deliveryMode = deliveryModePtr.map { String(cString: $0) } ?? ChannelPluginRecord.DeliveryMode.http
        let channelIds = (try? JSONDecoder().decode([String].self, from: Data(String(cString: channelIdsPtr).utf8))) ?? []
        let config = (try? JSONDecoder().decode([String: String].self, from: Data(String(cString: configPtr).utf8))) ?? [:]
        let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
        let updatedAt = isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt

        return ChannelPluginRecord(
            id: String(cString: idPtr),
            type: String(cString: typePtr),
            baseUrl: String(cString: baseUrlPtr),
            channelIds: channelIds,
            config: config,
            enabled: enabled,
            deliveryMode: deliveryMode,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
#endif
}
