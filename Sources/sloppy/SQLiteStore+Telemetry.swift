import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
#endif

extension SQLiteStore {
    /// Persists prompt/completion token usage metrics.
    public func persistTokenUsage(channelId: String, taskId: String?, usage: TokenUsage) async {
#if canImport(CSQLite3)
        guard let db else { return }

        let sql =
            """
            INSERT INTO token_usage(
                id,
                channel_id,
                task_id,
                prompt_tokens,
                completion_tokens,
                total_tokens,
                cached_input_tokens,
                cache_creation_input_tokens,
                reasoning_tokens,
                created_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        bindText(UUID().uuidString, at: 1, statement: statement)
        bindText(channelId, at: 2, statement: statement)
        bindOptionalText(taskId, at: 3, statement: statement)
        sqlite3_bind_int(statement, 4, Int32(usage.prompt))
        sqlite3_bind_int(statement, 5, Int32(usage.completion))
        sqlite3_bind_int(statement, 6, Int32(usage.total))
        sqlite3_bind_int(statement, 7, Int32(usage.cachedInput))
        sqlite3_bind_int(statement, 8, Int32(usage.cacheCreationInput))
        sqlite3_bind_int(statement, 9, Int32(usage.reasoning))
        bindText(isoFormatter.string(from: Date()), at: 10, statement: statement)

        _ = sqlite3_step(statement)
#endif
    }

    /// Lists token usage records with optional filters.
    public func listTokenUsage(channelId: String?, taskId: String?, from: Date?, to: Date?) async -> [TokenUsageRecord] {
#if canImport(CSQLite3)
        guard let db else { return [] }

        var conditions: [String] = []
        if channelId != nil { conditions.append("channel_id = ?") }
        if taskId != nil { conditions.append("task_id = ?") }
        if from != nil { conditions.append("created_at >= ?") }
        if to != nil { conditions.append("created_at <= ?") }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

        let sql =
            """
            SELECT id, channel_id, task_id, prompt_tokens, completion_tokens, total_tokens,
                   cached_input_tokens, cache_creation_input_tokens, reasoning_tokens, created_at
            FROM token_usage
            \(whereClause)
            ORDER BY created_at DESC
            LIMIT 1000;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var paramIndex: Int32 = 1
        if let channelId {
            bindText(channelId, at: paramIndex, statement: statement)
            paramIndex += 1
        }
        if let taskId {
            bindOptionalText(taskId, at: paramIndex, statement: statement)
            paramIndex += 1
        }
        if let from {
            bindText(isoFormatter.string(from: from), at: paramIndex, statement: statement)
            paramIndex += 1
        }
        if let to {
            bindText(isoFormatter.string(from: to), at: paramIndex, statement: statement)
        }

        var result: [TokenUsageRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let channelIdPtr = sqlite3_column_text(statement, 1),
                let createdAtPtr = sqlite3_column_text(statement, 9)
            else {
                continue
            }

            let id = String(cString: idPtr)
            let recordChannelId = String(cString: channelIdPtr)
            let taskId = optionalText(statement: statement, index: 2)
            let promptTokens = Int(sqlite3_column_int(statement, 3))
            let completionTokens = Int(sqlite3_column_int(statement, 4))
            let totalTokens = Int(sqlite3_column_int(statement, 5))
            let cachedInputTokens = Int(sqlite3_column_int(statement, 6))
            let cacheCreationInputTokens = Int(sqlite3_column_int(statement, 7))
            let reasoningTokens = Int(sqlite3_column_int(statement, 8))
            let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()

            result.append(
                TokenUsageRecord(
                    id: id,
                    channelId: recordChannelId,
                    taskId: taskId,
                    promptTokens: promptTokens,
                    completionTokens: completionTokens,
                    totalTokens: totalTokens,
                    cachedInputTokens: cachedInputTokens,
                    cacheCreationInputTokens: cacheCreationInputTokens,
                    reasoningTokens: reasoningTokens,
                    createdAt: createdAt
                )
            )
        }

        return result
#else
        return []
#endif
    }

