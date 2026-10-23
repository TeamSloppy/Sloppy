import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
#endif

extension SQLiteStore {
    /// Persists runtime event envelope.
    public func persist(event: EventEnvelope) async {
#if canImport(CSQLite3)
        guard let db else {
            persistFallbackEvent(event)
            return
        }

        let sql =
            """
            INSERT INTO events(
                id,
                message_type,
                channel_id,
                task_id,
                branch_id,
                worker_id,
                payload_json,
                extensions_json,
                created_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            persistFallbackEvent(event)
            return
        }
        defer { sqlite3_finalize(statement) }

        let payloadData = try? JSONEncoder().encode(event.payload)
        let payloadString = payloadData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let extensionsData = try? JSONEncoder().encode(event.extensions)
        let extensionsString = extensionsData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        bindText(event.messageId, at: 1, statement: statement)
        bindText(event.messageType.rawValue, at: 2, statement: statement)
        bindText(event.channelId, at: 3, statement: statement)
        bindOptionalText(event.taskId, at: 4, statement: statement)
        bindOptionalText(event.branchId, at: 5, statement: statement)
        bindOptionalText(event.workerId, at: 6, statement: statement)
        bindText(payloadString, at: 7, statement: statement)
        bindText(extensionsString, at: 8, statement: statement)
        bindText(isoFormatter.string(from: event.ts), at: 9, statement: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            persistFallbackEvent(event)
            return
        }

        upsertChannel(db: db, channelId: event.channelId, timestamp: event.ts)
        upsertTask(db: db, event: event)
#else
        persistFallbackEvent(event)
#endif
    }

    /// Persists generated memory bulletin.
    public func persistBulletin(_ bulletin: MemoryBulletin) async {
#if canImport(CSQLite3)
        guard let db else {
            fallbackBulletins.append(bulletin)
            return
        }

        let sql =
            """
            INSERT INTO memory_bulletins(
                id,
                headline,
                digest,
                items_json,
                created_at
            ) VALUES(?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            fallbackBulletins.append(bulletin)
            return
        }
        defer { sqlite3_finalize(statement) }

        let itemsJSON = (try? String(data: JSONEncoder().encode(bulletin.items), encoding: .utf8)) ?? "[]"
        bindText(bulletin.id, at: 1, statement: statement)
        bindText(bulletin.headline, at: 2, statement: statement)
        bindText(bulletin.digest, at: 3, statement: statement)
        bindText(itemsJSON, at: 4, statement: statement)
        bindText(isoFormatter.string(from: bulletin.generatedAt), at: 5, statement: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            fallbackBulletins.append(bulletin)
        }
#else
        fallbackBulletins.append(bulletin)
#endif
    }

    /// Lists persisted events in deterministic replay order.
    public func listPersistedEvents() async -> [EventEnvelope] {
#if canImport(CSQLite3)
        guard let db else {
            return sortedFallbackEvents()
        }

        let result = loadPersistedEvents(db: db)
        if result.isEmpty && !fallbackEvents.isEmpty {
            return sortedFallbackEvents()
        }
        return result
#else
        return sortedFallbackEvents()
#endif
    }

    public func listChannelEvents(
        channelId: String,
        limit: Int,
        cursor: PersistedEventCursor?,
        before: Date?,
        after: Date?
    ) async -> [EventEnvelope] {
        guard limit > 0 else {
            return []
        }
#if canImport(CSQLite3)
        guard let db else {
            return filteredFallbackChannelEvents(
                channelId: channelId,
                limit: limit,
                cursor: cursor,
                before: before,
                after: after
            )
        }

        let result = loadChannelEvents(
            db: db,
            channelId: channelId,
            limit: limit,
            cursor: cursor,
            before: before,
            after: after
        )
        if result.isEmpty && !fallbackEvents.isEmpty {
            return filteredFallbackChannelEvents(
                channelId: channelId,
                limit: limit,
                cursor: cursor,
                before: before,
                after: after
            )
        }
        return result
#else
        return filteredFallbackChannelEvents(
            channelId: channelId,
            limit: limit,
            cursor: cursor,
            before: before,
            after: after
        )
#endif
    }

