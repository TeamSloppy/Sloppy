import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
#endif

extension SQLiteStore {
    public func upsertSelfImprovementProposalReviewJob(
        agentId: String,
        sessionId: String,
        projectId: String,
        reason: String,
        reviewContext: String?,
        nextRunAt: Date
    ) async -> SelfImprovementProposalReviewJob {
        let now = Date()
#if canImport(CSQLite3)
        guard let db else {
            return upsertFallbackSelfImprovementProposalReviewJob(
                agentId: agentId,
                sessionId: sessionId,
                projectId: projectId,
                reason: reason,
                reviewContext: reviewContext,
                nextRunAt: nextRunAt,
                now: now
            )
        }
        if var existing = loadSelfImprovementProposalReviewJob(
            db: db,
            agentId: agentId,
            sessionId: sessionId,
            reason: reason
        ) {
            existing.projectId = projectId
            existing.reviewContext = reviewContext
            existing.status = "pending"
            existing.nextRunAt = nextRunAt
            existing.lastError = nil
            existing.updatedAt = now
            await saveSelfImprovementProposalReviewJob(existing)
            return existing
        }
#endif
        let job = SelfImprovementProposalReviewJob(
            id: UUID().uuidString.lowercased(),
            agentId: agentId,
            sessionId: sessionId,
            projectId: projectId,
            reason: reason,
            reviewContext: reviewContext,
            nextRunAt: nextRunAt,
            createdAt: now,
            updatedAt: now
        )
        await saveSelfImprovementProposalReviewJob(job)
        return job
    }

    public func listSelfImprovementProposalReviewJobs(statuses: [String]?) async -> [SelfImprovementProposalReviewJob] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackSelfImprovementProposalReviewJobs(statuses: statuses)
        }
        var sql =
            """
            SELECT id, agent_id, session_id, project_id, reason, review_context, status, attempts, next_run_at, last_error, created_at, updated_at
            FROM self_improvement_proposal_review_queue
            """
        if let statuses, !statuses.isEmpty {
            sql += " WHERE status IN (\(Array(repeating: "?", count: statuses.count).joined(separator: ",")))"
        }
        sql += " ORDER BY created_at ASC;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        if let statuses {
            for (index, status) in statuses.enumerated() {
                bindText(status, at: Int32(index + 1), statement: statement)
            }
        }
        var jobs: [SelfImprovementProposalReviewJob] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let job = decodeSelfImprovementProposalReviewJob(statement: statement) {
                jobs.append(job)
            }
        }
        return jobs
#else
        return fallbackSelfImprovementProposalReviewJobs(statuses: statuses)
