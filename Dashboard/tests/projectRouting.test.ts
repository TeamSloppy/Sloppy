import assert from "node:assert/strict";
import test from "node:test";
import { buildPathFromRoute, normalizeProjectTab, parseRouteFromPath } from "../src/app/routing/dashboardRouteAdapter.ts";

test("initiative navigation preserves its tab instead of falling back to overview", () => {
  const route = parseRouteFromPath("/projects/demo");
  const selected = { ...route, projectTab: normalizeProjectTab("initiatives") };
  assert.equal(selected.projectTab, "initiatives");
  assert.equal(buildPathFromRoute(selected), "/projects/demo/initiatives");
});

test("initiative deep links survive reload and retain the project ID", () => {
  const path = "/projects/my%20project/initiatives";
  const route = parseRouteFromPath(path);
  assert.equal(route.projectId, "my project");
  assert.equal(route.projectTab, "initiatives");
  assert.equal(buildPathFromRoute(route), path);
  assert.equal(normalizeProjectTab("unknown-tab"), "overview");
});
