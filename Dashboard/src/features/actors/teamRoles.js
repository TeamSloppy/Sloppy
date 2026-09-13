export const TEAM_ROLES = [
  { id: "developer", title: "Developer" },
  { id: "reviewer", title: "Reviewer" },
  { id: "qa", title: "QA" },
  { id: "manager", title: "Lead" }
];

export const TASK_STAGES = TEAM_ROLES.slice(0, 3);

export function memberRoles(team, actor) {
  if (!team?.memberActorIds?.includes(actor.id)) return [];
  return team.memberRoles?.[actor.id] ?? (actor.systemRole ? [actor.systemRole] : []);
}

export function teamDefaults(team, actors) {
  return Object.fromEntries(TASK_STAGES.map(({ id }) => [id,
    team?.memberActorIds?.find((actorId) => {
      const actor = actors.find((item) => item.id === actorId);
      return actor && memberRoles(team, actor).includes(id);
    }) || ""
  ]));
}
