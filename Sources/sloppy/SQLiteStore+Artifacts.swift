import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
#endif

extension SQLiteStore {
    /// Lists persisted artifacts in creation order.
    public func listPersistedArtifacts() async -> [PersistedArtifactRecord] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackArtifacts.values.sorted { $0.createdAt < $1.createdAt }
        }

        let result = loadPersistedArtifacts(db: db)
        if result.isEmpty && !fallbackArtifacts.isEmpty {
            return fallbackArtifacts.values.sorted { $0.createdAt < $1.createdAt }
        }
        return result
#else
        return fallbackArtifacts.values.sorted { $0.createdAt < $1.createdAt }
#endif
    }

    /// Persists artifact metadata and content by identifier.
    public func persistArtifact(record: PersistedArtifactRecord) async {
#if canImport(CSQLite3)
        guard let db else {
            persistFallbackArtifact(record: record)
            return
        }

        let sql =
            """
            INSERT OR REPLACE INTO artifacts(
                id,
                title,
                kind,
                media_type,
                content,
                preview_text,
                widget_size,
                widget_width,
                widget_height,
                widget_entry,
                bundle_path,
                created_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            persistFallbackArtifact(record: record)
            return
        }
        defer { sqlite3_finalize(statement) }

        bindText(record.id, at: 1, statement: statement)
        bindText(record.title, at: 2, statement: statement)
        bindText(record.kind, at: 3, statement: statement)
        bindText(record.mediaType, at: 4, statement: statement)
        bindText(record.content, at: 5, statement: statement)
        bindOptionalText(record.previewText, at: 6, statement: statement)
        bindOptionalText(record.widgetSize, at: 7, statement: statement)
        bindOptionalInt(record.widgetWidth, at: 8, statement: statement)
        bindOptionalInt(record.widgetHeight, at: 9, statement: statement)
        bindOptionalText(record.widgetEntry, at: 10, statement: statement)
        bindOptionalText(record.bundlePath, at: 11, statement: statement)
        bindText(isoFormatter.string(from: record.createdAt), at: 12, statement: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            persistFallbackArtifact(record: record)
            return
        }

        fallbackArtifacts[record.id] = record
#else
        persistFallbackArtifact(record: record)
#endif
    }

    /// Persists artifact text payload by identifier.
    public func persistArtifact(id: String, content: String) async {
        let record = await persistedArtifact(id: id)?.updatingContent(content) ?? PersistedArtifactRecord(
            id: id,
            content: content,
            previewText: String(content.prefix(160)),
            createdAt: Date()
        )
        await persistArtifact(
            record: record
        )
    }

    /// Removes persisted artifact metadata and content by identifier.
    public func deleteArtifact(id: String) async -> Bool {
        let removedFallback = fallbackArtifacts.removeValue(forKey: id) != nil
#if canImport(CSQLite3)
        guard let db else {
            return removedFallback
        }

        let sql = "DELETE FROM artifacts WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return removedFallback
        }
        defer { sqlite3_finalize(statement) }

        bindText(id, at: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            return removedFallback
        }
        return sqlite3_changes(db) > 0 || removedFallback
#else
        return removedFallback
#endif
    }

    public func listPublishedSites() async -> [PersistedPublishedSiteRecord] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackPublishedSites.values.sorted { $0.updatedAt > $1.updatedAt }
        }
        let sql = """
            SELECT id, slug, title, visibility, owner_id, project_id, entry_file,
                   bundle_path, revision, created_at, updated_at
            FROM published_sites
            ORDER BY updated_at DESC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return fallbackPublishedSites.values.sorted { $0.updatedAt > $1.updatedAt }
        }
        defer { sqlite3_finalize(statement) }
        var sites: [PersistedPublishedSiteRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let site = persistedPublishedSite(from: statement) {
                sites.append(site)
            }
        }
        return sites.isEmpty && !fallbackPublishedSites.isEmpty
            ? fallbackPublishedSites.values.sorted { $0.updatedAt > $1.updatedAt }
            : sites
