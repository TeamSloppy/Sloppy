import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
#endif

extension SQLiteStore {
    public func listChannelAccessUsers(platform: String?) async -> [ChannelAccessUser] {
#if canImport(CSQLite3)
        guard let db else {
            let all = fallbackAccessUsers.values.sorted { $0.createdAt < $1.createdAt }
            guard let platform else { return all }
            return all.filter { $0.platform == platform }
        }
        let sql: String
        if let platform {
            sql = "SELECT id, platform, platform_user_id, display_name, status, created_at, updated_at FROM channel_access_users WHERE platform = ? ORDER BY created_at DESC;"
        } else {
            sql = "SELECT id, platform, platform_user_id, display_name, status, created_at, updated_at FROM channel_access_users ORDER BY created_at DESC;"
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        if let platform {
            bindText(platform, at: 1, statement: statement)
        }
        var results: [ChannelAccessUser] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let platformPtr = sqlite3_column_text(statement, 1),
                let userIdPtr = sqlite3_column_text(statement, 2),
                let namePtr = sqlite3_column_text(statement, 3),
                let statusPtr = sqlite3_column_text(statement, 4),
                let createdAtPtr = sqlite3_column_text(statement, 5),
                let updatedAtPtr = sqlite3_column_text(statement, 6)
            else { continue }
            results.append(ChannelAccessUser(
                id: String(cString: idPtr),
                platform: String(cString: platformPtr),
                platformUserId: String(cString: userIdPtr),
                displayName: String(cString: namePtr),
                status: String(cString: statusPtr),
                createdAt: isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date(),
                updatedAt: isoFormatter.date(from: String(cString: updatedAtPtr)) ?? Date()
            ))
        }
        return results
#else
        return []
#endif
    }

    public func channelAccessUser(platform: String, platformUserId: String) async -> ChannelAccessUser? {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackAccessUsers.values.first { $0.platform == platform && $0.platformUserId == platformUserId }
        }
        let sql = "SELECT id, platform, platform_user_id, display_name, status, created_at, updated_at FROM channel_access_users WHERE platform = ? AND platform_user_id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(platform, at: 1, statement: statement)
        bindText(platformUserId, at: 2, statement: statement)
        if sqlite3_step(statement) == SQLITE_ROW,
           let idPtr = sqlite3_column_text(statement, 0),
           let platformPtr = sqlite3_column_text(statement, 1),
           let userIdPtr = sqlite3_column_text(statement, 2),
           let namePtr = sqlite3_column_text(statement, 3),
           let statusPtr = sqlite3_column_text(statement, 4),
           let createdAtPtr = sqlite3_column_text(statement, 5),
           let updatedAtPtr = sqlite3_column_text(statement, 6) {
            return ChannelAccessUser(
                id: String(cString: idPtr),
                platform: String(cString: platformPtr),
                platformUserId: String(cString: userIdPtr),
                displayName: String(cString: namePtr),
                status: String(cString: statusPtr),
                createdAt: isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date(),
                updatedAt: isoFormatter.date(from: String(cString: updatedAtPtr)) ?? Date()
            )
        }
        return nil
#else
        return nil
#endif
    }

    public func saveChannelAccessUser(_ user: ChannelAccessUser) async {
#if canImport(CSQLite3)
        guard let db else {
            if let existing = fallbackAccessUsers.values.first(where: { $0.platform == user.platform && $0.platformUserId == user.platformUserId }) {
                fallbackAccessUsers[existing.id] = nil
            }
            fallbackAccessUsers[user.id] = user
            return
        }
        let sql = """
            INSERT INTO channel_access_users(id, platform, platform_user_id, display_name, status, created_at, updated_at)
            VALUES(?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(platform, platform_user_id) DO UPDATE SET
                display_name = excluded.display_name,
                status = excluded.status,
                updated_at = excluded.updated_at;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }
        bindText(user.id, at: 1, statement: statement)
        bindText(user.platform, at: 2, statement: statement)
        bindText(user.platformUserId, at: 3, statement: statement)
        bindText(user.displayName, at: 4, statement: statement)
        bindText(user.status, at: 5, statement: statement)
        bindText(isoFormatter.string(from: user.createdAt), at: 6, statement: statement)
        bindText(isoFormatter.string(from: user.updatedAt), at: 7, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

    public func deleteChannelAccessUser(id: String) async {
#if canImport(CSQLite3)
        guard let db else {
            fallbackAccessUsers[id] = nil
            return
        }
        let sql = "DELETE FROM channel_access_users WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }
}
