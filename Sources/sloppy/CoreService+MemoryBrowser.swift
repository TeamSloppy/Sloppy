import Foundation
import Protocols

extension CoreService {
    func listMemories(search: String?, filter: AgentMemoryFilter, sharedOnly: Bool, limit: Int, offset: Int) async -> MemoryListResponse {
        await waitForStartup()
        let all = await memoryStore.entries(filter: .default)
        let scoped = sharedOnly ? all.filter { $0.scope.type == .global } : all
        let entries = filterAgentMemoryEntries(scoped, search: search, filter: filter).sorted {
            $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
        }
        let boundedLimit = max(1, min(limit, 100))
        let boundedOffset = max(0, offset)
        return MemoryListResponse(
            items: entries.dropFirst(boundedOffset).prefix(boundedLimit).map { makeAgentMemoryItem(from: $0) },
            total: entries.count,
            limit: boundedLimit,
            offset: boundedOffset
        )
    }
}
