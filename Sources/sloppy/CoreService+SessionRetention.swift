import Foundation
import Logging
import Protocols

// MARK: - Session Retention

extension CoreService {
    struct SessionRetentionCleanupResult: Sendable, Equatable {
        var agentSessionsDeleted: Int
        var channelSessionsDeleted: Int
    }

    func deleteExpiredAgentSessionsIfNeeded(referenceDate: Date? = nil) async -> Int {
        while let pending = agentSessionRetentionTask {
            let count = await pending.value
            if referenceDate == nil { return count }
        }

        let retention = currentConfig.sessionRetention
        guard retention.enabled else {
            lastAgentSessionRetention = nil
            return 0
        }

        let root = agentsRootURL
        if referenceDate == nil, let last = lastAgentSessionRetention, last.root == root, last.days == retention.days,
           last.checkedAt.duration(to: .now) < .seconds(300) {
            return 0
        }

        let cutoffDate = (referenceDate ?? Date()).addingTimeInterval(-TimeInterval(retention.days * 24 * 60 * 60))
        let task = Task {
            defer { agentSessionRetentionTask = nil }
            let count = await cleanupExpiredAgentSessions(root: root, retention: retention, cutoffDate: cutoffDate)
            if referenceDate == nil, agentsRootURL == root, currentConfig.sessionRetention == retention {
                lastAgentSessionRetention = (root, retention.days, .now)
            }
            return count
        }
        agentSessionRetentionTask = task
        return await task.value
    }

    private func cleanupExpiredAgentSessions(root: URL, retention: CoreConfig.SessionRetention, cutoffDate: Date) async -> Int {
        var deletedCount = 0
        do {
            let agentIDs = try listAgents().map(\.id)
            var catalogs: [String: [AgentSessionSummary]] = [:]
            for agentID in agentIDs {
                guard agentsRootURL == root, currentConfig.sessionRetention == retention else { return deletedCount }
                catalogs[agentID] = try await scanSessionCatalog(agentID: agentID, includeHeartbeat: true)
            }
            guard agentsRootURL == root, currentConfig.sessionRetention == retention else { return deletedCount }
            for agentID in agentIDs {
                let candidates = (catalogs[agentID] ?? []).filter { $0.updatedAt < cutoffDate && $0.kind != .longChat }
                let batchSize = 16
                for start in stride(from: 0, to: candidates.count, by: batchSize) {
                    if start > 0 { await Task.yield() }
                    guard agentsRootURL == root, currentConfig.sessionRetention == retention else { return deletedCount }
                    guard let config = try? agentCatalogStore.getAgentRuntimeConfig(agentID: agentID) else { break }
                    let state = try longChats().state
                    let separate = Set(state.separateSessionIds ?? [])
                    let end = min(start + batchSize, candidates.count)
                    for summary in candidates[start..<end] {
                        // Preserve old project chats until their owner migrates them.
                        if config.type == .native && summary.projectId != nil && summary.parentSessionId == nil
                            && summary.taskId == nil && summary.workspaceId == nil && !separate.contains(summary.id) {
                            continue
                        }
                        if let context = state.workerContexts?[summary.id],
                           (try? sessionStore.loadSessionSummary(agentID: context.agentId, sessionID: context.parentSessionId)) != nil {
                            continue
                        }
                        guard try sessionStore.deleteSessionIfExpired(agentID: agentID, sessionID: summary.id, olderThan: cutoffDate)
                        else { continue }
                        deletedCount += 1
                        Task { try? await launches.deleteSession(agentID: agentID, sessionID: summary.id) }
                        sessionExtraRoots.removeValue(forKey: summary.id)
                        sessionWorkingDirectories.removeValue(forKey: summary.id)
                        sessionAddedRoots.removeValue(forKey: summary.id)
                        sessionSubagentToolAllowList.removeValue(forKey: summary.id)
                        sessionToolUsageLimitBypass.remove(summary.id)
                        sessionToolApprovalBypass.remove(summary.id)
                        toolApprovalSessionAllowances.removeValue(forKey: "\(agentID)\nsession:\(summary.id)")
                    }
                }
            }
            if deletedCount > 0 {
                logger.info(
                    "session_retention.agent_sessions_deleted",
                    metadata: ["count": .stringConvertible(deletedCount)]
                )
            }
        } catch {
            logger.warning(
                "session_retention.agent_cleanup_failed",
                metadata: ["error": .string(String(describing: error))]
            )
        }
        return deletedCount
    }

    @discardableResult
    func deleteExpiredSessionsIfNeeded(referenceDate: Date? = nil) async -> SessionRetentionCleanupResult {
        let agentCount = await deleteExpiredAgentSessionsIfNeeded(referenceDate: referenceDate)
        let retention = currentConfig.sessionRetention
        guard retention.enabled else {
            return SessionRetentionCleanupResult(
                agentSessionsDeleted: agentCount,
                channelSessionsDeleted: 0
            )
        }

        let cutoffDate = (referenceDate ?? Date()).addingTimeInterval(-TimeInterval(retention.days * 24 * 60 * 60))
        do {
            let deleted = try await channelSessionStore.deleteExpiredSessions(olderThan: cutoffDate)
            for summary in deleted {
                clearChannelSessionDirectories(channelID: summary.channelId)
            }
            if !deleted.isEmpty {
                logger.info(
                    "session_retention.channel_sessions_deleted",
                    metadata: ["count": .stringConvertible(deleted.count)]
                )
            }
            return SessionRetentionCleanupResult(
                agentSessionsDeleted: agentCount,
                channelSessionsDeleted: deleted.count
            )
        } catch {
            logger.warning(
                "session_retention.channel_cleanup_failed",
                metadata: ["error": .string(String(describing: error))]
            )
            return SessionRetentionCleanupResult(
                agentSessionsDeleted: agentCount,
                channelSessionsDeleted: 0
            )
        }
    }
}
