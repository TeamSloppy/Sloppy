import assert from "node:assert/strict";
import test from "node:test";

import { resolveDroppedPluginDirectory } from "../src/features/config/pluginDrop.ts";

test("plugin directory drop uses native picker when the browser hides the path", async () => {
  let pickerCalls = 0;
  const dataTransfer = {
    getData: () => "",
    items: [
      {
        webkitGetAsEntry: () => ({ isDirectory: true, name: "demo-plugin" }),
        getAsFile: () => null
      }
    ],
    files: []
  };

  const result = await resolveDroppedPluginDirectory(dataTransfer, async () => {
    pickerCalls += 1;
    return { path: "/Users/me/demo-plugin" };
  });

  assert.equal(pickerCalls, 1);
  assert.deepEqual(result, {
    path: "/Users/me/demo-plugin",
    name: "demo-plugin",
    status: "ready"
  });
});