#else
        return fallbackPublishedSites.values.sorted { $0.updatedAt > $1.updatedAt }
#endif
    }

    public func publishedSite(id: String) async -> PersistedPublishedSiteRecord? {
        await loadPublishedSite(column: "id", value: id) ?? fallbackPublishedSites[id]
    }

    public func publishedSite(slug: String) async -> PersistedPublishedSiteRecord? {
        await loadPublishedSite(column: "slug", value: slug)
            ?? fallbackPublishedSites.values.first { $0.slug == slug }
    }

    public func savePublishedSite(_ site: PersistedPublishedSiteRecord) async {
        fallbackPublishedSites[site.id] = site
#if canImport(CSQLite3)
        guard let db else { return }
        let sql = """
            INSERT INTO published_sites(
                id, slug, title, visibility, owner_id, project_id, entry_file,
                bundle_path, revision, created_at, updated_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                slug = excluded.slug,
                title = excluded.title,
                visibility = excluded.visibility,
                owner_id = excluded.owner_id,
                project_id = excluded.project_id,
                entry_file = excluded.entry_file,
                bundle_path = excluded.bundle_path,
                revision = excluded.revision,
                updated_at = excluded.updated_at;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(site.id, at: 1, statement: statement)
        bindText(site.slug, at: 2, statement: statement)
        bindText(site.title, at: 3, statement: statement)
        bindText(site.visibility.rawValue, at: 4, statement: statement)
        bindText(site.ownerId, at: 5, statement: statement)
        bindOptionalText(site.projectId, at: 6, statement: statement)
        bindText(site.entryFile, at: 7, statement: statement)
        bindText(site.bundlePath, at: 8, statement: statement)
        sqlite3_bind_int64(statement, 9, Int64(site.revision))
        bindText(isoFormatter.string(from: site.createdAt), at: 10, statement: statement)
        bindText(isoFormatter.string(from: site.updatedAt), at: 11, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

    public func deletePublishedSite(id: String) async -> Bool {
        let removedFallback = fallbackPublishedSites.removeValue(forKey: id) != nil
#if canImport(CSQLite3)
        guard let db else { return removedFallback }
        let sql = "DELETE FROM published_sites WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return removedFallback
        }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { return removedFallback }
        return sqlite3_changes(db) > 0 || removedFallback
#else
        return removedFallback
#endif
    }

    func loadPublishedSite(column: String, value: String) async -> PersistedPublishedSiteRecord? {
#if canImport(CSQLite3)
        guard let db, column == "id" || column == "slug" else { return nil }
        let sql = """
            SELECT id, slug, title, visibility, owner_id, project_id, entry_file,
                   bundle_path, revision, created_at, updated_at
            FROM published_sites
            WHERE \(column) = ?
            LIMIT 1;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(value, at: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return persistedPublishedSite(from: statement)
#else
        return nil
#endif
    }

#if canImport(CSQLite3)
    func persistedPublishedSite(from statement: OpaquePointer?) -> PersistedPublishedSiteRecord? {
        guard let id = optionalText(statement: statement, index: 0),
              let slug = optionalText(statement: statement, index: 1),
              let title = optionalText(statement: statement, index: 2),
              let rawVisibility = optionalText(statement: statement, index: 3),
              let visibility = PublishedSiteVisibility(rawValue: rawVisibility),
              let ownerId = optionalText(statement: statement, index: 4),
              let entryFile = optionalText(statement: statement, index: 6),
              let bundlePath = optionalText(statement: statement, index: 7),
              let createdRaw = optionalText(statement: statement, index: 9),
              let updatedRaw = optionalText(statement: statement, index: 10)
        else { return nil }
        return PersistedPublishedSiteRecord(
            id: id,
            slug: slug,
            title: title,
            visibility: visibility,
            ownerId: ownerId,
            projectId: optionalText(statement: statement, index: 5),
            entryFile: entryFile,
            bundlePath: bundlePath,
            revision: Int(sqlite3_column_int64(statement, 8)),
            createdAt: isoFormatter.date(from: createdRaw) ?? Date(),
            updatedAt: isoFormatter.date(from: updatedRaw) ?? Date()
        )
    }
#endif

    /// Returns artifact metadata by identifier.
    public func persistedArtifact(id: String) async -> PersistedArtifactRecord? {
#if canImport(CSQLite3)
        if let db {
            let sql =
                """
                SELECT
                    id,
                    title,
                    kind,
                    media_type,
                    content,
                    preview_text,
                    widget_size,
                    widget_width,
                    widget_height,
                    widget_entry,
                    bundle_path,
                    created_at
                FROM artifacts
                WHERE id = ?
                LIMIT 1;
                """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return fallbackArtifacts[id]
            }
            defer { sqlite3_finalize(statement) }

            bindText(id, at: 1, statement: statement)
            if sqlite3_step(statement) == SQLITE_ROW {
                return persistedArtifact(from: statement)
            }
        }
#endif
        return fallbackArtifacts[id]
    }

    /// Returns artifact text payload by identifier.
    public func artifactContent(id: String) async -> String? {
#if canImport(CSQLite3)
        if let db {
            let sql =
                """
                SELECT content
                FROM artifacts
                WHERE id = ?
                LIMIT 1;
                """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return fallbackArtifacts[id]?.content
            }
            defer { sqlite3_finalize(statement) }

            bindText(id, at: 1, statement: statement)
            if sqlite3_step(statement) == SQLITE_ROW,
               let cString = sqlite3_column_text(statement, 0) {
                return String(cString: cString)
            }
        }
