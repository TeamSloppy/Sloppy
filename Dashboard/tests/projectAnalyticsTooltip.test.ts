import assert from "node:assert/strict";
import test from "node:test";

import {
  analyticsTooltipContentStyle,
  analyticsTooltipTextStyle
} from "../src/views/Projects/projectAnalyticsTooltip.ts";

test("analytics tooltip styles keep tooltip text readable on dark surfaces", () => {
  assert.equal(analyticsTooltipContentStyle().color, "var(--text, #e2e8f0)");
  assert.equal(analyticsTooltipTextStyle().color, "var(--text, #e2e8f0)");
});
