import Foundation
import Protocols

// MARK: - Cron Tasks

extension CoreService {
    public func listAgentCronTasks(agentID: String) async throws -> [AgentCronTask] {
        guard !agentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentCronTaskError.invalidAgentID
        }
        return await store.listCronTasks(agentId: agentID)
    }

    public func createAgentCronTask(agentID: String, request: AgentCronTaskCreateRequest) async throws -> AgentCronTask {
        guard !agentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentCronTaskError.invalidAgentID
        }
        let task = AgentCronTask(
            id: UUID().uuidString,
            agentId: agentID,
            channelId: request.channelId,
            schedule: request.schedule,
            command: request.command,
            enabled: request.enabled ?? true
        )
        await store.saveCronTask(task)
        return task
    }

    public func updateAgentCronTask(agentID: String, cronID: String, request: AgentCronTaskUpdateRequest) async throws -> AgentCronTask {
        guard let existing = await store.cronTask(id: cronID), existing.agentId == agentID else {
            throw AgentCronTaskError.notFound
        }
        var updated = existing
        if let schedule = request.schedule { updated.schedule = schedule }
        if let command = request.command { updated.command = command }
        if let channelId = request.channelId { updated.channelId = channelId }
        if let enabled = request.enabled { updated.enabled = enabled }
        updated.updatedAt = Date()
        await store.saveCronTask(updated)
        return updated
    }

    public func deleteAgentCronTask(agentID: String, cronID: String) async throws {
        guard let existing = await store.cronTask(id: cronID), existing.agentId == agentID else {
            throw AgentCronTaskError.notFound
        }
        await store.deleteCronTask(id: cronID)
    }
}
