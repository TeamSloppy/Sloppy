import assert from "node:assert/strict";
import test from "node:test";
import {
    normalizeTrackerMarkdown,
    parseTrackerMarkdown
} from "../src/views/Projects/trackerMarkdown.js";

test("normalizes Tracker anchors, sized images and YFM tables", () => {
    const source = [
        "## Checklist {#check-list}",
        "![Screenshot](https://jing.yandex-team.ru/files/user/image.png =869x600)",
        "#|",
        "|| **Name** | **State** ||",
        "|| Build | Ready ||",
        "|#"
    ].join("\n");
    const normalized = normalizeTrackerMarkdown(source);
    assert.match(normalized, /^## Checklist$/m);
    assert.match(normalized, /\"yfm-size:869x600\"/);
    assert.match(normalized, /\| --- \| --- \|/);
});

test("parses nested cuts and keeps their titles", () => {
    const nodes = parseTrackerMarkdown([
        "Before",
        "{% cut \"Desktop\" %}",
        "First",
        "{% cut title=\"Screenshot\" %}",
        "![image](https://example.test/image.png)",
        "{% endcut %}",
        "{% endcut %}",
        "After"
    ].join("\n"));
    assert.equal(nodes[1].type, "cut");
    assert.equal(nodes[1].title, "Desktop");
    assert.equal(nodes[1].children[1].title, "Screenshot");
    assert.match(nodes[2].content, /After/);
});

test("does not interpret YFM directives inside fenced code", () => {
    const source = "```text\n{% cut \"Raw\" %}\n{% endcut %}\n```";
    assert.deepEqual(parseTrackerMarkdown(normalizeTrackerMarkdown(source)), [
        { type: "markdown", content: source }
    ]);
});