    public func listTokenUsage(channelIds: [String], from: Date?, to: Date?) async -> [TokenUsageRecord] {
#if canImport(CSQLite3)
        guard let db else { return [] }
        guard !channelIds.isEmpty else { return [] }

        var conditions: [String] = []
        let placeholders = channelIds.map { _ in "?" }.joined(separator: ", ")
        conditions.append("channel_id IN (\(placeholders))")
        if from != nil { conditions.append("created_at >= ?") }
        if to != nil { conditions.append("created_at <= ?") }
        let whereClause = "WHERE " + conditions.joined(separator: " AND ")

        let sql =
            """
            SELECT id, channel_id, task_id, prompt_tokens, completion_tokens, total_tokens,
                   cached_input_tokens, cache_creation_input_tokens, reasoning_tokens, created_at
            FROM token_usage
            \(whereClause)
            ORDER BY created_at DESC
            LIMIT 2000;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var paramIndex: Int32 = 1
        for id in channelIds {
            bindText(id, at: paramIndex, statement: statement)
            paramIndex += 1
        }
        if let from {
            bindText(isoFormatter.string(from: from), at: paramIndex, statement: statement)
            paramIndex += 1
        }
        if let to {
            bindText(isoFormatter.string(from: to), at: paramIndex, statement: statement)
        }

        var result: [TokenUsageRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let channelIdPtr = sqlite3_column_text(statement, 1),
                let createdAtPtr = sqlite3_column_text(statement, 9)
            else {
                continue
            }

            let id = String(cString: idPtr)
            let recordChannelId = String(cString: channelIdPtr)
            let taskId = optionalText(statement: statement, index: 2)
            let promptTokens = Int(sqlite3_column_int(statement, 3))
            let completionTokens = Int(sqlite3_column_int(statement, 4))
            let totalTokens = Int(sqlite3_column_int(statement, 5))
            let cachedInputTokens = Int(sqlite3_column_int(statement, 6))
            let cacheCreationInputTokens = Int(sqlite3_column_int(statement, 7))
            let reasoningTokens = Int(sqlite3_column_int(statement, 8))
            let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()

            result.append(
                TokenUsageRecord(
                    id: id,
                    channelId: recordChannelId,
                    taskId: taskId,
                    promptTokens: promptTokens,
                    completionTokens: completionTokens,
                    totalTokens: totalTokens,
                    cachedInputTokens: cachedInputTokens,
                    cacheCreationInputTokens: cacheCreationInputTokens,
                    reasoningTokens: reasoningTokens,
                    createdAt: createdAt
                )
            )
        }

        return result
#else
        return []
#endif
    }

    public func persistSemanticDecisionUsage(record: SemanticDecisionUsageRecord) async {
#if canImport(CSQLite3)
        guard let db else {
            fallbackSemanticDecisionUsages.append(record)
            return
        }
        let sql = """
            INSERT INTO semantic_decision_usage(
                id, channel_id, input_tokens, output_tokens, cost_usd, cost_is_estimated, created_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            fallbackSemanticDecisionUsages.append(record)
            return
        }
        defer { sqlite3_finalize(statement) }
        bindText(record.id, at: 1, statement: statement)
        bindText(record.channelId, at: 2, statement: statement)
        sqlite3_bind_int64(statement, 3, Int64(record.inputTokens))
        sqlite3_bind_int64(statement, 4, Int64(record.outputTokens))
        sqlite3_bind_double(statement, 5, record.costUSD)
        sqlite3_bind_int(statement, 6, record.costIsEstimated ? 1 : 0)
        bindText(isoFormatter.string(from: record.createdAt), at: 7, statement: statement)
        if sqlite3_step(statement) != SQLITE_DONE {
            fallbackSemanticDecisionUsages.append(record)
        }
#else
        fallbackSemanticDecisionUsages.append(record)
#endif
    }