#endif
    }

    public func claimNextSelfImprovementProposalReviewJob(now: Date) async -> SelfImprovementProposalReviewJob? {
#if canImport(CSQLite3)
        guard let db else {
            return claimFallbackSelfImprovementProposalReviewJob(now: now)
        }
        let sql =
            """
            SELECT id, agent_id, session_id, project_id, reason, review_context, status, attempts, next_run_at, last_error, created_at, updated_at
            FROM self_improvement_proposal_review_queue
            WHERE status = 'pending' AND next_run_at <= ?
            ORDER BY next_run_at ASC, created_at ASC
            LIMIT 1;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(isoFormatter.string(from: now), at: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              var job = decodeSelfImprovementProposalReviewJob(statement: statement)
        else { return nil }
        job.status = "running"
        job.updatedAt = now
        await saveSelfImprovementProposalReviewJob(job)
        return job
#else
        return claimFallbackSelfImprovementProposalReviewJob(now: now)
#endif
    }

    public func saveSelfImprovementProposalReviewJob(_ job: SelfImprovementProposalReviewJob) async {
        fallbackSelfImprovementProposalReviewJobs[job.id] = job
#if canImport(CSQLite3)
        guard let db else { return }
        let sql =
            """
            INSERT OR REPLACE INTO self_improvement_proposal_review_queue(
                id, agent_id, session_id, project_id, reason, review_context, status, attempts, next_run_at, last_error, created_at, updated_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(job.id, at: 1, statement: statement)
        bindText(job.agentId, at: 2, statement: statement)
        bindText(job.sessionId, at: 3, statement: statement)
        bindText(job.projectId, at: 4, statement: statement)
        bindText(job.reason, at: 5, statement: statement)
        bindOptionalText(job.reviewContext, at: 6, statement: statement)
        bindText(job.status, at: 7, statement: statement)
        sqlite3_bind_int(statement, 8, Int32(job.attempts))
        bindText(isoFormatter.string(from: job.nextRunAt), at: 9, statement: statement)
        bindOptionalText(job.lastError, at: 10, statement: statement)
        bindText(isoFormatter.string(from: job.createdAt), at: 11, statement: statement)
        bindText(isoFormatter.string(from: job.updatedAt), at: 12, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

    public func autodreamSessionReview(agentId: String, sessionId: String) async -> AutodreamSessionReviewRecord? {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackAutodreamSessionReviews[autodreamSessionReviewKey(agentId: agentId, sessionId: sessionId)]
        }
        let sql =
            """
            SELECT agent_id, session_id, status, reason, session_updated_at, reviewed_at, last_error
            FROM autodream_session_reviews
            WHERE agent_id = ? AND session_id = ?
            LIMIT 1;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(agentId, at: 1, statement: statement)
        bindText(sessionId, at: 2, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return decodeAutodreamSessionReview(statement: statement)
#else
        return fallbackAutodreamSessionReviews[autodreamSessionReviewKey(agentId: agentId, sessionId: sessionId)]
#endif
    }

    public func saveAutodreamSessionReview(_ record: AutodreamSessionReviewRecord) async {
        fallbackAutodreamSessionReviews[autodreamSessionReviewKey(agentId: record.agentId, sessionId: record.sessionId)] = record
#if canImport(CSQLite3)
        guard let db else { return }
        let sql =
            """
            INSERT OR REPLACE INTO autodream_session_reviews(
                agent_id, session_id, status, reason, session_updated_at, reviewed_at, last_error
            ) VALUES(?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(record.agentId, at: 1, statement: statement)
        bindText(record.sessionId, at: 2, statement: statement)
        bindText(record.status, at: 3, statement: statement)
        bindText(record.reason, at: 4, statement: statement)
        bindText(isoFormatter.string(from: record.sessionUpdatedAt), at: 5, statement: statement)
        bindText(isoFormatter.string(from: record.reviewedAt), at: 6, statement: statement)
        bindOptionalText(record.lastError, at: 7, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

#if canImport(CSQLite3)
    func fallbackSelfImprovementProposalReviewJobs(statuses: [String]?) -> [SelfImprovementProposalReviewJob] {
        let allowed = statuses.map(Set.init)
        return fallbackSelfImprovementProposalReviewJobs.values
            .filter { job in allowed?.contains(job.status) ?? true }
            .sorted { $0.createdAt < $1.createdAt }
    }
#endif

#if canImport(CSQLite3)
    func upsertFallbackSelfImprovementProposalReviewJob(
        agentId: String,
        sessionId: String,
        projectId: String,
        reason: String,
        reviewContext: String?,
        nextRunAt: Date,
        now: Date
    ) -> SelfImprovementProposalReviewJob {
        if var existing = fallbackSelfImprovementProposalReviewJobs.values.first(where: {
            $0.agentId == agentId && $0.sessionId == sessionId && $0.reason == reason
        }) {
            existing.projectId = projectId
            existing.reviewContext = reviewContext
            existing.status = "pending"
            existing.nextRunAt = nextRunAt
            existing.lastError = nil
            existing.updatedAt = now
            fallbackSelfImprovementProposalReviewJobs[existing.id] = existing
            return existing
        }
        let job = SelfImprovementProposalReviewJob(
            id: UUID().uuidString.lowercased(),
            agentId: agentId,
            sessionId: sessionId,
            projectId: projectId,
            reason: reason,
            reviewContext: reviewContext,
            nextRunAt: nextRunAt,
            createdAt: now,
            updatedAt: now
        )
        fallbackSelfImprovementProposalReviewJobs[job.id] = job
        return job
    }
#endif

#if canImport(CSQLite3)
    func claimFallbackSelfImprovementProposalReviewJob(now: Date) -> SelfImprovementProposalReviewJob? {
        guard var job = fallbackSelfImprovementProposalReviewJobs.values
            .filter({ $0.status == "pending" && $0.nextRunAt <= now })
            .sorted(by: { $0.nextRunAt < $1.nextRunAt })
            .first
        else { return nil }
        job.status = "running"
        job.updatedAt = now
        fallbackSelfImprovementProposalReviewJobs[job.id] = job
        return job
    }
#endif

#if canImport(CSQLite3)
    func decodeSelfImprovementProposalReviewJob(statement: OpaquePointer?) -> SelfImprovementProposalReviewJob? {
        guard
            let idPtr = sqlite3_column_text(statement, 0),
            let agentPtr = sqlite3_column_text(statement, 1),
            let sessionPtr = sqlite3_column_text(statement, 2),
            let projectPtr = sqlite3_column_text(statement, 3),
            let reasonPtr = sqlite3_column_text(statement, 4),
            let statusPtr = sqlite3_column_text(statement, 6),
            let nextRunPtr = sqlite3_column_text(statement, 8),
            let createdAtPtr = sqlite3_column_text(statement, 10),
            let updatedAtPtr = sqlite3_column_text(statement, 11)
        else {
            return nil
        }
        let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
        return SelfImprovementProposalReviewJob(
            id: String(cString: idPtr),
            agentId: String(cString: agentPtr),
            sessionId: String(cString: sessionPtr),
            projectId: String(cString: projectPtr),
            reason: String(cString: reasonPtr),
            reviewContext: optionalText(statement: statement, index: 5),
            status: String(cString: statusPtr),
            attempts: Int(sqlite3_column_int(statement, 7)),
            nextRunAt: isoFormatter.date(from: String(cString: nextRunPtr)) ?? Date(),
            lastError: optionalText(statement: statement, index: 9),
            createdAt: createdAt,
            updatedAt: isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt
        )
    }
#endif

#if canImport(CSQLite3)
    func loadSelfImprovementProposalReviewJob(
        db: OpaquePointer,
        agentId: String,
        sessionId: String,
        reason: String
    ) -> SelfImprovementProposalReviewJob? {
        let sql =
            """
            SELECT id, agent_id, session_id, project_id, reason, review_context, status, attempts, next_run_at, last_error, created_at, updated_at
            FROM self_improvement_proposal_review_queue
            WHERE agent_id = ? AND session_id = ? AND reason = ?
            LIMIT 1;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(agentId, at: 1, statement: statement)
        bindText(sessionId, at: 2, statement: statement)
        bindText(reason, at: 3, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return decodeSelfImprovementProposalReviewJob(statement: statement)
    }
#endif

#if canImport(CSQLite3)
    func decodeAutodreamSessionReview(statement: OpaquePointer?) -> AutodreamSessionReviewRecord? {
        guard
            let agentPtr = sqlite3_column_text(statement, 0),
            let sessionPtr = sqlite3_column_text(statement, 1),
            let statusPtr = sqlite3_column_text(statement, 2),
            let reasonPtr = sqlite3_column_text(statement, 3),
            let sessionUpdatedAtPtr = sqlite3_column_text(statement, 4),
            let reviewedAtPtr = sqlite3_column_text(statement, 5)
        else {
            return nil
        }
        let reviewedAt = isoFormatter.date(from: String(cString: reviewedAtPtr)) ?? Date()
        return AutodreamSessionReviewRecord(
            agentId: String(cString: agentPtr),
            sessionId: String(cString: sessionPtr),
            status: String(cString: statusPtr),
            reason: String(cString: reasonPtr),
            sessionUpdatedAt: isoFormatter.date(from: String(cString: sessionUpdatedAtPtr)) ?? reviewedAt,
            reviewedAt: reviewedAt,
            lastError: optionalText(statement: statement, index: 6)
        )
    }
#endif

#if canImport(CSQLite3)
    func encodedStringArray(_ values: [String]) -> String {
        let encoded = (try? JSONEncoder().encode(values)) ?? Data("[]".utf8)
        return String(data: encoded, encoding: .utf8) ?? "[]"
    }
#endif

#if canImport(CSQLite3)
    func decodeOptionalStringArray(_ raw: String?) -> [String]? {
        guard let raw, !raw.isEmpty else {
            return nil
        }
        guard let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            return nil
        }
        return values.isEmpty ? nil : values
    }
#endif

    func autodreamSessionReviewKey(agentId: String, sessionId: String) -> String {
        "\(agentId)::\(sessionId)"
    }
}
