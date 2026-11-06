import Foundation
import AgentRuntime
import Logging
import PluginSDK
import Protocols

public final class AgentSessionFileStore: @unchecked Sendable {
    public enum StoreError: Error, CustomStringConvertible {
        case invalidAgentID
        case invalidSessionID
        case agentNotFound
        case sessionNotFound
        case sessionFileNotFound(agentID: String, sessionID: String, agentsRoot: String)
        case sessionEventsEmpty(agentID: String, sessionID: String, lineCount: Int, filePath: String)
        case invalidPayload
        case unsupportedJournalVersion(Int)
        case unsupportedRuntimeVersion(component: String, version: Int)

        public var description: String {
            switch self {
            case .invalidAgentID: return "invalidAgentID"
            case .invalidSessionID: return "invalidSessionID"
            case .agentNotFound: return "agentNotFound"
            case .sessionNotFound: return "sessionNotFound"
            case .sessionFileNotFound(let a, let s, let root):
                return "sessionFileNotFound(agent=\(a), session=\(s), agentsRoot=\(root))"
            case .sessionEventsEmpty(let a, let s, let lc, let fp):
                return "sessionEventsEmpty(agent=\(a), session=\(s), lines=\(lc), file=\(fp))"
            case .invalidPayload: return "invalidPayload"
            case .unsupportedJournalVersion(let version):
                return "Unsupported session journal version \(version); use a compatible Core before continuing."
            case .unsupportedRuntimeVersion(let component, let version):
                return "Unsupported session \(component) version \(version); use a compatible Core before continuing."
            }
        }
    }

    let fileManager: FileManager
    private var agentsRootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: Logger
    private let journalOwnership: FileOwnershipLease.Reference?
    private let authorizeJournalWrite: (@Sendable (URL, Int) throws -> Void)?
    private static let operationLock = NSRecursiveLock()
    private static let summaryCacheSchemaVersion = 5
    private static let decodedEventsCacheLimit = 8

    /// Decoded journal of a recently used session, valid only while the file still has the same fingerprint.
    /// Without it every tool call re-read and re-decoded the whole journal several times under `operationLock`.
    private struct DecodedEventsCache {
        var byteCount: Int
        var modifiedAt: TimeInterval
        var events: [AgentSessionEvent]
    }
    private var decodedEventsCache: [String: DecodedEventsCache] = [:]
    private var decodedEventsCacheOrder: [String] = []

    public init(agentsRootURL: URL, fileManager: FileManager = .default,
        journalOwnership: FileOwnershipLease.Reference? = nil,
        authorizeJournalWrite: (@Sendable (URL, Int) throws -> Void)? = nil) {
        self.fileManager = fileManager
        self.journalOwnership = journalOwnership
        self.agentsRootURL = agentsRootURL
        self.authorizeJournalWrite = authorizeJournalWrite
        var logger = Logger(label: "sloppy.session.store")
        if ProcessInfo.processInfo.environment["SLOPPY_QUIET_LOGS"] == "1" {
            logger.logLevel = .critical
        }
        self.logger = logger

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func updateAgentsRootURL(_ url: URL) {
        withLock {
            self.agentsRootURL = url
        }
    }

    public func listSessions(
        agentID: String,
        includeHeartbeat: Bool = false,
        limit: Int? = nil,
        offset: Int = 0
    ) throws -> [AgentSessionSummary] {
        try withLock {
            let normalizedAgentID = try normalizedAgentID(agentID)
            let sessionsDirectory = try sessionsDirectoryURL(agentID: normalizedAgentID, createIfMissing: false)

            guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
                return []
            }
            try migrateLegacySessions(in: sessionsDirectory)

            let resolver = try sessionPathResolver(agentID: normalizedAgentID)
            var seenSessionIDs = Set<String>()
            let canonicalFiles = resolver.canonicalSessionFiles()
            let legacyFiles = try fileManager.contentsOfDirectory(
                at: sessionsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "jsonl" }
            let sessionFiles = canonicalFiles + legacyFiles
            var summaries: [AgentSessionSummary] = []
            for file in sessionFiles {
                let sessionID = file.lastPathComponent == "session.jsonl"
                    ? AgentSessionPathResolver.sessionID(fromCanonicalSessionFile: file)
                    : file.deletingPathExtension().lastPathComponent
                guard seenSessionIDs.insert(sessionID).inserted else {
                    continue
                }
                if let summary = try? loadSessionSummary(agentID: normalizedAgentID, sessionID: sessionID, fileURL: file),
                   includeHeartbeat || summary.kind != .heartbeat {
                    summaries.append(summary)
                }
            }

            let sorted = summaries.sorted { $0.updatedAt > $1.updatedAt }
            return Self.paginated(sorted, limit: limit, offset: offset)
        }
    }

