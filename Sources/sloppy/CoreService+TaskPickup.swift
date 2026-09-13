import Protocols

extension CoreService {
    func pickupRulesPermit(project: ProjectRecord, task: ProjectTask) -> Bool {
        let rules = project.autopilotSettings.pickupRules
        guard !rules.conditions.isEmpty else { return true }
        var candidate = task
        var visited = Set<String>()
        // Generated subtasks inherit their root's admission criteria rather than
        // being rejected because the planner is their local author.
        while candidate.createdBy == "autopilot", let parentID = candidate.parentTaskId {
            guard visited.insert(candidate.id).inserted,
                  let parent = project.tasks.first(where: { $0.id == parentID }) else { return false }
            candidate = parent
        }
        return rules.matches(candidate)
    }

    func currentPickupRulesPermit(projectID: String, taskID: String) async -> Bool {
        guard let project = await store.project(id: projectID),
              project.automaticTaskPickupEnabled,
              let task = project.tasks.first(where: { $0.id == taskID }) else { return false }
        return pickupRulesPermit(project: project, task: task)
    }
}
