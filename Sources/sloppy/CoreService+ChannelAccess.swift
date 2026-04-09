import Foundation
import Protocols

// MARK: - Channel Access Approvals

extension CoreService {
    public func listPendingApprovals() async -> [PendingApprovalEntry] {
        let pending = await pendingApprovalService.listPending()
        return await filterOutBlockedUsers(pending)
    }

    public func listPendingApprovals(platform: String) async -> [PendingApprovalEntry] {
        let pending = await pendingApprovalService.listPending(platform: platform)
        return await filterOutBlockedUsers(pending)
    }

    func filterOutBlockedUsers(_ entries: [PendingApprovalEntry]) async -> [PendingApprovalEntry] {
        let blockedUsers = await store.listChannelAccessUsers(platform: nil)
            .filter { $0.status == "blocked" }
        let blockedKeys = Set(blockedUsers.map { "\($0.platform):\($0.platformUserId)" })
        var cleanedIds: [String] = []
        let filtered = entries.filter { entry in
            let key = "\(entry.platform):\(entry.platformUserId)"
            if blockedKeys.contains(key) {
                cleanedIds.append(entry.id)
                return false
            }
            return true
        }
        for id in cleanedIds {
            await pendingApprovalService.removePending(id: id)
        }
        return filtered
    }

    public func approvePendingApproval(id: String, code: String) async -> Bool {
        guard let entry = await pendingApprovalService.findById(id) else {
            return false
        }
        guard entry.code.uppercased() == code.uppercased() else {
            return false
        }
        let user = ChannelAccessUser(
            id: UUID().uuidString,
            platform: entry.platform,
            platformUserId: entry.platformUserId,
            displayName: entry.displayName,
            status: "approved"
        )
        await store.saveChannelAccessUser(user)
        await pendingApprovalService.removePending(id: id)
        return true
    }

    public func rejectPendingApproval(id: String) async {
        await pendingApprovalService.removePending(id: id)
    }

    public func blockPendingApproval(id: String) async -> Bool {
        guard let entry = await pendingApprovalService.findById(id) else { return false }
        let user = ChannelAccessUser(
            id: UUID().uuidString,
            platform: entry.platform,
            platformUserId: entry.platformUserId,
            displayName: entry.displayName,
            status: "blocked"
        )
        await store.saveChannelAccessUser(user)
        await pendingApprovalService.removePending(id: id)
        return true
    }

    public func listAccessUsers(platform: String?) async -> [ChannelAccessUser] {
        await store.listChannelAccessUsers(platform: platform)
    }

    public func deleteAccessUser(id: String) async -> Bool {
        let users = await store.listChannelAccessUsers(platform: nil)
        guard users.contains(where: { $0.id == id }) else { return false }
        await store.deleteChannelAccessUser(id: id)
        return true
    }

}
