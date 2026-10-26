import Foundation

/// A rebuildable projection of session journals. Query execution never walks the filesystem.
final class TextSearchIndexer {
    struct ScanResult: Sendable { var indexed = 0; var failed = 0 }
    private struct Journal {
        let url: URL
        let source: String
        let agentID: String?
        var sessionID: String {
            url.lastPathComponent == "session.jsonl" ? url.deletingLastPathComponent().lastPathComponent : url.deletingPathExtension().lastPathComponent
        }
        var key: String { "\(source):\(agentID ?? ""):\(sessionID)" }
    }

    private let root: URL
    private let database: TextSearchDatabase
    private let files = FileManager.default

    init(root: URL, database: TextSearchDatabase) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
        self.database = database
    }

    func synchronize() throws -> ScanResult {
        var result = ScanResult()
        let previous = try database.rows("SELECT * FROM sources")
        let manifests = Dictionary(uniqueKeysWithValues: previous.map { ($0["path"] ?? "", $0) })
        let discovered = try journalFiles()
        let paths = Set(discovered.map { $0.url.path })
        for source in previous where !paths.contains(source["path"] ?? "") {
            try Task.checkCancellation()
            try remove(path: source["path"] ?? "")
        }
        for journal in discovered {
            try Task.checkCancellation()
            do {
                try synchronize(journal, previous: manifests[journal.url.path])
                result.indexed += 1
            } catch is CancellationError { throw CancellationError() }
            catch { result.failed += 1 }
        }
        return result
    }

    private func journalFiles() throws -> [Journal] {
        var result: [Journal] = []
        let agents = root.appendingPathComponent("agents", isDirectory: true)
        if files.fileExists(atPath: agents.path) {
            for agent in try files.contentsOfDirectory(at: agents, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                guard try agent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
                result += try journals(in: agent.appendingPathComponent("sessions", isDirectory: true), canonicalOnly: true)
                    .map { Journal(url: $0, source: "agent", agentID: agent.lastPathComponent) }
            }
        }
        result += try journals(in: root.appendingPathComponent("channel-sessions", isDirectory: true), canonicalOnly: false)
            .map { Journal(url: $0, source: "channel", agentID: nil) }
        // Canonical and legacy paths can coexist while a journal is being migrated.
        var unique: [String: Journal] = [:]
        for journal in result {
            if unique[journal.key] == nil || journal.url.lastPathComponent == "session.jsonl" {
                unique[journal.key] = journal
            }
        }
        return unique.values.sorted { $0.url.path < $1.url.path }
    }

    private func journals(in directory: URL, canonicalOnly: Bool) throws -> [URL] {
        guard files.fileExists(atPath: directory.path) else { return [] }
        var enumerationFailed = false
        guard let iterator = files.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles], errorHandler: { _, _ in enumerationFailed = true; return false }) else {
            throw CocoaError(.fileReadUnknown)
        }
        var result: [URL] = []
        for case let url as URL in iterator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            if url.lastPathComponent == "assets" { iterator.skipDescendants(); continue }
            guard values.isRegularFile == true, url.pathExtension == "jsonl" else { continue }
            if !canonicalOnly || url.lastPathComponent == "session.jsonl" || url.deletingLastPathComponent() == directory {
                result.append(url)
            }
        }
        guard !enumerationFailed else { throw CocoaError(.fileReadNoPermission) }
        return result
    }

    private func remove(path: String) throws {
        try database.transaction {
            try database.execute("DELETE FROM documents WHERE path=?", [path])
            try database.execute("DELETE FROM sources WHERE path=?", [path])
        }
    }

    private func synchronize(_ journal: Journal, previous: [String: String]?) throws {
        let url = journal.url
        let attributes = try files.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = String((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        if previous?["size"] == String(size), previous?["modified"] == modified { return }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let oldOffset = UInt64(previous?["offset"] ?? "") ?? 0
        let oldSize = UInt64(previous?["size"] ?? "") ?? 0
        let headLength = min(oldOffset, 512)
        let oldHead = try read(handle, at: 0, count: Int(headLength)).base64EncodedString()
        let oldBoundary = try read(handle, at: oldOffset - min(oldOffset, 512), count: Int(min(oldOffset, 512))).base64EncodedString()
        let canAppend = previous != nil && size > oldSize && oldOffset > 0
            && oldHead == previous?["head"] && oldBoundary == previous?["boundary"]
        var offset: UInt64 = canAppend ? oldOffset : 0
        let relative = journal.key
        let isChannel = journal.source == "channel"
        let sessionID = journal.sessionID
        let agentID = journal.agentID
        if !canAppend {
            try database.transaction {
                try database.execute("DELETE FROM documents WHERE path=?", [url.path])
                try database.execute("""
                    INSERT INTO sources(path,source,agent_id,session_id,title) VALUES(?,?,?,?,?)
                    ON CONFLICT(path) DO UPDATE SET source=excluded.source,agent_id=excluded.agent_id,session_id=excluded.session_id,
                      title=excluded.title,project_id=NULL,offset=0,size=0,modified='',head='',boundary=''
                    """, [url.path, isChannel ? "channel" : "agent", agentID, sessionID, sessionID])
            }
        }
        try handle.seek(toOffset: offset)
        var pending = Data()
        var consumed = offset
        while consumed < size {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: Int(min(256 * 1024, size - consumed))) ?? Data()
            if chunk.isEmpty { break }
            consumed += UInt64(chunk.count)
            pending.append(chunk)
            guard let lastNewline = pending.lastIndex(of: 0x0A) else { continue }
            let completed = pending.prefix(through: lastNewline)
            let chunkStart = offset
            try database.transaction {
                var lineOffset = chunkStart
                for line in completed.split(separator: 0x0A, omittingEmptySubsequences: false).dropLast() {
                    lineOffset += UInt64(line.count + 1)
                    if !line.isEmpty { try index(line: Data(line), path: url.path, key: relative, end: lineOffset) }
                }
                // Checkpoints and their FTS rows commit together. A crash can only replay a committed boundary.
                try database.execute("UPDATE sources SET offset=? WHERE path=?", [String(chunkStart + UInt64(completed.count)), url.path])
            }
            offset += UInt64(completed.count)
            pending = Data(pending.suffix(from: lastNewline + 1))
        }
        let head = try read(handle, at: 0, count: Int(min(offset, 512))).base64EncodedString()
        let boundary = try read(handle, at: offset - min(offset, 512), count: Int(min(offset, 512))).base64EncodedString()
        try database.execute("UPDATE sources SET offset=?,size=?,modified=?,head=?,boundary=? WHERE path=?",
            [String(offset), String(size), modified, head, boundary, url.path])
    }

    private func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }

    private func index(line: Data, path: String, key: String, end: UInt64) throws {
        // Structural fields select journal payloads; model prose never controls indexing behavior.
        guard let event = try JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = event["id"] as? String else { return }
        let kind = event["type"] as? String ?? "message"
        if let metadata = event["metadata"] as? [String: Any], let title = metadata["title"] as? String {
            try database.execute("UPDATE sources SET title=?,project_id=? WHERE path=?", [title, metadata["projectId"] as? String, path])
        }
        let message = event["message"] as? [String: Any]
        var parts: [String] = []
        if let segments = message?["segments"] as? [[String: Any]] {
            for segment in segments {
                if let text = segment["text"] as? String { parts.append(text) }
                if let attachment = segment["attachment"] as? [String: Any], let name = attachment["fileName"] as? String { parts.append(name) }
            }
        }
        if let content = event["content"] as? String { parts.append(content) }
        for field in ["toolCall", "toolResult", "planArtifact", "inputRequest", "inputResponse", "buildProgress", "runStatus", "runControl", "memoryCheckpoint", "subSession", "longChatTask", "selfImprovementReview"] {
            if let value = event[field], JSONSerialization.isValidJSONObject(value) {
                parts.append(String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self))
            }
        }
        if kind == "session_created", let metadata = event["metadata"] as? [String: Any], let title = metadata["title"] as? String { parts.append(title) }
        let text = parts.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try database.execute("""
            INSERT INTO documents(id,path,event_id,message_id,before_offset,kind,role,created_at,text) VALUES(?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET message_id=excluded.message_id,before_offset=excluded.before_offset,
              kind=excluded.kind,role=excluded.role,created_at=excluded.created_at,text=excluded.text
            """, [key + "#" + id, path, id, message?["id"] as? String, String(end), kind,
                    message?["role"] as? String ?? event["userId"] as? String, event["createdAt"] as? String ?? "", text])
    }
}
