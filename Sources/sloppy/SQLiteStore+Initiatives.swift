import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
#endif

extension SQLiteStore {
    public func listInitiatives(projectID: String) async -> [InitiativeRecord] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackInitiatives(projectID: projectID)
        }

        let sql =
            """
            SELECT
                id,
                project_id,
                title,
                goal,
                phase,
                execution_mode,
                success_metrics_json,
                constraints_json,
                resume_point,
                blocker,
                metadata_json,
                created_at,
                updated_at
            FROM project_initiatives
            WHERE project_id = ?
            ORDER BY created_at ASC;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return fallbackInitiatives(projectID: projectID)
        }
        defer { sqlite3_finalize(statement) }

        bindText(projectID, at: 1, statement: statement)
        var result: [InitiativeRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let record = initiativeRecord(from: statement) {
                result.append(record)
            }
        }
        return result.isEmpty ? fallbackInitiatives(projectID: projectID) : result
#else
        return fallbackInitiatives(projectID: projectID)
#endif
    }

    public func getInitiative(projectID: String, initiativeID: String) async -> InitiativeRecord? {
#if canImport(CSQLite3)
        if let db {
            let sql =
                """
                SELECT
                    id,
                    project_id,
                    title,
                    goal,
                    phase,
                    execution_mode,
                    success_metrics_json,
                    constraints_json,
                    resume_point,
                    blocker,
                    metadata_json,
                    created_at,
                    updated_at
                FROM project_initiatives
                WHERE project_id = ? AND id = ?
                LIMIT 1;
                """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return fallbackProjectInitiatives[initiativeID]
            }
            defer { sqlite3_finalize(statement) }

            bindText(projectID, at: 1, statement: statement)
            bindText(initiativeID, at: 2, statement: statement)
            if sqlite3_step(statement) == SQLITE_ROW {
                return initiativeRecord(from: statement)
            }
        }
#endif
        guard let record = fallbackProjectInitiatives[initiativeID], record.projectID == projectID else {
            return nil
        }
        return record
    }

    public func saveInitiative(_ record: InitiativeRecord) async {
#if canImport(CSQLite3)
        guard let db else {
            fallbackProjectInitiatives[record.id] = record
            return
        }

        let sql =
            """
            INSERT OR REPLACE INTO project_initiatives(
                id,
                project_id,
                title,
                goal,
                phase,
                execution_mode,
                success_metrics_json,
                constraints_json,
                resume_point,
                blocker,
                metadata_json,
                created_at,
                updated_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            fallbackProjectInitiatives[record.id] = record
            return
        }
        defer { sqlite3_finalize(statement) }

        bindText(record.id, at: 1, statement: statement)
        bindText(record.projectID, at: 2, statement: statement)
        bindText(record.title, at: 3, statement: statement)
        bindText(record.goal, at: 4, statement: statement)
        bindText(record.phase.rawValue, at: 5, statement: statement)
        bindText(record.executionMode.rawValue, at: 6, statement: statement)
        bindText(jsonString(record.successMetrics, fallback: "[]"), at: 7, statement: statement)
        bindText(jsonString(record.constraints, fallback: "[]"), at: 8, statement: statement)
        bindOptionalText(record.resumePoint, at: 9, statement: statement)
        bindOptionalText(record.blocker, at: 10, statement: statement)
        bindText(jsonString(record.metadata, fallback: "{}"), at: 11, statement: statement)
        bindText(isoFormatter.string(from: record.createdAt), at: 12, statement: statement)
        bindText(isoFormatter.string(from: record.updatedAt), at: 13, statement: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            fallbackProjectInitiatives[record.id] = record
            return
        }

        fallbackProjectInitiatives[record.id] = record
#else
        fallbackProjectInitiatives[record.id] = record
