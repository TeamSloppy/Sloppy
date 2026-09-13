import React, { useState } from "react";
import { updateActorTeam } from "../../api";
import { TeamRolesEditor } from "../../features/actors/TeamRolesEditor";
import { TeamAssignmentPicker } from "../../features/actors/TeamAssignmentPicker";
import { TEAM_ROLES, TASK_STAGES, memberRoles, teamDefaults } from "../../features/actors/teamRoles";
import { projectDefaultCandidates } from "../../features/actors/projectTeamDefaults";

export function TeamBoardPanel({ project, actors, teams, onUpdateProject, onTeamsChange, bulkUpdateTasks }) {
  const [editing, setEditing] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [showDefaults, setShowDefaults] = useState(false);
  async function save(action) {
    setBusy(true); setError(""); setNotice("");
    try { await action(); } catch (err) { setError(err.message || "Could not save team settings."); }
    finally { setBusy(false); }
  }
  const linked = (project.teams || []).map((id) => teams.find((team) => team.id === id)).filter(Boolean);
  const defaultTeam = linked.length === 1 ? linked[0] : null;
  const defaults = teamDefaults(defaultTeam, actors);
  const candidates = defaultTeam ? projectDefaultCandidates(project.tasks || [], defaultTeam.id) : [];
  return <section className="team-board-panel" aria-label="Board team">
    <div className="team-board-heading"><div><strong>{project.name} · Board team</strong><p>Set the team once for this project. New unassigned tasks receive its roles automatically.</p></div>
      <TeamAssignmentPicker label="Board team" value={linked.length === 1 ? linked[0].id : ""}
        emptyLabel={linked.length > 1 ? `${linked.length} linked teams` : "Choose a team"}
        options={teams.map((team) => ({ id: team.id, name: team.name }))} disabled={busy}
        onChange={(id) => save(async () => { const result = await onUpdateProject({ teams: id ? [id] : [] }); if (!result) throw new Error("Could not link the team."); setEditing(null); })} />
    </div>
    {linked.map((team) => <div key={team.id} className="team-board-roster">
      <div className="team-board-heading"><strong>{team.name}</strong><button type="button" disabled={busy} onClick={() => setEditing({ ...team, memberRoles: { ...team.memberRoles } })}>Members & roles</button></div>
      <div className="team-board-members">{(team.memberActorIds || []).map((id) => {
        const actor = actors.find((item) => item.id === id) || { id, displayName: id };
        const roles = memberRoles(team, actor);
        return <button key={id} type="button" className="team-board-member" onClick={() => setEditing({ ...team, memberRoles: { ...team.memberRoles } })}>
          <span className="team-board-avatar">{actor.displayName.slice(0, 2)}</span><span>{actor.displayName}<small>{roles.map((role) => TEAM_ROLES.find((item) => item.id === role)?.title || role).join(" · ") || "No role assigned"}</small></span>
        </button>;
      })}</div>
      {!team.memberActorIds?.length && <p className="team-role-note">Add members on the Actors board.</p>}
    </div>)}
    {defaultTeam && <div className="team-role-actions"><button type="button" aria-expanded={showDefaults} onClick={() => setShowDefaults((value) => !value)}>Project defaults</button></div>}
    {defaultTeam && showDefaults && <div className="project-team-defaults">
      <div className="task-stage-grid">{TASK_STAGES.map((stage) => <div key={stage.id}>
        <span className="team-role-label">{stage.title}{stage.id === "qa" ? " · manual" : ""}</span>
        <strong>{actors.find((actor) => actor.id === defaults[stage.id])?.displayName || "No team member with this role"}</strong>
      </div>)}</div>
      <p className="team-role-note">Defaults use the first member with each role. Roles are shared wherever this team is used. Task overrides stay unchanged.</p>
      {bulkUpdateTasks && candidates.length > 0 && Object.values(defaults).some(Boolean) && <div className="team-role-actions">
        <button type="button" disabled={busy} onClick={() => save(async () => {
          const result = await bulkUpdateTasks(candidates.map((task) => task.id), {
            teamId: defaultTeam.id, stageAssignments: defaults
          }, "Project team applied to unassigned backlog tasks.");
          if (!result) throw new Error("Some tasks could not be updated. Check the board and retry the remaining tasks.");
          setNotice(`Team applied to ${candidates.length} backlog tasks.`);
        })}>{busy ? "Applying…" : `Apply to ${candidates.length} unassigned backlog tasks`}</button>
      </div>}
      {candidates.length > 0 && <p className="team-role-note">Applies across this project's backlog, including tasks hidden by filters. Tasks already assigned or started are excluded.</p>}
    </div>}
    {linked.length > 1 && <p className="team-role-note">Choose one board team to enable automatic defaults for new tasks.</p>}
    {editing && <div className="team-board-edit"><strong>{editing.name} · Team roles</strong>
      <TeamRolesEditor team={editing} actors={actors} disabled={busy} onChange={(memberRoles) => setEditing({ ...editing, memberRoles })} />
      <p className="team-role-note">An agent can have several roles. New tasks use the first member with each role; existing task assignments stay unchanged.</p>
      <div className="team-role-actions"><button type="button" disabled={busy} onClick={() => save(async () => {
        const result = await updateActorTeam(editing.id, editing); if (!result) throw new Error("Could not save team roles.");
        onTeamsChange(result.teams); setEditing(null);
      })}>{busy ? "Saving…" : "Save roles"}</button><button type="button" disabled={busy} onClick={() => setEditing(null)}>Cancel</button></div>
    </div>}
    {error && <p role="alert" className="team-role-error">{error}</p>}
    {notice && <p role="status" className="team-role-note">{notice}</p>}
  </section>;
}
