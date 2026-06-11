import assert from "node:assert/strict";
import test from "node:test";

import { taskDescriptionMode } from "../src/views/Projects/taskDescriptionMode.js";

test("task description starts in markdown preview when text exists", () => {
    assert.equal(taskDescriptionMode("## Goal\nShip it", false), "preview");
});

test("task description uses raw editor while editing", () => {
    assert.equal(taskDescriptionMode("## Goal\nShip it", true), "editor");
});

test("task description keeps raw editor for empty descriptions", () => {
    assert.equal(taskDescriptionMode("   ", false), "editor");
});
