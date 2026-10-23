import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
#endif

extension SQLiteStore {
    public func listClarifications(projectId: String, taskId: String) async -> [TaskClarificationRecord] {
#if canImport(CSQLite3)
        guard let db else { return [] }
        let sql =
            """
            SELECT id, project_id, task_id, status, target_type, target_actor_id, target_channel_id,
                   question_text, options_json, allow_note, created_by_agent_id,
                   selected_option_ids_json, note, created_at, answered_at
            FROM task_clarifications
            WHERE project_id = ? AND task_id = ?
            ORDER BY created_at DESC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(projectId, at: 1, statement: statement)
        bindText(taskId, at: 2, statement: statement)
        var result: [TaskClarificationRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let record = decodeClarificationRow(statement: statement) {
                result.append(record)
            }
        }
        return result
#else
        return []
#endif
    }

    public func clarification(id: String) async -> TaskClarificationRecord? {
#if canImport(CSQLite3)
        guard let db else { return nil }
        let sql =
            """
            SELECT id, project_id, task_id, status, target_type, target_actor_id, target_channel_id,
                   question_text, options_json, allow_note, created_by_agent_id,
                   selected_option_ids_json, note, created_at, answered_at
            FROM task_clarifications
            WHERE id = ?
            LIMIT 1;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        if sqlite3_step(statement) == SQLITE_ROW {
            return decodeClarificationRow(statement: statement)
        }
        return nil
#else
        return nil
#endif
    }

    public func saveClarification(_ record: TaskClarificationRecord) async {
#if canImport(CSQLite3)
        guard let db else { return }
        let sql =
            """
            INSERT OR REPLACE INTO task_clarifications(
                id, project_id, task_id, status, target_type, target_actor_id, target_channel_id,
                question_text, options_json, allow_note, created_by_agent_id,
                selected_option_ids_json, note, created_at, answered_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        let optionsJSON = (try? String(data: JSONEncoder().encode(record.options), encoding: .utf8)) ?? "[]"
        let selectedJSON = (try? String(data: JSONEncoder().encode(record.selectedOptionIds), encoding: .utf8)) ?? "[]"

        bindText(record.id, at: 1, statement: statement)
        bindText(record.projectId, at: 2, statement: statement)
        bindText(record.taskId, at: 3, statement: statement)
        bindText(record.status.rawValue, at: 4, statement: statement)
        bindText(record.targetType.rawValue, at: 5, statement: statement)
        bindOptionalText(record.targetActorId, at: 6, statement: statement)
        bindOptionalText(record.targetChannelId, at: 7, statement: statement)
        bindText(record.questionText, at: 8, statement: statement)
        bindText(optionsJSON, at: 9, statement: statement)
        sqlite3_bind_int(statement, 10, record.allowNote ? 1 : 0)
        bindOptionalText(record.createdByAgentId, at: 11, statement: statement)
        bindText(selectedJSON, at: 12, statement: statement)
        bindOptionalText(record.note, at: 13, statement: statement)
        bindText(isoFormatter.string(from: record.createdAt), at: 14, statement: statement)
        if let answeredAt = record.answeredAt {
            bindText(isoFormatter.string(from: answeredAt), at: 15, statement: statement)
        } else {
            sqlite3_bind_null(statement, 15)
        }
        _ = sqlite3_step(statement)
#endif
    }

    public func deleteClarification(id: String) async {
#if canImport(CSQLite3)
        guard let db else { return }
        let sql = "DELETE FROM task_clarifications WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

#if canImport(CSQLite3)
    func decodeClarificationRow(statement: OpaquePointer?) -> TaskClarificationRecord? {
        guard
            let idPtr = sqlite3_column_text(statement, 0),
            let projectIdPtr = sqlite3_column_text(statement, 1),
            let taskIdPtr = sqlite3_column_text(statement, 2),
            let statusPtr = sqlite3_column_text(statement, 3),
            let targetTypePtr = sqlite3_column_text(statement, 4),
            let questionPtr = sqlite3_column_text(statement, 7),
            let optionsPtr = sqlite3_column_text(statement, 8),
            let createdAtPtr = sqlite3_column_text(statement, 13)
        else {
            return nil
        }

        let allowNote = sqlite3_column_int(statement, 9) != 0
        let selectedJSON = sqlite3_column_text(statement, 11).map { String(cString: $0) } ?? "[]"
        let selectedOptionIds = (try? JSONDecoder().decode([String].self, from: Data(selectedJSON.utf8))) ?? []
        let optionsJSON = String(cString: optionsPtr)
        let options = (try? JSONDecoder().decode([ClarificationOption].self, from: Data(optionsJSON.utf8))) ?? []
        let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
        let answeredAtRaw = optionalText(statement: statement, index: 14)
        let answeredAt = answeredAtRaw.flatMap { isoFormatter.date(from: $0) }

        return TaskClarificationRecord(
            id: String(cString: idPtr),
            projectId: String(cString: projectIdPtr),
            taskId: String(cString: taskIdPtr),
            status: ClarificationStatus(rawValue: String(cString: statusPtr)) ?? .pending,
            targetType: ClarificationTargetType(rawValue: String(cString: targetTypePtr)) ?? .human,
            targetActorId: optionalText(statement: statement, index: 5),
            targetChannelId: optionalText(statement: statement, index: 6),
            questionText: String(cString: questionPtr),
            options: options,
            allowNote: allowNote,
            createdByAgentId: optionalText(statement: statement, index: 10),
            selectedOptionIds: selectedOptionIds,
            note: optionalText(statement: statement, index: 12),
            createdAt: createdAt,
            answeredAt: answeredAt
        )
    }
#endif
}
