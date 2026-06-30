import Foundation
import Protocols

extension CoreService {
    enum InitiativeDecisionPacketKind: String, Sendable {
        case waitingInput = "waiting_input"
        case blocked
    }

    func nextInitiativeExecutionMode(
        current: InitiativeExecutionMode,
        signal: InitiativeExecutionSignal
    ) -> InitiativeExecutionMode {
        switch signal {
        case .needsIndependentVerification, .needsSpecialist:
            return .delegation
        case .parallelizableStreamsDetected:
            return .swarm
        case .tradeoffDecisionRequired:
            return .councilReview
        }
    }

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

    public func updateInitiativeExecutionMode(
        projectID: String,
        initiativeID: String,
        signal: InitiativeExecutionSignal
    ) async throws -> InitiativeRecord {
        let normalizedID = try await requireExistingProjectID(projectID)
        guard var initiative = await store.getInitiative(projectID: normalizedID, initiativeID: initiativeID) else {
            throw ProjectError.notFound
        }
        let nextMode = nextInitiativeExecutionMode(current: initiative.executionMode, signal: signal)
        initiative.executionMode = nextMode
        initiative.updatedAt = Date()
        await store.saveInitiative(initiative)
        return initiative
    }

    func listActiveInitiatives(projectID: String) async throws -> [InitiativeRecord] {
        let normalizedID = try await requireExistingProjectID(projectID)
        return await store.listInitiatives(projectID: normalizedID).filter {
            $0.phase != .done && $0.phase != .abandoned
        }
    }

    func syncInitiativePhaseForTaskStatusChange(
        projectID: String,
        previousTask: ProjectTask,
        currentTask: ProjectTask
    ) async {
        guard let initiativeID = currentTask.initiativeID ?? previousTask.initiativeID,
              let initiative = await store.getInitiative(projectID: projectID, initiativeID: initiativeID)
        else {
            return
        }

        let targetPhase = inferredInitiativePhase(
            currentTaskStatus: currentTask.statusValue,
            previousTaskStatus: previousTask.statusValue,
            currentInitiativePhase: initiative.phase
        )
        guard let targetPhase, targetPhase != initiative.phase else {
            return
        }

        var updated = initiative
        updated.phase = targetPhase
        updated.updatedAt = Date()
        if updated.resumePoint == nil || updated.resumePoint?.isEmpty == true {
            updated.resumePoint = defaultResumePoint(for: targetPhase, task: currentTask)
        }
        if targetPhase != .blocked, targetPhase != .needsUserDecision {
            updated.blocker = nil
        } else if targetPhase == .blocked, updated.blocker?.isEmpty != false {
            updated.blocker = "Task \(currentTask.id) entered blocked state."
        }
        await store.saveInitiative(updated)
    }

    private func inferredInitiativePhase(
        currentTaskStatus: ProjectTaskStatus?,
        previousTaskStatus: ProjectTaskStatus?,
        currentInitiativePhase: InitiativePhase
    ) -> InitiativePhase? {
        guard let currentTaskStatus else {
            return nil
        }

        switch currentTaskStatus {
        case .backlog, .pendingApproval:
            return currentInitiativePhase == .intake ? .framing : nil
        case .ready:
            if previousTaskStatus == .done {
                return .planning
            }
            return currentInitiativePhase == .intake || currentInitiativePhase == .framing ? .planning : nil
        case .inProgress:
            return .executing
        case .needsReview:
            return .reviewing
        case .waitingInput:
            return .needsUserDecision
        case .blocked:
            return .blocked
        case .done:
            return .verifying
        case .cancelled:
            return currentInitiativePhase == .done ? nil : .abandoned
        }
    }

    private func defaultResumePoint(for phase: InitiativePhase, task: ProjectTask) -> String {
        switch phase {
        case .framing:
            return "Refine initiative scope from task \(task.id)"
        case .planning:
            return "Select next task after \(task.id)"
        case .executing:
            return "Continue execution through task \(task.id)"
        case .verifying:
            return "Verify completion evidence from task \(task.id)"
        case .reviewing:
            return "Review work product from task \(task.id)"
        case .needsUserDecision:
            return "Resume after answering task \(task.id)"
        case .blocked:
            return "Unblock task \(task.id)"
        case .done:
            return "Initiative complete"
        case .abandoned:
            return "Initiative abandoned"
        case .intake:
            return "Start initiative intake"
        case .researching:
            return "Continue research for task \(task.id)"
        }
    }