    public func createSession(
        agentID: String,
        request: AgentSessionCreateRequest,
        createdAt: Date = Date(),
        importedSessionID: String? = nil
    ) throws -> AgentSessionSummary {
        try withLock {
            let ownership = try retainJournalOwnership()
            defer { withExtendedLifetime(ownership) {} }
            let normalizedAgentID = try normalizedAgentID(agentID)
            let normalizedParentSessionID = try normalizedOptionalSessionID(request.parentSessionId)
            _ = try sessionsDirectoryURL(agentID: normalizedAgentID, createIfMissing: true)
            let resolver = try sessionPathResolver(agentID: normalizedAgentID)

            let sessionID = try importedSessionID.map { try normalizedSessionID($0) } ?? "session-\(UUID().uuidString.lowercased())"
            if importedSessionID != nil, let existing = sessionFileURL(agentID: normalizedAgentID, sessionID: sessionID), fileManager.fileExists(atPath: existing.path) {
                return try loadSession(agentID: normalizedAgentID, sessionID: sessionID).summary
            }
            let trimmedTitle = request.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String
            let titleIsAutomatic: Bool
            if let trimmedTitle, !trimmedTitle.isEmpty {
                title = trimmedTitle
                titleIsAutomatic = false
            } else {
                title = AgentSessionTitleGenerator.fallbackTitle
                titleIsAutomatic = true
            }

            let projectIdMeta: String? = {
                guard let raw = request.projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                    return nil
                }
                return raw
            }()
            let taskIdMeta: String? = {
                guard let raw = request.taskId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                    return nil
                }
                return raw
            }()
            let workspaceIdMeta: String? = {
                guard let raw = request.workspaceId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                    return nil
                }
                return raw
            }()

            let createdEvent = AgentSessionEvent(
                agentId: normalizedAgentID,
                sessionId: sessionID,
                type: .sessionCreated,
                createdAt: createdAt,
                metadata: AgentSessionMetadataEvent(
                    title: title,
                    parentSessionId: normalizedParentSessionID,
                    kind: request.kind,
                    projectId: projectIdMeta,
                    taskId: taskIdMeta,
                    workspaceId: workspaceIdMeta,
                    titleIsAutomatic: titleIsAutomatic
                )
            )

            let location = resolver.canonicalLocation(sessionID: sessionID, createdAt: createdAt)
            try fileManager.createDirectory(at: location.directoryURL, withIntermediateDirectories: true)
            let fileURL = location.sessionFileURL
            try append(events: [createdEvent], to: fileURL, createIfMissing: true)
            return try refreshSummaryCache(agentID: normalizedAgentID, sessionID: sessionID, fileURL: fileURL)
        }
    }

    @discardableResult
    public func deleteExpiredSessions(
        agentIDs: [String],
        olderThan cutoffDate: Date,
        protectedSessionIDs: Set<String> = []
    ) throws -> [AgentSessionSummary] {
        try withLock {
            let ownership = try retainJournalOwnership()
            defer { withExtendedLifetime(ownership) {} }
            var deleted: [AgentSessionSummary] = []
            for agentID in agentIDs {
                let normalizedAgentID = try normalizedAgentID(agentID)
                let summaries = try listSessions(agentID: normalizedAgentID, includeHeartbeat: true)
                let longChatIDs = Set(summaries.filter { $0.kind == .longChat }.map(\.id))
                for summary in summaries where summary.kind != .longChat && !protectedSessionIDs.contains(summary.id) && summary.parentSessionId.map(longChatIDs.contains) != true && summary.updatedAt < cutoffDate {
                    try deleteSession(agentID: normalizedAgentID, sessionID: summary.id)
                    deleted.append(summary)
                }
            }
            return deleted
        }
    }

    public func loadSession(agentID: String, sessionID: String) throws -> AgentSessionDetail {
        try withLock {
            let normalizedAgentID = try normalizedAgentID(agentID)
            let normalizedSessionID = try normalizedSessionID(sessionID)
            let events = try readEvents(agentID: normalizedAgentID, sessionID: normalizedSessionID)
            let summary = summaryForSession(agentID: normalizedAgentID, sessionID: normalizedSessionID, events: events)
            return AgentSessionDetail(summary: summary, events: events)
        }
    }

    func retainJournalOwnership() throws -> FileOwnershipLease? { try journalOwnership?.capture() }

    public func attachmentReferences(agentID: String, sessionID: String) throws -> [AgentAttachment] {
        try withLock {
            let file = URL(fileURLWithPath: try sessionFilePath(agentID: agentID, sessionID: sessionID))
            return try journalRecords(from: Data(contentsOf: file), hydrate: false).flatMap { record in
                (record.event.message?.segments.compactMap(\.attachment) ?? []) +
                    [record.event.runtimeMetadata?.toolOutputArtifact?.attachment].compactMap { $0 }
            }
        }
    }

    /// Discover download references without hydrating externalized payloads into memory.
    public func toolOutputArtifactReferences(agentID: String, sessionID: String) throws -> [AgentToolOutputArtifact] {
        try withLock {
            let file = URL(fileURLWithPath: try sessionFilePath(agentID: agentID, sessionID: sessionID))
            return try journalRecords(from: Data(contentsOf: file), hydrate: false).compactMap { record in
                guard let artifact = record.event.runtimeMetadata?.toolOutputArtifact,
                      artifact.agentId == record.event.agentId, artifact.sessionId == record.event.sessionId else { return nil }
                return artifact
            }
        }
    }

    /// Capture physical byte cursors and domain events under the same append lock.
    public func loadJournal(agentID: String, sessionID: String) throws -> AgentSessionJournalSnapshot {
        try withLock {
            let agentID = try normalizedAgentID(agentID)
            let sessionID = try normalizedSessionID(sessionID)
            let fileURL = URL(fileURLWithPath: try sessionFilePath(agentID: agentID, sessionID: sessionID))
            let data = try Data(contentsOf: fileURL)
            let records = try journalRecords(from: data)
            let events = records.map(\.event)
            guard !events.isEmpty else {
                throw StoreError.sessionEventsEmpty(agentID: agentID, sessionID: sessionID,
                    lineCount: records.count, filePath: fileURL.path)
            }
            let summary = summaryForSession(agentID: agentID, sessionID: sessionID, events: events)
            return .init(detail: .init(summary: summary, events: events), records: records, cursor: UInt64(data.count))
        }
    }

    /// Read only the requested tail of the append-only log. The summary/control
    /// snapshot is maintained on writes; old caches are upgraded once.
    public func loadSessionPage(
        agentID: String, sessionID: String, limit: Int, before: String? = nil, excludingDerivedWork: Bool = false
    ) throws -> AgentSessionDetail {
        try withLock {
            let agentID = try normalizedAgentID(agentID)
            let sessionID = try normalizedSessionID(sessionID)
            guard (1...200).contains(limit) else { throw StoreError.invalidPayload }
            guard let fileURL = sessionFileURL(agentID: agentID, sessionID: sessionID),
                  fileManager.fileExists(atPath: fileURL.path) else { throw StoreError.sessionNotFound }
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let fileEnd = try handle.seekToEnd()
            let end: UInt64
            if let before {
                guard let offset = UInt64(before), offset <= fileEnd else { throw StoreError.invalidPayload }
                if offset > 0 {
                    try handle.seek(toOffset: offset - 1)
                    guard try handle.read(upToCount: 1) == Data([0x0A]) else { throw StoreError.invalidPayload }
                }
                end = offset
            } else {
                end = fileEnd
            }
            let rows = try readEventTail(handle: handle, end: end, count: limit + 1, excludingDerivedWork: excludingDerivedWork)
            let selected = Array(rows.prefix(limit))
            let hasMore = rows.count > limit
            let summary: AgentSessionSummary
            let stateEvents: [AgentSessionEvent]
            if let cache = try? readSummarySnapshot(agentID: agentID, sessionID: sessionID, fileURL: fileURL) {
                summary = cache.summary
                stateEvents = cache.stateEvents
            } else {
                // The derived cache is optional, including for paged control-state reads.
                // Canonical validation still runs before any best-effort cache update.
                let events = try readEvents(agentID: agentID, sessionID: sessionID)
                summary = summaryForSession(agentID: agentID, sessionID: sessionID, events: events)
                stateEvents = summaryStateEvents(in: events)
                updateSummaryCacheIfPossible(summary, events: events, fileURL: fileURL)
            }
            return AgentSessionDetail(
                summary: summary,
                events: selected.reversed().map(\.event),
                historyPage: AgentSessionHistoryPage(
                    nextBefore: hasMore ? selected.last.map { String($0.offset) } : nil,
                    hasMore: hasMore
                ),
                stateEvents: stateEvents
            )
        }
    }

    private func readEventTail(
        handle: FileHandle, end: UInt64, count: Int, excludingDerivedWork: Bool = false
    ) throws -> [(offset: UInt64, event: AgentSessionEvent)] {
        var position = end
        var pending = Data()
        var rows: [(offset: UInt64, event: AgentSessionEvent)] = []
        while position > 0 {
            let size = Int(min(position, 64 * 1_024))
            position -= UInt64(size)
            try handle.seek(toOffset: position)
            var block = try handle.read(upToCount: size) ?? Data()
            guard block.count == size else { throw StoreError.invalidPayload }
            block.append(pending)
            var lineEnd = block.endIndex
            for index in block.indices.reversed() where block[index] == 0x0A {
                let start = index + 1
                if start < lineEnd,
                   let event = try decodeJournalLine(block.subdata(in: start..<lineEnd)) {
                    if excludingDerivedWork && event.runtimeMetadata?.derivedSource != nil { lineEnd = index; continue }
                    rows.append((position + UInt64(start), event))
                    if rows.count == count { return rows }
                }
                lineEnd = index
            }
            pending = block.subdata(in: 0..<lineEnd)
        }
        if !pending.isEmpty, let event = try decodeJournalLine(pending),
           !excludingDerivedWork || event.runtimeMetadata?.derivedSource == nil {
            rows.append((0, event))
        }
        return rows
    }

    public func sessionFilePath(agentID: String, sessionID: String) throws -> String {
        try withLock {
            let normalizedAgentID = try normalizedAgentID(agentID)
            let normalizedSessionID = try normalizedSessionID(sessionID)
            guard let fileURL = sessionFileURL(agentID: normalizedAgentID, sessionID: normalizedSessionID),
                  fileManager.fileExists(atPath: fileURL.path) else {
                throw StoreError.sessionNotFound
            }
            return fileURL.standardizedFileURL.path
        }
    }

    @discardableResult
    public func appendEvents(agentID: String, sessionID: String, events: [AgentSessionEvent]) throws -> AgentSessionSummary {
        try withLock {
            let ownership = try retainJournalOwnership()
            defer { withExtendedLifetime(ownership) {} }
            let normalizedAgentID = try normalizedAgentID(agentID)
            let normalizedSessionID = try normalizedSessionID(sessionID)
            guard !events.isEmpty else {
                throw StoreError.invalidPayload
            }

            guard let fileURL = sessionFileURL(agentID: normalizedAgentID, sessionID: normalizedSessionID),
                  fileManager.fileExists(atPath: fileURL.path) else {
                throw StoreError.sessionNotFound
            }

            // Validate the existing journal before writing, including entries outside a requested page.
            let previous = try readEvents(agentID: normalizedAgentID, sessionID: normalizedSessionID)
            _ = try SessionInputLifecycle.states(in: previous + events)
            try authorizeWrite(agentID: normalizedAgentID, events: previous + events)
            if events.contains(where: { $0.version >= 3 }) {
                guard events.allSatisfy({ $0.agentId == normalizedAgentID && $0.sessionId == normalizedSessionID }) else {
                    throw StoreError.invalidPayload
                }
            }
            let cachedBeforeAppend = cachedDecodedEvents(for: fileURL)
            try append(events: events, to: fileURL, createIfMissing: false)
            if let cachedBeforeAppend {
                // Cache what a re-read would produce: the journal stores dates with second precision.
                if let persisted = try? events.map({ try decoder.decode(AgentSessionEvent.self, from: encoder.encode($0)) }) {
                    storeDecodedEvents(
                        cachedBeforeAppend + persisted,
                        for: fileURL
                    )
                } else {
                    invalidateDecodedEvents(for: fileURL)
                }
            }
            return try refreshSummaryCache(agentID: normalizedAgentID, sessionID: normalizedSessionID, fileURL: fileURL)
        }
    }

    /// A timeout placeholder must never replace a known outcome that won the append race.
    /// Use the same process-wide append lock across store instances, including a late writer.
    @discardableResult
    public func appendRuntimeToolResult(agentID: String, sessionID: String, event: AgentSessionEvent) throws -> AgentSessionSummary? {
        try withLock {
            let ownership = try retainJournalOwnership()
            defer { withExtendedLifetime(ownership) {} }
            let normalizedAgentID = try normalizedAgentID(agentID)
            let normalizedSessionID = try normalizedSessionID(sessionID)
            try validateJournalEvent(event)
            guard event.type == .toolResult, !event.isHistorical, let result = event.toolResult,
                  let callID = result.callEventId, event.runtimeMetadata?.callEventId == callID else {
                throw StoreError.invalidPayload
            }
            let events = try readEvents(agentID: normalizedAgentID, sessionID: normalizedSessionID)
            if result.executionOutcome?.requiresReconciliation == true,
               let prior = events.last(where: { !$0.isHistorical && $0.toolResult?.callEventId == callID })?.toolResult,
               prior.tool == result.tool,
               prior.ok || prior.executionOutcome?.requiresReconciliation == false {
                return nil
            }
            return try appendEvents(agentID: normalizedAgentID, sessionID: normalizedSessionID, events: [event])
        }
    }

    /// Upgrade only the creation metadata, retaining message IDs, timestamps and unknown journal fields.
    @discardableResult
    public func promoteToLongChat(agentID: String, sessionID: String) throws -> AgentSessionSummary {
        try withLock {
            let ownership = try retainJournalOwnership()
            defer { withExtendedLifetime(ownership) {} }
            let detail = try loadSession(agentID: agentID, sessionID: sessionID)
            if detail.summary.kind == .longChat { return detail.summary }
            try authorizeWrite(agentID: agentID, events: detail.events)
            guard detail.summary.kind == .chat, detail.summary.parentSessionId == nil,
                  detail.summary.taskId == nil, detail.summary.workspaceId == nil,
                  let fileURL = sessionFileURL(agentID: agentID, sessionID: sessionID) else {
                throw StoreError.invalidPayload
            }
            let data = try Data(contentsOf: fileURL)
            guard let content = String(data: data, encoding: .utf8) else { throw StoreError.invalidPayload }
            var lines = content.components(separatedBy: "\n")
            var changed = false
            for i in lines.indices where !lines[i].isEmpty {
                guard var record = try JSONSerialization.jsonObject(with: Data(lines[i].utf8)) as? [String: Any],
                      record["type"] as? String == AgentSessionEventType.sessionCreated.rawValue,
                      var metadata = record["metadata"] as? [String: Any] else { continue }
                metadata["kind"] = AgentSessionKind.longChat.rawValue
                record["metadata"] = metadata
                lines[i] = String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self)
                changed = true
            }
            guard changed else { throw StoreError.invalidPayload }
            try Data(lines.joined(separator: "\n").utf8).write(to: fileURL, options: .atomic)
            invalidateDecodedEvents(for: fileURL)
            return try refreshSummaryCache(agentID: agentID, sessionID: sessionID, fileURL: fileURL)
        }
    }

    /// Change only the title metadata, preserving the journal and its unknown fields.
    public func renameSession(agentID: String, sessionID: String, title: String) throws -> AgentSessionSummary {
        try withLock {
            let ownership = try retainJournalOwnership()
            defer { withExtendedLifetime(ownership) {} }
            let agentID = try normalizedAgentID(agentID)
            let sessionID = try normalizedSessionID(sessionID)
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 200 else { throw StoreError.invalidPayload }
            let detail = try loadSession(agentID: agentID, sessionID: sessionID)
            try authorizeWrite(agentID: agentID, events: detail.events)
            guard let fileURL = sessionFileURL(agentID: agentID, sessionID: sessionID),
                  let content = String(data: try Data(contentsOf: fileURL), encoding: .utf8) else {
                throw StoreError.invalidPayload
            }
            var lines = content.components(separatedBy: "\n")
            var changed = false
            for index in lines.indices where !lines[index].isEmpty {
                guard var record = try JSONSerialization.jsonObject(with: Data(lines[index].utf8)) as? [String: Any],
                      record["type"] as? String == AgentSessionEventType.sessionCreated.rawValue,
                      var metadata = record["metadata"] as? [String: Any] else { continue }
                metadata["title"] = title
                metadata["titleIsAutomatic"] = false
                record["metadata"] = metadata
                lines[index] = String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self)
                changed = true
            }
            guard changed else { throw StoreError.invalidPayload }
            try Data(lines.joined(separator: "\n").utf8).write(to: fileURL, options: .atomic)
            invalidateDecodedEvents(for: fileURL)
            return try refreshSummaryCache(agentID: agentID, sessionID: sessionID, fileURL: fileURL)
        }
    }

    public func deleteSession(agentID: String, sessionID: String) throws {
        try withLock {
            let ownership = try retainJournalOwnership()
            defer { withExtendedLifetime(ownership) {} }
            let normalizedAgentID = try normalizedAgentID(agentID)
            let normalizedSessionID = try normalizedSessionID(sessionID)

            guard let fileURL = sessionFileURL(agentID: normalizedAgentID, sessionID: normalizedSessionID),
                  fileManager.fileExists(atPath: fileURL.path) else {
                throw StoreError.sessionNotFound
            }

            let location = try sessionPathResolver(agentID: normalizedAgentID)
                .existingLocation(sessionID: normalizedSessionID)
            try fileManager.removeItem(at: fileURL)
            invalidateDecodedEvents(for: fileURL)
            removeSummaryCache(agentID: normalizedAgentID, sessionID: normalizedSessionID)

            if location?.isLegacy == false {
                try? fileManager.removeItem(at: location!.directoryURL)
                return
            }

            if let sidecar = sessionSidecarURL(agentID: normalizedAgentID, sessionID: normalizedSessionID),
               fileManager.fileExists(atPath: sidecar.path) {
                try? fileManager.removeItem(at: sidecar)
            }

            if let assetsDirectory = assetsDirectoryURL(agentID: normalizedAgentID, sessionID: normalizedSessionID),
               fileManager.fileExists(atPath: assetsDirectory.path) {
                try fileManager.removeItem(at: assetsDirectory)
            }
        }
    }

    public func incrementUserTurnCount(agentID: String, sessionID: String) throws -> Int {
        try withLock {
            let ownership = try retainJournalOwnership()
            defer { withExtendedLifetime(ownership) {} }
            let normalizedAgentID = try normalizedAgentID(agentID)
            let normalizedSessionID = try normalizedSessionID(sessionID)
            let prior = try readUserTurnCount(agentID: normalizedAgentID, sessionID: normalizedSessionID)
            let next = prior + 1
            try writeUserTurnCount(agentID: normalizedAgentID, sessionID: normalizedSessionID, count: next)
            return next
        }
    }

    public func resetUserTurnCount(agentID: String, sessionID: String) throws {
        try withLock {
            let ownership = try retainJournalOwnership()
            defer { withExtendedLifetime(ownership) {} }
            let normalizedAgentID = try normalizedAgentID(agentID)
            let normalizedSessionID = try normalizedSessionID(sessionID)
            try writeUserTurnCount(agentID: normalizedAgentID, sessionID: normalizedSessionID, count: 0)
        }
    }

    private struct AgentSessionSidecar: Codable {
        var userTurnCount: Int
    }

    private func sessionSidecarURL(agentID: String, sessionID: String) -> URL? {
        guard let resolver = try? sessionPathResolver(agentID: agentID) else {
            return nil
        }
        return resolver.existingLocation(sessionID: sessionID)?.sidecarURL
            ?? resolver.legacyLocation(sessionID: sessionID).sidecarURL
    }

    private func readUserTurnCount(agentID: String, sessionID: String) throws -> Int {
        guard let url = sessionSidecarURL(agentID: agentID, sessionID: sessionID),
              fileManager.fileExists(atPath: url.path) else {
            return 0
        }
        let data = try Data(contentsOf: url)
        let sidecar = try JSONDecoder().decode(AgentSessionSidecar.self, from: data)
        return max(0, sidecar.userTurnCount)
    }

    private func writeUserTurnCount(agentID: String, sessionID: String, count: Int) throws {
        guard let url = sessionSidecarURL(agentID: agentID, sessionID: sessionID) else {
            throw StoreError.agentNotFound
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = try JSONEncoder().encode(AgentSessionSidecar(userTurnCount: max(0, count)))
        try payload.write(to: url, options: .atomic)
        removeSummaryCache(agentID: agentID, sessionID: sessionID)
    }

    public func persistAttachments(agentID: String, sessionID: String, uploads: [AgentAttachmentUpload]) throws -> [AgentAttachment] {
        try withLock {
            let ownership = try retainJournalOwnership()
            defer { withExtendedLifetime(ownership) {} }
            let normalizedAgentID = try normalizedAgentID(agentID)
            let normalizedSessionID = try normalizedSessionID(sessionID)

            if uploads.isEmpty {
                return []
            }

            var attachments: [AgentAttachment] = []
            for upload in uploads {
                let cleanName = sanitizeFilename(upload.name)
                let normalizedName = cleanName.isEmpty ? "attachment.bin" : cleanName
                let mimeType = upload.mimeType.trimmingCharacters(in: .whitespacesAndNewlines)
                let attachmentID = UUID().uuidString.lowercased()
                let fileName = "\(attachmentID)-\(normalizedName)"

                var relativePath: String?
                var persistedSize = max(upload.sizeBytes, 0)
                if let contentBase64 = upload.contentBase64 {
                    guard let data = Data(base64Encoded: contentBase64, options: [.ignoreUnknownCharacters]) else {
                        throw StoreError.invalidPayload
                    }

                    guard let assetsDirectory = assetsDirectoryURL(agentID: normalizedAgentID, sessionID: normalizedSessionID),
                          let agentDirectory = resolvedAgentDirectoryURL(agentID: normalizedAgentID) else {
                        throw StoreError.agentNotFound
                    }
                    try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

                    let fileURL = assetsDirectory.appendingPathComponent(fileName)
                    try data.write(to: fileURL, options: .atomic)
                    let handle = try FileHandle(forWritingTo: fileURL)
                    defer { try? handle.close() }
                    try handle.synchronize()
                    persistedSize = data.count
                    relativePath = AgentSessionPathResolver.relativePath(from: agentDirectory, to: fileURL)
                }

                attachments.append(
                    AgentAttachment(
                        id: attachmentID,
                        name: normalizedName,
                        mimeType: mimeType.isEmpty ? "application/octet-stream" : mimeType,
                        sizeBytes: persistedSize,
                        relativePath: relativePath
                    )
                )
            }

            return attachments
        }
    }

    /// Canonical input blobs must belong to this session, including after resolving symlinks.
    public func readInputAttachment(agentID: String, sessionID: String, attachment: AgentAttachment) throws -> Data {
        try withLock {
            let agentID = try normalizedAgentID(agentID)
            let sessionID = try normalizedSessionID(sessionID)
            guard let directory = resolvedAgentDirectoryURL(agentID: agentID)?.resolvingSymlinksInPath().standardizedFileURL,
                  let assets = assetsDirectoryURL(agentID: agentID, sessionID: sessionID)?.resolvingSymlinksInPath().standardizedFileURL,
                  let file = try resolveAttachmentFileURL(agentID: agentID, attachment: attachment)?.resolvingSymlinksInPath().standardizedFileURL,
                  assets.path.hasPrefix(directory.path + "/"), file.path.hasPrefix(assets.path + "/") else { throw StoreError.invalidPayload }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, attachment.sizeBytes >= 0, attachment.sizeBytes < Int.max,
                  values.fileSize == attachment.sizeBytes else { throw StoreError.invalidPayload }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: attachment.sizeBytes + 1) ?? Data()
            guard data.count == attachment.sizeBytes else { throw StoreError.invalidPayload }
            return data
        }
    }

    public func resolveAttachmentFileURL(agentID: String, attachment: AgentAttachment) throws -> URL? {
        try withLock {
            let normalizedAgentID = try normalizedAgentID(agentID)
            guard let relativePath = attachment.relativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !relativePath.isEmpty,
                  let agentDirectory = resolvedAgentDirectoryURL(agentID: normalizedAgentID) else {
                return nil
            }
            let directURL = agentDirectory.appendingPathComponent(relativePath, isDirectory: false)
            if fileManager.fileExists(atPath: directURL.path) {
                return directURL
            }

            if let migratedURL = migratedAttachmentURL(agentID: normalizedAgentID, legacyRelativePath: relativePath),
               fileManager.fileExists(atPath: migratedURL.path) {
                return migratedURL
            }
            return directURL
        }
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        Self.operationLock.lock()
        defer { Self.operationLock.unlock() }
        return try body()
    }

    private func authorizeWrite(agentID: String, events: [AgentSessionEvent]) throws {
        guard let authorizeJournalWrite else { return }
        let version = events.contains(where: { $0.runtimeMetadata?.toolOutputArtifact?.schemaVersion == 2 })
            ? 8 : (events.map(\.version).max() ?? 1)
        guard version >= 3 else { return }
        guard let directory = resolvedAgentDirectoryURL(agentID: agentID) else { throw StoreError.agentNotFound }
        try authorizeJournalWrite(directory, version)
    }

    private func append(events: [AgentSessionEvent], to fileURL: URL, createIfMissing: Bool) throws {
        let ownership = try journalOwnership?.capture()
        defer { withExtendedLifetime(ownership) {} }
        // Encode the entire batch before touching the file; an invalid later event must not append a prefix.
        var payload = Data()
        for event in events {
            try validateJournalEvent(event)
            var encoded = event
            if !event.isHistorical, event.runtimeMetadata?.toolOutputArtifact?.schemaVersion == 2 {
                encoded.toolResult?.data = nil
                encoded.toolResult?.error = nil
            }
            payload.append(try encoder.encode(encoded))
            payload.append(0x0A)
        }
        if createIfMissing && !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        }

        let handle = try FileHandle(forUpdating: fileURL)
        defer {
            try? handle.close()
        }
        let end = try handle.seekToEnd()
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            let last = try handle.read(upToCount: 1)
            try handle.seekToEnd()
            if last != Data([0x0A]) { try handle.write(contentsOf: Data([0x0A])) }
        }
        try handle.write(contentsOf: payload)
        try handle.synchronize()
    }

    private func readEvents(agentID: String, sessionID: String) throws -> [AgentSessionEvent] {
        if let sessionsDirectory = try? sessionsDirectoryURL(agentID: agentID, createIfMissing: false),
           fileManager.fileExists(atPath: sessionsDirectory.path) {
            try? migrateLegacySessions(in: sessionsDirectory)
        }

        guard let fileURL = sessionFileURL(agentID: agentID, sessionID: sessionID) else {
            logger.warning(
                "Session file URL resolution failed",
                metadata: [
                    "agent_id": .string(agentID),
                    "session_id": .string(sessionID),
                    "agents_root": .string(agentsRootURL.path)
                ]
            )
            throw StoreError.sessionFileNotFound(
                agentID: agentID,
                sessionID: sessionID,
                agentsRoot: agentsRootURL.path
            )
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw StoreError.sessionFileNotFound(
                agentID: agentID,
                sessionID: sessionID,
                agentsRoot: agentsRootURL.path
            )
        }

        if let cached = cachedDecodedEvents(for: fileURL) {
            return cached
        }

        let data = try Data(contentsOf: fileURL)
        let events = try journalRecords(from: data).map(\.event)

        if events.isEmpty {
            throw StoreError.sessionEventsEmpty(
                agentID: agentID,
                sessionID: sessionID,
                lineCount: data.split(separator: 0x0A).count,
                filePath: fileURL.path
            )
        }

        storeDecodedEvents(events, for: fileURL)
        return events
    }

    private func journalRecords(from data: Data, hydrate: Bool = true) throws -> [AgentSessionJournalRecord] {
        guard String(data: data, encoding: .utf8) != nil else { throw StoreError.invalidPayload }
        var cursor: UInt64 = 0
        var records: [AgentSessionJournalRecord] = []
        // JSONL uses LF, not every Unicode character classified as a newline inside JSON strings.
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: false) {
            let start = cursor
            cursor = min(UInt64(data.count), cursor + UInt64(line.count) + 1)
            if let event = try decodeJournalLine(Data(line), hydrate: hydrate) {
                records.append(.init(startCursor: start, endCursor: cursor, event: event))
            }
        }
        _ = try SessionInputLifecycle.states(in: records.map(\.event))
        return records
    }

    private func decodeJournalLine(_ data: Data, hydrate: Bool = true) throws -> AgentSessionEvent? {
        var event: AgentSessionEvent
        do {
            event = try decoder.decode(AgentSessionEvent.self, from: data)
        } catch {
            // Inspect an undecodable envelope too: an unknown enum must not hide an incompatible version.
            // Ordinary valid rows need only one JSON decode.
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let version = object?["version"] as? Int,
               !(1...AgentSessionEvent.latestJournalVersion).contains(version) {
                throw StoreError.unsupportedJournalVersion(version)
            }
            if let metadata = object?["runtimeMetadata"] as? [String: Any] {
                try validateRuntimeVersion(metadata["schemaVersion"] as? Int, component: "metadata", maximum: AgentRunMetadata.currentSchemaVersion)
                try validateRuntimeVersion(metadata["engineVersion"] as? Int, component: "engine")
                try validateRuntimeVersion(metadata["completionPolicyVersion"] as? Int, component: "completion policy")
            }
            // Preserve historical malformed-line tolerance only for legacy records.
            if let transitions = object?["inputTransitions"], !(transitions is NSNull) { throw StoreError.invalidPayload }
            if let metadata = object?["runtimeMetadata"], !(metadata is NSNull) { throw StoreError.invalidPayload }
            return nil
        }
        try validateJournalEvent(event)
        if hydrate, let artifact = event.runtimeMetadata?.toolOutputArtifact, artifact.schemaVersion == 2,
           !event.isHistorical || event.toolResult?.data == nil {
            let payload = try readToolOutputArtifact(artifact)
            guard payload.tool == event.toolResult?.tool, payload.ok == event.toolResult?.ok else { throw StoreError.invalidPayload }
            event.toolResult?.data = payload.data
            event.toolResult?.error = payload.error
        }
        return event
    }

    private func validateRuntimeVersion(_ version: Int?, component: String, maximum: Int = 1) throws {
        guard let version else { throw StoreError.invalidPayload }
        guard (1...maximum).contains(version) else { throw StoreError.unsupportedRuntimeVersion(component: component, version: version) }
    }

    private func validateJournalEvent(_ event: AgentSessionEvent) throws {
        guard (1...AgentSessionEvent.latestJournalVersion).contains(event.version) else {
            throw StoreError.unsupportedJournalVersion(event.version)
        }
        if let transitions = event.inputTransitions {
            guard event.version >= 3, !transitions.isEmpty,
                  Set(transitions.map(\.messageId)).count == transitions.count else { throw StoreError.invalidPayload }
            for transition in transitions { try SessionInputLifecycle.validate(transition) }
        }
        guard let metadata = event.runtimeMetadata else { return }
        if let artifact = metadata.toolOutputArtifact {
            guard event.type == .toolResult, metadata.executionPhase == .settled,
                  (1...2).contains(artifact.schemaVersion), artifact.format == "tool_invocation_result_v1",
                  artifact.callEventId == metadata.callEventId, artifact.callEventId == event.toolResult?.callEventId,
                  event.isHistorical || (artifact.agentId == event.agentId && artifact.sessionId == event.sessionId),
                  artifact.sha256.utf8.count == 64,
                  artifact.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  artifact.attachment.mimeType == "application/json", artifact.attachment.sizeBytes > 0,
                  artifact.schemaVersion == 2 || artifact.attachment.sizeBytes <= 25 * 1_024 * 1_024,
                  artifact.attachment.relativePath != nil else { throw StoreError.invalidPayload }
        }
        try validateRuntimeVersion(metadata.schemaVersion, component: "metadata", maximum: AgentRunMetadata.currentSchemaVersion)
        try validateRuntimeVersion(metadata.engineVersion, component: "engine")
        try validateRuntimeVersion(metadata.completionPolicyVersion, component: "completion policy")
        if metadata.auxiliaryPurpose != nil {
            guard metadata.modelResponse != nil, metadata.presentationOnly == true,
                  metadata.stepId != nil, metadata.attemptId != nil,
                  metadata.executionPhase == nil, metadata.completionCandidate == nil,
                  metadata.instruction == nil, metadata.admissionInstructions == nil,
                  event.toolCall == nil, event.toolResult == nil else { throw StoreError.invalidPayload }
        }
        if let record = metadata.usageRequest {
            try record.validateRunIdentity()
            guard metadata.schemaVersion == 2,
                  metadata.presentationOnly != true || metadata.auxiliaryPurpose != nil,
                  record.runId == metadata.runId, record.userTurnId == metadata.userTurnId,
                  let step = metadata.stepId, let attempt = metadata.attemptId,
                  record.id == (try UsageRequestRecord.nativeIdentifier(channelId: record.channelId,
                    runId: metadata.runId, userTurnId: metadata.userTurnId, stepId: step, attemptId: attempt)),
                  record.agentId?.isEmpty == false, record.sessionId?.isEmpty == false,
                  event.isHistorical || (record.agentId == event.agentId && record.sessionId == event.sessionId),
                  !record.provider.isEmpty, !record.model.isEmpty, !record.channelId.isEmpty,
                  record.createdAt.timeIntervalSince1970.isFinite,
                  record.components.isEmpty, record.calls.isEmpty, !record.complete,
                  let usage = record.usage, usage.prompt >= 0, usage.completion >= 0,
                  !usage.prompt.addingReportingOverflow(usage.completion).overflow,
                  usage.cachedInput >= 0, usage.cacheCreationInput >= 0, usage.reasoning >= 0,
                  let raw = metadata.modelResponse,
                  try JSONValueCoder.decode(ModelStepResponse.self, from: raw).usage == usage else {
                throw StoreError.invalidPayload
            }
        } else if metadata.schemaVersion == 2 { throw StoreError.invalidPayload }
        if let instruction = metadata.instruction {
            try validateRuntimeVersion(instruction.schemaVersion, component: "instruction")
            guard instruction.id == event.id, !instruction.id.isEmpty,
                  !instruction.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  instruction.text.utf8.count <= 8_192 else { throw StoreError.invalidPayload }
        }
        let savedState = try metadata.runState.map { try JSONValueCoder.decode(RunStateSnapshot.self, from: $0) }
        if let source = metadata.derivedSource {
            guard source.isValid, source.owner.runId != metadata.runId,
                  event.isHistorical || (source.agentID == event.agentId && source.sessionID == event.sessionId),
                  metadata.requestFingerprint == nil, metadata.inputMessageId == nil,
                  event.inputTransitions == nil,
                  savedState == nil || (savedState?.loopConfig?.completionContract == .background &&
                      savedState?.requestSettings?.derivedSource == source) else { throw StoreError.invalidPayload }
        } else if savedState?.requestSettings?.derivedSource != nil { throw StoreError.invalidPayload }
        if let instructions = metadata.admissionInstructions {
            let userAdmission = metadata.requestFingerprint != nil && metadata.inputMessageId != nil
            let internalReport = savedState?.requestSettings?.coordinatorNotification == true &&
                savedState?.requestSettings?.notificationSourceEventID == metadata.userTurnId &&
                metadata.requestFingerprint == nil && metadata.inputMessageId == nil
            let derivedAdmission = metadata.derivedSource != nil && savedState?.loopConfig?.completionContract == .background
            let proactiveAdmission = savedState?.requestSettings?.proactiveJob != nil &&
                savedState?.loopConfig?.completionContract == .session && metadata.requestFingerprint == nil && metadata.inputMessageId == nil
            guard savedState != nil, userAdmission || internalReport || derivedAdmission || proactiveAdmission, metadata.stepId == nil,
                  metadata.instruction == nil, metadata.presentationOnly != true,
                  Set(instructions.map(\.id)).count == instructions.count else { throw StoreError.invalidPayload }
            for instruction in instructions {
                try validateRuntimeVersion(instruction.schemaVersion, component: "admission instruction")
                guard instruction.kind == .turnContext, !instruction.id.isEmpty, instruction.id != event.id,
                      !instruction.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      instruction.text.utf8.count <= 8_192 else { throw StoreError.invalidPayload }
            }
        }
        if let raw = metadata.completionCandidate {
            let candidate = try JSONValueCoder.decode(RunCompletion.self, from: raw)
            guard event.type == .toolResult, event.toolResult?.ok == true,
                  event.toolResult?.executionOutcome?.state == .completed,
                  event.toolResult?.executionOutcome?.requiresReconciliation != true,
                  metadata.executionPhase == .settled, metadata.observationOnly != true,
                  let callID = metadata.callEventId, event.toolResult?.callEventId == callID,
                  !candidate.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StoreError.invalidPayload
            }
        }
        if let rawEvidence = metadata.verificationEvidence, !rawEvidence.isEmpty {
            let evidence = try rawEvidence.map { try JSONValueCoder.decode(VerificationEvidence.self, from: $0) }
            guard event.type == .toolResult, event.toolResult?.ok == true,
                  event.toolResult?.executionOutcome?.state == .completed,
                  event.toolResult?.executionOutcome?.requiresReconciliation != true,
                  metadata.executionPhase == .settled, metadata.observationOnly == false,
                  let callID = metadata.callEventId, event.toolResult?.callEventId == callID,
                  Set(evidence.map(\.id)).count == evidence.count,
                  evidence.allSatisfy({ !$0.id.isEmpty && $0.tool == event.toolResult?.tool &&
                      $0.observedAt.timeIntervalSince1970.isFinite }) else { throw StoreError.invalidPayload }
        }
        if let snapshot = savedState {
            if !(1...RunStateSnapshot.currentSchemaVersion).contains(snapshot.schemaVersion) {
                throw StoreError.unsupportedRuntimeVersion(component: "run state", version: snapshot.schemaVersion)
            }
            try snapshot.validate()
            guard snapshot.runID == metadata.runId, snapshot.userTurnID == metadata.userTurnId,
                  snapshot.generation == metadata.generation else { throw StoreError.invalidPayload }
        }
        guard !metadata.runId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !metadata.userTurnId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              metadata.generation >= 0,
              metadata.sourceOrder.map({ $0 >= 0 }) ?? true else { throw StoreError.invalidPayload }
    }

    private func cachedDecodedEvents(for fileURL: URL) -> [AgentSessionEvent]? {
        withLock {
            let key = fileURL.path
            guard let entry = decodedEventsCache[key] else { return nil }
            guard let fingerprint = try? sourceFingerprint(fileURL: fileURL),
                  fingerprint.byteCount == entry.byteCount,
                  fingerprint.modifiedAt == entry.modifiedAt else {
                decodedEventsCache.removeValue(forKey: key)
                decodedEventsCacheOrder.removeAll { $0 == key }
                return nil
            }
            return entry.events
        }
    }

    /// Journal rewrites (rename, promotion, deletion) can keep the same size within one timestamp tick,
    /// so they drop the cached copy explicitly instead of relying on the fingerprint.
    private func invalidateDecodedEvents(for fileURL: URL) {
        withLock {
            decodedEventsCache.removeValue(forKey: fileURL.path)
            decodedEventsCacheOrder.removeAll { $0 == fileURL.path }
        }
    }

    private func storeDecodedEvents(_ events: [AgentSessionEvent], for fileURL: URL) {
        withLock {
            let key = fileURL.path
            guard let fingerprint = try? sourceFingerprint(fileURL: fileURL) else {
                decodedEventsCache.removeValue(forKey: key)
                decodedEventsCacheOrder.removeAll { $0 == key }
                return
            }
            decodedEventsCache[key] = DecodedEventsCache(
                byteCount: fingerprint.byteCount,
                modifiedAt: fingerprint.modifiedAt,
                events: events
            )
            decodedEventsCacheOrder.removeAll { $0 == key }
            decodedEventsCacheOrder.append(key)
            while decodedEventsCacheOrder.count > Self.decodedEventsCacheLimit {
                decodedEventsCache.removeValue(forKey: decodedEventsCacheOrder.removeFirst())
            }
        }
    }

    private struct AgentSessionSummaryCache: Codable {
        var schemaVersion: Int
        var sourceByteCount: Int
        var sourceModifiedAt: TimeInterval
        var summary: AgentSessionSummary
        var stateEvents: [AgentSessionEvent]
    }

    private func loadSessionSummary(agentID: String, sessionID: String, fileURL: URL) throws -> AgentSessionSummary {
        if let cached = try? readSummaryCache(agentID: agentID, sessionID: sessionID, fileURL: fileURL) {
            return cached
        }
        return try refreshSummaryCache(agentID: agentID, sessionID: sessionID, fileURL: fileURL)
    }

    @discardableResult
    private func refreshSummaryCache(agentID: String, sessionID: String, fileURL: URL) throws -> AgentSessionSummary {
        let events = try readEvents(agentID: agentID, sessionID: sessionID)
        let summary = summaryForSession(agentID: agentID, sessionID: sessionID, events: events)
        updateSummaryCacheIfPossible(summary, events: events, fileURL: fileURL)
        return summary
    }

    private func readSummaryCache(agentID: String, sessionID: String, fileURL: URL) throws -> AgentSessionSummary? {
        try readSummarySnapshot(agentID: agentID, sessionID: sessionID, fileURL: fileURL)?.summary
    }

    private func readSummarySnapshot(agentID: String, sessionID: String, fileURL: URL) throws -> AgentSessionSummaryCache? {
        guard let cacheURL = sessionSummaryCacheURL(agentID: agentID, sessionID: sessionID),
              fileManager.fileExists(atPath: cacheURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: cacheURL)
        let cache = try decoder.decode(AgentSessionSummaryCache.self, from: data)
        guard cache.schemaVersion == Self.summaryCacheSchemaVersion,
              let fingerprint = try sourceFingerprint(fileURL: fileURL),
              cache.sourceByteCount == fingerprint.byteCount,
              cache.sourceModifiedAt == fingerprint.modifiedAt else {
            return nil
        }
        return cache
    }

    private func summaryStateEvents(in events: [AgentSessionEvent]) -> [AgentSessionEvent] {
        let events = events.filter { $0.runtimeMetadata?.derivedSource == nil }
        let answeredIDs = Set(events.compactMap(\.inputResponse?.requestId))
        var stateEvents: [AgentSessionEvent] = []
        if let status = events.last(where: { $0.runStatus != nil }) { stateEvents.append(status) }
        if let request = events.last(where: { event in
            event.inputRequest.map { !answeredIDs.contains($0.id) } ?? false
        }) { stateEvents.append(request) }
        // Parallel-agent indicators need current links/tasks, not their entire
        // transcripts. Keep only the latest event for each child/task.
        var latestLinks: [String: AgentSessionEvent] = [:]
        var latestTasks: [String: AgentSessionEvent] = [:]
        for event in events {
            if let child = event.subSession { latestLinks[child.childSessionId] = event }
            if let task = event.longChatTask { latestTasks[task.task.id] = event }
        }
        stateEvents += latestLinks.values.sorted { $0.createdAt < $1.createdAt }
        stateEvents += latestTasks.values.sorted { $0.createdAt < $1.createdAt }
        return stateEvents
    }

    private func updateSummaryCacheIfPossible(_ summary: AgentSessionSummary, events: [AgentSessionEvent], fileURL: URL) {
        do { try writeSummaryCache(summary, events: events, fileURL: fileURL) }
        catch {
            logger.warning("Session summary cache could not be written", metadata: [
                "agent_id": .string(summary.agentId), "session_id": .string(summary.id),
                "error": .string(String(describing: error))
            ])
        }
    }

    private func writeSummaryCache(_ summary: AgentSessionSummary, events: [AgentSessionEvent], fileURL: URL) throws {
        guard let cacheURL = sessionSummaryCacheURL(agentID: summary.agentId, sessionID: summary.id),
              let fingerprint = try sourceFingerprint(fileURL: fileURL) else {
            return
        }
        let cache = AgentSessionSummaryCache(
            schemaVersion: Self.summaryCacheSchemaVersion,
            sourceByteCount: fingerprint.byteCount,
            sourceModifiedAt: fingerprint.modifiedAt,
            summary: summary,
            stateEvents: summaryStateEvents(in: events)
        )
        let payload = try encoder.encode(cache)
        try payload.write(to: cacheURL, options: .atomic)
    }

    private func removeSummaryCache(agentID: String, sessionID: String) {
        guard let cacheURL = sessionSummaryCacheURL(agentID: agentID, sessionID: sessionID),
              fileManager.fileExists(atPath: cacheURL.path) else {
            return
        }
        try? fileManager.removeItem(at: cacheURL)
    }

    private func sessionSummaryCacheURL(agentID: String, sessionID: String) -> URL? {
        guard let resolver = try? sessionPathResolver(agentID: agentID) else {
            return nil
        }
        return resolver.existingLocation(sessionID: sessionID)?.summaryURL
            ?? resolver.legacyLocation(sessionID: sessionID).summaryURL
    }

    private func sourceFingerprint(fileURL: URL) throws -> (byteCount: Int, modifiedAt: TimeInterval)? {
        // Not `URL.resourceValues`: a URL instance caches them, so a fingerprint taken from the same
        // URL after an append would still describe the file as it was before the write.
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber,
              let modifiedAt = attributes[.modificationDate] as? Date else {
            return nil
        }
        return (size.intValue, modifiedAt.timeIntervalSince1970)
    }

    private static func paginated(_ summaries: [AgentSessionSummary], limit: Int?, offset: Int) -> [AgentSessionSummary] {
        let start = min(max(0, offset), summaries.count)
        let tail = summaries[start...]
        guard let limit else {
            return Array(tail)
        }
        return Array(tail.prefix(max(0, limit)))
    }

    private func summaryForSession(agentID: String, sessionID: String, events: [AgentSessionEvent]) -> AgentSessionSummary {
        var title = "Session \(sessionID.prefix(8))"
        var parentSessionID: String?
        var kind: AgentSessionKind = .chat
        var projectID: String?
        var taskID: String?
        var workspaceID: String?
        var titleIsAutomatic = false
        var userMessages: [AgentSessionMessage] = []
        var messages: [AgentSessionMessage] = []
        var createdAt = events.first?.createdAt ?? Date()
        var updatedAt = createdAt
        var messageCount = 0
        var lastPreview: String?

        for event in events where event.runtimeMetadata?.derivedSource == nil {
            createdAt = min(createdAt, event.createdAt)
            updatedAt = max(updatedAt, event.createdAt)

            if event.type == .sessionCreated, let metadata = event.metadata {
                title = metadata.title
                parentSessionID = metadata.parentSessionId
                kind = metadata.kind
                projectID = metadata.projectId
                taskID = metadata.taskId
                workspaceID = metadata.workspaceId
                titleIsAutomatic = metadata.titleIsAutomatic
            }

            if let message = event.message, event.runtimeMetadata?.auxiliaryPurpose == nil {
                if message.role == .user {
                    userMessages.append(message)
                }
                messageCount += 1
                messages.append(message)
            }
        }

        // Only the newest message with a preview matters; scanning from the end avoids trimming every transcript line.
        for message in messages.reversed() {
            if let preview = previewText(for: message), !preview.isEmpty {
                lastPreview = preview
                break
            }
        }

        if titleIsAutomatic {
            title = AgentSessionTitleGenerator.title(for: userMessages)
        }

        let userTurnCount = (try? readUserTurnCount(agentID: agentID, sessionID: sessionID)) ?? 0

        return AgentSessionSummary(
            id: sessionID,
            agentId: agentID,
            title: title,
            parentSessionId: parentSessionID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messageCount: messageCount,
            lastMessagePreview: lastPreview,
            kind: kind,
            userTurnCount: userTurnCount,
            projectId: projectID,
            taskId: taskID,
            workspaceId: workspaceID
        )
    }

    private func previewText(for message: AgentSessionMessage) -> String? {
        for segment in message.segments {
            if let text = segment.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text.count > 120 ? String(text.prefix(120)) : text
            }
            if let attachment = segment.attachment {
                return "Attachment: \(attachment.name)"
            }
        }
        return nil
    }

    func resolvedAgentDirectoryURL(agentID: String) -> URL? {
        let regular = agentsRootURL.appendingPathComponent(agentID, isDirectory: true)
        if fileManager.fileExists(atPath: regular.path) {
            return regular
        }
        let system = agentsRootURL.appendingPathComponent(".system", isDirectory: true)
            .appendingPathComponent(agentID, isDirectory: true)
        if fileManager.fileExists(atPath: system.path) {
            return system
        }
        return nil
    }

    private func sessionsDirectoryURL(agentID: String, createIfMissing: Bool) throws -> URL {
        guard let agentDirectory = resolvedAgentDirectoryURL(agentID: agentID) else {
            throw StoreError.agentNotFound
        }

        let sessionsDirectory = agentDirectory.appendingPathComponent("sessions", isDirectory: true)
        if createIfMissing {
            try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        }
        return sessionsDirectory
    }

    private func sessionFileURL(agentID: String, sessionID: String) -> URL? {
        guard let resolver = try? sessionPathResolver(agentID: agentID) else {
            return nil
        }
        return resolver.existingLocation(sessionID: sessionID)?.sessionFileURL
    }

    func assetsDirectoryURL(agentID: String, sessionID: String) -> URL? {
        guard let resolver = try? sessionPathResolver(agentID: agentID) else {
            return nil
        }
        return resolver.existingLocation(sessionID: sessionID)?.assetsURL
    }

    private func sessionPathResolver(agentID: String) throws -> AgentSessionPathResolver {
        guard let agentDirectory = resolvedAgentDirectoryURL(agentID: agentID) else {
            throw StoreError.agentNotFound
        }
        return AgentSessionPathResolver(agentDirectoryURL: agentDirectory, fileManager: fileManager)
    }

    private func migrateLegacySessions(in sessionsDirectory: URL) throws {
        let files = try fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }

        let resolver = AgentSessionPathResolver(
            agentDirectoryURL: sessionsDirectory.deletingLastPathComponent(),
            fileManager: fileManager
        )

        for fileURL in files {
            let sessionID = fileURL.deletingPathExtension().lastPathComponent
            guard resolver.existingCanonicalLocation(sessionID: sessionID) == nil else {
                continue
            }

            let createdAt = legacySessionCreatedAt(fileURL: fileURL) ?? legacyFileModifiedAt(fileURL: fileURL) ?? Date()
            let destination = resolver.canonicalLocation(sessionID: sessionID, createdAt: createdAt)
            try fileManager.createDirectory(at: destination.directoryURL, withIntermediateDirectories: true)
            let legacy = resolver.legacyLocation(sessionID: sessionID)

            try moveIfPossible(from: legacy.summaryURL, to: destination.summaryURL)
            try moveIfPossible(from: legacy.sidecarURL, to: destination.sidecarURL)
            try moveIfPossible(from: legacy.acpStateURL, to: destination.acpStateURL)
            try moveIfPossible(from: legacy.assetsURL, to: destination.assetsURL)
            try moveIfPossible(from: legacy.sessionFileURL, to: destination.sessionFileURL)
        }
    }

    private func moveIfPossible(from sourceURL: URL, to destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceURL.path),
              !fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private func legacySessionCreatedAt(fileURL: URL) -> Date? {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        for line in content.split(whereSeparator: \.isNewline) {
            guard line.contains(where: { !$0.isWhitespace }),
                  let lineData = String(line).data(using: .utf8),
                  let event = try? decoder.decode(AgentSessionEvent.self, from: lineData),
                  event.type == .sessionCreated else {
                continue
            }
            return event.createdAt
        }
        return nil
    }

    private func legacyFileModifiedAt(fileURL: URL) -> Date? {
        try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func migratedAttachmentURL(agentID: String, legacyRelativePath: String) -> URL? {
        let prefix = "sessions/"
        guard legacyRelativePath.hasPrefix(prefix) else {
            return nil
        }
        let tail = String(legacyRelativePath.dropFirst(prefix.count))
        guard let assetsRange = tail.range(of: ".assets/") else {
            return nil
        }
        let sessionID = String(tail[..<assetsRange.lowerBound])
        let fileName = String(tail[assetsRange.upperBound...])
        guard !sessionID.isEmpty,
              !fileName.isEmpty,
              let resolver = try? sessionPathResolver(agentID: agentID),
              let location = resolver.existingCanonicalLocation(sessionID: sessionID) else {
            return nil
        }
        return location.assetsURL.appendingPathComponent(fileName, isDirectory: false)
    }

    func normalizedAgentID(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StoreError.invalidAgentID
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard trimmed.rangeOfCharacter(from: allowed.inverted) == nil else {
            throw StoreError.invalidAgentID
        }

        return trimmed
    }

    func normalizedSessionID(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StoreError.invalidSessionID
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard trimmed.rangeOfCharacter(from: allowed.inverted) == nil else {
            throw StoreError.invalidSessionID
        }

        return trimmed
    }

    private func normalizedOptionalSessionID(_ raw: String?) throws -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        return try normalizedSessionID(trimmed)
    }

    private static func shortSessionID(_ sessionID: String) -> String {
        let prefix = "session-"
        if sessionID.hasPrefix(prefix) {
            return String(sessionID.dropFirst(prefix.count).prefix(8))
        }
        return String(sessionID.prefix(8))
    }

    private func sanitizeFilename(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ""
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let scalars = trimmed.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }

        let normalized = String(scalars)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))

        return normalized
    }
}
