import assert from "node:assert/strict";
import test from "node:test";
import { parseRouteFromPath, buildPathFromRoute } from "../src/app/routing/dashboardRouteAdapter.ts";

test("memory routes preserve tabs and scoped deep links", () => {
  for (const path of ["/memory/overview", "/memory/memories", "/memory/memories/global", "/memory/memories/agent/my%20agent", "/memory/memories/project/proj", "/memory/settings", "/memory/dreams"]) {
    const route = parseRouteFromPath(path);
    assert.equal(route.section, "memory");
    assert.equal(buildPathFromRoute(route), path);
  }
  assert.equal(buildPathFromRoute(parseRouteFromPath("/memory")), "/memory/overview");
});

test("old agent and project memory links reach the new section with their scope intact", () => {
  for (const [before, after] of [
    ["/agents/my%20agent/memories", "/memory/memories/agent/my%20agent"],
    ["/projects/project/memory", "/memory/memories/project/project"],
    ["/config/memory", "/memory/settings"], ["/config/memory-dreams", "/memory/dreams"]
  ]) assert.equal(buildPathFromRoute(parseRouteFromPath(before)), after);
  assert.equal(buildPathFromRoute(parseRouteFromPath("/agents/a/chat/session")), "/agents/a/chat/session");
});
