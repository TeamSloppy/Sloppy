import assert from "node:assert/strict";
import test from "node:test";
import { emptyFilterState, filterError, filterValueOptions, normalizeTaskFilter, parseFilterState, taskFilterStorageKey, taskMatchesFilter } from "../src/features/kanban-filters/taskFilters.js";

const task = { id: "P-1", title: "Проверить фильтры", description: "Case insensitive literal search", status: "ready", priority: "high", tags: ["iOS", "team,alpha"], actorId: "agent:dev", claimedActorId: "agent:review", claimedAgentId: "review", teamId: "team:best", stageAssignments: { reviewer: "agent:review", qa: "agent:review" }, externalMetadata: { providerId: "startrek", externalIssueKey: "CORE-42", externalQueue: "CORE", externalStatus: { key: "inProgress", display: "In Progress" }, externalCreator: { login: "alice", id: "uid-1", displayName: "Alice Smith" }, externalAssigneeIdentity: { login: "bob", id: "uid-2" } } };
const rule = (field, operation, values = []) => ({ id: field, field, operation, values });
const filter = (rules = [], match = "all", query = "") => ({ rules, match, query });

test("combines conditions and alternatives without interpreting query as code", () => {
  const rules = [rule("tag", "is", ["android", "IOS"]), rule("status", "is", ["backlog"])];
  assert.equal(taskMatchesFilter(task, filter(rules)), false);
  assert.equal(taskMatchesFilter(task, filter(rules, "any")), true);
  assert.equal(taskMatchesFilter(task, filter([], "all", "ФИЛЬТРЫ core-42")), true);
  assert.equal(taskMatchesFilter(task, filter([], "all", "#CORE-42")), true);
  assert.equal(taskMatchesFilter(task, filter([], "all", ".*")), false);
  assert.equal(taskMatchesFilter(task, filter([], "all", "missing")), false);
});

test("exclusions include missing values while empty checks are explicit", () => {
  assert.equal(taskMatchesFilter(task, filter([rule("tag", "is_not", ["ios"])])), false);
  assert.equal(taskMatchesFilter({}, filter([rule("tag", "is_not", ["ios"])])), true);
  assert.equal(taskMatchesFilter({}, filter([rule("assignee", "is_empty")])), true);
  assert.equal(taskMatchesFilter(task, filter([rule("assignee", "is_empty")])), false);
  assert.equal(taskMatchesFilter(task, filter([rule("title", "contains", ["фильтр"])])), true);
  assert.equal(taskMatchesFilter(task, filter([rule("title", "not_contains", ["фильтр"])])), false);
});

test("matches typed local and source identities, including multi-role actors", () => {
  for (const [field, value] of [["assignee", "agent:dev"], ["assignee", "agent:review"], ["team", "team:best"], ["author", "uid-1"], ["author", "alice"], ["external_assignee", "bob"], ["source", "startrek"], ["external_status", "inprogress"], ["queue", "core"], ["reviewer", "agent:review"], ["qa", "agent:review"]]) {
    assert.equal(taskMatchesFilter(task, filter([rule(field, "is", [value])])), true, field);
  }
  assert.equal(taskMatchesFilter(task, filter([rule("author", "is", ["Alice Smith"])])), false);
  assert.equal(taskMatchesFilter({ ...task, externalMetadata: null, createdBy: "local-author" }, filter([rule("author", "is", ["local-author"]), rule("source", "is", ["local"])])), true);
  assert.equal(taskMatchesFilter({ ...task, externalMetadata: null }, filter([rule("queue", "is", ["CORE"])])), false);
});

test("invalid and empty conditions cannot silently expand a filter", () => {
  for (const invalid of [rule("unknown", "is", ["x"]), rule("tag", "regex", [".*"]), rule("tag", "is", [" "])]) {
    const invalidFilter = filter([rule("status", "is", ["ready"]), invalid], "any");
    assert.ok(filterError(invalidFilter));
    assert.equal(taskMatchesFilter(task, invalidFilter), false);
  }
  assert.equal(taskMatchesFilter(task, filter()), true);
});

test("saved filters round trip and stay isolated by project and server", () => {
  const state = emptyFilterState();
  const definition = normalizeTaskFilter(filter([rule("tag", "is", ["team,alpha"])], "any", "Фильтр"));
  state.saved = [{ id: "one", name: "My work", filter: definition }];
  state.activeId = "one";
  state.filter = definition;
  assert.deepEqual(parseFilterState(JSON.stringify(state)), state);
  assert.notEqual(taskFilterStorageKey("https://one", "p"), taskFilterStorageKey("https://two", "p"));
  assert.notEqual(taskFilterStorageKey("https://one", "p"), taskFilterStorageKey("https://one", "q"));
  assert.equal(taskFilterStorageKey("https://one/", "p"), taskFilterStorageKey("https://one", "p"));
  assert.throws(() => parseFilterState("broken"));
  assert.throws(() => parseFilterState('{"version":2}'));
});

test("options use human labels and retain exact IDs and tags with commas", () => {
  assert.deepEqual(filterValueOptions("author", [task]).find((option) => option.id === "alice"), { id: "alice", label: "Alice Smith (alice)" });
  assert.ok(filterValueOptions("tag", [task]).some((option) => option.id === "team,alpha"));
  assert.equal(filterValueOptions("reviewer", [task], [{ id: "agent:review", displayName: "QA Agent" }]).find((option) => option.id === "agent:review").label, "QA Agent");
});
