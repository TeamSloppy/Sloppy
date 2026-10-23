import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
#endif

extension SQLiteStore {
    public func listWorkspaces() async -> [WorkspaceRecord] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackWorkspaces.values.sorted { $0.updatedAt > $1.updatedAt }
        }
        let sql =
            """
            SELECT id, title, description, cover, owner_id, project_id, revision, is_archived, created_at, updated_at
            FROM workspaces
            ORDER BY updated_at DESC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return fallbackWorkspaces.values.sorted { $0.updatedAt > $1.updatedAt }
        }
        defer { sqlite3_finalize(statement) }
        var records: [WorkspaceRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let record = decodeWorkspace(statement: statement) {
                records.append(record)
            }
        }
        return records
#else
        return fallbackWorkspaces.values.sorted { $0.updatedAt > $1.updatedAt }
#endif
    }

    public func workspace(id: String) async -> WorkspaceRecord? {
#if canImport(CSQLite3)
        guard let db else { return fallbackWorkspaces[id] }
        let sql =
            """
            SELECT id, title, description, cover, owner_id, project_id, revision, is_archived, created_at, updated_at
            FROM workspaces
            WHERE id = ?
            LIMIT 1;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return fallbackWorkspaces[id]
        }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return fallbackWorkspaces[id] }
        return decodeWorkspace(statement: statement)
#else
        return fallbackWorkspaces[id]
