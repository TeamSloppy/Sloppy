import assert from "node:assert/strict";
import test from "node:test";

import { buildRelatedIssueGroups } from "../src/views/Projects/taskRelations.js";

test("related issue groups include parent, child, and dependency links", () => {
  const current = {
    id: "CLIENT-2",
    title: "Package client",
    parentTaskId: "CLIENT-1",
    dependsOnTaskIds: ["CLIENT-3"]
  };
  const groups = buildRelatedIssueGroups(current, [
    {
      id: "CLIENT-1",
      title: "Launch client"
    },
    current,
    {
      id: "CLIENT-3",
      title: "Build release binary"
    },
    {
      id: "CLIENT-4",
      title: "Publish release notes",
      parentTaskId: "CLIENT-2"
    },
    {
      id: "CLIENT-5",
      title: "Run QA smoke",
      dependsOnTaskIds: ["CLIENT-2"]
    }
  ]);

  assert.deepEqual(groups.map((group) => group.id), ["parent", "children", "blocks", "blocked_by"]);
  assert.deepEqual(groups.find((group) => group.id === "parent").items.map((item) => item.task.id), ["CLIENT-1"]);
  assert.deepEqual(groups.find((group) => group.id === "children").items.map((item) => item.task.id), ["CLIENT-4"]);
  assert.deepEqual(groups.find((group) => group.id === "blocks").items.map((item) => item.task.id), ["CLIENT-5"]);
  assert.deepEqual(groups.find((group) => group.id === "blocked_by").items.map((item) => item.task.id), ["CLIENT-3"]);
});

test("related issue groups include swarm children when project task links are absent", () => {
  const current = {
    id: "CLIENT-2",
    title: "Package client",
    swarmId: "swarm-1",
    swarmTaskId: "task:CLIENT-2"
  };
  const groups = buildRelatedIssueGroups(current, [
    current,
    {
      id: "CLIENT-6",
      title: "Notarize app",
      swarmId: "swarm-1",
      swarmParentTaskId: "task:CLIENT-2"
    }
  ]);

  assert.deepEqual(groups.map((group) => group.id), ["swarm_children"]);
  assert.deepEqual(groups[0].items.map((item) => item.task.id), ["CLIENT-6"]);
});
