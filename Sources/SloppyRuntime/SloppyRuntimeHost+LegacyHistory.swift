import Foundation
import Protocols

extension SloppyRuntimeHost {
    func latestLegacySessionID(workspaceURL: URL) throws -> String? {
        let root = workspaceURL.appendingPathComponent(".ada/workspace/agents")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(Self.agentID).path) else { return nil }
        return try AgentSessionFileStore(agentsRootURL: root).listSessions(agentID: Self.agentID, limit: 1).first?.id
    }

    /// Import only settled context. Source bytes remain untouched and copied records cannot own effects.
    func importLegacyHistoryIfNeeded(store: AgentSessionFileStore, sessionID: String, workspaceURL: URL) throws {
        let current = try store.loadSession(agentID: Self.agentID, sessionID: sessionID)
        guard current.events.allSatisfy({ $0.type == .sessionCreated }) else { return }
        let legacy = AgentSessionFileStore(agentsRootURL: workspaceURL.appendingPathComponent(".ada/workspace/agents"))
        guard (try? legacy.sessionFilePath(agentID: Self.agentID, sessionID: sessionID)) != nil else { return }
        let lease = try FileOwnershipLease.acquire(at: URL(fileURLWithPath: store.sessionFilePath(agentID: Self.agentID,
            sessionID: sessionID)).appendingPathExtension("owner.lock"))
        defer { lease.release() }
        guard try store.loadSession(agentID: Self.agentID, sessionID: sessionID).events.allSatisfy({ $0.type == .sessionCreated }) else { return }
        let detail = try legacy.loadSession(agentID: Self.agentID, sessionID: sessionID)
        guard detail.events.allSatisfy({ $0.runtimeMetadata == nil && $0.inputTransitions == nil && $0.runControl == nil }) else {
            throw HostError.runtimeFailure("The legacy path contains native ownership records. Use its original compatible store.")
        }
        guard SessionToolRecovery.interruptionEvents(for: detail).isEmpty else { throw HostError.reconciliationRequired }
        var attachments: [String: AgentAttachment] = [:]
        let copies = try detail.events.filter { $0.type != .sessionCreated }.map { event in
            var copy = event
            copy.id = UUID().uuidString
            copy.forkOrigin = .init(sourceAgentId: event.agentId, sourceSessionId: event.sessionId, sourceEventId: event.id)
            if var message = copy.message {
                message.id = copy.id
                message.segments = try message.segments.map { segment in
                    var segment = segment
                    if let attachment = segment.attachment {
                        if let previous = attachments[attachment.id] { segment.attachment = previous }
                        else {
                            let bytes = attachment.relativePath == nil ? nil : try legacy.readInputAttachment(agentID: Self.agentID,
                                sessionID: sessionID, attachment: attachment)
                            let saved = try store.persistAttachments(agentID: Self.agentID, sessionID: sessionID, uploads: [
                                .init(name: attachment.name, mimeType: attachment.mimeType, sizeBytes: attachment.sizeBytes,
                                    contentBase64: bytes?.base64EncodedString())
                            ])
                            guard let saved = saved.first else { throw HostError.runtimeFailure("The legacy attachment could not be copied.") }
                            attachments[attachment.id] = saved; segment.attachment = saved
                        }
                    }
                    return segment
                }
                copy.message = message
            }
            return copy
        }
        if !copies.isEmpty { _ = try store.appendEvents(agentID: Self.agentID, sessionID: sessionID, events: copies) }
    }
}
