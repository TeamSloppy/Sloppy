import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
#endif

extension SQLiteStore {
    public func saveWorkflowRun(_ run: WorkflowRun) async {
#if canImport(CSQLite3)
        guard let db else {
            fallbackWorkflowRuns[run.id] = run
            return
        }
        let sql =
            """
            INSERT OR REPLACE INTO workflow_runs(
                id, workflow_id, workflow_version, project_id, task_id, status,
                current_node_ids_json, started_by, started_at, finished_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            fallbackWorkflowRuns[run.id] = run
            return
        }
        defer { sqlite3_finalize(statement) }

        bindText(run.id, at: 1, statement: statement)
        bindText(run.workflowId, at: 2, statement: statement)
        sqlite3_bind_int(statement, 3, Int32(run.workflowVersion))
        bindText(run.projectId, at: 4, statement: statement)
        bindOptionalText(run.taskId, at: 5, statement: statement)
        bindText(run.status.rawValue, at: 6, statement: statement)
        bindText(jsonString(run.currentNodeIds, fallback: "[]"), at: 7, statement: statement)
        bindText(run.startedBy, at: 8, statement: statement)
        bindText(isoFormatter.string(from: run.startedAt), at: 9, statement: statement)
        bindOptionalText(run.finishedAt.map { isoFormatter.string(from: $0) }, at: 10, statement: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            fallbackWorkflowRuns[run.id] = run
        }
#else
        fallbackWorkflowRuns[run.id] = run
#endif
    }

    public func listWorkflowRuns(projectId: String) async -> [WorkflowRun] {
#if canImport(CSQLite3)
        guard let db else { return fallbackWorkflowRuns(projectId: projectId) }
        let sql =
            """
            SELECT id, workflow_id, workflow_version, project_id, task_id, status, current_node_ids_json, started_by, started_at, finished_at
            FROM workflow_runs
            WHERE project_id = ?
            ORDER BY started_at DESC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(projectId, at: 1, statement: statement)
        var result: [WorkflowRun] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let run = decodeWorkflowRun(statement: statement) {
                result.append(run)
            }
        }
        return result
#else
        return fallbackWorkflowRuns(projectId: projectId)
#endif
    }

    public func getWorkflowRun(id: String) async -> WorkflowRun? {
#if canImport(CSQLite3)
        guard let db else { return fallbackWorkflowRuns[id] }
        let sql =
            """
            SELECT id, workflow_id, workflow_version, project_id, task_id, status, current_node_ids_json, started_by, started_at, finished_at
            FROM workflow_runs
            WHERE id = ?;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return decodeWorkflowRun(statement: statement)
#else
        return fallbackWorkflowRuns[id]
#endif
    }

    public func saveWorkflowRunStep(_ step: WorkflowRunStep) async {
#if canImport(CSQLite3)
        guard let db else {
            fallbackWorkflowRunSteps[step.id] = step
            return
        }
        let sql =
            """
            INSERT OR REPLACE INTO workflow_run_steps(
                id, run_id, node_id, status, input_json, output_json, error, started_at, finished_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            fallbackWorkflowRunSteps[step.id] = step
            return
        }
        defer { sqlite3_finalize(statement) }
        bindText(step.id, at: 1, statement: statement)
        bindText(step.runId, at: 2, statement: statement)
        bindText(step.nodeId, at: 3, statement: statement)
        bindText(step.status.rawValue, at: 4, statement: statement)
        bindText(jsonString(step.input, fallback: "{}"), at: 5, statement: statement)
        bindText(jsonString(step.output, fallback: "{}"), at: 6, statement: statement)
        bindOptionalText(step.error, at: 7, statement: statement)
        bindText(isoFormatter.string(from: step.startedAt), at: 8, statement: statement)
        bindOptionalText(step.finishedAt.map { isoFormatter.string(from: $0) }, at: 9, statement: statement)
        if sqlite3_step(statement) != SQLITE_DONE {
            fallbackWorkflowRunSteps[step.id] = step
        }
#else
        fallbackWorkflowRunSteps[step.id] = step
#endif
    }

    public func listWorkflowRunSteps(runId: String) async -> [WorkflowRunStep] {
#if canImport(CSQLite3)
        guard let db else { return fallbackWorkflowRunSteps(runId: runId) }
        let sql =
            """
            SELECT id, run_id, node_id, status, input_json, output_json, error, started_at, finished_at
            FROM workflow_run_steps
            WHERE run_id = ?
            ORDER BY started_at ASC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(runId, at: 1, statement: statement)
        var result: [WorkflowRunStep] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let step = decodeWorkflowRunStep(statement: statement) {
                result.append(step)
            }
        }
        return result
#else
        return fallbackWorkflowRunSteps(runId: runId)
#endif
    }

    public func saveWorkflowPendingAction(_ action: WorkflowPendingAction) async {
#if canImport(CSQLite3)
        guard let db else {
            fallbackWorkflowPendingActions[action.id] = action
            return
        }
        let sql =
            """
            INSERT OR REPLACE INTO workflow_pending_actions(
                id, project_id, workflow_run_id, node_id, task_id, assignee, prompt,
                decisions_json, created_at, resolved_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            fallbackWorkflowPendingActions[action.id] = action
            return
        }
        defer { sqlite3_finalize(statement) }
        bindText(action.id, at: 1, statement: statement)
        bindText(action.projectId, at: 2, statement: statement)
        bindText(action.workflowRunId, at: 3, statement: statement)
        bindText(action.nodeId, at: 4, statement: statement)
        bindOptionalText(action.taskId, at: 5, statement: statement)
        bindText(action.assignee, at: 6, statement: statement)
        bindText(action.prompt, at: 7, statement: statement)
        bindText(jsonString(action.decisions, fallback: "[]"), at: 8, statement: statement)
        bindText(isoFormatter.string(from: action.createdAt), at: 9, statement: statement)
        bindOptionalText(action.resolvedAt.map { isoFormatter.string(from: $0) }, at: 10, statement: statement)
        if sqlite3_step(statement) != SQLITE_DONE {
            fallbackWorkflowPendingActions[action.id] = action
        }
#else
        fallbackWorkflowPendingActions[action.id] = action
#endif
    }

    public func listWorkflowPendingActions(projectId: String, includeResolved: Bool) async -> [WorkflowPendingAction] {
#if canImport(CSQLite3)
        guard let db else { return fallbackWorkflowPendingActions(projectId: projectId, includeResolved: includeResolved) }
        let resolvedClause = includeResolved ? "" : "AND resolved_at IS NULL"
        let sql =
            """
            SELECT id, project_id, workflow_run_id, node_id, task_id, assignee, prompt, decisions_json, created_at, resolved_at
            FROM workflow_pending_actions
            WHERE project_id = ? \(resolvedClause)
            ORDER BY created_at DESC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(projectId, at: 1, statement: statement)
        var result: [WorkflowPendingAction] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let action = decodeWorkflowPendingAction(statement: statement) {
                result.append(action)
            }
        }
        return result
#else
        return fallbackWorkflowPendingActions(projectId: projectId, includeResolved: includeResolved)
#endif
    }

    public func listWorkflowPendingActions(runId: String) async -> [WorkflowPendingAction] {
#if canImport(CSQLite3)
        guard let db else { return fallbackWorkflowPendingActions(runId: runId) }
        let sql =
            """
            SELECT id, project_id, workflow_run_id, node_id, task_id, assignee, prompt, decisions_json, created_at, resolved_at
            FROM workflow_pending_actions
            WHERE workflow_run_id = ?
            ORDER BY created_at DESC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(runId, at: 1, statement: statement)
        var result: [WorkflowPendingAction] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let action = decodeWorkflowPendingAction(statement: statement) {
                result.append(action)
            }
        }
        return result
