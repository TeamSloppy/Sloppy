import assert from "node:assert/strict";
import test from "node:test";

import { costsPeriodRange, formatSpendingUSD, spendingBuckets } from "../src/features/costs/costsModel.ts";
import { buildPathFromRoute, parseRouteFromPath } from "../src/app/routing/dashboardRouteAdapter.ts";

test("Costs has a direct sidebar route", () => {
  const route = parseRouteFromPath("/costs");
  assert.equal(route.section, "costs");
  assert.equal(buildPathFromRoute(route), "/costs");
});

test("spending period begins at UTC midnight and includes the current day", () => {
  const range = costsPeriodRange("7d", new Date("2026-09-25T18:45:00Z"));
  assert.equal(range.from, "2026-09-19T00:00:00.000Z");
  assert.equal(range.to, "2026-09-25T18:45:00.000Z");
});

test("daily buckets preserve exact and estimated JEV cost", () => {
  const buckets = spendingBuckets([
    { day: "2026-09-24", usage: { requestCount: 2, inputTokens: 120, outputTokens: 8, totalCostUSD: 0.0012, estimatedCostUSD: 0.0002 } },
    { day: "2026-09-25", usage: { requestCount: 1, inputTokens: 40, outputTokens: 3, totalCostUSD: 0.0004, estimatedCostUSD: 0.0004 } }
  ], "7d", new Date("2026-09-25T18:45:00Z"));

  assert.equal(buckets.length, 7);
  assert.equal(buckets.at(-2)?.usage.totalCostUSD, 0.0012);
  assert.equal(buckets.at(-2)?.usage.estimatedCostUSD, 0.0002);
  assert.equal(buckets.at(-1)?.usage.requestCount, 1);
  assert.equal(buckets[0].usage.totalCostUSD, 0);
  assert.equal(formatSpendingUSD(0.0012), "$0.0012");
  assert.equal(formatSpendingUSD(0.00001155), "$0.00001155");
});

test("ninety-day view groups records by UTC week", () => {
  const usage = { requestCount: 1, inputTokens: 10, outputTokens: 1, totalCostUSD: 0.001, estimatedCostUSD: 0 };
  const buckets = spendingBuckets([
    { day: "2026-09-21", usage },
    { day: "2026-09-25", usage }
  ], "90d", new Date("2026-09-25T18:45:00Z"));

  assert.equal(buckets.at(-1)?.key, "2026-09-21");
  assert.equal(buckets.at(-1)?.usage.requestCount, 2);
  assert.equal(buckets.at(-1)?.usage.totalCostUSD, 0.002);
});
