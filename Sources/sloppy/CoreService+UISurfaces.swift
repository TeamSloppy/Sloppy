import Foundation
import Protocols

extension CoreService: UIToolService {
    enum AgentUIError: Error {
        case revisionConflict(Int)
        case actionConflict, invalidAction, forbidden
    }

    /// Read-only projection of the latest supported surface revisions in this session's journal.
    public func listAgentUISurfaces(agentID: String, sessionID: String) throws -> [AgentUISurfaceSnapshot] {
        try agentUISurfaceStates(agentID: agentID, sessionID: sessionID).filter { $0.isDeleted != true }
    }

    func agentUISurfaceStates(agentID: String, sessionID: String) throws -> [AgentUISurfaceSnapshot] {
        var detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        let persisted = Set(detail.events.map(\.id))
        var repaired = false
        for entry in try sessionMessageInbox().entries
        where entry.agentId == agentID && entry.sessionId == sessionID && entry.uiSnapshot != nil
            && !persisted.contains("ui-accepted-" + entry.id)
        {
            try persistAcceptedUISnapshot(entry)
            repaired = true
        }
        if repaired { detail = try getAgentSession(agentID: agentID, sessionID: sessionID) }
        var surfaces: [String: AgentUISurfaceSnapshot] = [:]
        for event in detail.events where event.type == .message {
            guard event.agentId == detail.summary.agentId, event.sessionId == detail.summary.id,
                event.message?.role == .assistant, let surface = event.message?.uiSurface,
                (try? surface.validate()) != nil
            else { continue }
            if let previous = surfaces[surface.surfaceId], previous.revision >= surface.revision { continue }
            surfaces[surface.surfaceId] = surface
        }
        return surfaces.values.sorted { $0.surfaceId < $1.surfaceId }
    }

    func renderAgentUI(agentID: String, sessionID: String, request: AgentUIRenderRequest) throws -> AgentUISurfaceSnapshot {
        let transaction = try AgentUITransaction(json: request.messages)
        let previous = try agentUISurfaceStates(agentID: agentID, sessionID: sessionID).first { $0.surfaceId == transaction.surfaceId }
        guard request.expectedRevision >= 0, request.expectedRevision == (previous?.revision ?? 0) else {
            throw AgentUIError.revisionConflict(previous?.revision ?? 0)
        }
        let surface = try transaction.applying(to: previous, fallbackText: request.fallbackText)
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        let event = AgentSessionEvent(
            agentId: detail.summary.agentId, sessionId: detail.summary.id, type: .message,
            message: .init(role: .assistant, segments: [.init(kind: .text, text: surface.fallbackText)], uiSurface: surface))
        do {
            let summary = try sessionStore.appendEvents(agentID: agentID, sessionID: sessionID, events: [event])
            publishLiveSessionEvents(agentID: agentID, sessionID: sessionID, summary: summary, events: [event])
        } catch { throw AgentSessionError.storageFailure }
        return surface
    }

    func agentUICatalog(agentID: String, sessionID: String, surfaceID: String?) throws -> JSONValue {
        let surfaces = try agentUISurfaceStates(agentID: agentID, sessionID: sessionID)
        return .object([
            "catalogId": .string(AgentUISurfaceSnapshot.supportedCatalogID), "version": .string("v0.9.1"),
            "componentSchemas": try JSONDecoder().decode(JSONValue.self, from: AgentUIComponent.catalogSchemaData()),
            "operations": .array(["createSurface", "updateComponents", "updateDataModel", "deleteSurface"].map(JSONValue.string)),
            "constraints": .string(
                "One surface per atomic batch; required root, fully reachable tree, at most 128 components and depth 16. Forms use absolute JSON Pointer binding paths. Button action is a symbolic event name delivered to this agent, never a tool invocation. No functions, theme or sendDataModel. Detach nodes by deleting and recreating the surface. messages is a JSON-array string, at most 64 KiB. Data model supports JSON Pointers with replacement/removal of existing array indices."
            ),
            "surfaces": .array(
                surfaces.prefix(32).map {
                    .object([
                        "surfaceId": .string($0.surfaceId), "revision": .number(Double($0.revision)),
                        "isDeleted": .bool($0.isDeleted == true), "submitted": .bool($0.submittedActionId != nil),
                    ])
                }),
            "hasMore": .bool(surfaces.count > 32),
            "surface": surfaceID.flatMap { id in surfaces.first { $0.surfaceId == id } }.map(encodeJSONValue) ?? .null,
        ])
    }
}
