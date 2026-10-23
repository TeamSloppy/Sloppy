import Foundation
import Logging

#if canImport(CSQLite3)
import CSQLite3

/// Versioned schema upgrades for `SQLiteStore`.
///
/// `schema.sql` is applied on every open and only creates missing tables. Anything it cannot
/// express for an already-existing database (new columns, data fixes) lives here.
///
/// The database version is stored in `PRAGMA user_version`:
/// - `0`: never migrated. The idempotent baseline below runs once, then the version becomes `1`.
/// - `n`: every entry of `steps` with a greater version runs once, in order, inside a transaction.
///
/// Do not add new statements to the baseline functions: databases already stamped with version `1`
/// never run them again. Append a `Step` instead, and mirror the change in `schema.sql` for fresh databases.
extension SQLiteStore {
    private struct MigrationStep {
        let version: Int
        let name: String
        let statements: [String]
    }

    private final class BaselineReport {
        var failures = 0
    }

    private static let baselineVersion = 1

    /// Ordered upgrades applied after the baseline. Versions must be strictly increasing and start at 2.
    private static let steps: [MigrationStep] = []

    static var latestSchemaVersion: Int {
        steps.last?.version ?? baselineVersion
    }

    private static let migrationLogger = Logger.sloppy(label: "sloppy.sqlite.migrations")

    /// Brings `db` to `latestSchemaVersion`. Returns an error message when an upgrade step fails.
    static func applyMigrations(db: OpaquePointer?) -> String? {
        guard let db else { return nil }

        var version = schemaVersion(db: db)
        if version > latestSchemaVersion {
            migrationLogger.warning(
                "Database schema version \(version) is newer than this build supports (\(latestSchemaVersion)); continuing without migrating"
            )
            return nil
        }

        if version < baselineVersion {
            guard applyBaselineMigrations(db: db) else {
                // Leave the version untouched so the baseline is retried on the next start.
                return nil
            }
            guard setSchemaVersion(baselineVersion, db: db) else {
                return "Failed to record SQLite schema version \(baselineVersion)"
            }
            version = baselineVersion
        }

        for step in steps where step.version > version {
            if let error = apply(step: step, db: db) {
                return "SQLite migration \(step.version) (\(step.name)) failed: \(error)"
            }
        }
        return nil
    }

    static func schemaVersion(db: OpaquePointer?) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func setSchemaVersion(_ version: Int, db: OpaquePointer?) -> Bool {
        sqlite3_exec(db, "PRAGMA user_version = \(version);", nil, nil, nil) == SQLITE_OK
    }

