import React, { useState } from "react";
import { updateActorTeam } from "../../api";
import { TeamRolesEditor } from "../../features/actors/TeamRolesEditor";
import { TeamAssignmentPicker } from "../../features/actors/TeamAssignmentPicker";
import { TEAM_ROLES, memberRoles } from "../../features/actors/teamRoles";

export function TeamBoardPanel({ project, actors, teams, onUpdateProject, onTeamsChange }) {
  const [editing, setEditing] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  async function save(action) {
    setBusy(true); setError("");
    try { await action(); } catch (err) { setError(err.message || "Could not save team settings."); }
    finally { setBusy(false); }
  }
  const linked = (project.teams || []).map((id) => teams.find((team) => team.id === id)).filter(Boolean);
  return <section className="team-board-panel" aria-label="Board team">
    <div className="team-board-heading"><div><strong>Board team</strong><p>Roles and responsibilities for this kanban</p></div>
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
    {editing && <div className="team-board-edit"><strong>{editing.name} · Team roles</strong>
      <TeamRolesEditor team={editing} actors={actors} disabled={busy} onChange={(memberRoles) => setEditing({ ...editing, memberRoles })} />
      <p className="team-role-note">An agent can have several roles. New tasks use the first member with each role; existing task assignments stay unchanged.</p>
      <div className="team-role-actions"><button type="button" disabled={busy} onClick={() => save(async () => {
        const result = await updateActorTeam(editing.id, editing); if (!result) throw new Error("Could not save team roles.");
        onTeamsChange(result.teams); setEditing(null);
      })}>{busy ? "Saving…" : "Save roles"}</button><button type="button" disabled={busy} onClick={() => setEditing(null)}>Cancel</button></div>
    </div>}
    {error && <p role="alert" className="team-role-error">{error}</p>}
  </section>;
}
