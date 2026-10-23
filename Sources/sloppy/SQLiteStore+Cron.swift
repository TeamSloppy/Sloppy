import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
#endif

extension SQLiteStore {
    public func listAllCronTasks() async -> [AgentCronTask] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackCronTasks.values.sorted { $0.createdAt < $1.createdAt }
        }
        let sql =
            """
            SELECT id, agent_id, channel_id, schedule, command, enabled, created_at, updated_at
            FROM agent_cron_tasks
            ORDER BY created_at ASC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var result: [AgentCronTask] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let agentIdPtr = sqlite3_column_text(statement, 1),
                let channelIdPtr = sqlite3_column_text(statement, 2),
                let schedulePtr = sqlite3_column_text(statement, 3),
                let commandPtr = sqlite3_column_text(statement, 4),
                let createdAtPtr = sqlite3_column_text(statement, 6),
                let updatedAtPtr = sqlite3_column_text(statement, 7)
            else { continue }

            let id = String(cString: idPtr)
            let agentId = String(cString: agentIdPtr)
            let channelId = String(cString: channelIdPtr)
            let schedule = String(cString: schedulePtr)
            let command = String(cString: commandPtr)
            let enabled = sqlite3_column_int(statement, 5) != 0

            guard
                let createdAtDate = isoFormatter.date(from: String(cString: createdAtPtr)),
                let updatedAtDate = isoFormatter.date(from: String(cString: updatedAtPtr))
            else { continue }

            result.append(
                AgentCronTask(
                    id: id,
                    agentId: agentId,
                    channelId: channelId,
                    schedule: schedule,
                    command: command,
                    enabled: enabled,
                    createdAt: createdAtDate,
                    updatedAt: updatedAtDate
                )
            )
        }
        return result
#else
        return fallbackCronTasks.values.sorted { $0.createdAt < $1.createdAt }
#endif
    }

    public func listCronTasks(agentId: String) async -> [AgentCronTask] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackCronTasks.values.filter { $0.agentId == agentId }.sorted { $0.createdAt < $1.createdAt }
        }
        let sql =
            """
            SELECT id, agent_id, channel_id, schedule, command, enabled, created_at, updated_at
            FROM agent_cron_tasks
            WHERE agent_id = ?
            ORDER BY created_at ASC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(agentId, at: 1, statement: statement)

        var result: [AgentCronTask] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let agentIdPtr = sqlite3_column_text(statement, 1),
                let channelIdPtr = sqlite3_column_text(statement, 2),
                let schedulePtr = sqlite3_column_text(statement, 3),
                let commandPtr = sqlite3_column_text(statement, 4),
                let createdAtPtr = sqlite3_column_text(statement, 6),
                let updatedAtPtr = sqlite3_column_text(statement, 7)
            else { continue }

            let enabled = sqlite3_column_int(statement, 5) != 0
            let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
            let updatedAt = isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt

            result.append(AgentCronTask(
                id: String(cString: idPtr),
                agentId: String(cString: agentIdPtr),
                channelId: String(cString: channelIdPtr),
                schedule: String(cString: schedulePtr),
                command: String(cString: commandPtr),
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
        return result
#else
        return fallbackCronTasks.values.filter { $0.agentId == agentId }.sorted { $0.createdAt < $1.createdAt }
#endif
    }

    public func saveCronTask(_ task: AgentCronTask) async {
        fallbackCronTasks[task.id] = task
#if canImport(CSQLite3)
        guard let db else { return }
        let sql =
            """
            INSERT OR REPLACE INTO agent_cron_tasks(
                id, agent_id, channel_id, schedule, command, enabled, created_at, updated_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        bindText(task.id, at: 1, statement: statement)
        bindText(task.agentId, at: 2, statement: statement)
        bindText(task.channelId, at: 3, statement: statement)
        bindText(task.schedule, at: 4, statement: statement)
        bindText(task.command, at: 5, statement: statement)
        sqlite3_bind_int(statement, 6, task.enabled ? 1 : 0)
        bindText(isoFormatter.string(from: task.createdAt), at: 7, statement: statement)
        bindText(isoFormatter.string(from: task.updatedAt), at: 8, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

    public func deleteCronTask(id: String) async {
        fallbackCronTasks[id] = nil
#if canImport(CSQLite3)
        guard let db else { return }
        let sql = "DELETE FROM agent_cron_tasks WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

    public func cronTask(id: String) async -> AgentCronTask? {
#if canImport(CSQLite3)
        guard let db else { return fallbackCronTasks[id] }
        let sql =
            """
            SELECT id, agent_id, channel_id, schedule, command, enabled, created_at, updated_at
            FROM agent_cron_tasks
            WHERE id = ?
            LIMIT 1;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return fallbackCronTasks[id] }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)

        if sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let agentIdPtr = sqlite3_column_text(statement, 1),
                let channelIdPtr = sqlite3_column_text(statement, 2),
                let schedulePtr = sqlite3_column_text(statement, 3),
                let commandPtr = sqlite3_column_text(statement, 4),
                let createdAtPtr = sqlite3_column_text(statement, 6),
                let updatedAtPtr = sqlite3_column_text(statement, 7)
            else { return nil }

            let enabled = sqlite3_column_int(statement, 5) != 0
            let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
            let updatedAt = isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt

            return AgentCronTask(
                id: String(cString: idPtr),
                agentId: String(cString: agentIdPtr),
                channelId: String(cString: channelIdPtr),
                schedule: String(cString: schedulePtr),
                command: String(cString: commandPtr),
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
        return nil
#else
        return fallbackCronTasks[id]
#endif
    }
}
