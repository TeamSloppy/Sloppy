import Foundation
import Protocols

extension CoreService {
    /// Snapshot team defaults when a task is created or its team is changed.
    /// Later team edits do not silently reassign existing work.
    func taskStageAssignments(
        requested: TaskStageAssignments?,
        teamID: String?
    ) throws -> TaskStageAssignments? {
        guard requested != nil || teamID != nil else { return nil }
        let board = try getActorBoard()
        let team = teamID.flatMap { id in board.teams.first { $0.id == id } }
        if requested != nil, teamID != nil, team == nil { throw ProjectError.invalidPayload }
        guard requested != nil || team?.memberRoles.isEmpty == false else { return nil }
        var assignments = requested ?? team?.defaultAssignments(nodes: board.nodes) ?? TaskStageAssignments()
        func normalize(_ raw: String?) throws -> String? {
            guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard board.nodes.contains(where: { $0.id == id }),
                  team == nil || team?.memberActorIds.contains(id) == true else {
                throw ProjectError.invalidPayload
            }
            return id
        }
        assignments.developer = try normalize(assignments.developer)
        assignments.reviewer = try normalize(assignments.reviewer)
        assignments.qa = try normalize(assignments.qa)
        return assignments
    }
}