#else
        return fallbackWorkflowPendingActions(runId: runId)
#endif
    }

    public func resolveWorkflowPendingAction(actionId: String, resolvedAt: Date) async -> WorkflowPendingAction? {
#if canImport(CSQLite3)
        guard let db else { return resolveFallbackWorkflowPendingAction(actionId: actionId, resolvedAt: resolvedAt) }
        let sql = "UPDATE workflow_pending_actions SET resolved_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(isoFormatter.string(from: resolvedAt), at: 1, statement: statement)
        bindText(actionId, at: 2, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { return nil }
        return workflowPendingAction(id: actionId)
#else
        return resolveFallbackWorkflowPendingAction(actionId: actionId, resolvedAt: resolvedAt)
#endif
    }

    public func saveAutomationRun(_ run: AutomationRun) async {
#if canImport(CSQLite3)
        guard let db else {
            fallbackAutomationRuns[run.id] = run
            return
        }
        let sql =
            """
            INSERT OR REPLACE INTO automation_runs(
                id, automation_id, project_id, workflow_id, workflow_run_id, repository_full_name,
                trigger_type, trigger_event_id, status, task_id, summary, started_at, finished_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            fallbackAutomationRuns[run.id] = run
            return
        }
        defer { sqlite3_finalize(statement) }

        bindText(run.id, at: 1, statement: statement)
        bindText(run.automationId, at: 2, statement: statement)
        bindText(run.projectId, at: 3, statement: statement)
        bindText(run.workflowId, at: 4, statement: statement)
        bindOptionalText(run.workflowRunId, at: 5, statement: statement)
        bindText(run.repositoryFullName, at: 6, statement: statement)
        bindText(run.triggerType.rawValue, at: 7, statement: statement)
        bindOptionalText(run.triggerEventId, at: 8, statement: statement)
        bindText(run.status.rawValue, at: 9, statement: statement)
        bindOptionalText(run.taskId, at: 10, statement: statement)
        bindOptionalText(run.summary, at: 11, statement: statement)
        bindText(isoFormatter.string(from: run.startedAt), at: 12, statement: statement)
        bindOptionalText(run.finishedAt.map { isoFormatter.string(from: $0) }, at: 13, statement: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            fallbackAutomationRuns[run.id] = run
        }
#else
        fallbackAutomationRuns[run.id] = run
#endif
    }

    public func listAutomationRuns(projectId: String) async -> [AutomationRun] {
#if canImport(CSQLite3)
        guard let db else { return fallbackAutomationRuns(projectId: projectId) }
        let sql =
            """
            SELECT id, automation_id, project_id, workflow_id, workflow_run_id, repository_full_name, trigger_type, trigger_event_id, status, task_id, summary, started_at, finished_at
            FROM automation_runs
            WHERE project_id = ?
            ORDER BY started_at DESC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(projectId, at: 1, statement: statement)
        var result: [AutomationRun] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let run = decodeAutomationRun(statement: statement) {
                result.append(run)
            }
        }
        return result
#else
        return fallbackAutomationRuns(projectId: projectId)
#endif
    }

    public func listAutomationRuns(automationId: String) async -> [AutomationRun] {
#if canImport(CSQLite3)
        guard let db else { return fallbackAutomationRuns(automationId: automationId) }
        let sql =
            """
            SELECT id, automation_id, project_id, workflow_id, workflow_run_id, repository_full_name, trigger_type, trigger_event_id, status, task_id, summary, started_at, finished_at
            FROM automation_runs
            WHERE automation_id = ?
            ORDER BY started_at DESC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(automationId, at: 1, statement: statement)
        var result: [AutomationRun] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let run = decodeAutomationRun(statement: statement) {
                result.append(run)
            }
        }
        return result
#else
        return fallbackAutomationRuns(automationId: automationId)
#endif
    }

    public func getAutomationRun(id: String) async -> AutomationRun? {
#if canImport(CSQLite3)
        guard let db else { return fallbackAutomationRuns[id] }
        let sql =
            """
            SELECT id, automation_id, project_id, workflow_id, workflow_run_id, repository_full_name, trigger_type, trigger_event_id, status, task_id, summary, started_at, finished_at
            FROM automation_runs
            WHERE id = ?;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return decodeAutomationRun(statement: statement)
#else
        return fallbackAutomationRuns[id]
#endif
    }

