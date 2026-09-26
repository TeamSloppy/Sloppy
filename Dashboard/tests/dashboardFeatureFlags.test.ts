import assert from "node:assert/strict";
import test from "node:test";

import { resolveDashboardFeatureFlags } from "../src/shared/ui/dashboardFeatureFlags.ts";

test("sidebar project chats are hidden unless explicitly enabled", () => {
  assert.equal(resolveDashboardFeatureFlags(undefined).sidebarProjectChats, false);
  assert.equal(resolveDashboardFeatureFlags({}).sidebarProjectChats, false);
  assert.equal(resolveDashboardFeatureFlags({ theme: "modern" }).sidebarProjectChats, false);
  assert.equal(resolveDashboardFeatureFlags({ theme: "minimal" }).sidebarProjectChats, false);
  assert.equal(resolveDashboardFeatureFlags({ theme: "brutalist" }).sidebarProjectChats, false);
  assert.equal(resolveDashboardFeatureFlags({ features: { sidebarProjectChats: false } }).sidebarProjectChats, false);
  assert.equal(resolveDashboardFeatureFlags({ features: { sidebarProjectChats: true } }).sidebarProjectChats, true);
});