#endif
    }

    public func deleteInitiative(projectID: String, initiativeID: String) async -> Bool {
        let removedFallback = fallbackProjectInitiatives.removeValue(forKey: initiativeID)?.projectID == projectID
        fallbackDecisionPacketsByID = fallbackDecisionPacketsByID.filter { _, packet in
            !(packet.projectID == projectID && packet.initiativeID == initiativeID)
        }
#if canImport(CSQLite3)
        guard let db else {
            return removedFallback
        }

        let deletePacketsSQL = "DELETE FROM initiative_decision_packets WHERE project_id = ? AND initiative_id = ?;"
        var packetStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deletePacketsSQL, -1, &packetStatement, nil) == SQLITE_OK {
            bindText(projectID, at: 1, statement: packetStatement)
            bindText(initiativeID, at: 2, statement: packetStatement)
            _ = sqlite3_step(packetStatement)
        }
        sqlite3_finalize(packetStatement)

        let sql = "DELETE FROM project_initiatives WHERE project_id = ? AND id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return removedFallback
        }
        defer { sqlite3_finalize(statement) }

        bindText(projectID, at: 1, statement: statement)
        bindText(initiativeID, at: 2, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            return removedFallback
        }
        return sqlite3_changes(db) > 0 || removedFallback
#else
        return removedFallback
#endif
    }

    public func listDecisionPackets(projectID: String, initiativeID: String) async -> [DecisionPacketRecord] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackDecisionPackets(projectID: projectID, initiativeID: initiativeID)
        }

        let sql =
            """
            SELECT
                id,
                project_id,
                initiative_id,
                summary,
                rationale,
                tradeoffs_json,
                requested_action,
                resume_point,
                status,
                created_at,
                updated_at
            FROM initiative_decision_packets
            WHERE project_id = ? AND initiative_id = ?
            ORDER BY created_at ASC;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return fallbackDecisionPackets(projectID: projectID, initiativeID: initiativeID)
        }
        defer { sqlite3_finalize(statement) }

        bindText(projectID, at: 1, statement: statement)
        bindText(initiativeID, at: 2, statement: statement)
        var result: [DecisionPacketRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let record = decisionPacketRecord(from: statement) {
                result.append(record)
            }
        }
        return result.isEmpty ? fallbackDecisionPackets(projectID: projectID, initiativeID: initiativeID) : result
#else
        return fallbackDecisionPackets(projectID: projectID, initiativeID: initiativeID)
#endif
    }

    public func saveDecisionPacket(_ record: DecisionPacketRecord) async {
#if canImport(CSQLite3)
        guard let db else {
            fallbackDecisionPacketsByID[record.id] = record
            return
        }

        let sql =
            """
            INSERT OR REPLACE INTO initiative_decision_packets(
                id,
                project_id,
                initiative_id,
                summary,
                rationale,
                tradeoffs_json,
                requested_action,
                resume_point,
                status,
                created_at,
                updated_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            fallbackDecisionPacketsByID[record.id] = record
            return
        }
        defer { sqlite3_finalize(statement) }

        bindText(record.id, at: 1, statement: statement)
        bindText(record.projectID, at: 2, statement: statement)
        bindText(record.initiativeID, at: 3, statement: statement)
        bindText(record.summary, at: 4, statement: statement)
        bindText(record.rationale, at: 5, statement: statement)
        bindText(jsonString(record.tradeoffs, fallback: "[]"), at: 6, statement: statement)
        bindText(record.requestedAction, at: 7, statement: statement)
        bindOptionalText(record.resumePoint, at: 8, statement: statement)
        bindText(record.status, at: 9, statement: statement)
        bindText(isoFormatter.string(from: record.createdAt), at: 10, statement: statement)
        bindText(isoFormatter.string(from: record.updatedAt), at: 11, statement: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            fallbackDecisionPacketsByID[record.id] = record
            return
        }

        fallbackDecisionPacketsByID[record.id] = record
#else
        fallbackDecisionPacketsByID[record.id] = record
#endif
    }