#if canImport(CSQLite3)
    func fallbackWorkflowRuns(projectId: String) -> [WorkflowRun] {
        fallbackWorkflowRuns.values
            .filter { $0.projectId == projectId }
            .sorted { $0.startedAt > $1.startedAt }
    }
#endif

#if canImport(CSQLite3)
    func fallbackWorkflowRunSteps(runId: String) -> [WorkflowRunStep] {
        fallbackWorkflowRunSteps.values
            .filter { $0.runId == runId }
            .sorted { $0.startedAt < $1.startedAt }
    }
#endif

#if canImport(CSQLite3)
    func fallbackWorkflowPendingActions(projectId: String, includeResolved: Bool) -> [WorkflowPendingAction] {
        fallbackWorkflowPendingActions.values
            .filter { $0.projectId == projectId && (includeResolved || $0.resolvedAt == nil) }
            .sorted { $0.createdAt > $1.createdAt }
    }
#endif

#if canImport(CSQLite3)
    func fallbackWorkflowPendingActions(runId: String) -> [WorkflowPendingAction] {
        fallbackWorkflowPendingActions.values
            .filter { $0.workflowRunId == runId }
            .sorted { $0.createdAt > $1.createdAt }
    }
#endif

#if canImport(CSQLite3)
    func fallbackAutomationRuns(projectId: String) -> [AutomationRun] {
        fallbackAutomationRuns.values
            .filter { $0.projectId == projectId }
            .sorted { $0.startedAt > $1.startedAt }
    }
