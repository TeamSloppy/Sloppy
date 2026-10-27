import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { transform } from "esbuild";
const { code } = await transform(
  await readFile(
    new URL("../src/features/agents/ui/uiSurface.ts", import.meta.url),
    "utf8",
  ),
  { loader: "ts", format: "esm" },
);
const ui = await import(
  `data:text/javascript;base64,${Buffer.from(code).toString("base64")}`
);
for (const name of ["brief", "comparison", "parameters"]) {
  const frames = JSON.parse(
    await readFile(
      new URL(
        `../../Packages/SloppyA2UI/Tests/SloppyA2UITests/Fixtures/${name}.json`,
        import.meta.url,
      ),
      "utf8",
    ),
  );
  const surface = {
    protocolVersion: "0.9.1",
    catalogId: "urn:sloppy:a2ui:catalog:v1",
    surfaceId: name,
    revision: 1,
    fallbackText: "Example",
    components: frames[1].updateComponents.components,
  };
  assert.equal(ui.validSurface(surface), true);
  const values = ui.initialValues(surface);
  assert.ok(Object.keys(ui.validationErrors(surface, values)).length);
  if (name === "brief") {
    values["/goal"] = "Ship";
    values["/platform"] = "ios";
  }
  if (name === "comparison") values["/choice"] = "fast";
  if (name === "parameters") {
    values["/count"] = "12";
    assert.ok(ui.validationErrors(surface, values)["/count"]);
    values["/count"] = "2";
    assert.equal(ui.normalizedValues(surface, values)["/count"], 2);
  }
  assert.deepEqual(ui.validationErrors(surface, values), {});
  const draft = {
    values,
    defaults: ui.initialValues(surface),
    revision: 1,
    pending: { actionId: "test" },
  };
  const next = ui.reconcileDraft({ ...surface, revision: 2 }, draft);
  assert.deepEqual(next.values, values);
  assert.equal(next.pending, undefined);
  const accepted = ui.reconcileDraft(
    { ...surface, revision: 2, submittedActionId: "test" },
    draft,
  );
  assert.deepEqual(accepted.values, ui.initialValues(surface));
  assert.equal(
    ui.validSurface({
      ...surface,
      components: [{ id: "root", component: "Column", children: ["root"] }],
    }),
    false,
  );
}
console.log(
  "A2UI: three shared examples, validation, numeric normalization, draft reconciliation and unsafe graph checks passed",
);
