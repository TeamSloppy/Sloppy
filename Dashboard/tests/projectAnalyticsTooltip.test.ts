import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  analyticsTooltipContentStyle,
  analyticsTooltipTextStyle
} from "../src/views/Projects/projectAnalyticsTooltip.ts";

const dashboardRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const overviewCss = readFileSync(join(dashboardRoot, "src", "styles", "overview.css"), "utf8");

test("analytics tooltip styles keep tooltip text readable on dark surfaces", () => {
  assert.equal(analyticsTooltipContentStyle().color, "var(--text, #e2e8f0)");
  assert.equal(analyticsTooltipTextStyle().color, "var(--text, #e2e8f0)");
});

test("agent usage overview styles stay aligned with the accent theme", () => {
  const heroRule = overviewCss.match(/\.agent-usage-hero\s*\{([^}]+)\}/)?.[1] || "";

  assert.match(heroRule, /background:\s*var\(--surface\)/);
  assert.doesNotMatch(heroRule, /linear-gradient/);
  assert.match(overviewCss, /\.agent-usage-mode-toggle button\.active\s*\{[\s\S]*?background:\s*color-mix\(in srgb, var\(--accent\) 18%, transparent\)/);
  assert.match(overviewCss, /\.agent-usage-day\s*\{[\s\S]*?linear-gradient\(180deg, color-mix\(in srgb, var\(--accent\) 72%, white 28%\), color-mix\(in srgb, var\(--accent\) 58%, black 42%\)\)/);
});
