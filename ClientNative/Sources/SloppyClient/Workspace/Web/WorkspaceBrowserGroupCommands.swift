import Foundation
import SloppyClientCore

extension WorkspaceBrowserSession {
    func executeGroups(_ input: WorkspaceBrowserCommand.Input) throws -> WorkspaceBrowserPage {
        guard let workspace, workspace.isBrowsing else { throw WorkspaceBrowserRuntimeError.unavailable }
        let groupID = input.groupId.flatMap(UUID.init(uuidString:))
        if let raw = input.groupId, (groupID == nil || !workspace.groups.contains(where: { $0.id == groupID })) {
            throw WorkspaceBrowserRuntimeError.evaluationFailed("Unknown group ID: \(raw)")
        }
        let rawIDs = input.tabIds ?? []
        let ids = rawIDs.compactMap(UUID.init(uuidString:))
        guard rawIDs.count <= 500, ids.count == rawIDs.count,
              ids.allSatisfy({ id in workspace.tabs.contains { $0.id == id } }) else {
            throw WorkspaceBrowserRuntimeError.invalidArguments
        }
        switch input.operation {
        case "list": break
        case "create", "rename":
            guard let title = input.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  title.count <= 80, input.operation != "rename" || groupID != nil,
                  input.operation != "create" || groupID == nil else { throw WorkspaceBrowserRuntimeError.invalidArguments }
            guard let saved = workspace.saveGroup(title: title, id: groupID) else { throw WorkspaceBrowserRuntimeError.invalidArguments }
            for id in ids { workspace.assign(id, to: saved) }
        case "move":
            guard !ids.isEmpty else { throw WorkspaceBrowserRuntimeError.invalidArguments }
            for id in ids { workspace.assign(id, to: groupID) }
        default: throw WorkspaceBrowserRuntimeError.invalidArguments
        }
        return workspaceSnapshot(workspace)
    }
}