#endif
        return fallbackArtifacts[id]?.content
    }

    func persistFallbackArtifact(record: PersistedArtifactRecord) {
        fallbackArtifacts[record.id] = record
    }

#if canImport(CSQLite3)
    func loadPersistedArtifacts(db: OpaquePointer) -> [PersistedArtifactRecord] {
        let sql =
            """
            SELECT
                id,
                title,
                kind,
                media_type,
                content,
                preview_text,
                widget_size,
                widget_width,
                widget_height,
                widget_entry,
                bundle_path,
                created_at
            FROM artifacts
            ORDER BY created_at ASC, id ASC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var result: [PersistedArtifactRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let record = persistedArtifact(from: statement) else {
                continue
            }
            result.append(record)
        }

        return result
    }
#endif

#if canImport(CSQLite3)
    func persistedArtifact(from statement: OpaquePointer?) -> PersistedArtifactRecord? {
        guard
            let statement,
            let idPtr = sqlite3_column_text(statement, 0),
            let contentPtr = sqlite3_column_text(statement, 4),
            let createdAtPtr = sqlite3_column_text(statement, 11)
        else {
            return nil
        }

        let id = String(cString: idPtr)
        let title = optionalText(statement: statement, index: 1) ?? id
        let kind = optionalText(statement: statement, index: 2) ?? "document"
        let mediaType = optionalText(statement: statement, index: 3) ?? "text/plain"
        let content = String(cString: contentPtr)
        let previewText = optionalText(statement: statement, index: 5)
        let widgetSize = optionalText(statement: statement, index: 6)
        let widgetWidth = optionalInt(statement: statement, index: 7)
        let widgetHeight = optionalInt(statement: statement, index: 8)
        let widgetEntry = optionalText(statement: statement, index: 9)
        let bundlePath = optionalText(statement: statement, index: 10)
        let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()

        return PersistedArtifactRecord(
            id: id,
            title: title,
            kind: kind,
            mediaType: mediaType,
            content: content,
            previewText: previewText,
            widgetSize: widgetSize,
            widgetWidth: widgetWidth,
            widgetHeight: widgetHeight,
            widgetEntry: widgetEntry,
            bundlePath: bundlePath,
            createdAt: createdAt
        )
    }
#endif
}