    private static func apply(step: MigrationStep, db: OpaquePointer?) -> String? {
        guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
            return lastError(db: db)
        }
        for statement in step.statements {
            if sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK {
                let message = lastError(db: db)
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                return message
            }
        }
        guard setSchemaVersion(step.version, db: db) else {
            let message = lastError(db: db)
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return message
        }
        guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            let message = lastError(db: db)
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return message
        }
        return nil
    }

    private static func lastError(db: OpaquePointer?) -> String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }

    // MARK: - Baseline (databases created before schema versioning)

    /// Returns `false` when any statement failed for a reason other than "already applied".
    private static func applyBaselineMigrations(db: OpaquePointer?) -> Bool {
        guard let db else { return false }
        let report = BaselineReport()
        applyRuntimeEventMigrations(db: db, report: report)
        applyArtifactMigrations(db: db, report: report)
        applyWorkspaceMigrations(db: db, report: report)
        applyProjectTaskMigrations(db: db, report: report)
        applyInitiativeMigrations(db: db, report: report)
        applyChannelPluginMigrations(db: db, report: report)
        applyWorkflowMigrations(db: db, report: report)
        applyAutomationMigrations(db: db, report: report)
        applyAutodreamMigrations(db: db, report: report)
        applyCronTaskMigrations(db: db, report: report)
        applyTokenUsageMigrations(db: db, report: report)
        applyDashboardProjectsMigrations(db: db, report: report)
        applyClarificationMigrations(db: db, report: report)
        return report.failures == 0
    }

    /// Runs one idempotent baseline statement. Re-adding an existing column is expected and silent;
    /// every other failure is logged and counted.
    private static func runStatement(_ db: OpaquePointer?, _ report: BaselineReport, _ sql: String) {
        guard sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK else { return }
        let message = lastError(db: db)
        if message.hasPrefix("duplicate column name") { return }
        report.failures += 1
        migrationLogger.warning("Baseline migration statement failed: \(message)", metadata: ["sql": "\(sql.prefix(120))"])
    }

    private static func applyProjectTaskMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else {
            return
        }

        let statements = [
            "ALTER TABLE dashboard_project_tasks ADD COLUMN actor_id TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN initiative_id TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN team_id TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN claimed_actor_id TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN claimed_agent_id TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN swarm_id TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN swarm_task_id TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN swarm_parent_task_id TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN swarm_dependency_ids_json TEXT NOT NULL DEFAULT '[]';",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN swarm_depth INTEGER;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN swarm_actor_path_json TEXT NOT NULL DEFAULT '[]';",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN parent_task_id TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN created_by TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN depends_on_task_ids_json TEXT NOT NULL DEFAULT '[]';",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN execution_node_id TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN kanban_column_entered_at TEXT;"
        ]

        for statement in statements {
            runStatement(db, report, statement)
        }
    }
    private static func applyRuntimeEventMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else {
            return
        }
        runStatement(db, report, "ALTER TABLE events ADD COLUMN extensions_json TEXT NOT NULL DEFAULT '{}';")
    }
    private static func applyArtifactMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else {
            return
        }

        let statements = [
            "ALTER TABLE artifacts ADD COLUMN title TEXT;",
            "ALTER TABLE artifacts ADD COLUMN kind TEXT;",
            "ALTER TABLE artifacts ADD COLUMN media_type TEXT;",
            "ALTER TABLE artifacts ADD COLUMN preview_text TEXT;",
            "ALTER TABLE artifacts ADD COLUMN widget_size TEXT;",
            "ALTER TABLE artifacts ADD COLUMN widget_width INTEGER;",
            "ALTER TABLE artifacts ADD COLUMN widget_height INTEGER;",
            "ALTER TABLE artifacts ADD COLUMN widget_entry TEXT;",
            "ALTER TABLE artifacts ADD COLUMN bundle_path TEXT;"
        ]

        for statement in statements {
            runStatement(db, report, statement)
        }
    }
    private static func applyWorkspaceMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else { return }
        runStatement(db, report, """
            CREATE TABLE IF NOT EXISTS session_launch_state (
                agent_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                payload TEXT NOT NULL,
                PRIMARY KEY (agent_id, session_id)
            );

            CREATE TABLE IF NOT EXISTS workspaces (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                cover TEXT,
                owner_id TEXT NOT NULL,
                project_id TEXT,
                revision INTEGER NOT NULL DEFAULT 0,
                is_archived INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_workspaces_project_updated ON workspaces(project_id, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_workspaces_archived_updated ON workspaces(is_archived, updated_at DESC);
            CREATE TABLE IF NOT EXISTS workspace_members (
                workspace_id TEXT NOT NULL,
                principal_kind TEXT NOT NULL,
                principal_id TEXT NOT NULL,
                role TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY(workspace_id, principal_kind, principal_id)
            );
            CREATE TABLE IF NOT EXISTS workspace_snapshots (
                workspace_id TEXT PRIMARY KEY,
                revision INTEGER NOT NULL,
                document_json TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS workspace_transactions (
                workspace_id TEXT NOT NULL,
                id TEXT NOT NULL,
                revision INTEGER NOT NULL,
                transaction_json TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY(workspace_id, id),
                UNIQUE(workspace_id, revision)
            );
            CREATE INDEX IF NOT EXISTS idx_workspace_transactions_revision
                ON workspace_transactions(workspace_id, revision);
            CREATE TABLE IF NOT EXISTS workspace_templates (
                id TEXT PRIMARY KEY,
                visibility TEXT NOT NULL,
                owner_id TEXT,
                template_json TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
    }
    private static func applyInitiativeMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else {
            return
        }

        runStatement(db, report, """
            CREATE TABLE IF NOT EXISTS project_initiatives (
                id TEXT NOT NULL,
                project_id TEXT NOT NULL,
                title TEXT NOT NULL,
                goal TEXT NOT NULL,
                phase TEXT NOT NULL,
                execution_mode TEXT NOT NULL,
                success_metrics_json TEXT NOT NULL DEFAULT '[]',
                constraints_json TEXT NOT NULL DEFAULT '[]',
                resume_point TEXT,
                blocker TEXT,
                metadata_json TEXT NOT NULL DEFAULT '{}',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (project_id, id)
            );
            """)
        runStatement(db, report, "CREATE INDEX IF NOT EXISTS idx_project_initiatives_project ON project_initiatives(project_id, created_at DESC);")
        runStatement(db, report, """
            CREATE TABLE IF NOT EXISTS initiative_decision_packets (
                id TEXT NOT NULL,
                project_id TEXT NOT NULL,
                initiative_id TEXT NOT NULL,
                summary TEXT NOT NULL,
                rationale TEXT NOT NULL,
                tradeoffs_json TEXT NOT NULL DEFAULT '[]',
                requested_action TEXT NOT NULL,
                resume_point TEXT,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (project_id, id)
            );
            """)
        runStatement(db, report, """
            CREATE INDEX IF NOT EXISTS idx_initiative_decision_packets_initiative
            ON initiative_decision_packets(project_id, initiative_id, created_at DESC);
            """)
    }
    private static func applyChannelPluginMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else {
            return
        }
        runStatement(db, report, "ALTER TABLE channel_plugins ADD COLUMN delivery_mode TEXT NOT NULL DEFAULT 'http';")
    }
    private static func applyWorkflowMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else { return }
        runStatement(db, report, """
            CREATE TABLE IF NOT EXISTS workflow_runs (
                id TEXT PRIMARY KEY,
                workflow_id TEXT NOT NULL,
                workflow_version INTEGER NOT NULL,
                project_id TEXT NOT NULL,
                task_id TEXT,
                status TEXT NOT NULL,
                current_node_ids_json TEXT NOT NULL,
                started_by TEXT NOT NULL,
                started_at TEXT NOT NULL,
                finished_at TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_workflow_runs_project ON workflow_runs(project_id, started_at DESC);

            CREATE TABLE IF NOT EXISTS workflow_run_steps (
                id TEXT PRIMARY KEY,
                run_id TEXT NOT NULL,
                node_id TEXT NOT NULL,
                status TEXT NOT NULL,
                input_json TEXT NOT NULL,
                output_json TEXT NOT NULL,
                error TEXT,
                started_at TEXT NOT NULL,
                finished_at TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_workflow_run_steps_run ON workflow_run_steps(run_id, started_at ASC);

            CREATE TABLE IF NOT EXISTS workflow_pending_actions (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                workflow_run_id TEXT NOT NULL,
                node_id TEXT NOT NULL,
                task_id TEXT,
                assignee TEXT NOT NULL,
                prompt TEXT NOT NULL,
                decisions_json TEXT NOT NULL,
                created_at TEXT NOT NULL,
                resolved_at TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_workflow_pending_actions_project ON workflow_pending_actions(project_id, resolved_at, created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_workflow_pending_actions_run ON workflow_pending_actions(workflow_run_id);
            """)
    }
    private static func applyAutomationMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else { return }
        runStatement(db, report, """
            CREATE TABLE IF NOT EXISTS automation_runs (
                id TEXT PRIMARY KEY,
                automation_id TEXT NOT NULL,
                project_id TEXT NOT NULL,
                workflow_id TEXT NOT NULL,
                workflow_run_id TEXT,
                repository_full_name TEXT NOT NULL,
                trigger_type TEXT NOT NULL,
                trigger_event_id TEXT,
                status TEXT NOT NULL,
                task_id TEXT,
                summary TEXT,
                started_at TEXT NOT NULL,
                finished_at TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_automation_runs_project ON automation_runs(project_id, started_at DESC);
            CREATE INDEX IF NOT EXISTS idx_automation_runs_automation ON automation_runs(automation_id, started_at DESC);
            """)
    }
    private static func applyAutodreamMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else { return }
        runStatement(db, report, """
            CREATE TABLE IF NOT EXISTS autodream_session_reviews (
                agent_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                status TEXT NOT NULL,
                reason TEXT NOT NULL,
                session_updated_at TEXT NOT NULL,
                reviewed_at TEXT NOT NULL,
                last_error TEXT,
                PRIMARY KEY(agent_id, session_id)
            );
            CREATE INDEX IF NOT EXISTS idx_autodream_session_reviews_status_reviewed
            ON autodream_session_reviews(status, reviewed_at DESC);
            """)
    }
    private static func applyCronTaskMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else { return }
        runStatement(db, report, """
            CREATE TABLE IF NOT EXISTS agent_cron_tasks(
                id TEXT PRIMARY KEY,
                agent_id TEXT NOT NULL,
                channel_id TEXT NOT NULL,
                schedule TEXT NOT NULL,
                command TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
    }
    private static func applyTokenUsageMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else { return }
        let statements = [
            "ALTER TABLE token_usage ADD COLUMN cached_input_tokens INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE token_usage ADD COLUMN cache_creation_input_tokens INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE token_usage ADD COLUMN reasoning_tokens INTEGER NOT NULL DEFAULT 0;"
        ]
        for statement in statements {
            runStatement(db, report, statement)
        }
    }
    private static func applyClarificationMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else { return }
        runStatement(db, report, """
            CREATE TABLE IF NOT EXISTS task_clarifications (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                task_id TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                target_type TEXT NOT NULL DEFAULT 'human',
                target_actor_id TEXT,
                target_channel_id TEXT,
                question_text TEXT NOT NULL,
                options_json TEXT NOT NULL DEFAULT '[]',
                allow_note INTEGER NOT NULL DEFAULT 1,
                created_by_agent_id TEXT,
                selected_option_ids_json TEXT NOT NULL DEFAULT '[]',
                note TEXT,
                created_at TEXT NOT NULL,
                answered_at TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_task_clarifications_task ON task_clarifications(project_id, task_id);
            """)

        let taskColumnMigrations = [
            "ALTER TABLE dashboard_project_tasks ADD COLUMN kind TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN loop_mode_override TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN origin_type TEXT;",
            "ALTER TABLE dashboard_project_tasks ADD COLUMN origin_channel_id TEXT;"
        ]
        for statement in taskColumnMigrations {
            runStatement(db, report, statement)
        }

        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN task_loop_mode TEXT NOT NULL DEFAULT 'human';")
    }
    private static func applyDashboardProjectsMigrations(db: OpaquePointer?, report: BaselineReport) {
        guard let db else { return }
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN actors_json TEXT NOT NULL DEFAULT '[]';")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN teams_json TEXT NOT NULL DEFAULT '[]';")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN models_json TEXT NOT NULL DEFAULT '[]';")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN agent_files_json TEXT NOT NULL DEFAULT '[]';")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN heartbeat_json TEXT NOT NULL DEFAULT '{\"enabled\":false,\"intervalMinutes\":5}';")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN repo_path TEXT;")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN review_settings_json TEXT NOT NULL DEFAULT '{\"enabled\":false,\"approvalMode\":\"human\"}';")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN automatic_task_pickup_enabled INTEGER NOT NULL DEFAULT 1;")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN autopilot_settings_json TEXT NOT NULL DEFAULT '{}';")
        runStatement(db, report, "ALTER TABLE dashboard_project_tasks ADD COLUMN worktree_branch TEXT;")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN icon TEXT;")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0;")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;")
        runStatement(db, report, "ALTER TABLE dashboard_project_tasks ADD COLUMN selected_model TEXT;")
        runStatement(db, report, "ALTER TABLE dashboard_project_tasks ADD COLUMN stage_assignments_json TEXT;")
        runStatement(db, report, "ALTER TABLE dashboard_project_tasks ADD COLUMN active_stage TEXT;")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN task_sync_settings_json TEXT NOT NULL DEFAULT '{}';")
        runStatement(db, report, "ALTER TABLE dashboard_project_tasks ADD COLUMN attachments_json TEXT NOT NULL DEFAULT '[]';")
        runStatement(db, report, "ALTER TABLE dashboard_project_tasks ADD COLUMN external_metadata_json TEXT;")
        runStatement(db, report, "ALTER TABLE dashboard_project_tasks ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]';")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN source_control_provider_id TEXT;")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN project_kind TEXT NOT NULL DEFAULT 'project';")
        runStatement(db, report, "ALTER TABLE dashboard_projects ADD COLUMN directory_paths_json TEXT NOT NULL DEFAULT '[]';")
        runStatement(db, report, "ALTER TABLE dashboard_project_tasks ADD COLUMN source_control_provider_id TEXT;")
    }
}
#endif
