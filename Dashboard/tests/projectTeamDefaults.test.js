import test from "node:test";
import assert from "node:assert/strict";
import { projectDefaultCandidates, taskResponsibility } from "../src/features/actors/projectTeamDefaults.js";
import { teamDefaults } from "../src/features/actors/teamRoles.js";

test("project defaults only apply to untouched compatible backlog tasks", () => {
  const base = { status: "backlog" };
  const tasks = [
    { ...base, id: "unassigned" }, { ...base, id: "same-team", teamId: "team" },
    ...[{ status: "ready" }, { status: "in_progress" }, { isArchived: true },
      { actorId: "dev" }, { claimedActorId: "dev" }, { claimedAgentId: "agent" },
      { activeStage: "development" }, { stageAssignments: {} },
      { stageAssignments: { developer: "dev" } }, { teamId: "other" }]
      .map((override, index) => ({ ...base, id: String(index), ...override }))
  ];
  assert.deepEqual(projectDefaultCandidates(tasks, "team").map((task) => task.id), ["unassigned", "same-team"]);
});

test("shared roles resolve deterministically in team membership order", () => {
  const actors = [{ id: "a" }, { id: "b" }];
  const team = { memberActorIds: ["b", "a"], memberRoles: { a: ["developer"], b: ["developer", "reviewer", "qa"] } };
  assert.deepEqual(teamDefaults(team, actors), { developer: "b", reviewer: "b", qa: "b" });
});

test("card responsibility uses typed active stage and actual claimant", () => {
  const task = { stageAssignments: { developer: "dev", reviewer: "review", qa: "test" } };
  assert.deepEqual(taskResponsibility(task), { role: "developer", actorId: "dev" });
  assert.deepEqual(taskResponsibility({ ...task, activeStage: "review" }), { role: "reviewer", actorId: "review" });
  assert.deepEqual(taskResponsibility({ ...task, activeStage: "qa", claimedActorId: "actual" }), { role: "qa", actorId: "actual" });
});
