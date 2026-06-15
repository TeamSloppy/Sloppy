import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const dashboardRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const detailsSource = readFileSync(join(dashboardRoot, "src", "views", "Projects", "ProjectTaskDetails.jsx"), "utf8");
const projectsCss = readFileSync(join(dashboardRoot, "src", "styles", "projects.css"), "utf8");

test("side and mobile task details render properties inline before tabs", () => {
  const inlineIndex = detailsSource.indexOf("{useInlineProperties ? renderInlineProperties() : null}");
  const tabsIndex = detailsSource.indexOf("td-tabs-section");

  assert.notEqual(inlineIndex, -1);
  assert.ok(inlineIndex < tabsIndex);
  assert.match(detailsSource, /const useInlineProperties = isSideView \|\| isMobileTaskDetail;/);
  assert.match(detailsSource, /\{!useInlineProperties \? \(\s*<aside/);
});

test("mobile task properties no longer use a separate fixed drawer scroll", () => {
  assert.doesNotMatch(projectsCss, /td-page--mobile-props[\s\S]*?position:\s*fixed/);
  assert.doesNotMatch(projectsCss, /\.td-sidebar-backdrop\s*\{/);
  assert.match(projectsCss, /\.td-inline-properties\s*\{/);
  assert.match(projectsCss, /\.td-inline-properties-body\s*\{/);
});

test("task detail header uses a compact toolbar with a close control", () => {
  assert.match(detailsSource, /className="td-toolbar"/);
  assert.match(detailsSource, /className="td-toolbar-action td-toolbar-action--close"/);
  assert.match(detailsSource, /onClick=\{closeTaskDetails\}/);
  assert.match(detailsSource, /aria-label="Close task details"/);
  assert.match(projectsCss, /\.td-toolbar\s*\{/);
  assert.match(projectsCss, /\.td-toolbar-action\s*\{/);
  assert.match(projectsCss, /\.td-toolbar-divider\s*\{/);
});
