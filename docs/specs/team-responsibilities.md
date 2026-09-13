# Team responsibilities

The Actors board and project kanban share the same team memberships. A member can
hold Developer, Reviewer, QA and Lead roles simultaneously. Roles belong to the
membership, not the agent profile; protected system actors can therefore receive
team roles without changing their identity or global instructions.

## Configuration

- Edit a team on the Actors board to choose members and their roles.
- In a project's Tasks tab, use **Board team** to link a team, and **Members & roles**
  to edit its roles directly above the kanban.
- Existing projects with several linked teams show each roster. Selecting a single
  team replaces the project's linked-team list; choosing no team removes the links.
- New tasks inherit the project's team when exactly one team is linked, unless an
  explicit task team was supplied. The first member with each role is the default
  owner, using the team's saved member order.
- Task properties expose Developer, Reviewer and QA owners independently. **Use
  team defaults** copies the current defaults into the edit draft; saving applies
  them. Each stage can be reassigned or cleared individually.

Assignments are snapshots: editing team roles does not silently reassign existing
tasks. A task can use the same actor for development and review, or review and QA.
The UI labels these combinations. Explicit task owners can be any member of the
selected team, including a human; they are not constrained to default role owners.

## Execution boundary

Developer assignments participate in normal task pickup. Explicit missing owners
must not fall through to an unrelated agent. Reviewer assignments participate in
the existing review handoff and follow the project's existing review approval mode.
The task's persisted `activeStage` distinguishes a review pass from development,
including when both use the same agent. Rejection returns to the designated developer.

QA ownership is recorded and displayed in this first version. It does not add a QA
column, start an automatic QA worker, or impose a new completion gate. QA results
are recorded using the existing task comments. Existing completion and merge rules
remain in effect.

## Wire and persistence

`ActorTeam.memberRoles` maps actor IDs to arrays of `ActorSystemRole`. Missing map
entries use a legacy actor's explicit `systemRole`; an empty array means no role.
The board store removes entries for deleted/non-member actors and deduplicates roles.

`ProjectTask.stageAssignments` stores optional `developer`, `reviewer`, and `qa`
actor IDs. Create/update requests accept the same object. Omission preserves an
existing assignment; an empty object clears all stage owners. Assignment changes
validate actor existence and membership in a selected team. Task metadata updates
do not recompute assignments. Changing the team without supplying assignments
copies the new team's defaults.

SQLite persists assignments and the active stage in `stage_assignments_json` and
`active_stage`; bootstrap migrations add both columns. Older task and team payloads
remain readable. Legacy tasks without stage assignments keep their existing routing.

### Project board configuration and existing backlog

The board exposes a `Project defaults` panel showing the effective first member for
Development, Review and manual QA. Team roles are shared between projects using
the same team. A single board team supplies defaults for new unassigned tasks.

`Apply to N unassigned backlog tasks` copies the displayed team and assignments to
existing backlog tasks across the project (including filtered-out tasks). It skips
archived tasks, other teams, explicit stage overrides (including an empty object),
assigned actors, claims and tasks with an active stage. It uses the existing task
update API; partial failure is reported and the remaining candidates can be retried.
This is an explicit snapshot operation, not live reassignment when a team changes.

Cards default to a compact owner/team presentation; `Card details` restores the
full metadata. Review appears next to development. Selecting a task also shows its
stored stage owners and typed active stage. The UI does not infer individual stage
completion or introduce an automatic QA column.