#endif

#if canImport(CSQLite3)
    func fallbackAutomationRuns(automationId: String) -> [AutomationRun] {
        fallbackAutomationRuns.values
            .filter { $0.automationId == automationId }
            .sorted { $0.startedAt > $1.startedAt }
    }
#endif

#if canImport(CSQLite3)
    func resolveFallbackWorkflowPendingAction(actionId: String, resolvedAt: Date) -> WorkflowPendingAction? {
        guard var action = fallbackWorkflowPendingActions[actionId] else {
            return nil
        }
        action.resolvedAt = resolvedAt
        fallbackWorkflowPendingActions[actionId] = action
        return action
    }
#endif

#if canImport(CSQLite3)
    func workflowPendingAction(id: String) -> WorkflowPendingAction? {
#if canImport(CSQLite3)
        guard let db else { return fallbackWorkflowPendingActions[id] }
        let sql =
            """
            SELECT id, project_id, workflow_run_id, node_id, task_id, assignee, prompt, decisions_json, created_at, resolved_at
            FROM workflow_pending_actions
            WHERE id = ?;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return decodeWorkflowPendingAction(statement: statement)
#else
        return fallbackWorkflowPendingActions[id]
#endif
    }
#endif

#if canImport(CSQLite3)
    func decodeWorkflowRun(statement: OpaquePointer?) -> WorkflowRun? {
        guard
            let idPtr = sqlite3_column_text(statement, 0),
            let workflowIdPtr = sqlite3_column_text(statement, 1),
            let projectIdPtr = sqlite3_column_text(statement, 3),
            let statusPtr = sqlite3_column_text(statement, 5),
            let currentNodeIdsPtr = sqlite3_column_text(statement, 6),
            let startedByPtr = sqlite3_column_text(statement, 7),
            let startedAtPtr = sqlite3_column_text(statement, 8)
        else {
            return nil
        }
        let currentNodeIds = decodeJSON([String].self, from: String(cString: currentNodeIdsPtr), fallback: [])
        let startedAt = isoFormatter.date(from: String(cString: startedAtPtr)) ?? Date()
        let finishedAt = optionalText(statement: statement, index: 9).flatMap { isoFormatter.date(from: $0) }
        return WorkflowRun(
            id: String(cString: idPtr),
            workflowId: String(cString: workflowIdPtr),
            workflowVersion: Int(sqlite3_column_int(statement, 2)),
            projectId: String(cString: projectIdPtr),
            taskId: optionalText(statement: statement, index: 4),
            status: WorkflowRunStatus(rawValue: String(cString: statusPtr)) ?? .failed,
            currentNodeIds: currentNodeIds,
            startedBy: String(cString: startedByPtr),
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }
#endif

#if canImport(CSQLite3)
    func decodeWorkflowRunStep(statement: OpaquePointer?) -> WorkflowRunStep? {
        guard
            let idPtr = sqlite3_column_text(statement, 0),
            let runIdPtr = sqlite3_column_text(statement, 1),
            let nodeIdPtr = sqlite3_column_text(statement, 2),
            let statusPtr = sqlite3_column_text(statement, 3),
            let inputPtr = sqlite3_column_text(statement, 4),
            let outputPtr = sqlite3_column_text(statement, 5),
            let startedAtPtr = sqlite3_column_text(statement, 7)
        else {
            return nil
        }
        let input = decodeJSON([String: JSONValue].self, from: String(cString: inputPtr), fallback: [:])
        let output = decodeJSON([String: JSONValue].self, from: String(cString: outputPtr), fallback: [:])
        let startedAt = isoFormatter.date(from: String(cString: startedAtPtr)) ?? Date()
        let finishedAt = optionalText(statement: statement, index: 8).flatMap { isoFormatter.date(from: $0) }
        return WorkflowRunStep(
            id: String(cString: idPtr),
            runId: String(cString: runIdPtr),
            nodeId: String(cString: nodeIdPtr),
            status: WorkflowStepStatus(rawValue: String(cString: statusPtr)) ?? .failed,
            input: input,
            output: output,
            error: optionalText(statement: statement, index: 6),
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }
#endif

#if canImport(CSQLite3)
    func decodeWorkflowPendingAction(statement: OpaquePointer?) -> WorkflowPendingAction? {
        guard
            let idPtr = sqlite3_column_text(statement, 0),
            let projectIdPtr = sqlite3_column_text(statement, 1),
            let runIdPtr = sqlite3_column_text(statement, 2),
            let nodeIdPtr = sqlite3_column_text(statement, 3),
            let assigneePtr = sqlite3_column_text(statement, 5),
            let promptPtr = sqlite3_column_text(statement, 6),
            let decisionsPtr = sqlite3_column_text(statement, 7),
            let createdAtPtr = sqlite3_column_text(statement, 8)
        else {
            return nil
        }
        let decisions = decodeJSON([WorkflowHumanDecision].self, from: String(cString: decisionsPtr), fallback: [])
        let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
        let resolvedAt = optionalText(statement: statement, index: 9).flatMap { isoFormatter.date(from: $0) }
        return WorkflowPendingAction(
            id: String(cString: idPtr),
            projectId: String(cString: projectIdPtr),
            workflowRunId: String(cString: runIdPtr),
            nodeId: String(cString: nodeIdPtr),
            taskId: optionalText(statement: statement, index: 4),
            assignee: String(cString: assigneePtr),
            prompt: String(cString: promptPtr),
            decisions: decisions,
            createdAt: createdAt,
            resolvedAt: resolvedAt
        )
    }
#endif

#if canImport(CSQLite3)
    func decodeAutomationRun(statement: OpaquePointer?) -> AutomationRun? {
        guard
            let idPtr = sqlite3_column_text(statement, 0),
            let automationIdPtr = sqlite3_column_text(statement, 1),
            let projectIdPtr = sqlite3_column_text(statement, 2),
            let workflowIdPtr = sqlite3_column_text(statement, 3),
            let repositoryPtr = sqlite3_column_text(statement, 5),
            let triggerTypePtr = sqlite3_column_text(statement, 6),
            let statusPtr = sqlite3_column_text(statement, 8),
            let startedAtPtr = sqlite3_column_text(statement, 11)
        else {
            return nil
        }
        let startedAt = isoFormatter.date(from: String(cString: startedAtPtr)) ?? Date()
        let finishedAt = optionalText(statement: statement, index: 12).flatMap { isoFormatter.date(from: $0) }
        return AutomationRun(
            id: String(cString: idPtr),
            automationId: String(cString: automationIdPtr),
            projectId: String(cString: projectIdPtr),
            workflowId: String(cString: workflowIdPtr),
            workflowRunId: optionalText(statement: statement, index: 4),
            repositoryFullName: String(cString: repositoryPtr),
            triggerType: AutomationTriggerKind(rawValue: String(cString: triggerTypePtr)) ?? .manual,
            triggerEventId: optionalText(statement: statement, index: 7),
            status: AutomationRunStatus(rawValue: String(cString: statusPtr)) ?? .failed,
            taskId: optionalText(statement: statement, index: 9),
            summary: optionalText(statement: statement, index: 10),
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }
#endif
}