    @discardableResult
    func ensureInitiativeDecisionPacket(
        projectID: String,
        task: ProjectTask,
        kind: InitiativeDecisionPacketKind,
        summary: String,
        rationale: String,
        requestedAction: String,
        resumePoint: String?,
        tradeoffs: [String] = []
    ) async -> DecisionPacketRecord? {
        guard let initiativeID = task.initiativeID,
              let initiative = await store.getInitiative(projectID: projectID, initiativeID: initiativeID)
        else {
            return nil
        }

        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRationale = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAction = requestedAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSummary.isEmpty, !normalizedRationale.isEmpty, !normalizedAction.isEmpty else {
            return nil
        }

        let existing = await store.listDecisionPackets(projectID: projectID, initiativeID: initiativeID)
        if let match = existing.last(where: {
            $0.status == "open"
                && $0.summary == normalizedSummary
                && $0.requestedAction == normalizedAction
        }) {
            return match
        }

        let now = Date()
        let packet = DecisionPacketRecord(
            id: UUID().uuidString.lowercased(),
            projectID: projectID,
            initiativeID: initiativeID,
            summary: normalizedSummary,
            rationale: normalizedRationale,
            tradeoffs: tradeoffs,
            requestedAction: normalizedAction,
            resumePoint: resumePoint,
            status: "open",
            createdAt: now,
            updatedAt: now
        )
        await store.saveDecisionPacket(packet)

        if kind == .blocked {
            var updatedInitiative = initiative
            if updatedInitiative.blocker?.isEmpty != false {
                updatedInitiative.blocker = normalizedRationale
            }
            if updatedInitiative.resumePoint?.isEmpty != false, let resumePoint {
                updatedInitiative.resumePoint = resumePoint
            }
            updatedInitiative.updatedAt = now
            await store.saveInitiative(updatedInitiative)
        }

        return packet
    }

    @discardableResult
    func resolveOpenDecisionPacketsForTask(
        projectID: String,
        task: ProjectTask,
        resumePoint: String? = nil
    ) async -> [DecisionPacketRecord] {
        guard let initiativeID = task.initiativeID else {
            return []
        }
        let packets = await store.listDecisionPackets(projectID: projectID, initiativeID: initiativeID)
        let openMatches = packets.filter {
            $0.status == "open"
                && ($0.summary.contains(task.id)
                    || $0.requestedAction.contains(task.id)
                    || ($0.resumePoint?.contains(task.id) ?? false))
        }
        guard !openMatches.isEmpty else {
            return []
        }

        var resolved: [DecisionPacketRecord] = []
        for packet in openMatches {
            var updated = packet
            updated.status = "resolved"
            updated.updatedAt = Date()
            if let resumePoint, !resumePoint.isEmpty {
                updated.resumePoint = resumePoint
            }
            await store.saveDecisionPacket(updated)
            resolved.append(updated)
        }

        if var initiative = await store.getInitiative(projectID: projectID, initiativeID: initiativeID),
           initiative.phase == .needsUserDecision || initiative.phase == .blocked {
            initiative.phase = .planning
            initiative.blocker = nil
            if let resumePoint, !resumePoint.isEmpty {
                initiative.resumePoint = resumePoint
            }
            initiative.updatedAt = Date()
            await store.saveInitiative(initiative)
        }

        return resolved
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

    public func updateInitiativeDecisionPacket(
        projectID: String,
        initiativeID: String,
        packetID: String,
        request: UpdateDecisionPacketRequest
    ) async throws -> DecisionPacketDetailResponse {
        let normalizedID = try await requireExistingProjectID(projectID)
        guard await store.getInitiative(projectID: normalizedID, initiativeID: initiativeID) != nil else {
            throw ProjectError.notFound
        }

        guard var packet = await store.listDecisionPackets(projectID: normalizedID, initiativeID: initiativeID)
            .first(where: { $0.id == packetID }) else {
            throw ProjectError.notFound
        }

        let normalizedStatus = request.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedStatus.isEmpty else {
            throw ProjectError.invalidPayload
        }

        packet.status = normalizedStatus
        packet.updatedAt = Date()
        if let resumePoint = request.resumePoint, !resumePoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            packet.resumePoint = resumePoint
        }
        await store.saveDecisionPacket(packet)

        if normalizedStatus == "resolved",
           var initiative = await store.getInitiative(projectID: normalizedID, initiativeID: initiativeID),
           initiative.phase == .needsUserDecision || initiative.phase == .blocked {
            initiative.phase = .planning
            initiative.blocker = nil
            if let resumePoint = packet.resumePoint, !resumePoint.isEmpty {
                initiative.resumePoint = resumePoint
            }
            initiative.updatedAt = Date()
            await store.saveInitiative(initiative)
        }

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
