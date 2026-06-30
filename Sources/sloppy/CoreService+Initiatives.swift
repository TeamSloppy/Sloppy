import Foundation
import Protocols

extension CoreService {
    public func listInitiatives(projectID: String) async throws -> InitiativeListResponse {
        let normalizedID = try await requireExistingProjectID(projectID)
        let initiatives = await store.listInitiatives(projectID: normalizedID)
        return InitiativeListResponse(initiatives: initiatives)
    }

    public func getInitiative(projectID: String, initiativeID: String) async throws -> InitiativeDetailResponse {
        let normalizedID = try await requireExistingProjectID(projectID)
        guard let initiative = await store.getInitiative(projectID: normalizedID, initiativeID: initiativeID) else {
            throw ProjectError.notFound
        }
        return InitiativeDetailResponse(initiative: initiative)
    }

    public func createInitiative(projectID: String, request: CreateInitiativeRequest) async throws -> InitiativeDetailResponse {
        let normalizedID = try await requireExistingProjectID(projectID)
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = request.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !goal.isEmpty else {
            throw ProjectError.invalidPayload
        }

        let now = Date()
        let initiative = InitiativeRecord(
            id: UUID().uuidString.lowercased(),
            projectID: normalizedID,
            title: title,
            goal: goal,
            phase: .intake,
            executionMode: .singleAgent,
            successMetrics: request.successMetrics,
            constraints: request.constraints,
            resumePoint: "start framing",
            blocker: nil,
            metadata: request.metadata,
            createdAt: now,
            updatedAt: now
        )
        await store.saveInitiative(initiative)
        return InitiativeDetailResponse(initiative: initiative)
    }

    public func updateInitiative(projectID: String, initiativeID: String, request: UpdateInitiativeRequest) async throws -> InitiativeDetailResponse {
        let normalizedID = try await requireExistingProjectID(projectID)
        guard var initiative = await store.getInitiative(projectID: normalizedID, initiativeID: initiativeID) else {
            throw ProjectError.notFound
        }

        if let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            initiative.title = title
        }
        if let goal = request.goal?.trimmingCharacters(in: .whitespacesAndNewlines), !goal.isEmpty {
            initiative.goal = goal
        }
        if let phase = request.phase {
            initiative.phase = phase
        }
        if let executionMode = request.executionMode {
            initiative.executionMode = executionMode
        }
        if let successMetrics = request.successMetrics {
            initiative.successMetrics = successMetrics
        }
        if let constraints = request.constraints {
            initiative.constraints = constraints
        }
        if let resumePoint = request.resumePoint {
            initiative.resumePoint = resumePoint
        }
        if let blocker = request.blocker {
            initiative.blocker = blocker
        }
        if let metadata = request.metadata {
            initiative.metadata = metadata
        }
        initiative.updatedAt = Date()

        await store.saveInitiative(initiative)
        return InitiativeDetailResponse(initiative: initiative)
    }

    public func listInitiativeDecisionPackets(projectID: String, initiativeID: String) async throws -> DecisionPacketListResponse {
        let normalizedID = try await requireExistingProjectID(projectID)
        guard await store.getInitiative(projectID: normalizedID, initiativeID: initiativeID) != nil else {
            throw ProjectError.notFound
        }
        let packets = await store.listDecisionPackets(projectID: normalizedID, initiativeID: initiativeID)
        return DecisionPacketListResponse(decisionPackets: packets)
    }

    public func createInitiativeDecisionPacket(
        projectID: String,
        initiativeID: String,
        request: CreateDecisionPacketRequest
    ) async throws -> DecisionPacketDetailResponse {
        let normalizedID = try await requireExistingProjectID(projectID)
        guard await store.getInitiative(projectID: normalizedID, initiativeID: initiativeID) != nil else {
            throw ProjectError.notFound
        }

        let summary = request.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let rationale = request.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = request.requestedAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, !rationale.isEmpty, !action.isEmpty else {
            throw ProjectError.invalidPayload
        }

        let now = Date()
        let packet = DecisionPacketRecord(
            id: UUID().uuidString.lowercased(),
            projectID: normalizedID,
            initiativeID: initiativeID,
            summary: summary,
            rationale: rationale,
            tradeoffs: request.tradeoffs,
            requestedAction: action,
            resumePoint: request.resumePoint,
            status: "open",
            createdAt: now,
            updatedAt: now
        )
        await store.saveDecisionPacket(packet)
        return DecisionPacketDetailResponse(decisionPacket: packet)
    }

    private func requireExistingProjectID(_ projectID: String) async throws -> String {
        guard let normalizedID = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard await store.project(id: normalizedID) != nil else {
            throw ProjectError.notFound
        }
        return normalizedID
    }
}
