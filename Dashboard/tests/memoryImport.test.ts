import assert from "node:assert/strict";
import test from "node:test";
import { memoryImportMessage, memoryImportProgress, prepareMemoryAttachments, validateMemoryFiles } from "../src/features/agents/memoryImport.ts";

test("prepares multiple Unicode Markdown files without altering their bytes", async () => {
  const files = [new File(["# Память\nПредпочитаю Swift 🧠"], "память.md"), new File(["# Project\nDecision"], "project.MD")];
  const uploads = await prepareMemoryAttachments(files);
  assert.equal(uploads.length, 2);
  for (let i = 0; i < files.length; i++) {
    assert.equal(uploads[i].name, files[i].name);
    assert.equal(uploads[i].sizeBytes, files[i].size);
    assert.equal(Buffer.from(uploads[i].contentBase64, "base64").toString("utf8"), await files[i].text());
  }
});

test("rejects empty, binary, invalid UTF-8, oversized and non-Markdown files before upload", async () => {
  for (const files of [[], [{ name: "a.txt", size: 3 }], [{ name: "a.md", size: 0 }], [{ name: "a.md", size: 1024 * 1024 + 1 }],
    Array.from({ length: 21 }, () => ({ name: "a.md", size: 1 })),
    Array.from({ length: 6 }, () => ({ name: "a.md", size: 1024 * 1024 }))]) {
    assert.throws(() => validateMemoryFiles(files));
  }
  for (const file of [new File([" \n "], "empty.md"), new File([new Uint8Array([255])], "latin.md"), new File(["a\0b"], "binary.md")]) {
    await assert.rejects(prepareMemoryAttachments([file]));
  }
});

test("import explicitly invokes the skill and targets only the selected agent", () => {
  const message = memoryImportMessage("personal-agent");
  assert.match(message, /bundled\/memory-import/);
  assert.match(message, /scope_id = "personal-agent"/);
});

test("progress counts persisted IDs from typed tool events, never assistant claims", () => {
  const events = [
    { type: "message", message: { text: "Imported 100 memories successfully" } },
    { type: "tool_result", toolResult: { tool: "memory.save", ok: true, data: { id: "one" } } },
    { type: "tool_result", toolResult: { tool: "memory.save", ok: true, data: { id: "one" } } },
    { type: "tool_result", toolResult: { tool: "memory.save", ok: false } },
    { type: "tool_result", toolResult: { tool: "memory.search", ok: true, data: { id: "two" } } },
    { type: "run_status", runStatus: { stage: "paused" } }
  ];
  assert.deepEqual(memoryImportProgress(events), { saved: 1, failures: 1, stage: "paused" });
  assert.deepEqual(memoryImportProgress([{ type: "message" }]), { saved: 0, failures: 0, stage: "pending" });
});
