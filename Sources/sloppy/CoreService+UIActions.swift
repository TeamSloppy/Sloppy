import Foundation
import Protocols

extension CoreService {
    func persistAcceptedUISnapshot(_ entry: SessionMessageInboxFileStore.Entry) throws {
        guard let snapshot = entry.uiSnapshot else { return }
        let detail = try getAgentSession(agentID: entry.agentId, sessionID: entry.sessionId)
        let id = "ui-accepted-" + entry.id
        guard !detail.events.contains(where: { $0.id == id }) else { return }
        let event = AgentSessionEvent(
            id: id, agentId: entry.agentId, sessionId: entry.sessionId, type: .message,
            message: .init(role: .assistant, segments: [.init(kind: .text, text: "Form response accepted")], uiSurface: snapshot))
        let summary = try sessionStore.appendEvents(agentID: entry.agentId, sessionID: entry.sessionId, events: [event])
        publishLiveSessionEvents(agentID: entry.agentId, sessionID: entry.sessionId, summary: summary, events: [event])
    }

    public func submitAgentUIAction(
        agentID: String, sessionID: String, surfaceID: String, submission: AgentUISubmission, userID: String? = nil
    ) throws -> AgentUIActionReceipt {
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        guard UUID(uuidString: submission.actionId) != nil else { throw AgentUIError.invalidAction }
        var conversationID: String?
        if detail.summary.kind == .longChat {
            conversationID = sessionID
        } else if let parent = detail.summary.parentSessionId,
            try getAgentSession(agentID: agentID, sessionID: parent).summary.kind == .longChat
        {
            conversationID = parent
        }
        if detail.summary.kind == .longChatWorker, conversationID == nil { throw AgentUIError.invalidAction }
        let owner =
            try conversationID.map { try getLongChat(agentID: agentID, sessionID: $0).userId }
            ?? detail.events.reversed().compactMap(\.message).first(where: { $0.role == .user })?.userId ?? "local"
        let sender = userID ?? owner
        if conversationID != nil, sender != owner { throw AgentUIError.forbidden }
        let storage = try sessionMessageInbox()
        if let existing = storage.entries.first(where: { $0.id == submission.actionId }) {
            guard existing.agentId == agentID, existing.sessionId == sessionID, existing.uiSnapshot?.surfaceId == surfaceID,
                existing.uiSubmission == submission, existing.request.userId == sender, let snapshot = existing.uiSnapshot
            else { throw AgentUIError.actionConflict }
            try finishUIActionDelivery(existing, detail: detail)
            return .init(actionId: submission.actionId, surfaceId: surfaceID, revision: snapshot.revision, status: "accepted")
        }
        guard let surface = try agentUISurfaceStates(agentID: agentID, sessionID: sessionID).first(where: { $0.surfaceId == surfaceID })
        else { throw AgentUIError.invalidAction }
        guard surface.revision == submission.revision, surface.submittedActionId == nil else {
            throw AgentUIError.revisionConflict(surface.revision)
        }
        let accepted: AgentUISurfaceSnapshot
        do { accepted = try surface.accepting(submission) } catch { throw AgentUIError.invalidAction }
        guard let button = surface.components.first(where: { $0.id == submission.componentId }), let action = button.action else {
            throw AgentUIError.invalidAction
        }
        let body: JSONValue = .object([
            "surfaceId": .string(surfaceID), "componentId": .string(button.id),
            "action": .string(action), "values": encodeJSONValue(submission.values), "dataModel": encodeJSONValue(accepted.dataModel),
        ])
        let content = "[UI action]\n" + (stableJSONString(body) ?? "{}")
        let request = AgentSessionPostMessageRequest(
            userId: sender, content: content, clientMessageId: submission.actionId, supportsA2UI: true)
        let entry = try storage.enqueue(
            .init(
                id: submission.actionId, agentId: agentID, sessionId: sessionID, request: request,
                uiSnapshot: accepted, uiSubmission: submission))
        try finishUIActionDelivery(entry, detail: detail)
        return .init(actionId: submission.actionId, surfaceId: surfaceID, revision: accepted.revision, status: "accepted")
    }

    func uiActionDisplayText(_ entry: SessionMessageInboxFileStore.Entry) -> String {
        guard let snapshot = entry.uiSnapshot, let submission = entry.uiSubmission else { return entry.request.content }
        let title = snapshot.components.first(where: { $0.id == submission.componentId })?.label ?? "Form response"
        let fields = snapshot.components.filter(\.isInput).compactMap { field -> String? in
            guard let path = field.binding, let value = submission.values[path] else { return nil }
            let text: String
            if let selected = value.string {
                text = field.options?.first(where: { $0.value == selected })?.label ?? selected
            } else if let flag = value.boolean {
                text = flag ? "Yes" : "No"
            } else if let number = value.number {
                text = String(number)
            } else {
                text = "—"
            }
            return (field.label ?? "Value") + ": " + text
        }
        return ([title] + fields).joined(separator: "\n")
    }

    private func finishUIActionDelivery(_ entry: SessionMessageInboxFileStore.Entry, detail: AgentSessionDetail) throws {
        _ = try persistSessionInboxMessage(entry)
        if detail.summary.kind == .longChat {
            _ = try enqueueLongChatMessage(agentID: entry.agentId, sessionID: entry.sessionId, request: entry.request)
            try sessionMessageInbox().update(id: entry.id, state: .delivered)
        } else if entry.state == .queued {
            scheduleSessionInbox(agentID: entry.agentId, sessionID: entry.sessionId)
        }
    }
}