#if canImport(CSQLite3)
    func initiativeRecord(from statement: OpaquePointer?) -> InitiativeRecord? {
        guard
            let idPtr = sqlite3_column_text(statement, 0),
            let projectIdPtr = sqlite3_column_text(statement, 1),
            let titlePtr = sqlite3_column_text(statement, 2),
            let goalPtr = sqlite3_column_text(statement, 3),
            let phasePtr = sqlite3_column_text(statement, 4),
            let modePtr = sqlite3_column_text(statement, 5),
            let successMetricsPtr = sqlite3_column_text(statement, 6),
            let constraintsPtr = sqlite3_column_text(statement, 7),
            let metadataPtr = sqlite3_column_text(statement, 10),
            let createdAtPtr = sqlite3_column_text(statement, 11),
            let updatedAtPtr = sqlite3_column_text(statement, 12)
        else {
            return nil
        }

        let phase = InitiativePhase(rawValue: String(cString: phasePtr)) ?? .intake
        let mode = InitiativeExecutionMode(rawValue: String(cString: modePtr)) ?? .singleAgent
        let successMetrics = decodeJSON([String].self, from: String(cString: successMetricsPtr), fallback: [])
        let constraints = decodeJSON([String].self, from: String(cString: constraintsPtr), fallback: [])
        let metadata = decodeJSON([String: String].self, from: String(cString: metadataPtr), fallback: [:])
        let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
        let updatedAt = isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt

        return InitiativeRecord(
            id: String(cString: idPtr),
            projectID: String(cString: projectIdPtr),
            title: String(cString: titlePtr),
            goal: String(cString: goalPtr),
            phase: phase,
            executionMode: mode,
            successMetrics: successMetrics,
            constraints: constraints,
            resumePoint: optionalText(statement: statement, index: 8),
            blocker: optionalText(statement: statement, index: 9),
            metadata: metadata,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
#endif

#if canImport(CSQLite3)
    func decisionPacketRecord(from statement: OpaquePointer?) -> DecisionPacketRecord? {
        guard
            let idPtr = sqlite3_column_text(statement, 0),
            let projectIdPtr = sqlite3_column_text(statement, 1),
            let initiativeIdPtr = sqlite3_column_text(statement, 2),
            let summaryPtr = sqlite3_column_text(statement, 3),
            let rationalePtr = sqlite3_column_text(statement, 4),
            let tradeoffsPtr = sqlite3_column_text(statement, 5),
            let requestedActionPtr = sqlite3_column_text(statement, 6),
            let statusPtr = sqlite3_column_text(statement, 8),
            let createdAtPtr = sqlite3_column_text(statement, 9),
            let updatedAtPtr = sqlite3_column_text(statement, 10)
        else {
            return nil
        }

        let tradeoffs = decodeJSON([String].self, from: String(cString: tradeoffsPtr), fallback: [])
        let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
        let updatedAt = isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt

        return DecisionPacketRecord(
            id: String(cString: idPtr),
            projectID: String(cString: projectIdPtr),
            initiativeID: String(cString: initiativeIdPtr),
            summary: String(cString: summaryPtr),
            rationale: String(cString: rationalePtr),
            tradeoffs: tradeoffs,
            requestedAction: String(cString: requestedActionPtr),
            resumePoint: optionalText(statement: statement, index: 7),
            status: String(cString: statusPtr),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
#endif

#if canImport(CSQLite3)
    func fallbackInitiatives(projectID: String) -> [InitiativeRecord] {
        fallbackProjectInitiatives.values
            .filter { $0.projectID == projectID }
            .sorted { $0.createdAt < $1.createdAt }
    }
#endif

#if canImport(CSQLite3)
    func fallbackDecisionPackets(projectID: String, initiativeID: String) -> [DecisionPacketRecord] {
        fallbackDecisionPacketsByID.values
            .filter { $0.projectID == projectID && $0.initiativeID == initiativeID }
            .sorted { $0.createdAt < $1.createdAt }
    }
#endif
}
