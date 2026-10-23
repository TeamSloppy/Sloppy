import Foundation
import Protocols

#if canImport(CSQLite3)
import CSQLite3
#endif

/// SQLite-backed persistence store.
/// This backend works when the package `CSQLite3` system module can import `sqlite3`,
/// otherwise the actor automatically falls back to in-memory storage.
public actor SQLiteStore: PersistenceStore {
    var fallbackLaunchSessions: [String: LaunchSessionState] = [:]

    public func loadLaunchSessions() async throws -> [LaunchSessionState] {
#if canImport(CSQLite3)
        guard let db else { return Array(fallbackLaunchSessions.values) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM session_launch_state", -1, &statement, nil) == SQLITE_OK else {
            throw ProactivePersistenceError.database
        }
        defer { sqlite3_finalize(statement) }
        var records: [LaunchSessionState] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return records }
            guard result == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
                throw ProactivePersistenceError.database
            }
            records.append(try JSONDecoder().decode(LaunchSessionState.self, from: Data(String(cString: value).utf8)))
        }
#else
        return Array(fallbackLaunchSessions.values)
#endif
    }

    public func saveLaunchSession(_ state: LaunchSessionState) async throws {
#if canImport(CSQLite3)
        guard let db else { fallbackLaunchSessions[state.agentID + ":" + state.sessionID] = state; return }
        let data = try JSONEncoder().encode(state)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO session_launch_state (agent_id, session_id, payload) VALUES (?, ?, ?) ON CONFLICT(agent_id, session_id) DO UPDATE SET payload = excluded.payload", -1, &statement, nil) == SQLITE_OK else {
            throw ProactivePersistenceError.database
        }
        defer { sqlite3_finalize(statement) }
        bindText(state.agentID, at: 1, statement: statement)
        bindText(state.sessionID, at: 2, statement: statement)
        bindText(String(decoding: data, as: UTF8.self), at: 3, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ProactivePersistenceError.database }
#else
        fallbackLaunchSessions[state.agentID + ":" + state.sessionID] = state
#endif
    }

    public func deleteLaunchSession(agentID: String, sessionID: String) async throws {
#if canImport(CSQLite3)
        guard let db else { fallbackLaunchSessions.removeValue(forKey: agentID + ":" + sessionID); return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM session_launch_state WHERE agent_id = ? AND session_id = ?", -1, &statement, nil) == SQLITE_OK else {
            throw ProactivePersistenceError.database
        }
        defer { sqlite3_finalize(statement) }
        bindText(agentID, at: 1, statement: statement)
        bindText(sessionID, at: 2, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ProactivePersistenceError.database }
#else
        fallbackLaunchSessions.removeValue(forKey: agentID + ":" + sessionID)
#endif
    }

    var fallbackProactiveStates: [String: Data] = [:]

    public func loadProactiveState(agentId: String) async throws -> Data? {
#if canImport(CSQLite3)
        guard let db else { return fallbackProactiveStates[agentId] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM agent_proactive_state WHERE agent_id = ?", -1, &statement, nil) == SQLITE_OK else {
            throw ProactivePersistenceError.database
        }
        defer { sqlite3_finalize(statement) }
        bindText(agentId, at: 1, statement: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw ProactivePersistenceError.database }
        return Data(String(cString: text).utf8)
#else
        return fallbackProactiveStates[agentId]
#endif
    }

    public func saveProactiveState(agentId: String, data: Data) async throws {
#if canImport(CSQLite3)
        guard let db else { fallbackProactiveStates[agentId] = data; return }
        guard let payload = String(data: data, encoding: .utf8) else { throw ProactivePersistenceError.database }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO agent_proactive_state (agent_id, payload) VALUES (?, ?) ON CONFLICT(agent_id) DO UPDATE SET payload = excluded.payload", -1, &statement, nil) == SQLITE_OK else {
            throw ProactivePersistenceError.database
        }
        defer { sqlite3_finalize(statement) }
        bindText(agentId, at: 1, statement: statement)
        bindText(payload, at: 2, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ProactivePersistenceError.database }
#else
        fallbackProactiveStates[agentId] = data
#endif
    }
#if canImport(CSQLite3)
    var db: OpaquePointer?
