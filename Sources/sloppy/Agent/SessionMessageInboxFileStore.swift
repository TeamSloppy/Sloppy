import Foundation
import Logging
import Protocols

/// Owned by CoreService; native receipts live in the journal and legacy receipts in this file.
final class SessionMessageInboxFileStore {
    private let logger = Logger(label: "sloppy.core.session-inbox")
    enum State: String, Codable, Sendable { case queued, processing, delivered, failed, interrupted }
    struct Entry: Codable, Sendable, Equatable {
        var id: String
        var agentId: String
        var sessionId: String
        var request: AgentSessionPostMessageRequest
        var sourceRequest: AgentSessionPostMessageRequest? = nil
        var origin: AgentSessionPeerOrigin?
        var uiSnapshot: AgentUISurfaceSnapshot?
        var uiSubmission: AgentUISubmission?
        var state: State = .queued
        var error: String?
        // Optional so existing queues decode unchanged and older Core versions can still read them.
        var recordedOnly: Bool?
        var receiptState: String { recordedOnly == true ? "recorded" : state.rawValue }

        func originalRequest() throws -> AgentSessionPostMessageRequest {
            guard var source = sourceRequest else { return request }
            guard source.attachments.count == request.attachments.count else { throw PeerSessionMessageError.conflict }
            for index in source.attachments.indices { source.attachments[index].contentBase64 = request.attachments[index].contentBase64 }
            return source
        }
    }

    private struct Identity: Hashable {
        let agent: String
        let session: String
        let message: String
        init(_ entry: Entry) { agent = entry.agentId; session = entry.sessionId; message = entry.id }
    }

    private let url: URL
    private let scopesURL: URL
    private(set) var scopes: [String: [String]]
    private(set) var entries: [Entry]
    private var canonicalIDs: Set<Identity> = []
    private(set) var cacheWriteError: String?
    private(set) var quarantinedCache: URL?
    private var unpreservedCacheError: (any Error)?

    init(root: URL, recovering canonical: [Entry]? = nil,
         preserveCorruptCache: ((URL, URL) throws -> Void)? = nil) throws {
        url = root.appendingPathComponent("session-messages/inbox.json")
        scopesURL = root.appendingPathComponent("session-messages/worker-scopes.json")
        scopes = FileManager.default.fileExists(atPath: scopesURL.path)
            ? try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: scopesURL)) : [:]
        if FileManager.default.fileExists(atPath: url.path) {
            do { entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url)) }
            catch {
                guard canonical != nil else { throw error }
                entries = []
                // Preserve unreadable legacy data for manual recovery; never guess its requests.
                let backup = url.deletingLastPathComponent().appendingPathComponent("inbox-corrupt-" + UUID().uuidString + ".json")
                do {
                    if let preserveCorruptCache { try preserveCorruptCache(url, backup) }
                    else { try FileManager.default.copyItem(at: url, to: backup) }
                    quarantinedCache = backup
                } catch {
                    unpreservedCacheError = error
                    cacheWriteError = String(describing: error)
                    logger.warning("session_messages.cache_preservation_failed", metadata: ["error": "\(error)"])
                }
            }
        } else { entries = [] }
        if let canonical { try reconcileCanonical(canonical) }
    }

    func reconcileCanonical(_ canonical: [Entry]) throws {
        let prior = Set(entries.map(Identity.init))
        canonicalIDs = Set(canonical.map(Identity.init))
        let selected = canonical.filter { $0.state == .queued || $0.origin != nil || $0.uiSubmission != nil || prior.contains(Identity($0)) }
        try transaction { entries in
            entries.removeAll { canonicalIDs.contains(Identity($0)) }
            entries.append(contentsOf: selected)
        }
    }

    func registerCanonical(_ entry: Entry) { canonicalIDs.insert(Identity(entry)) }

    func transaction(_ update: (inout [Entry]) throws -> Void) throws {
        var next = entries
        try update(&next)
        let data = try JSONEncoder().encode(next)
        let changesLegacy = entries.filter { !canonicalIDs.contains(Identity($0)) }
            != next.filter { !canonicalIDs.contains(Identity($0)) }
        if let unpreservedCacheError {
            // The original may contain unknown legacy requests. Until it is preserved,
            // canonical entries can progress in memory, but nothing may overwrite it.
            guard !changesLegacy else { throw unpreservedCacheError }
            entries = next
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            cacheWriteError = nil
        } catch {
            guard !changesLegacy else { throw error }
            let description = String(describing: error)
            if cacheWriteError != description {
                logger.warning("session_messages.cache_write_failed", metadata: ["error": "\(description)"])
            }
            cacheWriteError = description
        }
        entries = next
    }

    func existingEquivalent(to entry: Entry) throws -> Entry? {
        if let existing = entries.first(where: { $0.id == entry.id }) {
            guard existing.agentId == entry.agentId, existing.sessionId == entry.sessionId,
                  existing.uiSubmission == entry.uiSubmission,
                  try NativeSessionDelivery.fingerprint(existing.originalRequest(), peerOrigin: existing.origin)
                    == NativeSessionDelivery.fingerprint(entry.originalRequest(), peerOrigin: entry.origin)
            else { throw PeerSessionMessageError.conflict }
            return existing
        }
        return nil
    }

    func enqueue(_ entry: Entry) throws -> Entry {
        if let existing = try existingEquivalent(to: entry) { return existing }
        try transaction { $0.append(entry) }
        return entry
    }

    func rememberScope(sessionID: String, toolIDs: Set<String>) throws {
        var next = scopes
        next[sessionID] = toolIDs.sorted()
        try FileManager.default.createDirectory(at: scopesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: scopesURL, options: .atomic)
        scopes = next
    }

    func update(id: String, state: State, error: String? = nil) throws {
        try transaction { entries in
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index].state = state
            entries[index].error = error
        }
    }

    func recordWithoutRun(id: String) throws {
        try transaction { entries in
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index].state = .delivered
            entries[index].recordedOnly = true
            entries[index].error = nil
        }
    }
}

enum PeerSessionMessageError: Error {
    case conflict, invalidArguments, chainLimit, selfMessage, workerUnavailable
    var code: String {
        switch self {
        case .conflict: "message_id_conflict"
        case .invalidArguments: "invalid_arguments"
        case .chainLimit: "message_chain_limit"
        case .selfMessage: "self_message"
        case .workerUnavailable: "worker_scope_unavailable"
        }
    }
    var description: String {
        switch self {
        case .conflict: "This messageId was already used for a different delivery."
        case .invalidArguments: "A valid target, nonempty content and an optional UUID messageId are required."
        case .chainLimit: "This automatic message chain has reached eight deliveries. Wait for a new user turn."
        case .selfMessage: "Use the current context directly; a session cannot message itself."
        case .workerUnavailable: "The worker's original execution scope is unavailable."
        }
    }
}
