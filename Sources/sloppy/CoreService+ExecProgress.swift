import Foundation
import Protocols

extension CoreService {
    func reportSessionRunStatus(agentID: String, sessionID: String, status: AgentRunStatusEvent) async {
        guard !Task.isCancelled else { return }
        let event = AgentSessionEvent(agentId: agentID, sessionId: sessionID, type: .runStatus, runStatus: status)
        do {
            let summary = try sessionStore.appendEvents(agentID: agentID, sessionID: sessionID, events: [event])
            publishLiveSessionEvents(agentID: agentID, sessionID: sessionID, summary: summary, events: [event])
        } catch {
            logger.warning("Could not record command progress", metadata: [
                "agent_id": .string(agentID), "session_id": .string(sessionID), "error": .string(String(describing: error))
            ])
        }
    }
}
