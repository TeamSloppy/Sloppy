import Foundation
import Protocols

extension CoreService {
    /// Read-only projection of the latest supported surface revisions in this session's journal.
    public func listAgentUISurfaces(agentID: String, sessionID: String) throws -> [AgentUISurfaceSnapshot] {
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        var surfaces: [String: AgentUISurfaceSnapshot] = [:]
        for event in detail.events where event.type == .message {
            guard event.agentId == detail.summary.agentId, event.sessionId == detail.summary.id,
                  event.message?.role == .assistant, let surface = event.message?.uiSurface,
                  (try? surface.validate()) != nil else { continue }
            if let previous = surfaces[surface.surfaceId], previous.revision >= surface.revision { continue }
            surfaces[surface.surfaceId] = surface
        }
        return surfaces.values.sorted { $0.surfaceId < $1.surfaceId }
    }
}
