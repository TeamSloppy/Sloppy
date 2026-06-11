import assert from "node:assert/strict";
import test from "node:test";

import { linkifyTaskReferences } from "../src/views/Projects/taskReferenceLinks.js";

test("task reference linkification handles issue ids without throwing", () => {
    const project = {
        tasks: Array.from({ length: 40 }, (_, index) => ({
            id: `SLOPPY-${index + 5}`,
            title: `Task ${index + 5}`
        }))
    };

    const markdown = "See SLOPPY-10, #SLOPPY-11, and (SLOPPY-12).";
    const linked = linkifyTaskReferences(markdown, project);

    assert.match(linked, /\[#SLOPPY-10\]\(sloppy-task:SLOPPY-10\)/);
    assert.match(linked, /\[#SLOPPY-11\]\(sloppy-task:SLOPPY-11\)/);
    assert.match(linked, /\[#SLOPPY-12\]\(sloppy-task:SLOPPY-12\)/);
});
