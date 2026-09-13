// Only untouched backlog tasks can adopt project defaults in bulk.
// An explicit (even empty) stage assignment is a task-level override.
export function projectDefaultCandidates(tasks, teamId) {
  return tasks.filter((task) => !task.isArchived && task.status === "backlog"
    && !task.actorId && !task.claimedActorId && !task.claimedAgentId && !task.activeStage
    && task.stageAssignments == null && (!task.teamId || task.teamId === teamId));
}

export function taskResponsibility(task) {
  const role = task.activeStage === "qa" ? "qa"
    : task.activeStage === "review" ? "reviewer" : "developer";
  return { role, actorId: task.claimedActorId || task.stageAssignments?.[role] || task.actorId };
}