    /// Lists persisted channels in creation order.
    public func listPersistedChannels() async -> [PersistedChannelRecord] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackChannels.values.sorted { $0.createdAt < $1.createdAt }
        }

        let result = loadPersistedChannels(db: db)
        if result.isEmpty && !fallbackChannels.isEmpty {
            return fallbackChannels.values.sorted { $0.createdAt < $1.createdAt }
        }
        return result
#else
        return fallbackChannels.values.sorted { $0.createdAt < $1.createdAt }
#endif
    }

    /// Lists persisted task rows in creation order.
    public func listPersistedTasks() async -> [PersistedTaskRecord] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackTasks.values.sorted { $0.createdAt < $1.createdAt }
        }

        let result = loadPersistedTasks(db: db)
        if result.isEmpty && !fallbackTasks.isEmpty {
            return fallbackTasks.values.sorted { $0.createdAt < $1.createdAt }
        }
        return result
#else
        return fallbackTasks.values.sorted { $0.createdAt < $1.createdAt }
#endif
    }

    /// Lists recent memory bulletins.
    public func listBulletins() async -> [MemoryBulletin] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackBulletins
        }

        let sql =
            """
            SELECT id, headline, digest, items_json, created_at
            FROM memory_bulletins
            ORDER BY created_at DESC
            LIMIT 100;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return fallbackBulletins
        }
        defer { sqlite3_finalize(statement) }

        var result: [MemoryBulletin] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let headlinePtr = sqlite3_column_text(statement, 1),
                let digestPtr = sqlite3_column_text(statement, 2),
                let itemsPtr = sqlite3_column_text(statement, 3),
                let createdAtPtr = sqlite3_column_text(statement, 4)
            else {
                continue
            }

            let id = String(cString: idPtr)
            let headline = String(cString: headlinePtr)
            let digest = String(cString: digestPtr)
            let itemsJSON = String(cString: itemsPtr)
            let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
            let itemsData = Data(itemsJSON.utf8)
            let items = (try? JSONDecoder().decode([String].self, from: itemsData)) ?? []

            result.append(
                MemoryBulletin(
                    id: id,
                    generatedAt: createdAt,
                    headline: headline,
                    digest: digest,
                    items: items
                )
            )
        }

        if result.isEmpty {
            return fallbackBulletins
        }
        return result
#else
        return fallbackBulletins
#endif
    }

    func sortedFallbackEvents() -> [EventEnvelope] {
        fallbackEvents.sorted { left, right in
            if left.ts == right.ts {
                return left.messageId < right.messageId
            }
            return left.ts < right.ts
        }
    }

    func filteredFallbackChannelEvents(
        channelId: String,
        limit: Int,
        cursor: PersistedEventCursor?,
        before: Date?,
        after: Date?
    ) -> [EventEnvelope] {
        var filtered = fallbackEvents
            .filter { $0.channelId == channelId }
            .sorted { left, right in
                if left.ts == right.ts {
                    return left.messageId > right.messageId
                }
                return left.ts > right.ts
            }

        filtered.removeAll { event in
            if let before, !(event.ts < before) {
                return true
            }
            if let after, !(event.ts > after) {
                return true
            }
            if let cursor {
                if event.ts > cursor.createdAt {
                    return true
                }
                if event.ts == cursor.createdAt, event.messageId >= cursor.eventId {
                    return true
                }
            }
            return false
        }

        return Array(filtered.prefix(limit))
    }

    func persistFallbackEvent(_ event: EventEnvelope) {
        fallbackEvents.append(event)
        upsertFallbackChannel(channelId: event.channelId, timestamp: event.ts)
        upsertFallbackTask(event: event)
    }

    func upsertFallbackChannel(channelId: String, timestamp: Date) {
        if var existing = fallbackChannels[channelId] {
            existing.updatedAt = max(existing.updatedAt, timestamp)
            fallbackChannels[channelId] = existing
            return
        }

        fallbackChannels[channelId] = PersistedChannelRecord(
            id: channelId,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    func upsertFallbackTask(event: EventEnvelope) {
        guard let taskID = event.taskId, !taskID.isEmpty else {
            return
        }

        let payload = event.payload.objectValue
        let status = inferredTaskStatus(from: event.messageType)
        let title = payload["title"]?.stringValue ?? payload["progress"]?.stringValue
        let objective = payload["objective"]?.stringValue

        if var existing = fallbackTasks[taskID] {
            existing.channelId = event.channelId
            existing.status = status ?? existing.status
            if let title, !title.isEmpty {
                existing.title = title
            }
            if let objective, !objective.isEmpty {
                existing.objective = objective
            }
            existing.updatedAt = max(existing.updatedAt, event.ts)
            fallbackTasks[taskID] = existing
            return
        }

        fallbackTasks[taskID] = PersistedTaskRecord(
            id: taskID,
            channelId: event.channelId,
            status: status ?? "unknown",
            title: title ?? "Task \(taskID)",
            objective: objective ?? "",
            createdAt: event.ts,
            updatedAt: event.ts
        )
    }

    func inferredTaskStatus(from messageType: MessageType) -> String? {
        switch messageType {
        case .workerSpawned:
            "queued"
        case .workerProgress:
            "running"
        case .workerCompleted:
            "completed"
        case .workerFailed:
            "failed"
        default:
            nil
        }
    }

#if canImport(CSQLite3)
    func loadPersistedEvents(db: OpaquePointer) -> [EventEnvelope] {
        let sql =
            """
            SELECT id, message_type, channel_id, task_id, branch_id, worker_id, payload_json, extensions_json, created_at
            FROM events
            ORDER BY created_at ASC, id ASC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var result: [EventEnvelope] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let messageTypePtr = sqlite3_column_text(statement, 1),
                let channelIDPtr = sqlite3_column_text(statement, 2),
                let payloadPtr = sqlite3_column_text(statement, 6),
                let extensionsPtr = sqlite3_column_text(statement, 7),
                let createdAtPtr = sqlite3_column_text(statement, 8)
            else {
                continue
            }

            let messageID = String(cString: idPtr)
            let rawMessageType = String(cString: messageTypePtr)
            guard let messageType = MessageType(rawValue: rawMessageType) else {
                continue
            }

            let timestamp = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
            let payloadJSON = String(cString: payloadPtr)
            let payloadData = Data(payloadJSON.utf8)
            let payload = (try? JSONDecoder().decode(JSONValue.self, from: payloadData)) ?? .object([:])
            let extensionsJSON = String(cString: extensionsPtr)
            let extensionsData = Data(extensionsJSON.utf8)
            let extensions = (try? JSONDecoder().decode([String: JSONValue].self, from: extensionsData)) ?? [:]

            result.append(
                EventEnvelope(
                    messageId: messageID,
                    messageType: messageType,
                    ts: timestamp,
                    traceId: messageID,
                    channelId: String(cString: channelIDPtr),
                    taskId: optionalText(statement: statement, index: 3),
                    branchId: optionalText(statement: statement, index: 4),
                    workerId: optionalText(statement: statement, index: 5),
                    payload: payload,
                    extensions: extensions
                )
            )
        }

        return result
    }
