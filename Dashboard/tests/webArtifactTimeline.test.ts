import assert from "node:assert/strict";
import test from "node:test";

import { webArtifactFromToolResult } from "../src/features/agents/webArtifactTimeline.ts";
import { sandboxedArtifactDocument } from "../src/shared/ui/sandboxedArtifactDocument.ts";
import { buildPathFromRoute, parseRouteFromPath } from "../src/app/routing/dashboardRouteAdapter.ts";

test("successful web artifact tool result produces a durable chat card", () => {
  const artifact = webArtifactFromToolResult({
    type: "tool_result",
    toolResult: {
      tool: "artifacts.web.create",
      ok: true,
      data: { artifact: { id: "visual-1", kind: "widget", mediaType: "text/html", title: "Trend", previewText: "Sales over time" } }
    }
  });
  assert.deepEqual(artifact, { id: "visual-1", title: "Trend", summary: "Sales over time" });
  assert.equal(webArtifactFromToolResult({ type: "tool_result", toolResult: { tool: "artifacts.web.create", ok: false } }), null);
});

test("artifact links round-trip through dashboard routing", () => {
  const path = "/artifacts/visual%20one";
  const route = parseRouteFromPath(path);
  assert.equal(route.artifactId, "visual one");
  assert.equal(buildPathFromRoute(route), path);
});

test("web visual document receives a restrictive policy before its own head content", () => {
  const html = sandboxedArtifactDocument("<!doctype html><html><head><title>Chart</title></head><body>Values</body></html>");
  assert.ok(html.indexOf("Content-Security-Policy") < html.indexOf("<title>"));
  assert.match(html, /default-src 'none'/);
});
