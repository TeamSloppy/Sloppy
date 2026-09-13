import React from "react";
import { TEAM_ROLES, memberRoles } from "./teamRoles";
import "../../styles/team-roles.css";

export function TeamRolesEditor({ team, actors, onChange, disabled = false }) {
  return <div className="team-role-editor" aria-label="Team member roles">
    {(team.memberActorIds || []).map((id) => {
      const actor = actors.find((item) => item.id === id) || { id, displayName: id };
      const roles = memberRoles(team, actor);
      return <div className="team-role-row" key={id}>
        <span className="team-role-person">{actor.displayName}</span>
        <div className="team-role-options">{TEAM_ROLES.map((role) => <label key={role.id}>
          <input type="checkbox" checked={roles.includes(role.id)} disabled={disabled}
            aria-label={`${actor.displayName}: ${role.title}`}
            onChange={(event) => onChange({ ...team.memberRoles, [id]: event.target.checked
              ? [...roles, role.id] : roles.filter((value) => value !== role.id) })} />
          {role.title}
        </label>)}</div>
      </div>;
    })}
  </div>;
}