    public func listSemanticDecisionUsage(channelId: String?, from: Date?, to: Date?) async -> [SemanticDecisionUsageRecord] {
        let fallback = fallbackSemanticDecisionUsages.filter { record in
            if let channelId, record.channelId != channelId { return false }
            if let from, record.createdAt < from { return false }
            if let to, record.createdAt > to { return false }
            return true
        }
#if canImport(CSQLite3)
        guard let db else { return fallback }
        var conditions: [String] = []
        if channelId != nil { conditions.append("channel_id = ?") }
        if from != nil { conditions.append("created_at >= ?") }
        if to != nil { conditions.append("created_at <= ?") }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let sql = """
            SELECT id, channel_id, input_tokens, output_tokens, cost_usd, cost_is_estimated, created_at
            FROM semantic_decision_usage
            \(whereClause)
            ORDER BY created_at DESC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return fallback }
        defer { sqlite3_finalize(statement) }
        var parameterIndex: Int32 = 1
        if let channelId {
            bindText(channelId, at: parameterIndex, statement: statement)
            parameterIndex += 1
        }
        if let from {
            bindText(isoFormatter.string(from: from), at: parameterIndex, statement: statement)
            parameterIndex += 1
        }
        if let to {
            bindText(isoFormatter.string(from: to), at: parameterIndex, statement: statement)
        }
        var records = fallback
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPointer = sqlite3_column_text(statement, 0),
                  let channelPointer = sqlite3_column_text(statement, 1),
                  let datePointer = sqlite3_column_text(statement, 6),
                  let createdAt = isoFormatter.date(from: String(cString: datePointer))
            else { continue }
            records.append(SemanticDecisionUsageRecord(
                id: String(cString: idPointer),
                channelId: String(cString: channelPointer),
                inputTokens: Int(sqlite3_column_int64(statement, 2)),
                outputTokens: Int(sqlite3_column_int64(statement, 3)),
                costUSD: sqlite3_column_double(statement, 4),
                costIsEstimated: sqlite3_column_int(statement, 5) != 0,
                createdAt: createdAt
            ))
        }
        return records
#else
        return fallback
#endif
    }

    public func persistToolInvocation(
        id: String,
        projectId: String?,
        taskId: String?,
        agentId: String,
        sessionId: String,
        tool: String,
        ok: Bool,
        durationMs: Int?,
        traceId: String?,
        createdAt: Date
    ) async {
#if canImport(CSQLite3)
        guard let db else { return }

        let sql =
            """
            INSERT INTO tool_invocations(
                id,
                project_id,
                task_id,
                agent_id,
                session_id,
                tool,
                ok,
                duration_ms,
                trace_id,
                created_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        bindText(id, at: 1, statement: statement)
        bindOptionalText(projectId, at: 2, statement: statement)
        bindOptionalText(taskId, at: 3, statement: statement)
        bindText(agentId, at: 4, statement: statement)
        bindText(sessionId, at: 5, statement: statement)
        bindText(tool, at: 6, statement: statement)
        sqlite3_bind_int(statement, 7, ok ? 1 : 0)
        if let durationMs {
            sqlite3_bind_int(statement, 8, Int32(durationMs))
        } else {
            sqlite3_bind_null(statement, 8)
        }
        bindOptionalText(traceId, at: 9, statement: statement)
        bindText(isoFormatter.string(from: createdAt), at: 10, statement: statement)

        _ = sqlite3_step(statement)
#endif
    }

    public func persistProjectEventFact(
        id: String,
        projectId: String,
        channelId: String,
        messageType: String,
        traceId: String?,
        createdAt: Date
    ) async {
#if canImport(CSQLite3)
        guard let db else { return }

        let sql =
            """
            INSERT INTO project_event_facts(
                id,
                project_id,
                channel_id,
                message_type,
                trace_id,
                created_at
            ) VALUES(?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        bindText(id, at: 1, statement: statement)
        bindText(projectId, at: 2, statement: statement)
        bindText(channelId, at: 3, statement: statement)
        bindText(messageType, at: 4, statement: statement)
        bindOptionalText(traceId, at: 5, statement: statement)
        bindText(isoFormatter.string(from: createdAt), at: 6, statement: statement)

        _ = sqlite3_step(statement)
#endif
    }

    public func listProjectEventCounts(projectId: String, from: Date?, to: Date?) async -> [String: Int] {
#if canImport(CSQLite3)
        guard let db else { return [:] }

        var conditions: [String] = ["project_id = ?"]
        if from != nil { conditions.append("created_at >= ?") }
        if to != nil { conditions.append("created_at <= ?") }
        let whereClause = "WHERE " + conditions.joined(separator: " AND ")

        let sql =
            """
            SELECT message_type, COUNT(*)
            FROM project_event_facts
            \(whereClause)
            GROUP BY message_type;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }

        var paramIndex: Int32 = 1
        bindText(projectId, at: paramIndex, statement: statement)
        paramIndex += 1
        if let from {
            bindText(isoFormatter.string(from: from), at: paramIndex, statement: statement)
            paramIndex += 1
        }
        if let to {
            bindText(isoFormatter.string(from: to), at: paramIndex, statement: statement)
        }

        var result: [String: Int] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let typePtr = sqlite3_column_text(statement, 0) else { continue }
            let type = String(cString: typePtr)
            let count = Int(sqlite3_column_int(statement, 1))
            result[type] = count
        }
        return result
#else
        return [:]
#endif
    }

    public func listToolInvocationAggregates(projectId: String, from: Date?, to: Date?) async -> [PersistedToolInvocationAggregate] {
#if canImport(CSQLite3)
        guard let db else { return [] }

        var conditions: [String] = ["project_id = ?"]
        if from != nil { conditions.append("created_at >= ?") }
        if to != nil { conditions.append("created_at <= ?") }
        let whereClause = "WHERE " + conditions.joined(separator: " AND ")

        let sql =
            """
            SELECT tool,
                   COUNT(*) AS calls,
                   SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS failures,
                   COALESCE(SUM(COALESCE(duration_ms, 0)), 0) AS total_duration
            FROM tool_invocations
            \(whereClause)
            GROUP BY tool;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var paramIndex: Int32 = 1
        bindText(projectId, at: paramIndex, statement: statement)
        paramIndex += 1
        if let from {
            bindText(isoFormatter.string(from: from), at: paramIndex, statement: statement)
            paramIndex += 1
        }
        if let to {
            bindText(isoFormatter.string(from: to), at: paramIndex, statement: statement)
        }

        var result: [PersistedToolInvocationAggregate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let toolPtr = sqlite3_column_text(statement, 0) else { continue }
            let tool = String(cString: toolPtr)
            let calls = Int(sqlite3_column_int(statement, 1))
            let failures = Int(sqlite3_column_int(statement, 2))
            let totalDuration = Int(sqlite3_column_int(statement, 3))
            result.append(.init(tool: tool, calls: calls, failures: failures, totalDurationMs: totalDuration))
        }
        return result
#else
        return []
#endif
    }

    public func listToolInvocations(projectId: String?, taskId: String?, limit: Int) async -> [PersistedToolInvocationRecord] {
#if canImport(CSQLite3)
        guard let db else { return [] }

        var conditions: [String] = []
        if projectId != nil { conditions.append("project_id = ?") }
        if taskId != nil { conditions.append("task_id = ?") }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let clampedLimit = max(1, min(limit, 500))

        let sql =
            """
            SELECT id, project_id, task_id, agent_id, session_id, tool, ok, duration_ms, trace_id, created_at
            FROM tool_invocations
            \(whereClause)
            ORDER BY created_at DESC
            LIMIT \(clampedLimit);
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var paramIndex: Int32 = 1
        if let projectId {
            bindText(projectId, at: paramIndex, statement: statement)
            paramIndex += 1
        }
        if let taskId {
            bindText(taskId, at: paramIndex, statement: statement)
        }

        var result: [PersistedToolInvocationRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(statement, 0),
                  let agentPtr = sqlite3_column_text(statement, 3),
                  let sessionPtr = sqlite3_column_text(statement, 4),
                  let toolPtr = sqlite3_column_text(statement, 5),
                  let createdAtPtr = sqlite3_column_text(statement, 9)
            else { continue }

            let durationMs: Int?
            if sqlite3_column_type(statement, 7) == SQLITE_NULL {
                durationMs = nil
            } else {
                durationMs = Int(sqlite3_column_int(statement, 7))
            }

            result.append(PersistedToolInvocationRecord(
                id: String(cString: idPtr),
                projectId: sqlite3_column_text(statement, 1).map { String(cString: $0) },
                taskId: sqlite3_column_text(statement, 2).map { String(cString: $0) },
                agentId: String(cString: agentPtr),
                sessionId: String(cString: sessionPtr),
                tool: String(cString: toolPtr),
                ok: sqlite3_column_int(statement, 6) != 0,
                durationMs: durationMs,
                traceId: sqlite3_column_text(statement, 8).map { String(cString: $0) },
                createdAt: isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
            ))
        }
        return result
#else
        return []
#endif
    }

    public func listToolInvocationDurations(projectId: String, from: Date?, to: Date?, limit: Int) async -> [Int] {
#if canImport(CSQLite3)
        guard let db else { return [] }

        var conditions: [String] = ["project_id = ?"]
        if from != nil { conditions.append("created_at >= ?") }
        if to != nil { conditions.append("created_at <= ?") }
        conditions.append("duration_ms IS NOT NULL")
        let whereClause = "WHERE " + conditions.joined(separator: " AND ")
        let clampedLimit = max(1, min(limit, 20_000))

        let sql =
            """
            SELECT duration_ms
            FROM tool_invocations
            \(whereClause)
            ORDER BY created_at DESC
            LIMIT \(clampedLimit);
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var paramIndex: Int32 = 1
        bindText(projectId, at: paramIndex, statement: statement)
        paramIndex += 1
        if let from {
            bindText(isoFormatter.string(from: from), at: paramIndex, statement: statement)
            paramIndex += 1
        }
        if let to {
            bindText(isoFormatter.string(from: to), at: paramIndex, statement: statement)
        }

        var result: [Int] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(Int(sqlite3_column_int(statement, 0)))
        }
        return result
#else
        return []
#endif
    }
}