#endif
    }

    public func saveWorkspace(_ workspace: WorkspaceRecord) async {
        fallbackWorkspaces[workspace.id] = workspace
#if canImport(CSQLite3)
        guard let db else { return }
        let sql =
            """
            INSERT INTO workspaces(
                id, title, description, cover, owner_id, project_id, revision, is_archived, created_at, updated_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                description = excluded.description,
                cover = excluded.cover,
                owner_id = excluded.owner_id,
                project_id = excluded.project_id,
                revision = excluded.revision,
                is_archived = excluded.is_archived,
                updated_at = excluded.updated_at;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(workspace.id, at: 1, statement: statement)
        bindText(workspace.title, at: 2, statement: statement)
        bindText(workspace.description, at: 3, statement: statement)
        bindOptionalText(workspace.cover, at: 4, statement: statement)
        bindText(workspace.ownerId, at: 5, statement: statement)
        bindOptionalText(workspace.projectId, at: 6, statement: statement)
        sqlite3_bind_int64(statement, 7, sqlite3_int64(workspace.revision))
        sqlite3_bind_int(statement, 8, workspace.isArchived ? 1 : 0)
        bindText(isoFormatter.string(from: workspace.createdAt), at: 9, statement: statement)
        bindText(isoFormatter.string(from: workspace.updatedAt), at: 10, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

    public func workspaceDocument(id: String) async -> WorkspaceDocument? {
#if canImport(CSQLite3)
        guard let db else { return fallbackWorkspaceDocuments[id] }
        let sql = "SELECT document_json FROM workspace_snapshots WHERE workspace_id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return fallbackWorkspaceDocuments[id]
        }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let payload = sqlite3_column_text(statement, 0)
        else {
            return fallbackWorkspaceDocuments[id]
        }
        return decodeJSON(
            WorkspaceDocument.self,
            from: String(cString: payload),
            fallback: WorkspaceDocument(workspaceId: id)
        )
#else
        return fallbackWorkspaceDocuments[id]
#endif
    }

    public func saveWorkspaceDocument(_ document: WorkspaceDocument) async {
        fallbackWorkspaceDocuments[document.workspaceId] = document
#if canImport(CSQLite3)
        guard let db else { return }
        let sql =
            """
            INSERT OR REPLACE INTO workspace_snapshots(workspace_id, revision, document_json, created_at)
            VALUES(?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(document.workspaceId, at: 1, statement: statement)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(document.revision))
        bindText(jsonString(document, fallback: "{}"), at: 3, statement: statement)
        bindText(isoFormatter.string(from: Date()), at: 4, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

    public func listWorkspaceTransactions(
        workspaceId: String,
        afterRevision: Int
    ) async -> [WorkspaceCommittedTransaction] {
#if canImport(CSQLite3)
        guard let db else {
            return (fallbackWorkspaceTransactions[workspaceId] ?? [])
                .filter { $0.revision > afterRevision }
                .sorted { $0.revision < $1.revision }
        }
        let sql =
            """
            SELECT transaction_json
            FROM workspace_transactions
            WHERE workspace_id = ? AND revision > ?
            ORDER BY revision ASC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(workspaceId, at: 1, statement: statement)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(afterRevision))
        var records: [WorkspaceCommittedTransaction] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let payload = sqlite3_column_text(statement, 0),
                  let data = String(cString: payload).data(using: .utf8),
                  let record = try? JSONDecoder().decode(WorkspaceCommittedTransaction.self, from: data)
            else {
                continue
            }
            records.append(record)
        }
        return records
#else
        return (fallbackWorkspaceTransactions[workspaceId] ?? [])
            .filter { $0.revision > afterRevision }
            .sorted { $0.revision < $1.revision }
#endif
    }

    public func workspaceTransaction(
        workspaceId: String,
        transactionId: String
    ) async -> WorkspaceCommittedTransaction? {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackWorkspaceTransactions[workspaceId]?.first { $0.id == transactionId }
        }
        let sql =
            """
            SELECT transaction_json
            FROM workspace_transactions
            WHERE workspace_id = ? AND id = ?
            LIMIT 1;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(workspaceId, at: 1, statement: statement)
        bindText(transactionId, at: 2, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let payload = sqlite3_column_text(statement, 0),
              let data = String(cString: payload).data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(WorkspaceCommittedTransaction.self, from: data)
#else
        return fallbackWorkspaceTransactions[workspaceId]?.first { $0.id == transactionId }
#endif
    }

    public func saveWorkspaceTransaction(_ transaction: WorkspaceCommittedTransaction) async {
        var fallback = fallbackWorkspaceTransactions[transaction.workspaceId] ?? []
        if let index = fallback.firstIndex(where: { $0.id == transaction.id }) {
            fallback[index] = transaction
        } else {
            fallback.append(transaction)
        }
        fallbackWorkspaceTransactions[transaction.workspaceId] = fallback
#if canImport(CSQLite3)
        guard let db else { return }
        let sql =
            """
            INSERT OR REPLACE INTO workspace_transactions(
                workspace_id, id, revision, transaction_json, created_at
            ) VALUES(?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(transaction.workspaceId, at: 1, statement: statement)
        bindText(transaction.id, at: 2, statement: statement)
        sqlite3_bind_int64(statement, 3, sqlite3_int64(transaction.revision))
        bindText(jsonString(transaction, fallback: "{}"), at: 4, statement: statement)
        bindText(isoFormatter.string(from: transaction.createdAt), at: 5, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

    public func listWorkspaceMembers(workspaceId: String) async -> [WorkspaceMember] {
#if canImport(CSQLite3)
        guard let db else { return fallbackWorkspaceMembers[workspaceId] ?? [] }
        let sql =
            """
            SELECT principal_kind, principal_id, role, created_at
            FROM workspace_members
            WHERE workspace_id = ?
            ORDER BY created_at ASC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(workspaceId, at: 1, statement: statement)
        var members: [WorkspaceMember] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let kindPtr = sqlite3_column_text(statement, 0),
                  let idPtr = sqlite3_column_text(statement, 1),
                  let rolePtr = sqlite3_column_text(statement, 2),
                  let createdPtr = sqlite3_column_text(statement, 3),
                  let kind = WorkspacePrincipalKind(rawValue: String(cString: kindPtr)),
                  let role = WorkspaceMemberRole(rawValue: String(cString: rolePtr))
            else {
                continue
            }
            members.append(WorkspaceMember(
                workspaceId: workspaceId,
                principalKind: kind,
                principalId: String(cString: idPtr),
                role: role,
                createdAt: isoFormatter.date(from: String(cString: createdPtr)) ?? Date()
            ))
        }
        return members
#else
        return fallbackWorkspaceMembers[workspaceId] ?? []
#endif
    }

    public func saveWorkspaceMember(_ member: WorkspaceMember) async {
        var fallback = fallbackWorkspaceMembers[member.workspaceId] ?? []
        fallback.removeAll {
            $0.principalKind == member.principalKind && $0.principalId == member.principalId
        }
        fallback.append(member)
        fallbackWorkspaceMembers[member.workspaceId] = fallback
#if canImport(CSQLite3)
        guard let db else { return }
        let sql =
            """
            INSERT OR REPLACE INTO workspace_members(
                workspace_id, principal_kind, principal_id, role, created_at
            ) VALUES(?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(member.workspaceId, at: 1, statement: statement)
        bindText(member.principalKind.rawValue, at: 2, statement: statement)
        bindText(member.principalId, at: 3, statement: statement)
        bindText(member.role.rawValue, at: 4, statement: statement)
        bindText(isoFormatter.string(from: member.createdAt), at: 5, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

    public func deleteWorkspaceMember(
        workspaceId: String,
        principalKind: WorkspacePrincipalKind,
        principalId: String
    ) async {
        fallbackWorkspaceMembers[workspaceId]?.removeAll {
            $0.principalKind == principalKind && $0.principalId == principalId
        }
#if canImport(CSQLite3)
        guard let db else { return }
        let sql =
            """
            DELETE FROM workspace_members
            WHERE workspace_id = ? AND principal_kind = ? AND principal_id = ?;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(workspaceId, at: 1, statement: statement)
        bindText(principalKind.rawValue, at: 2, statement: statement)
        bindText(principalId, at: 3, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

    public func listWorkspaceTemplates() async -> [WorkspaceTemplate] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackWorkspaceTemplates.values.sorted { $0.updatedAt > $1.updatedAt }
        }
        let sql = "SELECT template_json FROM workspace_templates ORDER BY updated_at DESC;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var templates: [WorkspaceTemplate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let payload = sqlite3_column_text(statement, 0),
                  let data = String(cString: payload).data(using: .utf8),
                  let template = try? JSONDecoder().decode(WorkspaceTemplate.self, from: data)
            else {
                continue
            }
            templates.append(template)
        }
        return templates
#else
        return fallbackWorkspaceTemplates.values.sorted { $0.updatedAt > $1.updatedAt }
#endif
    }

    public func saveWorkspaceTemplate(_ template: WorkspaceTemplate) async {
        fallbackWorkspaceTemplates[template.id] = template
#if canImport(CSQLite3)
        guard let db else { return }
        let sql =
            """
            INSERT OR REPLACE INTO workspace_templates(
                id, visibility, owner_id, template_json, created_at, updated_at
            ) VALUES(?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(template.id, at: 1, statement: statement)
        bindText(template.visibility.rawValue, at: 2, statement: statement)
        bindOptionalText(template.ownerId, at: 3, statement: statement)
        bindText(jsonString(template, fallback: "{}"), at: 4, statement: statement)
        bindText(isoFormatter.string(from: template.createdAt), at: 5, statement: statement)
        bindText(isoFormatter.string(from: template.updatedAt), at: 6, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

#if canImport(CSQLite3)
    func decodeWorkspace(statement: OpaquePointer?) -> WorkspaceRecord? {
        guard let idPtr = sqlite3_column_text(statement, 0),
              let titlePtr = sqlite3_column_text(statement, 1),
              let descriptionPtr = sqlite3_column_text(statement, 2),
              let ownerPtr = sqlite3_column_text(statement, 4),
              let createdPtr = sqlite3_column_text(statement, 8),
              let updatedPtr = sqlite3_column_text(statement, 9)
        else {
            return nil
        }
        return WorkspaceRecord(
            id: String(cString: idPtr),
            title: String(cString: titlePtr),
            description: String(cString: descriptionPtr),
            cover: optionalText(statement: statement, index: 3),
            ownerId: String(cString: ownerPtr),
            projectId: optionalText(statement: statement, index: 5),
            revision: Int(sqlite3_column_int64(statement, 6)),
            isArchived: sqlite3_column_int(statement, 7) != 0,
            createdAt: isoFormatter.date(from: String(cString: createdPtr)) ?? Date(),
            updatedAt: isoFormatter.date(from: String(cString: updatedPtr)) ?? Date()
        )
    }
#endif
}
