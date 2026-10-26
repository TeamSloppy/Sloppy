import Foundation
import Protocols
import CSQLite3

/// Each connection has its own lock. The indexer and UI use separate connections in WAL mode.
final class TextSearchDatabase: @unchecked Sendable {
    enum Failure: Error { case sqlite(String), invalidQuery }
    private let lock = NSLock()
    private var db: OpaquePointer?

    init(url: URL, readOnly: Bool = false) throws {
        if !readOnly { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(url.path, &db, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = Failure.sqlite(db.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open search index")
            sqlite3_close(db); db = nil
            throw error
        }
        sqlite3_busy_timeout(db, 1_000)
        if !readOnly {
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=NORMAL")
            try execute("""
                CREATE TABLE IF NOT EXISTS sources (
                  path TEXT PRIMARY KEY, source TEXT NOT NULL, agent_id TEXT, session_id TEXT NOT NULL,
                  project_id TEXT, title TEXT NOT NULL, offset INTEGER NOT NULL DEFAULT 0,
                  size INTEGER NOT NULL DEFAULT 0, modified TEXT NOT NULL DEFAULT '',
                  head TEXT NOT NULL DEFAULT '', boundary TEXT NOT NULL DEFAULT ''
                );
                CREATE TABLE IF NOT EXISTS documents (
                  id TEXT UNIQUE NOT NULL, path TEXT NOT NULL, event_id TEXT NOT NULL, message_id TEXT,
                  before_offset TEXT NOT NULL, kind TEXT NOT NULL, role TEXT, created_at TEXT NOT NULL, text TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS documents_path ON documents(path);
                CREATE VIRTUAL TABLE IF NOT EXISTS words USING fts5(text, content='documents', content_rowid='rowid', prefix='1 2 3');
                CREATE VIRTUAL TABLE IF NOT EXISTS substrings USING fts5(text, content='documents', content_rowid='rowid', tokenize='trigram');
                CREATE TRIGGER IF NOT EXISTS documents_insert AFTER INSERT ON documents BEGIN
                  INSERT INTO words(rowid,text) VALUES(new.rowid,new.text);
                  INSERT INTO substrings(rowid,text) VALUES(new.rowid,new.text);
                END;
                CREATE TRIGGER IF NOT EXISTS documents_delete AFTER DELETE ON documents BEGIN
                  INSERT INTO words(words,rowid,text) VALUES('delete',old.rowid,old.text);
                  INSERT INTO substrings(substrings,rowid,text) VALUES('delete',old.rowid,old.text);
                END;
                CREATE TRIGGER IF NOT EXISTS documents_update AFTER UPDATE ON documents BEGIN
                  INSERT INTO words(words,rowid,text) VALUES('delete',old.rowid,old.text);
                  INSERT INTO substrings(substrings,rowid,text) VALUES('delete',old.rowid,old.text);
                  INSERT INTO words(rowid,text) VALUES(new.rowid,new.text);
                  INSERT INTO substrings(rowid,text) VALUES(new.rowid,new.text);
                END;
                """)
        }
    }

    deinit { sqlite3_close(db) }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try lock.withLock {
            try execute("BEGIN IMMEDIATE")
            do {
                let result = try body()
                try execute("COMMIT")
                return result
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    // Writer methods are confined to the indexer's single task (or a transaction).
    func execute(_ sql: String, _ values: [String?] = []) throws {
        if values.isEmpty {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
            return
        }
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func rows(_ sql: String, _ values: [String?] = []) throws -> [[String: String]] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [[String: String]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW else { throw failure() }
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                if let value = sqlite3_column_text(statement, index) {
                    row[String(cString: sqlite3_column_name(statement, index))] = String(cString: value)
                }
            }
            result.append(row)
        }
    }

    func search(query: String, mode: TextSearchMode, agentID: String?, projectID: String?, limit: Int, offset: Int) throws -> [TextSearchHit] {
        try lock.withLock {
            let table = mode == .text && query.count >= 3 ? "substrings" : "words"
            let quote: (String) -> String = { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            let expression: String
            if table == "substrings" {
                expression = quote(query)
            } else {
                let tokens = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                guard !tokens.isEmpty else { return [] }
                expression = tokens.enumerated().map { index, token in quote(token) + (index == tokens.count - 1 ? "*" : "") }.joined(separator: " AND ")
            }
            var filters = "\(table) MATCH ?"
            var values: [String?] = [expression]
            if let agentID { filters += " AND s.agent_id=?"; values.append(agentID) }
            if let projectID { filters += " AND s.project_id=?"; values.append(projectID) }
            values += [String(limit), String(offset)]
            let matches = try rows("""
                SELECT d.*, s.source, s.agent_id, s.session_id, s.project_id, s.title,
                  snippet(\(table),0,char(57344),char(57345),'…',40) AS snippet
                FROM \(table) JOIN documents d ON d.rowid=\(table).rowid JOIN sources s ON s.path=d.path
                WHERE \(filters) ORDER BY \(table).rowid DESC LIMIT ? OFFSET ?
                """, values)
            // A deleted journal must not remain visible during the short catch-up interval.
            return matches.filter { FileManager.default.fileExists(atPath: $0["path"] ?? "") }.map(Self.hit)
        }
    }

    func document(id: String) throws -> TextSearchDocumentResponse? {
        try lock.withLock {
            guard let row = try rows("""
                SELECT d.*,s.source,s.agent_id,s.session_id,s.project_id,s.title
                FROM documents d JOIN sources s ON s.path=d.path WHERE d.id=?
                """, [id]).first, FileManager.default.fileExists(atPath: row["path"] ?? "") else { return nil }
            return TextSearchDocumentResponse(hit: Self.hit(row), text: row["text"] ?? "")
        }
    }

    private static func hit(_ row: [String: String]) -> TextSearchHit {
        TextSearchHit(id: row["id"] ?? "", source: row["source"] ?? "agent", agentId: row["agent_id"],
            sessionId: row["session_id"] ?? "", projectId: row["project_id"], title: row["title"] ?? "Chat",
            eventId: row["event_id"] ?? "", messageId: row["message_id"], before: row["before_offset"] ?? "0",
            kind: row["kind"] ?? "message", role: row["role"], createdAt: row["created_at"] ?? "",
            snippet: row["snippet"] ?? String((row["text"] ?? "").prefix(240)))
    }

    private func prepare(_ sql: String, _ values: [String?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let code = value.map { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }
                ?? sqlite3_bind_null(statement, Int32(index + 1))
            guard code == SQLITE_OK else { sqlite3_finalize(statement); throw failure() }
        }
        return statement
    }

    private func failure() -> Failure { .sqlite(db.map { String(cString: sqlite3_errmsg($0)) } ?? "Search index is closed") }
}
