import React from "react";
import { TASK_STAGES } from "../../features/actors/teamRoles";
import { taskResponsibility } from "../../features/actors/projectTeamDefaults";

export function TaskResponsibilitySummary({ task, actors, teams, agentDirectory = {}, expanded = false }) {
  const { role, actorId } = taskResponsibility(task);
  const name = (id) => actors.find((actor) => actor.id === id)?.displayName || id || "Unassigned";
  const team = teams.find((item) => item.id === task.teamId);
  const ownerName = !task.claimedActorId && task.claimedAgentId
    ? agentDirectory[task.claimedAgentId]?.displayName || task.claimedAgentId : name(actorId);
  if (!expanded) return <div className="task-owner-summary">
    <span>{ownerName} · {TASK_STAGES.find((stage) => stage.id === role)?.title}</span>
    {team && <small>{team.name}</small>}
  </div>;
  return <section className="task-responsibility-summary" aria-label="Task responsibilities">
    <div className="team-board-heading"><strong>{task.id} · Stage responsibilities</strong><span>{team?.name}</span></div>
    <div className="task-stage-grid">{TASK_STAGES.map((stage, index) => <div key={stage.id}
      className={`task-responsibility-step${task.activeStage && task.status !== "done" && role === stage.id ? " active" : ""}`}>
      <small>0{index + 1} · {stage.title}</small>
      <strong>{name(task.stageAssignments?.[stage.id])}</strong>
      <span>{stage.id === "qa" ? "Manual testing · no automatic handoff"
        : task.activeStage && task.status !== "done" && role === stage.id ? "Current stage" : "Assigned responsibility"}</span>
    </div>)}</div>
  </section>;
}
