import assert from "node:assert/strict";
import test from "node:test";

import {
  buildActorLinkRenderModels,
  buildBezierPath
} from "../src/features/actors/actorLinkGeometry.ts";

const nodes = new Map([
  ["actor:source", { id: "actor:source", positionX: 100, positionY: 100 }],
  ["actor:target", { id: "actor:target", positionX: 420, positionY: 100 }]
]);

test("same-socket actor links receive parallel paths and separated labels", () => {
  const links = [
    {
      id: "chat-link",
      sourceActorId: "actor:source",
      targetActorId: "actor:target",
      sourceSocket: "right",
      targetSocket: "left",
      communicationType: "chat"
    },
    {
      id: "task-link",
      sourceActorId: "actor:source",
      targetActorId: "actor:target",
      sourceSocket: "right",
      targetSocket: "left",
      communicationType: "task"
    }
  ];

  const renderModels = buildActorLinkRenderModels(links, nodes);

  assert.equal(renderModels.length, 2);
  assert.notEqual(renderModels[0].path, renderModels[1].path);
  assert.notEqual(renderModels[0].midY, renderModels[1].midY);
});

test("single actor link keeps the original socket-center bezier", () => {
  const [renderModel] = buildActorLinkRenderModels([
    {
      id: "chat-link",
      sourceActorId: "actor:source",
      targetActorId: "actor:target",
      sourceSocket: "right",
      targetSocket: "left"
    }
  ], nodes);

  assert.equal(
    renderModel.path,
    buildBezierPath(renderModel.source, renderModel.target, "right", "left")
  );
  assert.equal(renderModel.midX, (renderModel.source.x + renderModel.target.x) / 2);
  assert.equal(renderModel.midY, (renderModel.source.y + renderModel.target.y) / 2);
});

test("two-way sibling links keep reverse flow on the same parallel curve", () => {
  const [renderModel] = buildActorLinkRenderModels([
    {
      id: "chat-link",
      sourceActorId: "actor:source",
      targetActorId: "actor:target",
      sourceSocket: "right",
      targetSocket: "left"
    },
    {
      id: "task-link",
      sourceActorId: "actor:source",
      targetActorId: "actor:target",
      sourceSocket: "right",
      targetSocket: "left"
    }
  ], nodes);

  const forwardEnd = renderModel.path.match(/, ([\d.-]+) ([\d.-]+)$/);
  const reverseStart = renderModel.reversePath.match(/^M ([\d.-]+) ([\d.-]+)/);

  assert.ok(forwardEnd);
  assert.ok(reverseStart);
  assert.deepEqual(reverseStart.slice(1), forwardEnd.slice(1));
});
