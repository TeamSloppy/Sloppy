import Foundation
import Protocols

extension AgentSessionFileStore {
    /// Copies factual context without transferring source ownership, receipts or runtime authority.
    public func makeHistoricalEvents(_ events: [AgentSessionEvent], agentID: String, sessionID: String) throws -> [AgentSessionEvent] {
        var ids: [String: String] = [:]
        for event in events {
            guard !event.id.isEmpty, ids[event.id] == nil else { throw StoreError.invalidPayload }
            ids[event.id] = UUID().uuidString
        }
        var assets: [String: AgentAttachment] = [:]
        return try events.map { source in
            var copy = source
            copy.id = ids[source.id] ?? UUID().uuidString
            copy.agentId = agentID
            copy.sessionId = sessionID
            copy.forkOrigin = .init(sourceAgentId: source.agentId, sourceSessionId: source.sessionId, sourceEventId: source.id)
            copy.runtimeMetadata = nil
            copy.inputTransitions = nil
            copy.runControl = nil
            if let correlated = copy.toolResult?.callEventId { copy.toolResult?.callEventId = ids[correlated] ?? correlated }
            if var message = copy.message {
                message.id = UUID().uuidString
                message.segments = try message.segments.map { segment in
                    var segment = segment
                    if let attachment = segment.attachment {
                        let key = source.agentId + "/" + attachment.id
                        if let copied = assets[key] { segment.attachment = copied }
                        else {
                            guard let file = try resolveAttachmentFileURL(agentID: source.agentId, attachment: attachment) else { throw StoreError.invalidPayload }
                            guard let root = resolvedAgentDirectoryURL(agentID: source.agentId)?.resolvingSymlinksInPath(),
                                  file.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else { throw StoreError.invalidPayload }
                            let data = try Data(contentsOf: file)
                            let upload = AgentAttachmentUpload(name: attachment.name, mimeType: attachment.mimeType,
                                sizeBytes: data.count, contentBase64: data.base64EncodedString())
                            guard let copied = try persistAttachments(agentID: agentID, sessionID: sessionID, uploads: [upload]).first else { throw StoreError.invalidPayload }
                            assets[key] = copied
                            segment.attachment = copied
                        }
                    }
                    return segment
                }
                copy.message = message
            }
            return copy
        }
    }
}