#endif

#if canImport(CSQLite3)
    func loadChannelEvents(
        db: OpaquePointer,
        channelId: String,
        limit: Int,
        cursor: PersistedEventCursor?,
        before: Date?,
        after: Date?
    ) -> [EventEnvelope] {
        var conditions: [String] = ["channel_id = ?"]
        if before != nil {
            conditions.append("created_at < ?")
        }
        if after != nil {
            conditions.append("created_at > ?")
        }
        if cursor != nil {
            conditions.append("(created_at < ? OR (created_at = ? AND id < ?))")
        }

        let whereClause = "WHERE " + conditions.joined(separator: " AND ")
        let sql =
            """
            SELECT id, message_type, channel_id, task_id, branch_id, worker_id, payload_json, extensions_json, created_at
            FROM events
            \(whereClause)
            ORDER BY created_at DESC, id DESC
            LIMIT ?;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var parameter: Int32 = 1
        bindText(channelId, at: parameter, statement: statement)
        parameter += 1

        if let before {
            bindText(isoFormatter.string(from: before), at: parameter, statement: statement)
            parameter += 1
        }
        if let after {
            bindText(isoFormatter.string(from: after), at: parameter, statement: statement)
            parameter += 1
        }
        if let cursor {
            let cursorTimestamp = isoFormatter.string(from: cursor.createdAt)
            bindText(cursorTimestamp, at: parameter, statement: statement)
            parameter += 1
            bindText(cursorTimestamp, at: parameter, statement: statement)
            parameter += 1
            bindText(cursor.eventId, at: parameter, statement: statement)
            parameter += 1
        }

        sqlite3_bind_int(statement, parameter, Int32(limit))

        var result: [EventEnvelope] = []
        result.reserveCapacity(limit)
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let messageTypePtr = sqlite3_column_text(statement, 1),
                let channelIDPtr = sqlite3_column_text(statement, 2),
                let payloadPtr = sqlite3_column_text(statement, 6),
                let extensionsPtr = sqlite3_column_text(statement, 7),
                let createdAtPtr = sqlite3_column_text(statement, 8)
            else {
                continue
            }

            let messageID = String(cString: idPtr)
            let rawMessageType = String(cString: messageTypePtr)
            guard let messageType = MessageType(rawValue: rawMessageType) else {
                continue
            }

            let timestamp = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
            let payloadJSON = String(cString: payloadPtr)
            let payloadData = Data(payloadJSON.utf8)
            let payload = (try? JSONDecoder().decode(JSONValue.self, from: payloadData)) ?? .object([:])
            let extensionsJSON = String(cString: extensionsPtr)
            let extensionsData = Data(extensionsJSON.utf8)
            let extensions = (try? JSONDecoder().decode([String: JSONValue].self, from: extensionsData)) ?? [:]

            result.append(
                EventEnvelope(
                    messageId: messageID,
                    messageType: messageType,
                    ts: timestamp,
                    traceId: messageID,
                    channelId: String(cString: channelIDPtr),
                    taskId: optionalText(statement: statement, index: 3),
                    branchId: optionalText(statement: statement, index: 4),
                    workerId: optionalText(statement: statement, index: 5),
                    payload: payload,
                    extensions: extensions
                )
            )
        }

        return result
    }
#endif

#if canImport(CSQLite3)
    func loadPersistedChannels(db: OpaquePointer) -> [PersistedChannelRecord] {
        let sql =
            """
            SELECT id, created_at, updated_at
            FROM channels
            ORDER BY created_at ASC, id ASC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var result: [PersistedChannelRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let createdAtPtr = sqlite3_column_text(statement, 1),
                let updatedAtPtr = sqlite3_column_text(statement, 2)
            else {
                continue
            }
            let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
            let updatedAt = isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt
            result.append(
                PersistedChannelRecord(
                    id: String(cString: idPtr),
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            )
        }

        return result
    }
#endif

#if canImport(CSQLite3)
    func loadPersistedTasks(db: OpaquePointer) -> [PersistedTaskRecord] {
        let sql =
            """
            SELECT id, channel_id, status, title, objective, created_at, updated_at
            FROM tasks
            ORDER BY created_at ASC, id ASC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var result: [PersistedTaskRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let channelIDPtr = sqlite3_column_text(statement, 1),
                let statusPtr = sqlite3_column_text(statement, 2),
                let titlePtr = sqlite3_column_text(statement, 3),
                let objectivePtr = sqlite3_column_text(statement, 4),
                let createdAtPtr = sqlite3_column_text(statement, 5),
                let updatedAtPtr = sqlite3_column_text(statement, 6)
            else {
                continue
            }

            let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
            let updatedAt = isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt
            result.append(
                PersistedTaskRecord(
                    id: String(cString: idPtr),
                    channelId: String(cString: channelIDPtr),
                    status: String(cString: statusPtr),
                    title: String(cString: titlePtr),
                    objective: String(cString: objectivePtr),
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            )
        }

        return result
    }
#endif

#if canImport(CSQLite3)
    func upsertChannel(db: OpaquePointer, channelId: String, timestamp: Date) {
        let createdAtText = isoFormatter.string(from: timestamp)
        let updatedAtText = createdAtText
        let insertSQL =
            """
            INSERT OR IGNORE INTO channels(id, created_at, updated_at)
            VALUES(?, ?, ?);
            """
        var insertStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &insertStatement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(insertStatement) }
            bindText(channelId, at: 1, statement: insertStatement)
            bindText(createdAtText, at: 2, statement: insertStatement)
            bindText(updatedAtText, at: 3, statement: insertStatement)
            _ = sqlite3_step(insertStatement)
        }

        let updateSQL =
            """
            UPDATE channels
            SET updated_at = ?
            WHERE id = ?;
            """
        var updateStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSQL, -1, &updateStatement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(updateStatement) }
            bindText(updatedAtText, at: 1, statement: updateStatement)
            bindText(channelId, at: 2, statement: updateStatement)
            _ = sqlite3_step(updateStatement)
        }
    }
#endif

#if canImport(CSQLite3)
    func upsertTask(db: OpaquePointer, event: EventEnvelope) {
        guard let taskID = event.taskId, !taskID.isEmpty else {
            return
        }

        let existing = loadPersistedTask(db: db, taskID: taskID)
        let payload = event.payload.objectValue
        let status = inferredTaskStatus(from: event.messageType) ?? existing?.status ?? "unknown"
        let title = payload["title"]?.stringValue ?? payload["progress"]?.stringValue ?? existing?.title ?? "Task \(taskID)"
        let objective = payload["objective"]?.stringValue ?? existing?.objective ?? ""
        let createdAt = existing?.createdAt ?? event.ts
        let updatedAt = max(existing?.updatedAt ?? event.ts, event.ts)

        let sql =
            """
            INSERT OR REPLACE INTO tasks(
                id,
                channel_id,
                status,
                title,
                objective,
                created_at,
                updated_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            upsertFallbackTask(event: event)
            return
        }
        defer { sqlite3_finalize(statement) }

        bindText(taskID, at: 1, statement: statement)
        bindText(event.channelId, at: 2, statement: statement)
        bindText(status, at: 3, statement: statement)
        bindText(title, at: 4, statement: statement)
        bindText(objective, at: 5, statement: statement)
        bindText(isoFormatter.string(from: createdAt), at: 6, statement: statement)
        bindText(isoFormatter.string(from: updatedAt), at: 7, statement: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            upsertFallbackTask(event: event)
        }
    }
#endif

#if canImport(CSQLite3)
    func loadPersistedTask(db: OpaquePointer, taskID: String) -> PersistedTaskRecord? {
        let sql =
            """
            SELECT id, channel_id, status, title, objective, created_at, updated_at
            FROM tasks
            WHERE id = ?
            LIMIT 1;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        bindText(taskID, at: 1, statement: statement)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let idPtr = sqlite3_column_text(statement, 0),
              let channelIDPtr = sqlite3_column_text(statement, 1),
              let statusPtr = sqlite3_column_text(statement, 2),
              let titlePtr = sqlite3_column_text(statement, 3),
              let objectivePtr = sqlite3_column_text(statement, 4),
              let createdAtPtr = sqlite3_column_text(statement, 5),
              let updatedAtPtr = sqlite3_column_text(statement, 6)
        else {
            return nil
        }

        let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
        let updatedAt = isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt
        return PersistedTaskRecord(
            id: String(cString: idPtr),
            channelId: String(cString: channelIDPtr),
            status: String(cString: statusPtr),
            title: String(cString: titlePtr),
            objective: String(cString: objectivePtr),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
#endif
}

private extension JSONValue {
    var objectValue: [String: JSONValue] {
        if case .object(let object) = self {
            return object
        }
        return [:]
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}
