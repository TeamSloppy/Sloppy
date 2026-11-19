import Foundation
import Protocols

extension CoreService {
    private struct SSHMachine: Decodable {
        var alias: String
        var name: String
        var projectId: String?
    }

    func listMachineMentions(projectId: String?) throws -> [MachineMention] {
        let online = try nodeMeshStore.listNodes().filter { $0.status == .online }
        let targets = try remoteExecutionTargets().filter { projectId == nil || $0.projectId == projectId }
        let sshURL = workspaceRootURL.appendingPathComponent("ssh-machine-targets.json")
        let sshMachines = FileManager.default.fileExists(atPath: sshURL.path)
            ? try JSONDecoder().decode([SSHMachine].self, from: Data(contentsOf: sshURL)) : []
        var mentions: [String: MachineMention] = [:]
        for machine in sshMachines where machine.projectId == nil || projectId == nil || machine.projectId == projectId {
            guard Self.isMachineMentionAlias(machine.alias) else { continue }
            mentions[machine.alias] = .init(alias: machine.alias, name: machine.name, transport: .ssh)
        }
        for node in online {
            let aliases = targets.filter { $0.nodeId == node.id }.map(\.alias).filter(Self.isMachineMentionAlias)
            let nodeAlias = "$" + node.id
            for alias in aliases.isEmpty && Self.isMachineMentionAlias(nodeAlias) ? [nodeAlias] : aliases {
                mentions[alias] = .init(alias: alias, name: node.name, transport: .relay)
            }
        }
        return mentions.values.sorted { $0.alias < $1.alias }
    }

    private static func isMachineMentionAlias(_ alias: String) -> Bool {
        guard alias.first == "$", (2...128).contains(alias.utf8.count) else { return false }
        return alias.utf8.dropFirst().allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45 || byte == 95
        }
    }
}
