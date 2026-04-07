import Foundation
import Protocols

// #region agent log
func _debugLog980519(_ location: String, _ message: String, _ data: [String: Any] = [:]) {
    let path = "/Users/vprusakov/Developer/SloppyTeam/Sloppy/.cursor/debug-980519.log"
    var payload: [String: Any] = [
        "sessionId": "980519",
        "location": location,
        "message": message,
        "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    if !data.isEmpty { payload["data"] = data }
    guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
          let line = String(data: jsonData, encoding: .utf8) else { return }
    let entry = Data((line + "\n").utf8)
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(entry)
        try? handle.close()
    } else {
        FileManager.default.createFile(atPath: path, contents: entry)
    }
}
// #endregion

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
        // #region agent log
        _debugLog980519("CoreService+ChannelAccess.swift:approvePendingApproval", "entry", ["id": id, "code": code, "hypothesisId": "H3,H4"])
        // #endregion
        guard let entry = await pendingApprovalService.findById(id) else {
            // #region agent log
            _debugLog980519("CoreService+ChannelAccess.swift:approvePendingApproval", "entry NOT found - returning false", ["id": id, "hypothesisId": "H3"])
            // #endregion
            return false
        }
        // #region agent log
        _debugLog980519("CoreService+ChannelAccess.swift:approvePendingApproval", "entry found", ["id": id, "entryCode": entry.code, "inputCode": code, "platform": entry.platform, "platformUserId": entry.platformUserId, "hypothesisId": "H3,H4"])
        // #endregion
        guard entry.code.uppercased() == code.uppercased() else {
            // #region agent log
            _debugLog980519("CoreService+ChannelAccess.swift:approvePendingApproval", "code MISMATCH - returning false", ["entryCode": entry.code.uppercased(), "inputCode": code.uppercased(), "hypothesisId": "H4"])
            // #endregion
            return false
        }
        let user = ChannelAccessUser(
            id: UUID().uuidString,
            platform: entry.platform,
            platformUserId: entry.platformUserId,
            displayName: entry.displayName,
            status: "approved"
        )
        // #region agent log
        _debugLog980519("CoreService+ChannelAccess.swift:approvePendingApproval", "calling store.saveChannelAccessUser", ["userId": user.id, "platform": user.platform, "platformUserId": user.platformUserId, "hypothesisId": "H1"])
        // #endregion
        await store.saveChannelAccessUser(user)
        // #region agent log
        _debugLog980519("CoreService+ChannelAccess.swift:approvePendingApproval", "save completed, removing pending", ["userId": user.id, "hypothesisId": "H1,H5"])
        // #endregion
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