#endif
    let isoFormatter = ISO8601DateFormatter()
    let fallbackProjectsFileURL: URL

    let usageMemoryLedger = UsageMemoryLedger()
    var fallbackEvents: [EventEnvelope] = []
    var fallbackSemanticDecisionUsages: [SemanticDecisionUsageRecord] = []
    var fallbackBulletins: [MemoryBulletin] = []
    var fallbackArtifacts: [String: PersistedArtifactRecord] = [:]
    var fallbackPublishedSites: [String: PersistedPublishedSiteRecord] = [:]
    var fallbackChannels: [String: PersistedChannelRecord] = [:]
    var fallbackTasks: [String: PersistedTaskRecord] = [:]
    var fallbackProjects: [String: ProjectRecord] = [:]
    var fallbackWorkspaces: [String: WorkspaceRecord] = [:]
    var fallbackWorkspaceDocuments: [String: WorkspaceDocument] = [:]
    var fallbackWorkspaceTransactions: [String: [WorkspaceCommittedTransaction]] = [:]
    var fallbackWorkspaceMembers: [String: [WorkspaceMember]] = [:]
    var fallbackWorkspaceTemplates: [String: WorkspaceTemplate] = [:]
    var fallbackPlugins: [String: ChannelPluginRecord] = [:]
    var fallbackAgentPlugins: [String: InstalledAgentPlugin] = [:]
    var fallbackAgentPluginRegistries: [String: AgentPluginRegistry] = [:]
    var fallbackCronTasks: [String: AgentCronTask] = [:]
    var fallbackAccessUsers: [String: ChannelAccessUser] = [:]
    var fallbackSelfImprovementProposalReviewJobs: [String: SelfImprovementProposalReviewJob] = [:]
    var fallbackAutodreamSessionReviews: [String: AutodreamSessionReviewRecord] = [:]
    var fallbackWorkflowRuns: [String: WorkflowRun] = [:]
    var fallbackWorkflowRunSteps: [String: WorkflowRunStep] = [:]
    var fallbackWorkflowPendingActions: [String: WorkflowPendingAction] = [:]
    var fallbackAutomationRuns: [String: AutomationRun] = [:]
    var fallbackProjectInitiatives: [String: InitiativeRecord] = [:]
    var fallbackDecisionPacketsByID: [String: DecisionPacketRecord] = [:]

    /// Creates a persistence store and applies schema when SQLite is available.
    public init(path: String, schemaSQL: String, fallbackProjectsPath: String? = nil) {
        fallbackProjectsFileURL = Self.resolveFallbackProjectsFileURL(
            sqlitePath: path,
            explicitPath: fallbackProjectsPath
        )
        fallbackProjects = Self.loadFallbackProjects(from: fallbackProjectsFileURL)
#if canImport(CSQLite3)
        self.db = Self.openDatabase(path: path, schemaSQL: schemaSQL).0
#endif
    }

    @discardableResult
    static func prepareDatabase(path: String, schemaSQL: String) -> String? {
#if canImport(CSQLite3)
        let (db, error) = openDatabase(path: path, schemaSQL: schemaSQL)
        if let db {
            sqlite3_close(db)
            return nil
        }
        return error ?? "Unknown SQLite initialization error"
#else
        return "SQLite3 is not available on this platform"
#endif
    }
    private static func resolveFallbackProjectsFileURL(
        sqlitePath: String,
        explicitPath: String?
    ) -> URL {
        if let explicitPath {
            let trimmed = explicitPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return URL(fileURLWithPath: trimmed)
            }
        }

        let fileManager = FileManager.default
        let sqliteDirectory = URL(fileURLWithPath: sqlitePath).deletingLastPathComponent().path
        let sqliteFileName = URL(fileURLWithPath: sqlitePath).lastPathComponent
        let fallbackFileName: String
        if sqliteFileName.isEmpty {
            fallbackFileName = "dashboard-projects-fallback.json"
        } else {
            fallbackFileName = "\(sqliteFileName).dashboard-projects-fallback.json"
        }
        if fileManager.isWritableFile(atPath: sqliteDirectory) {
            return URL(fileURLWithPath: sqliteDirectory, isDirectory: true)
                .appendingPathComponent(fallbackFileName)
        }

        let dataDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".data", isDirectory: true)
        return dataDirectory.appendingPathComponent(fallbackFileName)
    }

    private static func loadFallbackProjects(from fileURL: URL) -> [String: ProjectRecord] {
        guard let payload = try? Data(contentsOf: fileURL) else {
            return [:]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([ProjectRecord].self, from: payload) else {
            return [:]
        }

        var map: [String: ProjectRecord] = [:]
        for project in decoded {
            map[project.id] = project
        }
        return map
    }

#if canImport(CSQLite3)
    private static func openDatabase(path: String, schemaSQL: String) -> (OpaquePointer?, String?) {
        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            do {
                try FileManager.default.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                return (nil, "Failed to create database directory at \(directory): \(error.localizedDescription)")
            }
        }

        var db: OpaquePointer?
        let openResult = sqlite3_open(path, &db)
        guard openResult == SQLITE_OK else {
            let errorMsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Result code: \(openResult)"
            if let db {
                sqlite3_close(db)
            }
            return (nil, "Failed to open SQLite database at \(path): \(errorMsg)")
        }

        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA busy_timeout = 5000;", nil, nil, nil)

        if sqlite3_exec(db, schemaSQL, nil, nil, nil) != SQLITE_OK {
            let errorMsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown execution error"
            sqlite3_close(db)
            return (nil, "Failed to apply schema to database at \(path): \(errorMsg)")
        }

        if let error = applyMigrations(db: db) {
            sqlite3_close(db)
            return (nil, error)
        }
        if sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS agent_proactive_state (agent_id TEXT PRIMARY KEY, payload TEXT NOT NULL);", nil, nil, nil) != SQLITE_OK {
            sqlite3_close(db)
            return (nil, "Failed to apply proactive heartbeat schema")
        }
        return (db, nil)
    }
#endif
}
