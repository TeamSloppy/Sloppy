import React from "react";
import { TASK_STAGES, teamDefaults } from "../../features/actors/teamRoles";
import { TeamAssignmentPicker } from "../../features/actors/TeamAssignmentPicker";

export function TaskStageAssignmentsEditor({ draft, actors, teams, onChange }) {
  const team = teams.find((item) => item.id === draft.teamId);
  const assignments = draft.stageAssignments || {};
  const candidates = team ? actors.filter((actor) => team.memberActorIds?.includes(actor.id)) : actors;
  const assignedCount = TASK_STAGES.filter((role) => assignments[role.id]).length;
  return <details className="task-stage-assignments" aria-label="Stage responsibilities">
    <summary><strong>Stage responsibilities</strong><span>{assignedCount} of {TASK_STAGES.length} assigned</span><span className="material-symbols-rounded" aria-hidden="true">expand_more</span></summary>
    <div className="task-stage-assignments-body">
      {team ? <div className="team-board-heading"><button type="button" onClick={() => onChange(teamDefaults(team, actors))}>Use team defaults</button></div> : null}
      <p className="team-role-note">Task-specific assignments override the project's Board team.</p>
      <div className="task-stage-grid">{TASK_STAGES.map((role) => <div key={role.id}>
        <span className="team-role-label">{role.title}</span>
        <TeamAssignmentPicker label={`${role.title} assignee`} value={assignments[role.id] || ""}
          options={candidates.map((actor) => ({ id: actor.id, name: actor.displayName }))}
          onChange={(id) => onChange({ ...assignments, [role.id]: id || null })} />
      </div>)}</div>
      {assignments.developer && assignments.developer === assignments.reviewer && <p className="team-role-note">Self-review · This agent develops and reviews in separate passes.</p>}
      {assignments.reviewer && assignments.reviewer === assignments.qa && <p className="team-role-note">The reviewer also owns QA.</p>}
      <p className="team-role-note">QA records the test result on this task. Automatic QA handoff is not enabled.</p>
    </div>
  </details>;
}
