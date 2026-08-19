import assert from "node:assert/strict";
import test from "node:test";

import { imageArtifactFromToolResult } from "../src/features/agents/imageArtifactTimeline.ts";

test("successful images.generate result becomes an image artifact timeline item", () => {
  const artifact = imageArtifactFromToolResult({
    type: "tool_result",
    toolResult: {
      tool: "images.generate",
      ok: true,
      data: {
        model: "fal-ai/flux-2",
        modality: "text_to_image",
        artifact: {
          id: "image-1",
          kind: "image",
          mediaType: "image/png",
          width: 1024,
          height: 576
        }
      }
    }
  });

  assert.deepEqual(artifact, {
    id: "image-1",
    mediaType: "image/png",
    width: 1024,
    height: 576,
    model: "fal-ai/flux-2",
    modality: "text_to_image"
  });
});

test("failed or unrelated tool results do not create image previews", () => {
  assert.equal(imageArtifactFromToolResult({ type: "tool_result", toolResult: { tool: "images.generate", ok: false } }), null);
  assert.equal(imageArtifactFromToolResult({ type: "tool_result", toolResult: { tool: "files.read", ok: true } }), null);
});
